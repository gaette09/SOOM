import Foundation

struct ShareableWeeklyProgressCardModel: Equatable {
    let weekLabel: String
    let totalDistanceText: String
    let totalDurationText: String
    let workoutCountText: String
    let progressMessage: String
    let motivationText: String
    let footerText: String
    let visibility: ShareableWorkoutVisibility
}
