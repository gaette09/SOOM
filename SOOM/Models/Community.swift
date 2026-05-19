import Foundation

struct FeedPost: Identifiable {
    let id = UUID()
    let athleteName: String
    let handle: String
    let title: String
    let caption: String
    let sport: WorkoutSport
    let distance: String
    let duration: String
    let likes: Int
    let comments: Int
    let linkedWorkout: Workout?
}

struct Club: Identifiable {
    let id = UUID()
    let name: String
    let location: String
    let description: String
    let memberCount: Int
    let weeklyVolume: String
    let tags: [String]
    let upcoming: [String]
}
