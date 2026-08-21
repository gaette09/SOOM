import Foundation

struct WorkoutCompanionUpdateService {
    private let workoutStore: any UnifiedWorkoutStore

    init(workoutStore: any UnifiedWorkoutStore) {
        self.workoutStore = workoutStore
    }

    func updateCompanions(workoutId: UUID, names: [String]) async -> WorkoutCompanionUpdateResult {
        do {
            try await workoutStore.updateCompanions(id: workoutId, names: names)
            return .success(names)
        } catch {
            return .failure(.persistenceFailed)
        }
    }
}
