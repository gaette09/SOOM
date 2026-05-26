import XCTest
@testable import SOOM

@MainActor
final class LocalDataDetectorTests: XCTestCase {
    func testNoLocalDataBuildsEmptyPresence() async {
        let presence = await makeDetector().detect()

        XCTAssertFalse(presence.hasAnyData)
        XCTAssertEqual(presence.totalDetectedTypes, 0)
        XCTAssertTrue(presence.eligibleDataTypes.isEmpty)
    }

    func testSettingsOnlyPresenceMapsToTrainingSettings() async {
        let presence = await makeDetector(hasTrainingSettings: true).detect()

        XCTAssertTrue(presence.hasTrainingSettings)
        XCTAssertEqual(presence.totalDetectedTypes, 1)
        XCTAssertEqual(presence.eligibleDataTypes, [.trainingSettings])
    }

    func testWorkoutOnlyPresenceMapsToWorkouts() async {
        let presence = await makeDetector(hasWorkouts: true).detect()

        XCTAssertTrue(presence.hasWorkouts)
        XCTAssertEqual(presence.totalDetectedTypes, 1)
        XCTAssertEqual(presence.eligibleDataTypes, [.workouts])
    }

    func testRoutesOnlyPresenceMapsToRoutesAndCourseIdentities() async {
        let presence = await makeDetector(hasWorkoutRoutes: true).detect()

        XCTAssertTrue(presence.hasWorkoutRoutes)
        XCTAssertEqual(presence.totalDetectedTypes, 1)
        XCTAssertEqual(presence.eligibleDataTypes, [.workoutRoutes, .courseIdentities])
    }

    func testMixedPresenceMapsDetectedTypesOnly() async {
        let presence = await makeDetector(
            hasTrainingSettings: true,
            hasWorkouts: true,
            hasWorkoutRoutes: true,
            hasProgressionData: true
        ).detect()

        XCTAssertTrue(presence.hasAnyData)
        XCTAssertEqual(presence.totalDetectedTypes, 4)
        XCTAssertEqual(
            presence.eligibleDataTypes,
            [.trainingSettings, .workouts, .workoutRoutes, .courseIdentities, .progressionSummaries]
        )
    }

    func testDetectionFailureFallsBackToFalseWithoutMutation() async {
        var workoutCheckCount = 0
        let detector = LocalDataDetector(
            detectTrainingSettings: { false },
            detectWorkouts: {
                workoutCheckCount += 1
                throw SampleError.failed
            },
            detectWorkoutRoutes: { false },
            detectProgressionData: { false }
        )

        let presence = await detector.detect()

        XCTAssertEqual(workoutCheckCount, 1)
        XCTAssertFalse(presence.hasAnyData)
    }

    func testDetectorDoesNotUseRecoveryCalculator() async {
        let presence = await makeDetector(hasWorkouts: true).detect()

        XCTAssertTrue(presence.hasAnyData)
    }

    private func makeDetector(
        hasTrainingSettings: Bool = false,
        hasWorkouts: Bool = false,
        hasWorkoutRoutes: Bool = false,
        hasProgressionData: Bool = false
    ) -> LocalDataDetector {
        LocalDataDetector(
            detectTrainingSettings: { hasTrainingSettings },
            detectWorkouts: { hasWorkouts },
            detectWorkoutRoutes: { hasWorkoutRoutes },
            detectProgressionData: { hasProgressionData }
        )
    }

    private enum SampleError: Error {
        case failed
    }
}
