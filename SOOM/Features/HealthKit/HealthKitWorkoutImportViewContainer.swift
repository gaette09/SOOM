import UserNotifications
import UIKit
import HealthKit
import SwiftData
import SwiftUI

struct HealthKitWorkoutImportViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController

    var body: some View {
        if ReviewDemoMode.isActive {
            ReviewDemoIntegrationView(title: "Apple 건강 운동 가져오기")
        } else {
            HealthKitWorkoutImportView(
                viewModel: HealthKitWorkoutImportViewModel(
                    pipeline: HealthKitWorkoutImportPipeline(
                        workoutFetcher: HealthKitWorkoutFetcher(),
                        store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext),
                        routeLookupProvider: HealthKitWorkoutLookupProvider(),
                        routeFetcher: HealthKitWorkoutRouteFetcher(),
                        routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext),
                        telemetryFetcher: HealthKitWorkoutTelemetryFetcher(),
                        saveTelemetry: { try WorkoutTelemetryStore(modelContext: modelContext).save($0) },
                        autoPublishNewWorkouts: ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts, pendingAudience: storage.defaultWorkoutAudience
                    ),
                    publication: ImportedWorkoutPublication(context: modelContext, storage: storage)
                )
            )
        }
    }
}


@MainActor
enum HealthKitAutomaticImport {
    private static var running = false
    private static var runAgain = false

    private struct HistoryAuthorization {
        let ownerID: UUID
        let earliestActivity: Date
        let isCurrent: () -> Bool
    }
    static func isFullHistoryEnabled(for storage:HealthAccountStorageController) -> Bool {
        storage.userID != nil && UserDefaults.standard.bool(forKey:"SOOM.healthKitFullHistory.\(storage.scopeID)")
    }
    /// This is called only by the explicit source-setting choice, never by a
    /// public-profile toggle or remote summary-staging permission.
    static func setFullHistoryEnabled(_ enabled:Bool,for storage:HealthAccountStorageController) {
        guard storage.userID != nil else { return }
        UserDefaults.standard.set(enabled,forKey:"SOOM.healthKitFullHistory.\(storage.scopeID)")
    }

