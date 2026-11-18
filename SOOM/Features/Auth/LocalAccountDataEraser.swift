import Foundation
import SwiftData

enum LocalAccountDataStore: String, CaseIterable, Equatable {
    case workouts
    case workoutRoutes
    case feedDrafts
    case checkIns
    case recoverySnapshots
    case trainingSettings
    case clubData
    case deviceToken
    case checkInSkip

    var title: String {
        switch self {
        case .workouts: return "운동 기록"
        case .workoutRoutes: return "운동 경로"
        case .feedDrafts: return "공유 초안"
        case .checkIns: return "체크인"
        case .recoverySnapshots: return "회복 기록"
        case .trainingSettings: return "운동 설정"
        case .clubData: return "클럽 기록"
        case .deviceToken: return "알림 기기 정보"
        case .checkInSkip: return "체크인 알림 설정"
        }
    }
}

struct LocalAccountDataErasureResult: Equatable {
    let failedStores: [LocalAccountDataStore]

    var isComplete: Bool { failedStores.isEmpty }
}

/// Wipes every local store an account (guest or Supabase-linked) can have
/// written to, for the account-deletion flow. Mirrors `LocalDataDetector`'s
/// shape: injected closures plus a `.live(modelContext:)` factory, so each
/// store stays swappable in tests without this type knowing about SwiftData
/// or UserDefaults directly.
///
/// `AuthSessionStore` is not wiped here — `AuthViewModel.deleteAccount()`
/// already clears it via `repository.signOut()` as part of committing the
/// deletion decision, before this type ever runs.
struct LocalAccountDataEraser {
    private let eraseWorkouts: @MainActor () async throws -> Void
    private let eraseWorkoutRoutes: @MainActor () async throws -> Void
    private let eraseFeedDrafts: @MainActor () async throws -> Void
    private let eraseCheckIns: @MainActor () async throws -> Void
    private let eraseRecoverySnapshots: @MainActor () async throws -> Void
    private let eraseTrainingSettings: @MainActor () async throws -> Void
    private let eraseClubData: @MainActor () async throws -> Void
    private let eraseDeviceToken: @MainActor () async throws -> Void
    private let eraseCheckInSkip: @MainActor () async throws -> Void

    init(
        eraseWorkouts: @escaping @MainActor () async throws -> Void,
        eraseWorkoutRoutes: @escaping @MainActor () async throws -> Void,
        eraseFeedDrafts: @escaping @MainActor () async throws -> Void,
        eraseCheckIns: @escaping @MainActor () async throws -> Void,
        eraseRecoverySnapshots: @escaping @MainActor () async throws -> Void,
        eraseTrainingSettings: @escaping @MainActor () async throws -> Void,
        eraseClubData: @escaping @MainActor () async throws -> Void,
        eraseDeviceToken: @escaping @MainActor () async throws -> Void = {},
        eraseCheckInSkip: @escaping @MainActor () async throws -> Void = {}
    ) {
        self.eraseWorkouts = eraseWorkouts
        self.eraseWorkoutRoutes = eraseWorkoutRoutes
        self.eraseFeedDrafts = eraseFeedDrafts
        self.eraseCheckIns = eraseCheckIns
        self.eraseRecoverySnapshots = eraseRecoverySnapshots
        self.eraseTrainingSettings = eraseTrainingSettings
        self.eraseClubData = eraseClubData
        self.eraseDeviceToken = eraseDeviceToken
        self.eraseCheckInSkip = eraseCheckInSkip
    }

    @MainActor
    static func live(
        modelContext: ModelContext,
        trainingSettingsStore: TrainingSettingsStore = .shared,
        clubPersistence: LocalClubPersistence = LocalClubPersistence(),
        feedShareDraftStore: any FeedShareDraftStoreProtocol = FileFeedShareDraftStore.live,
        deviceTokenStore: DeviceTokenStore = .shared,
        morningCheckInSkipStore: MorningCheckInSkipStore = MorningCheckInSkipStore()
    ) -> LocalAccountDataEraser {
        let workoutStore = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)
        let checkInStore = SwiftDataCheckInStore(modelContext: modelContext)

        return LocalAccountDataEraser(
            eraseWorkouts: { try await workoutStore.deleteAllWorkouts() },
            eraseWorkoutRoutes: { try await routeStore.deleteAllRoutes() },
            eraseFeedDrafts: { try await feedShareDraftStore.deleteAllDrafts() },
            eraseCheckIns: { try await checkInStore.deleteAllCheckIns() },
            eraseRecoverySnapshots: {
                // Fetch every snapshot: the history API intentionally limits
                // dates, but account deletion must also remove older health data.
                let records = try modelContext.fetch(FetchDescriptor<DailyRecoverySnapshotRecord>())
                for record in records {
                    modelContext.delete(record)
                }
                try modelContext.save()
            },
            eraseTrainingSettings: { trainingSettingsStore.resetAll() },
            eraseClubData: { clubPersistence.reset() },
            eraseDeviceToken: { deviceTokenStore.clear() },
            eraseCheckInSkip: { morningCheckInSkipStore.clear() }
        )
    }

    /// Continue after a store fails, but report every incomplete deletion
    /// so the caller can keep reset available and offer a retry.
    @MainActor
    @discardableResult
    func eraseAll() async -> LocalAccountDataErasureResult {
        let erasures: [(LocalAccountDataStore, @MainActor () async throws -> Void)] = [
            (.workouts, eraseWorkouts),
            (.workoutRoutes, eraseWorkoutRoutes),
            (.feedDrafts, eraseFeedDrafts),
            (.checkIns, eraseCheckIns),
            (.recoverySnapshots, eraseRecoverySnapshots),
            (.trainingSettings, eraseTrainingSettings),
            (.clubData, eraseClubData),
            (.deviceToken, eraseDeviceToken),
            (.checkInSkip, eraseCheckInSkip)
        ]
        var failedStores: [LocalAccountDataStore] = []
        for (store, erase) in erasures {
            do {
                try await erase()
            } catch {
                failedStores.append(store)
            }
        }
        return LocalAccountDataErasureResult(failedStores: failedStores)
    }
}
