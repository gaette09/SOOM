import Foundation
import SwiftData

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
    private let eraseFeedDrafts: () async throws -> Void
    private let eraseTrainingSettings: () -> Void
    private let eraseClubData: () -> Void

    init(
        eraseWorkouts: @escaping @MainActor () async throws -> Void,
        eraseWorkoutRoutes: @escaping @MainActor () async throws -> Void,
        eraseFeedDrafts: @escaping () async throws -> Void,
        eraseTrainingSettings: @escaping () -> Void,
        eraseClubData: @escaping () -> Void
    ) {
        self.eraseWorkouts = eraseWorkouts
        self.eraseWorkoutRoutes = eraseWorkoutRoutes
        self.eraseFeedDrafts = eraseFeedDrafts
        self.eraseTrainingSettings = eraseTrainingSettings
        self.eraseClubData = eraseClubData
    }

    @MainActor
    static func live(
        modelContext: ModelContext,
        trainingSettingsStore: TrainingSettingsStore = .shared,
        clubPersistence: LocalClubPersistence = LocalClubPersistence(),
        feedShareDraftStore: any FeedShareDraftStoreProtocol = FileFeedShareDraftStore.live
    ) -> LocalAccountDataEraser {
        let workoutStore = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)

        return LocalAccountDataEraser(
            eraseWorkouts: { try await workoutStore.deleteAllWorkouts() },
            eraseWorkoutRoutes: { try await routeStore.deleteAllRoutes() },
            eraseFeedDrafts: { try await feedShareDraftStore.deleteAllDrafts() },
            eraseTrainingSettings: { trainingSettingsStore.resetAll() },
            eraseClubData: { clubPersistence.reset() }
        )
    }

    /// Best-effort: erases everything it can, does not stop on a single
    /// store's failure, since the deletion decision (remote or local-only)
    /// has already been committed by the caller by the time this runs.
    @MainActor
    func eraseAll() async {
        try? await eraseWorkouts()
        try? await eraseWorkoutRoutes()
        try? await eraseFeedDrafts()
        eraseTrainingSettings()
        eraseClubData()
    }
}
