import Foundation
import HealthKit

protocol HealthKitWorkoutImporting {
    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult
}

final class HealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    private let localDuplicateLookbackDays = 3_650

    private let workoutFetcher: any HealthKitWorkoutFetching
    private let mapper: HealthKitWorkoutToUnifiedWorkoutMapper
    private let store: any UnifiedWorkoutStore
    private let routeLookupProvider: (any HealthKitWorkoutLookingUp)?
    private let routeFetcher: (any HealthKitWorkoutRouteFetching)?
    private let routeStore: (any WorkoutRoutePersistenceStoring)?
    private let telemetryFetcher: (any HealthKitWorkoutTelemetryFetching)?
    private let saveTelemetry: (@MainActor (WorkoutTelemetry) throws -> Void)?
    private let mappedAt: () -> Date
    private let autoPublishNewWorkouts: Bool
    private let pendingAudience: FeedPostVisibility

    init(
        workoutFetcher: any HealthKitWorkoutFetching = HealthKitWorkoutFetcher(),
        mapper: HealthKitWorkoutToUnifiedWorkoutMapper = HealthKitWorkoutToUnifiedWorkoutMapper(),
        store: any UnifiedWorkoutStore,
        routeLookupProvider: (any HealthKitWorkoutLookingUp)? = nil,
        routeFetcher: (any HealthKitWorkoutRouteFetching)? = nil,
        routeStore: (any WorkoutRoutePersistenceStoring)? = nil,
        telemetryFetcher: (any HealthKitWorkoutTelemetryFetching)? = nil,
        saveTelemetry: (@MainActor (WorkoutTelemetry) throws -> Void)? = nil,
        mappedAt: @escaping () -> Date = Date.init,
        autoPublishNewWorkouts: Bool = false,
        pendingAudience: FeedPostVisibility = .privatePost
    ) {
        self.workoutFetcher = workoutFetcher
        self.mapper = mapper
        self.store = store
        self.routeLookupProvider = routeLookupProvider
        self.routeFetcher = routeFetcher
        self.routeStore = routeStore
        self.telemetryFetcher = telemetryFetcher
        self.saveTelemetry = saveTelemetry
        self.mappedAt = mappedAt
        self.autoPublishNewWorkouts = autoPublishNewWorkouts
        self.pendingAudience = pendingAudience
    }

    func importRecentWorkouts(limit: Int = 20) async -> HealthKitWorkoutImportResult {
        let workouts: [HealthKitWorkout]

        do {
            workouts = try await workoutFetcher.fetchRecentWorkouts(limit: max(limit, 1))
        } catch {
            return .failure(
                message: "HealthKit 운동 기록을 가져오지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }

        let importDate = mappedAt()
        let mapped = workouts.map { mapper.map($0, mappedAt: importDate) }
        do {
            let existing = try await store.fetchRecentWorkouts(days: localDuplicateLookbackDays)
            var added: [UnifiedWorkout] = []
            var refreshed: [UnifiedWorkout] = []
            var cardUpdates: [UnifiedWorkout] = []
            var detailWarningCount = 0
            var seen = Set<String>()
            for candidate in mapped {
                try Task.checkCancellation()
                let identity = candidate.externalId ?? candidate.id.uuidString
                guard seen.insert(identity).inserted else { continue }
                let previous = existing.first {
                    $0.source == .appleHealthKit && ($0.id == candidate.id || $0.externalId == candidate.externalId)
                }
                var workout = previous ?? candidate
                var cardChanged = false
                if previous == nil, autoPublishNewWorkouts {
                    // Hold plausible overlaps for an explicit source choice.
                    // Keep the raw watch data even when SOOM recorded the run.
                    let needsReview = (existing + added).contains {
                        UnifiedWorkoutDeduplicationEngine().compare($0, workout) != nil
                    }
                    workout.sharingVisibilityRaw = needsReview ? "source_review_pending" : ImportedWorkoutPublication.pendingVisibility(for:pendingAudience)
                }
                if previous == nil { try await store.saveWorkout(workout) }
                var telemetry: WorkoutTelemetry?
                var route: WorkoutRoute?
                if let routeLookupProvider,
                   let externalID = workout.externalId,
                   let raw = await routeLookupProvider.lookupWorkout(externalId: externalID) {
                    if let telemetryFetcher {
                        do {
                            let details = try await telemetryFetcher.fetchTelemetry(for: raw)
                            detailWarningCount += details.failedChannels.count
                            var value = details.telemetry
                            value.workoutID = workout.id
                            telemetry = value
                        } catch is CancellationError { throw CancellationError() }
                        catch { detailWarningCount += 1 }
                    }
                    if telemetryFetcher != nil { workout = workout.withHealthKitDetails(raw, telemetry: telemetry) }
                    cardChanged = previous.map { $0 != workout } ?? false
                    if let routeFetcher, let routeStore {
                        do {
                            if let fetched = try await routeFetcher.fetchRoute(for: raw) {
                                route = fetched.associated(with: workout)
                                let before = try await routeStore.fetchRoute(workoutId: workout.id)
                                let routeChanged = before?.coordinates != route?.coordinates
                                    || before?.totalDistanceMeters != route?.totalDistanceMeters
                                if routeChanged {
                                    do { try await routeStore.saveRoute(route!); cardChanged = true }
                                    catch {
                                        detailWarningCount += 1
                                        if before == nil { workout = workout.withRouteMissingReason(.routePersistenceFailed, updatedAt: mappedAt()) }
                                        route = before
                                    }
                                }
                                if route != nil, workout.routeMissingReason != .none {
                                    workout = workout.withRouteMissingReason(.none, updatedAt: mappedAt())
                                }
                            } else if try await routeStore.fetchRoute(workoutId: workout.id) == nil,
                                      workout.routeMissingReason != .healthKitRouteUnavailable {
                                workout = workout.withRouteMissingReason(.healthKitRouteUnavailable, updatedAt: mappedAt())
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            // A transient error never removes an existing route.
                            detailWarningCount += 1
                            if workout.routeMissingReason != .none || previous == nil {
                                workout = workout.withRouteMissingReason(.routeFetchFailed, updatedAt: mappedAt())
                            }
                        }
                    }
                } else if routeLookupProvider != nil {
                    detailWarningCount += 1
                    if previous == nil { workout = workout.withRouteMissingReason(.externalSourceRouteNotShared, updatedAt: mappedAt()) }
                }
                try Task.checkCancellation()
                if previous == nil || routeLookupProvider != nil {
                    try await store.saveWorkout(workout)
                    if let saveTelemetry {
                        var detail = telemetry ?? WorkoutTelemetry(workoutID: workout.id, source: .appleHealthKit)
                        // GPS altitude stays a measured elevation channel; speed
                        // and km splits from distance intervals are derived in UI.
                        detail.samples += (route?.coordinates ?? []).compactMap { coordinate in
                            guard let time = coordinate.timestamp, let altitude = coordinate.altitude else { return nil }
                            return WorkoutTelemetrySample(timestamp: time, elevationMeters: altitude, source: .appleHealthKit)
                        }
                        if !detail.isEmpty {
                            do { try await saveTelemetry(detail) }
                            catch { detailWarningCount += 1 }
                        }
                    }
                    if previous == nil { added.append(workout) } else {
                        refreshed.append(workout)
                        if cardChanged { cardUpdates.append(workout) }
                    }
                }
            }
            var result = HealthKitWorkoutImportResult.success(importedWorkouts: added, fetchedCount: workouts.count)
            result.refreshedWorkouts = refreshed
            result.cardUpdates = cardUpdates
            result.detailWarningCount = detailWarningCount
            if !refreshed.isEmpty { result.message = "새 운동 \(added.count)개 · 기존 운동 \(refreshed.count)개의 경로와 측정값을 다시 확인했어요." }
            if detailWarningCount > 0 { result.message += " 일부 상세 데이터는 읽지 못했어요. 권한과 Watch 동기화를 확인한 뒤 다시 시도해 주세요." }
            return result
        } catch {
            return .failure(fetchedCount: workouts.count, failedCount: mapped.count,
                message: "HealthKit 운동 기록을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

}

private extension WorkoutRoute {
    func associated(with workout: UnifiedWorkout) -> WorkoutRoute {
        WorkoutRoute(
            id: id,
            workoutId: workout.id,
            source: workout.source,
            coordinates: coordinates,
            totalDistanceMeters: totalDistanceMeters,
            totalElevationGain: totalElevationGain,
            bounds: bounds,
            createdAt: createdAt
        )
    }
}
