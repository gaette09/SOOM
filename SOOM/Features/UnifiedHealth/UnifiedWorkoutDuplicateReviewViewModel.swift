import Foundation

@MainActor
final class UnifiedWorkoutDuplicateReviewViewModel: ObservableObject {
    @Published private(set) var candidates: [UnifiedWorkoutDuplicateCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let store: any UnifiedWorkoutStore
    private let engine: UnifiedWorkoutDeduplicationEngine
    private let recentDays: Int

    init(
        store: any UnifiedWorkoutStore,
        engine: UnifiedWorkoutDeduplicationEngine = UnifiedWorkoutDeduplicationEngine(),
        recentDays: Int = 30
    ) {
        self.store = store
        self.engine = engine
        self.recentDays = recentDays
    }

    func loadDuplicateCandidates() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let workouts = try await store.fetchRecentWorkouts(days: recentDays)
            candidates = engine.findDuplicateCandidates(in: workouts)
        } catch {
            candidates = []
            errorMessage = "중복 후보를 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
        }

        isLoading = false
    }
}
