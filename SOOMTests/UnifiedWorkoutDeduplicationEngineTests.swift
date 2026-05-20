import XCTest
@testable import SOOM

final class UnifiedWorkoutDeduplicationEngineTests: XCTestCase {
    private let engine = UnifiedWorkoutDeduplicationEngine()

    func testSameSourceAndExternalIdCreatesHighConfidenceCandidate() {
        let externalId = "garmin-ride-001"
        let first = makeWorkout(source: .garmin, externalId: externalId)
        let second = makeWorkout(source: .garmin, externalId: externalId, startOffset: 30)

        let candidate = engine.compare(first, second)

        XCTAssertNotNil(candidate)
        XCTAssertGreaterThanOrEqual(candidate?.confidence ?? 0, 0.90)
        XCTAssertEqual(candidate?.resolutionPolicy, .keepPrimary)
        XCTAssertTrue(candidate?.reasons.contains("same externalId and source") == true)
    }

    func testGarminAndHealthKitSameWorkoutCreatesCandidate() {
        let garmin = makeWorkout(source: .garmin, type: .cycling)
        let healthKit = makeWorkout(
            source: .appleHealthKit,
            type: .cycling,
            startOffset: 120,
            durationSeconds: 3_680,
            distanceMeters: 40_800,
            averageHeartRate: 146
        )

        let candidate = engine.compare(garmin, healthKit)

        XCTAssertNotNil(candidate)
        XCTAssertGreaterThanOrEqual(candidate?.confidence ?? 0, 0.75)
        XCTAssertEqual(candidate?.preferredSource, .garmin)
        XCTAssertTrue(candidate?.reasons.contains("cross-source duplicate candidate") == true)
    }

    func testStartTimeTooDifferentDoesNotCreateCandidate() {
        let first = makeWorkout(startOffset: 0)
        let second = makeWorkout(startOffset: 20 * 60)

        XCTAssertNil(engine.compare(first, second))
    }

    func testDistanceDifferenceTooLargeDoesNotCreateCandidate() {
        let first = makeWorkout(distanceMeters: 40_000)
        let second = makeWorkout(distanceMeters: 55_000)

        XCTAssertNil(engine.compare(first, second))
    }

    func testManualSourceIsPreferredOverImportedSource() {
        let manual = makeWorkout(source: .manual, type: .running)
        let healthKit = makeWorkout(source: .appleHealthKit, type: .running, startOffset: 60)

        let candidate = engine.compare(healthKit, manual)

        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.preferredSource, .manual)
        XCTAssertEqual(candidate?.primaryWorkout.source, .manual)
    }

    func testConfidenceBelowThresholdIsExcludedFromCandidateList() {
        let first = makeWorkout(source: .garmin, type: .running, averageHeartRate: nil)
        let second = makeWorkout(
            source: .garmin,
            type: .running,
            externalId: "different-id",
            startOffset: 60,
            distanceMeters: nil,
            averageHeartRate: nil
        )

        let candidates = engine.findDuplicateCandidates(in: [first, second])

        XCTAssertTrue(candidates.isEmpty)
    }

    func testFindDuplicateCandidatesReturnsOnlyLikelyDuplicates() {
        let garmin = makeWorkout(source: .garmin, type: .cycling)
        let healthKitCopy = makeWorkout(source: .appleHealthKit, type: .cycling, startOffset: 90)
        let separateWorkout = makeWorkout(source: .appleHealthKit, type: .cycling, startOffset: 60 * 60)

        let candidates = engine.findDuplicateCandidates(in: [garmin, healthKitCopy, separateWorkout])

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.preferredSource, .garmin)
    }

    private func makeWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType = .cycling,
        externalId: String? = UUID().uuidString,
        baseDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        startOffset: TimeInterval = 0,
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 40_000,
        averageHeartRate: Double? = 144
    ) -> UnifiedWorkout {
        let startDate = baseDate.addingTimeInterval(startOffset)
        let endDate = startDate.addingTimeInterval(durationSeconds)

        return UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 620,
            averageHeartRate: averageHeartRate,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: endDate
        )
    }
}
