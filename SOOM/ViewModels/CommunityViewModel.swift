import Foundation

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var posts: [FeedPost]
    @Published private(set) var clubs: [Club]

    init(harness: WorkoutHarness) {
        self.posts = harness.loadFeedPosts()
        self.clubs = harness.loadClubs()
    }
}
