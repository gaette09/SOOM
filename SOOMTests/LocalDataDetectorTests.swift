import SwiftData
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

    func testHealthOnlyPresenceAllowsResetWithoutAddingMigrationTypes() async {
        let detector = LocalDataDetector(
            detectTrainingSettings: { false },
            detectWorkouts: { false },
            detectWorkoutRoutes: { false },
            detectCheckIns: { true },
            detectRecoverySnapshots: { true }
        )

        let presence = await detector.detect()

        XCTAssertTrue(presence.hasAnyData)
        XCTAssertTrue(presence.hasCheckIns)
        XCTAssertTrue(presence.hasRecoverySnapshots)
        XCTAssertTrue(presence.eligibleDataTypes.isEmpty)
        XCTAssertEqual(presence.totalDetectedTypes, 0, "Health reset availability must not change migration counts")
    }

    func testLiveDetectorFindsOldCheckInWhenItIsTheOnlyRemainingData() async throws {
        let fixture = try makeLiveFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = fixture.container.mainContext
        context.insert(CheckInRecord(
            date: Date(timeIntervalSince1970: 1_000_000),
            fatigueLevel: 3,
            sleepQuality: 2,
            muscleSoreness: 4,
            moodLevel: 3,
            note: "Test-only remaining note"
        ))
        try context.save()

        let detector = LocalDataDetector.live(
            modelContext: ModelContext(fixture.container),
            trainingSettingsStore: TrainingSettingsStore(userDefaults: fixture.defaults)
        )
        let presence = await detector.detect()

        XCTAssertTrue(presence.hasAnyData)
        XCTAssertTrue(presence.hasCheckIns)
        XCTAssertFalse(presence.hasRecoverySnapshots)
        XCTAssertFalse(presence.hasWorkouts)
        XCTAssertTrue(presence.eligibleDataTypes.isEmpty)
    }

    func testLiveDetectorFindsOldRecoverySnapshotWithoutWorkoutOrCheckIn() async throws {
        let fixture = try makeLiveFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = fixture.container.mainContext
        context.insert(DailyRecoverySnapshotRecord(
            date: Date(timeIntervalSince1970: 1_000_000),
            score: 62,
            status: "회복 필요",
            recommendation: "쉬기",
            coachMessage: "Test-only remaining snapshot",
            dataQuality: "estimated",
            activityCount: 0
        ))
        try context.save()

        let detector = LocalDataDetector.live(
            modelContext: ModelContext(fixture.container),
            trainingSettingsStore: TrainingSettingsStore(userDefaults: fixture.defaults)
        )
        let presence = await detector.detect()

        XCTAssertTrue(presence.hasAnyData)
        XCTAssertFalse(presence.hasCheckIns)
        XCTAssertTrue(presence.hasRecoverySnapshots)
        XCTAssertFalse(presence.hasWorkouts)
        XCTAssertTrue(presence.eligibleDataTypes.isEmpty)
    }

    func testOldSerializedPresenceDefaultsNewHealthFlagsToFalse() throws {
        let data = Data(#"{"hasTrainingSettings":false,"hasWorkouts":false,"hasWorkoutRoutes":false,"hasProgressionData":false}"#.utf8)

        let presence = try JSONDecoder().decode(LocalDataPresence.self, from: data)

        XCTAssertEqual(presence, .empty)
        XCTAssertFalse(presence.hasCheckIns)
        XCTAssertFalse(presence.hasRecoverySnapshots)
    }

    private func makeLiveFixture() throws -> (container: ModelContainer, defaults: UserDefaults, suiteName: String) {
        let schema = Schema([
            CheckInRecord.self,
            DailyRecoverySnapshotRecord.self,
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ])
        let configuration = ModelConfiguration(
            "LocalDataDetectorTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let suiteName = "LocalDataDetectorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (container, defaults, suiteName)
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
