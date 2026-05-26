import Foundation
import SwiftData

struct LocalDataDetector {
    private let detectTrainingSettings: @MainActor () -> Bool
    private let detectWorkouts: @MainActor () async throws -> Bool
    private let detectWorkoutRoutes: @MainActor () async throws -> Bool
    private let detectProgressionData: @MainActor () async throws -> Bool

    init(
        detectTrainingSettings: @escaping @MainActor () -> Bool,
        detectWorkouts: @escaping @MainActor () async throws -> Bool,
        detectWorkoutRoutes: @escaping @MainActor () async throws -> Bool,
        detectProgressionData: @escaping @MainActor () async throws -> Bool = { false }
    ) {
        self.detectTrainingSettings = detectTrainingSettings
        self.detectWorkouts = detectWorkouts
        self.detectWorkoutRoutes = detectWorkoutRoutes
        self.detectProgressionData = detectProgressionData
    }

    @MainActor
    static func live(
        modelContext: ModelContext,
        trainingSettingsStore: TrainingSettingsStore = .shared
    ) -> LocalDataDetector {
        let workoutStore = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let routeStore = SwiftDataWorkoutRoutePersistenceStore(modelContext: modelContext)

        return LocalDataDetector(
            detectTrainingSettings: {
                trainingSettingsStore.hasAnySavedTrainingSetting()
            },
            detectWorkouts: {
                try await workoutStore.hasAnyWorkout()
            },
            detectWorkoutRoutes: {
                try await routeStore.hasAnyWorkoutRoute()
            }
        )
    }

    @MainActor
    func detect() async -> LocalDataPresence {
        let hasTrainingSettings = detectTrainingSettings()
        let hasWorkouts = await safeDetect(detectWorkouts)
        let hasWorkoutRoutes = await safeDetect(detectWorkoutRoutes)
        let hasProgressionData = await safeDetect(detectProgressionData)

        return LocalDataPresence(
            hasTrainingSettings: hasTrainingSettings,
            hasWorkouts: hasWorkouts,
            hasWorkoutRoutes: hasWorkoutRoutes,
            hasProgressionData: hasProgressionData
        )
    }

    @MainActor
    private func safeDetect(_ detector: @MainActor () async throws -> Bool) async -> Bool {
        do {
            return try await detector()
        } catch {
            return false
        }
    }
}
