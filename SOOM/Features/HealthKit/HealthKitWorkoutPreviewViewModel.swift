import Foundation

@MainActor
final class HealthKitWorkoutPreviewViewModel: ObservableObject {
    @Published private(set) var workouts: [HealthKitWorkout] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let fetcher: any HealthKitWorkoutFetching
    private let limit: Int

    init(fetcher: any HealthKitWorkoutFetching, limit: Int = 10) {
        self.fetcher = fetcher
        self.limit = limit
    }

    func loadRecentWorkouts() async {
        isLoading = true
        errorMessage = nil

        do {
            workouts = try await fetcher.fetchRecentWorkouts(limit: limit)
        } catch {
            workouts = []
            errorMessage = "운동 기록을 불러오지 못했어요. 건강 앱 권한을 확인해 주세요."
        }

        isLoading = false
    }
}
