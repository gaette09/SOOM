import XCTest
@testable import SOOM

final class PersonalWorkoutRankingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let builder = PersonalWorkoutRankingBuilder()

    func testUsesOnlySelectedSportAndIncludedCompletedRecords() {
        let valid = make(distance: 5000)
        let excluded = make(distance: 9000, excluded: true)
        let cycling = make(distance: 10000, sport: .cycling)
        let future = make(distance: 20000, offset: 3600)
        let result = builder.build(workouts: [valid, excluded, cycling, future], sport: .running, metric: .distance, referenceDate: now)
        XCTAssertEqual(result.map(\.id), [valid.id])
    }

    func testTiesUseDisplayedPrecisionAndCompetitionRanks() {
        let first = make(distance: 10004, offset: -9000)
        let tied = make(distance: 10001, offset: -10000)
        let third = make(distance: 9000)
        let rows = builder.build(workouts: [third, tied, first], sport: .running, metric: .distance, referenceDate: now)
        XCTAssertEqual(rows.map(\.rank), [1, 1, 3])
        XCTAssertEqual(rows.map(\.id), [first.id, tied.id, third.id])
        XCTAssertEqual(rows.first?.valueText, "10.00 km")
    }

    func testFastestPaceUsesPreciseSecondsAndAscendingOrder() {
        let slow = make(distance: 5000, duration: 1600)
        let fast = make(distance: 5000, duration: 1440)
        let rows = builder.build(workouts: [slow, fast], sport: .running, metric: .pace, referenceDate: now)
        XCTAssertEqual(rows.first?.id, fast.id)
        XCTAssertEqual(rows.first?.valueText, "4:48 /km")
    }

    func testSpeedUsesSameDistanceAndActiveDurationDefinition() {
        let cycling = make(distance: 30000, duration: 3600, sport: .cycling)
        let rows = builder.build(workouts: [cycling], sport: .cycling, metric: .speed, referenceDate: now)
        XCTAssertEqual(rows.first?.valueText, "30.0 km/h")
    }

    func testInvalidMeasurementsNeverCreateRanks() {
        let workouts = [
            make(distance: nil), make(distance: 0), make(distance: -.infinity),
            make(distance: .nan), make(distance: 5000, duration: 0),
            make(distance: 5000, duration: .nan)
        ]
        XCTAssertTrue(builder.build(workouts: workouts, sport: .running, metric: .pace, referenceDate: now).isEmpty)
    }

    func testLatestExcludedDuplicateIsNotResurrected() {
        let id = UUID()
        let old = make(id: id, distance: 5000, updatedOffset: -20)
        let latest = make(id: id, distance: 5000, excluded: true, updatedOffset: -10)
        XCTAssertTrue(builder.build(workouts: [old, latest], sport: .running, metric: .distance, referenceDate: now).isEmpty)
    }

    func testExternalDuplicateIsCountedOnceAndSourceIsPartOfIdentity() {
        let old = make(distance: 5000, externalID: "42", updatedOffset: -20)
        let latest = make(distance: 5100, externalID: "42", updatedOffset: -10)
        let otherSource = make(distance: 6000, externalID: "42", source: .appleHealthKit)
        let rows = builder.build(workouts: [old, latest, otherSource], sport: .running, metric: .distance, referenceDate: now)
        XCTAssertEqual(Set(rows.map(\.id)), Set([latest.id, otherSource.id]))
    }

    func testAllTimeDoesNotDropOlderThanTenYears() {
        let ancient = make(distance: 5000, offset: -400_000_000)
        XCTAssertEqual(builder.build(workouts: [ancient], sport: .running, metric: .distance, referenceDate: now).count, 1)
        XCTAssertTrue(builder.build(workouts: [ancient], sport: .running, metric: .distance, period: .recent90Days, referenceDate: now).isEmpty)
    }

    func testDistanceBandsHaveNoBoundaryOverlap() {
        XCTAssertTrue(PersonalWorkoutDistanceBand.under5.includes(4999))
        XCTAssertFalse(PersonalWorkoutDistanceBand.under5.includes(5000))
        XCTAssertTrue(PersonalWorkoutDistanceBand.from5to10.includes(5000))
        XCTAssertFalse(PersonalWorkoutDistanceBand.from5to10.includes(10000))
        XCTAssertTrue(PersonalWorkoutDistanceBand.from10to21.includes(10000))
        XCTAssertFalse(PersonalWorkoutDistanceBand.from10to21.includes(21100))
        XCTAssertTrue(PersonalWorkoutDistanceBand.from21.includes(21100))
    }

    func testUnsupportedSportMetricAndMissingElevationAreEmpty() {
        XCTAssertTrue(builder.build(workouts: [make(distance: 5000)], sport: .strength, metric: .pace, referenceDate: now).isEmpty)
        XCTAssertTrue(builder.build(workouts: [make(distance: 5000)], sport: .running, metric: .elevation, referenceDate: now).isEmpty)
    }

    func testShuffledInputHasStableTieOrder() {
        let a = make(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!, distance: 5000)
        let b = make(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!, distance: 5000)
        let first = builder.build(workouts: [a, b], sport: .running, metric: .distance, referenceDate: now)
        let second = builder.build(workouts: [b, a], sport: .running, metric: .distance, referenceDate: now)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.rank), [1, 1])
    }

    private func make(
        id: UUID = UUID(), distance: Double?, duration: Double = 1800,
        sport: UnifiedWorkoutType = .running, excluded: Bool = false,
        offset: TimeInterval = -10000, externalID: String? = nil,
        source: UnifiedDataSource = .soomLocal, updatedOffset: TimeInterval = -1
    ) -> UnifiedWorkout {
        let start = now.addingTimeInterval(offset)
        return UnifiedWorkout(
            id: id, externalId: externalID, source: source, workoutType: sport,
            startDate: start, endDate: start.addingTimeInterval(duration.isFinite ? max(0, duration) : 1800),
            durationSeconds: duration, distanceMeters: distance, activeEnergyKcal: nil,
            averageHeartRate: nil, maxHeartRate: nil, averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil, dataQuality: .complete, isExcludedFromAnalysis: excluded,
            createdAt: start, updatedAt: now.addingTimeInterval(updatedOffset)
        )
    }
}
