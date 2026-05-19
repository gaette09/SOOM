import XCTest
@testable import SOOM

final class RecoveryActivityMapperTests: XCTestCase {
    func testLocalWorkoutSnapshotMapsToRecoveryActivity() {
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = LocalWorkoutSnapshot(
            sport: .run,
            durationMinutes: 52,
            distanceKm: 10.4,
            averageHeartRate: 151,
            relativeEffort: 72,
            trainingLoad: 118,
            completedAt: completedAt
        )

        let activity = RecoveryActivityMapper().map(snapshot)

        XCTAssertEqual(activity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(activity.durationMinutes, 52)
        XCTAssertEqual(activity.distanceKm, 10.4, accuracy: 0.001)
        XCTAssertEqual(activity.averageHeartRate, 151)
        XCTAssertEqual(activity.relativeEffort, 72)
        XCTAssertEqual(activity.trainingLoad, 118, accuracy: 0.001)
        XCTAssertEqual(activity.completedAt, completedAt)
    }
}
