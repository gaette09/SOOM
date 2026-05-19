import Foundation

protocol WorkoutHarness {
    func loadWorkouts() -> [Workout]
    func loadMonthlySnapshot() -> MonthlySnapshot
    func loadFeedPosts() -> [FeedPost]
    func loadClubs() -> [Club]
}
