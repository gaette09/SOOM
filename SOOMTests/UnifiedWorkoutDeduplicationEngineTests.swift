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

    func testCanonicalGroupMergesCrossSourceCopiesAndKeepsAdditionalMetrics() {
        let apple = makeWorkout(source: .appleHealthKit, type: .cycling)
        let google = makeWorkout(source: .googleHealth, type: .cycling, startOffset: 15,
                                 durationSeconds: 3_590, distanceMeters: 40_100)
        let later = makeWorkout(source: .appleHealthKit, type: .cycling, startOffset: 7_200)
        let groups = engine.canonicalGroups([google, later, apple])

        XCTAssertEqual(groups.count, 2)
        let merged = try? XCTUnwrap(groups.first { $0.sourceWorkouts.count == 2 })
        XCTAssertEqual(Set(merged?.sourceWorkouts.map(\.id) ?? []), Set([google.id, apple.id]))
        XCTAssertEqual(merged?.workout.distanceMeters, 40_000)
    }

    func testCanonicalGroupKeepsSimilarButDifferentSessionsSeparate() {
        let first = makeWorkout(source: .appleHealthKit, type: .running, distanceMeters: 5_000)
        let differentDistance = makeWorkout(source: .googleHealth, type: .running,
                                            startOffset: 50, durationSeconds: 3_600, distanceMeters: 7_000)
        let manual = makeWorkout(source: .manual, type: .running, distanceMeters: 5_000)

        XCTAssertEqual(engine.canonicalWorkouts([first, differentDistance, manual]).count, 3)
    }

    func testUnconfirmedGroupKeepsMissingMetricUntilOwnerConfirms() {
        let apple = makeWorkout(source: .appleHealthKit, type: .running, distanceMeters: nil)
        let google = makeWorkout(source: .googleHealth, type: .running, distanceMeters: 5_000)
        let group = engine.canonicalGroups([apple, google]).first

        XCTAssertEqual(group?.sourceWorkouts.count, 2)
        XCTAssertNil(group?.workout.distanceMeters)
    }

    func testMatchingBoundariesWithoutSharedMetricsStillFormOneWorkout() {
        let first = makeWorkout(source: .appleHealthKit, type: .strength,
                                distanceMeters: nil, averageHeartRate: nil, activeEnergyKcal: nil)
        let second = makeWorkout(source: .googleHealth, type: .strength,
                                 distanceMeters: nil, averageHeartRate: nil, activeEnergyKcal: nil)

        XCTAssertEqual(engine.canonicalWorkouts([first, second]).count, 1)
    }

    func testSeptemberThirtyRunIsReviewCandidateButNeverAutomaticallyMerged() {
        let local = makeWorkout(source: .soomLocal, type: .running, durationSeconds: 4_380, distanceMeters: 11_250)
        let watch = makeWorkout(source: .appleHealthKit, type: .running, startOffset: 240,
            durationSeconds: 4_140, distanceMeters: 10_030)
        XCTAssertNotNil(engine.compare(local, watch))
        XCTAssertFalse(engine.isSameActivity(local, watch))
        XCTAssertEqual(engine.canonicalWorkouts([local, watch]).count, 2)
    }

    func testExplicitWatchChoiceKeepsItsDistanceAndTimeAcrossThreeDevices() {
        var local = makeWorkout(source: .soomLocal, type: .running, durationSeconds: 4_380, distanceMeters: 11_250)
        var watch = makeWorkout(source: .appleHealthKit, type: .running, startOffset: 240,
            durationSeconds: 4_140, distanceMeters: 10_030)
        var garmin = makeWorkout(source: .garmin, type: .running, startOffset: 200,
            durationSeconds: 4_180, distanceMeters: 10_050)
        for index in 0..<3 {
            switch index { case 0: local.preferredWorkoutID = watch.id; case 1: watch.preferredWorkoutID = watch.id; default: garmin.preferredWorkoutID = watch.id }
        }
        let groups = engine.canonicalGroups([garmin, local, watch])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceWorkouts.count, 3)
        XCTAssertEqual(groups.first?.workout.id, watch.id)
        XCTAssertEqual(groups.first?.workout.distanceMeters, 10_030)
        XCTAssertEqual(groups.first?.workout.durationSeconds, 4_140)
        XCTAssertEqual(groups.first?.workout.averageSpeedMetersPerSecond ?? 0, 10_030 / 4_140, accuracy: 0.0001)
        XCTAssertNil(engine.compare(local, watch))
    }

    func testKeepSeparateOverridesAutomaticGroupingAndFutureReview() {
        var a = makeWorkout(source: .soomLocal, type: .running, distanceMeters: 10_000)
        var b = makeWorkout(source: .appleHealthKit, type: .running, distanceMeters: 10_000)
        a.keepSeparate = true
        b.keepSeparate = true
        XCTAssertEqual(engine.canonicalWorkouts([a, b]).count, 2)
        XCTAssertNil(engine.compare(a, b))
    }

    func testPublicationRequiresSourceChoiceRegardlessOfArrivalOrder() {
        var local = makeWorkout(source: .soomLocal, type: .running, durationSeconds: 4_380, distanceMeters: 11_250)
        var watch = makeWorkout(source: .appleHealthKit, type: .running, startOffset: 240,
            durationSeconds: 4_140, distanceMeters: 10_030)
        XCTAssertTrue(engine.needsSourceSelectionBeforePublication(local, in: [watch, local]))
        XCTAssertTrue(engine.needsSourceSelectionBeforePublication(watch, in: [local, watch]))
        watch.preferredWorkoutID = watch.id
        local.preferredWorkoutID = watch.id
        XCTAssertFalse(engine.needsSourceSelectionBeforePublication(watch, in: [local, watch]))
        XCTAssertTrue(engine.needsSourceSelectionBeforePublication(local, in: [local, watch]))
        watch.resolutionRequestID = UUID()
        XCTAssertTrue(engine.needsSourceSelectionBeforePublication(watch, in: [local, watch]))
        local.preferredWorkoutID = nil
        watch.preferredWorkoutID = nil
        watch.resolutionRequestID = nil
        local.keepSeparate = true
        watch.keepSeparate = true
        XCTAssertFalse(engine.needsSourceSelectionBeforePublication(local, in: [watch, local]))
        XCTAssertFalse(engine.needsSourceSelectionBeforePublication(watch, in: [local, watch]))
    }

    func testProvenanceDistinguishesSinglePendingAndConfirmedWithMissingHeartRate() throws {
        var phone = makeWorkout(source: .soomLocal, type: .running, distanceMeters: 5000, averageHeartRate: nil)
        var watch = makeWorkout(source: .appleHealthKit, type: .running, distanceMeters: 5100, averageHeartRate: 150)
        watch.deviceName = "Apple Watch"
        let single = UnifiedWorkoutProvenance(group: try XCTUnwrap(engine.canonicalGroups([phone]).first))
        XCTAssertTrue(single.status.contains("수집 원본 1건"))
        let pending = UnifiedWorkoutProvenance(group: try XCTUnwrap(engine.canonicalGroups([phone, watch]).first))
        XCTAssertTrue(pending.status.contains("병합 확인 전"))
        XCTAssertNil(pending.group.workout.averageHeartRate)
        XCTAssertNil(pending.source(for: \.averageHeartRate))
        phone.preferredWorkoutID = phone.id; watch.preferredWorkoutID = phone.id
        let confirmed = UnifiedWorkoutProvenance(group: try XCTUnwrap(engine.canonicalGroups([watch, phone]).first))
        XCTAssertTrue(confirmed.isConfirmed)
        XCTAssertEqual(confirmed.group.workout.distanceMeters, 5000)
        XCTAssertEqual(confirmed.group.workout.averageHeartRate, 150)
        XCTAssertEqual(confirmed.source(for: \.distanceMeters)?.id, phone.id)
        XCTAssertEqual(confirmed.source(for: \.averageHeartRate)?.id, watch.id)
        XCTAssertNil(phone.averageHeartRate)
        XCTAssertEqual(watch.distanceMeters, 5100)
        XCTAssertEqual(Set(confirmed.group.sourceWorkouts.map(\.id)), Set([phone.id, watch.id]))
        XCTAssertEqual(confirmed.group.workout, engine.canonicalGroups([phone, watch]).first?.workout)
    }

    func testUnknownHealthKitDeviceIsNeverAssumedToBeWatch() {
        let apple = makeWorkout(source: .appleHealthKit)
        XCTAssertEqual(apple.recordingSourceLabel, "Apple 건강 · 기기 미확인")
        XCTAssertEqual(makeWorkout(source: .soomLocal).recordingSourceLabel, "SOOM iPhone")
        var garmin = makeWorkout(source: .garmin)
        garmin.deviceName = "Garmin Watch"
        XCTAssertEqual(garmin.recordingSourceLabel, "Garmin Watch · garmin")
        var otherWatch = apple
        otherWatch.deviceName = "Galaxy Watch"
        XCTAssertEqual(otherWatch.recordingSourceLabel, "Galaxy Watch · appleHealthKit")
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
        averageHeartRate: Double? = 144,
        activeEnergyKcal: Double? = 620
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
            activeEnergyKcal: activeEnergyKcal,
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
