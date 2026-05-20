import Foundation

@MainActor
final class UnifiedWorkoutLibraryViewModel: ObservableObject {
    @Published private(set) var workouts: [UnifiedWorkout] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updatingWorkoutIDs: Set<UUID> = []

    private let store: any UnifiedWorkoutStore
    private let recentDays: Int

    init(
        store: any UnifiedWorkoutStore,
        recentDays: Int = 30
    ) {
        self.store = store
        self.recentDays = recentDays
    }

    func loadRecentWorkouts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            workouts = try await store.fetchRecentWorkouts(days: recentDays)
        } catch {
            workouts = []
            errorMessage = "가져온 운동 기록을 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
        }

        isLoading = false
    }

    func toggleExcluded(id: UUID) async {
        guard let workout = workouts.first(where: { $0.id == id }),
              !updatingWorkoutIDs.contains(id) else {
            return
        }

        let nextExcludedState = !workout.isExcludedFromAnalysis
        updatingWorkoutIDs.insert(id)
        errorMessage = nil

        do {
            try await store.markExcludedFromAnalysis(id: id, isExcluded: nextExcludedState)
            updateWorkout(id: id, isExcludedFromAnalysis: nextExcludedState)
        } catch {
            errorMessage = "분석 제외 상태를 변경하지 못했어요. 잠시 후 다시 시도해 주세요."
        }

        updatingWorkoutIDs.remove(id)
    }

    private func updateWorkout(id: UUID, isExcludedFromAnalysis: Bool) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let workout = workouts[index]
        workouts[index] = UnifiedWorkout(
            id: workout.id,
            externalId: workout.externalId,
            source: workout.source,
            workoutType: workout.workoutType,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.durationSeconds,
            distanceMeters: workout.distanceMeters,
            activeEnergyKcal: workout.activeEnergyKcal,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate,
            averageSpeedMetersPerSecond: workout.averageSpeedMetersPerSecond,
            elevationGainMeters: workout.elevationGainMeters,
            dataQuality: workout.dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: workout.createdAt,
            updatedAt: Date()
        )
    }
}
