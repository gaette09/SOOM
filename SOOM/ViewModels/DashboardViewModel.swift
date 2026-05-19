import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var workouts: [Workout]
    @Published private(set) var monthlySnapshot: MonthlySnapshot

    init(harness: WorkoutHarness) {
        self.workouts = harness.loadWorkouts()
        self.monthlySnapshot = harness.loadMonthlySnapshot()
    }

    var recentWorkouts: [Workout] {
        Array(workouts.prefix(4))
    }
}
