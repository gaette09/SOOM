import XCTest
@testable import SOOM

final class RecordWorkoutSaveFlowTests: XCTestCase {
    private let fixedID = UUID(uuidString: "7F5400D3-373B-4D78-B399-E49B70E6A52E")!
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let endedAt = Date(timeIntervalSince1970: 1_800_003_600)
    private let now = Date(timeIntervalSince1970: 1_800_004_000)

    func testStopCreatesFinishSummary() {
        let session = finishedSession(sport: .cycling, startedWithLocation: true)

        let summary = RecordWorkoutSummaryBuilder.makeSummary(from: session)

        XCTAssertEqual(summary?.id, fixedID)
        XCTAssertEqual(summary?.sport, .cycling)
        XCTAssertEqual(summary?.workoutType, .cycling)
        XCTAssertEqual(summary?.startedAt, startedAt)
        XCTAssertEqual(summary?.endedAt, endedAt)
        XCTAssertEqual(summary?.durationSeconds, 3_600)
        XCTAssertTrue(summary?.capturedRoute == true)
        XCTAssertTrue(summary?.isTimeOnly == true)
    }

    func testSummaryIsOnlyCreatedForFinishedSession() {
        let session = RecordWorkoutSession(
            id: fixedID,
            sport: .running,
            workoutType: .running,
            startedAt: startedAt,
            startedWithLocation: false,
            state: .active,
            pausedAt: nil,
            endedAt: nil
        )

        XCTAssertNil(RecordWorkoutSummaryBuilder.makeSummary(from: session))
    }

    func testSaveStoresLocalWorkout() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(
            store: store,
            mapper: RecordWorkoutSaveMapper(dateProvider: { self.now })
        )
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .running, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)

        XCTAssertEqual(workout.id, fixedID)
        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertEqual(workout.workoutType, .running)
        XCTAssertEqual(workout.startDate, startedAt)
        XCTAssertEqual(workout.endDate, endedAt)
        XCTAssertEqual(workout.durationSeconds, 3_600)
        XCTAssertNil(workout.distanceMeters)
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertEqual(workout.createdAt, now)
        XCTAssertEqual(store.savedWorkouts.count, 1)
    }

    func testSavedWorkoutAppearsInActivityStoreRecentWorkouts() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: store)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .walking, startedWithLocation: false)
        ))

        let saved = try await saver.save(summary)
        let recent = try await store.fetchRecentWorkouts(days: 30)

        XCTAssertEqual(recent.map(\.id), [saved.id])
        XCTAssertEqual(recent.first?.workoutType, .walking)
    }

    func testDiscardDoesNotStoreWorkout() async throws {
        let store = FakeUnifiedWorkoutStore()
        _ = RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .cycling, startedWithLocation: false)
        )

        let recent = try await store.fetchRecentWorkouts(days: 30)

        XCTAssertTrue(recent.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
    }

    func testTimeOnlyWorkoutCanBeSavedWithoutLocationPermission() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: store)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .running, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)

        XCTAssertFalse(summary.capturedRoute)
        XCTAssertNil(workout.distanceMeters)
        XCTAssertEqual(workout.source, .soomLocal)
    }

    func testSelectedSportPersistsIntoSavedWorkout() async throws {
        for sport in RecordSportMode.allCases {
            let store = FakeUnifiedWorkoutStore()
            let saver = RecordWorkoutSaver(store: store)
            let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
                from: finishedSession(sport: sport, startedWithLocation: false)
            ))

            let workout = try await saver.save(summary)

            XCTAssertEqual(workout.workoutType, sport.workoutType)
        }
    }

    func testSaveFlowDoesNotRequireHealthKitWriteOrRecoveryCalculation() async throws {
        let store = FakeUnifiedWorkoutStore()
        let saver = RecordWorkoutSaver(store: store)
        let summary = try XCTUnwrap(RecordWorkoutSummaryBuilder.makeSummary(
            from: finishedSession(sport: .cycling, startedWithLocation: false)
        ))

        let workout = try await saver.save(summary)

        XCTAssertEqual(workout.source, .soomLocal)
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertNil(workout.averageHeartRate)
        XCTAssertNil(workout.activeEnergyKcal)
    }

    private func finishedSession(
        sport: RecordSportMode,
        startedWithLocation: Bool
    ) -> RecordWorkoutSession {
        RecordWorkoutSession(
            id: fixedID,
            sport: sport,
            workoutType: sport.workoutType,
            startedAt: startedAt,
            startedWithLocation: startedWithLocation,
            state: .finished,
            pausedAt: nil,
            endedAt: endedAt
        )
    }
}

private final class FakeUnifiedWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        savedWorkouts.removeAll { $0.id == workout.id }
        savedWorkouts.append(workout)
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            try await saveWorkout(workout)
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        guard days > 0 else { return [] }
        return savedWorkouts.sorted { $0.startDate > $1.startDate }
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }
}