    static func isEnabled(for storage: HealthAccountStorageController) -> Bool {
        guard !ReviewDemoMode.isActive, storage.userID != nil else { return false }
        let key = "SOOM.healthKitAutoImport.\(storage.scopeID)"
        if let chosen = UserDefaults.standard.object(forKey: key) as? Bool { return chosen }
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate {
            $0.sourceRaw == "appleHealthKit"
        })
        descriptor.fetchLimit = 1
        let wasAlreadyUsingHealth = ((try? ModelContext(storage.container).fetch(descriptor))?.isEmpty == false)
        return wasAlreadyUsingHealth
    }

    static func setEnabled(_ enabled: Bool, for storage: HealthAccountStorageController) {
        UserDefaults.standard.set(enabled, forKey: "SOOM.healthKitAutoImport.\(storage.scopeID)")
    }

    static func notificationsEnabled(for storage: HealthAccountStorageController) -> Bool {
        UserDefaults.standard.bool(forKey: "SOOM.healthKitImportNotifications.\(storage.scopeID)")
    }

    static func setNotificationsEnabled(_ enabled: Bool, for storage: HealthAccountStorageController) {
        UserDefaults.standard.set(enabled, forKey: "SOOM.healthKitImportNotifications.\(storage.scopeID)")
    }

    static func run(storage: HealthAccountStorageController) async {
        guard isEnabled(for: storage) else { return }
        if running { runAgain = true; return }
        running = true
        defer { running = false }
        repeat {
            runAgain = false
            guard let owner = storage.userID else { return }
            let scope = storage.scopeID
            let context = ModelContext(storage.container)
            let history:HistoryAuthorization? = isFullHistoryEnabled(for:storage)
                ? .init(ownerID:owner,earliestActivity:.distantPast,isCurrent:{
                    storage.userID==owner && storage.scopeID==scope && isFullHistoryEnabled(for:storage)
                }) : nil
            let plan=HealthKitAutomaticHistoryPlan(scope:scope,authorizedSince:history?.earliestActivity)
            func importContextIsCurrent() -> Bool {
                guard storage.userID==owner,storage.scopeID==scope,context.container===storage.container,
                      isEnabled(for:storage),!HealthCloudJournal.isRetired(context) else { return false }
                if let history {
                    return history.isCurrent()
                }
                return true
            }
            let anchorKey = plan.anchorKey
            let startKey = plan.startKey
            let firstStart = UserDefaults.standard.object(forKey: startKey) as? Date
                ?? plan.initialStart
            if UserDefaults.standard.object(forKey: startKey) == nil {
                UserDefaults.standard.set(firstStart, forKey: startKey)
            }
            var anchor = UserDefaults.standard.data(forKey: anchorKey).flatMap {
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
            }
            // An authorized full-history pass has a distinct stable predicate
            // and anchor. Never reuse the old 90-day cursor for earlier history.
            let cutoff = plan.cutoff
            let fetcher = HealthKitWorkoutChangeFetcher(since: firstStart)
            let repairStore = SwiftDataUnifiedWorkoutStore(modelContext: context)
            let recent = (try? await repairStore.fetchRecentWorkouts(days: 3)) ?? []
            let repair = recent.filter { $0.source == .appleHealthKit }.prefix(6).map {
                HealthKitWorkout(id: UUID(uuidString: $0.externalId ?? "") ?? $0.id,
                    workoutType: HealthKitWorkoutType(rawValue: $0.workoutType.rawValue) ?? .other,
                    startDate: $0.startDate, endDate: $0.endDate, duration: $0.durationSeconds,
                    distance: $0.distanceMeters, averageHeartRate: $0.averageHeartRate,
                    calories: $0.activeEnergyKcal, deviceName: $0.deviceName)
            }
            if !repair.isEmpty {
                let repairPipeline = HealthKitWorkoutImportPipeline(
                    workoutFetcher: HealthKitChangedWorkoutBatch(workouts: repair), store: repairStore,
                    routeLookupProvider: HealthKitWorkoutLookupProvider(), routeFetcher: HealthKitWorkoutRouteFetcher(),
                    routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: context),
                    telemetryFetcher: HealthKitWorkoutTelemetryFetcher(),
                    saveTelemetry: { try WorkoutTelemetryStore(modelContext: context).save($0) })
                let repaired = await repairPipeline.importRecentWorkouts(limit: repair.count)
                guard !Task.isCancelled, storage.userID == owner, storage.scopeID == scope else { return }
                for updated in repaired.cardUpdates {
                    guard !Task.isCancelled, storage.userID == owner, storage.scopeID == scope else { return }
                    let management = WorkoutRecordManagement(workout: updated)
                    management.configure(context: context, storage: storage)
                    _ = await management.refreshProviderMeasurements()
                }
                if !repaired.refreshedWorkouts.isEmpty {
                    NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
                }
            }

            // Collect and checkpoint every local batch before attempting social
            // delivery. Durable auto_pending markers are retried independently;
            // a feed outage must not prevent newer Watch/HealthKit records loading.
            await HealthKitAutomaticImportSequence.run(
                isCurrent: importContextIsCurrent,
                importAndCheckpoint: {
                    for _ in 0..<100 {
                        guard !Task.isCancelled, importContextIsCurrent() else { return false }
                        let changes: HealthKitWorkoutChanges
                        do { changes = try await fetcher.fetch(after: anchor) }
                        catch { return false }
                        guard !Task.isCancelled, importContextIsCurrent() else { return false }
                        let pipeline = HealthKitWorkoutImportPipeline(
                            workoutFetcher: HealthKitChangedWorkoutBatch(
                                workouts: changes.workouts.filter { $0.startDate >= cutoff }),
                            store: SwiftDataUnifiedWorkoutStore(modelContext: context),
                            routeLookupProvider: HealthKitWorkoutLookupProvider(),
                            routeFetcher: HealthKitWorkoutRouteFetcher(),
                            routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: context),
                            telemetryFetcher: HealthKitWorkoutTelemetryFetcher(),
                            saveTelemetry: { try WorkoutTelemetryStore(modelContext: context).save($0) },
                            autoPublishNewWorkouts: ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts,
                            pendingAudience: storage.defaultWorkoutAudience
                        )
                        let result = await pipeline.importRecentWorkouts(limit: changes.workouts.count)
                        guard result.failedCount == 0, !Task.isCancelled,
                              importContextIsCurrent() else { return false }
                        // Anchor acknowledges local persistence, never social delivery.
                        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: changes.anchor,
                            requiringSecureCoding: true) else { return false }
                        UserDefaults.standard.set(data, forKey: anchorKey)
                        anchor = changes.anchor
                        if !result.importedWorkouts.isEmpty {
                            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
                            if history == nil, notificationsEnabled(for: storage), UIApplication.shared.applicationState != .active {
                                let content = UNMutableNotificationContent()
                                content.title = "새 운동을 가져왔어요"
                                content.body = "Apple 건강 앱의 운동 \(result.savedCount)개가 활동에 추가됐어요."
                                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                                try? await UNUserNotificationCenter.current().add(request)
                            }
                        }
                        UserDefaults.standard.set(changes.changeCount < 100,forKey:plan.drainedKey)
                        if changes.changeCount < 100 { break }
                    }
                    return true
                },
                publishPending: {
                    _ = await ImportedWorkoutPublication(context: context, storage: storage).publish()
                }
            )
        } while runAgain && isEnabled(for: storage)
    }
}

/// Local persistence/anchor completion is a separate phase from best-effort
/// publication. This seam deliberately has no publication-success prerequisite.
@MainActor
enum HealthKitAutomaticImportSequence {
    static func run(isCurrent: () -> Bool,
                    importAndCheckpoint: () async -> Bool,
                    publishPending: () async -> Void) async {
        guard !Task.isCancelled, isCurrent() else { return }
        guard await importAndCheckpoint(), !Task.isCancelled, isCurrent() else { return }
        await publishPending()
    }
}

/// Separate checkpoint namespaces retain the existing 90-day import history and
/// restart full-history pagination if its authorized lower bound changes.
struct HealthKitAutomaticHistoryPlan: Equatable {
    let anchorKey: String
    let startKey: String
    let drainedKey: String
    let initialStart: Date
    let cutoff: Date
    init(scope:String,authorizedSince:Date?,now:Date=Date()) {
        if let since=authorizedSince {
            let bound=String(Int64(since.timeIntervalSince1970.rounded(.down)))
            anchorKey="SOOM.healthKitWorkoutFullHistoryAnchorV3.\(scope).\(bound)"
            startKey="SOOM.healthKitWorkoutFullHistoryStartV3.\(scope).\(bound)"
            drainedKey="SOOM.healthKitWorkoutFullHistoryDrainedV3.\(scope).\(bound)"
            initialStart=since;cutoff=since
        } else {
            anchorKey="SOOM.healthKitWorkoutAnchorV2.\(scope)"
            startKey="SOOM.healthKitWorkoutStartV2.\(scope)"
            drainedKey="SOOM.healthKitWorkoutDrainedV2.\(scope)"
            initialStart=now.addingTimeInterval(-90*86_400);cutoff=initialStart
        }
    }
}
