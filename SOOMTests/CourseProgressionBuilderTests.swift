import XCTest
@testable import SOOM

final class CourseProgressionBuilderTests: XCTestCase {
    private let builder = CourseProgressionBuilder()

    func testRunningProgressionBuildsImprovingDirection() {
        let current = input(type: .running, distance: 10, duration: 48, daysAgo: 0)
        let older = input(type: .running, distance: 10, duration: 54, daysAgo: 21)
        let middle = input(type: .running, distance: 10, duration: 51, daysAgo: 14)
        let recent = input(type: .running, distance: 10, duration: 50, daysAgo: 7)

        let timeline = builder.build(current: current, candidateWorkouts: [older, middle, recent])

        XCTAssertEqual(timeline.direction, .improving)
        XCTAssertEqual(timeline.points.count, 4)
        XCTAssertEqual(timeline.points.last?.workoutId, current.id)
        XCTAssertEqual(timeline.points.last?.comparisonMetric, .pace)
    }

    func testCyclingProgressionBuildsStableDirection() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 25.4)
        let older = input(type: .cycling, distance: 30, duration: 71, speed: 25.0, daysAgo: 21)
        let middle = input(type: .cycling, distance: 30, duration: 70, speed: 25.2, daysAgo: 14)
        let recent = input(type: .cycling, distance: 30, duration: 70, speed: 25.1, daysAgo: 7)

        let timeline = builder.build(current: current, candidateWorkouts: [older, middle, recent])

        XCTAssertEqual(timeline.direction, .stable)
        XCTAssertEqual(timeline.points.last?.comparisonMetric, .averageSpeed)
    }

    func testProgressionBuildsFluctuatingDirection() {
        let current = input(type: .running, distance: 10, duration: 52, daysAgo: 0)
        let older = input(type: .running, distance: 10, duration: 50, daysAgo: 28)
        let lighter = input(type: .running, distance: 10, duration: 55, daysAgo: 21)
        let improved = input(type: .running, distance: 10, duration: 49, daysAgo: 14)
        let steady = input(type: .running, distance: 10, duration: 51, daysAgo: 7)

        let timeline = builder.build(current: current, candidateWorkouts: [older, lighter, improved, steady])

        XCTAssertEqual(timeline.direction, .fluctuating)
        XCTAssertTrue(timeline.summary.contains("흐름"))
    }

    func testInsufficientDataWhenComparableRecordsAreMissing() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 26)
        let running = input(type: .running, distance: 10, duration: 50, daysAgo: 7)

        let timeline = builder.build(current: current, candidateWorkouts: [running])

        XCTAssertEqual(timeline.direction, .insufficientData)
        XCTAssertTrue(timeline.points.isEmpty)
    }

    func testRouteIdentityAndRouteCandidatesScopeProgression() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 27)
        let sameCourse = input(type: .cycling, distance: 30, duration: 74, speed: 24, daysAgo: 14)
        let sameDistanceDifferentRoute = input(type: .cycling, distance: 30, duration: 68, speed: 29, daysAgo: 7)
        let identity = CourseIdentity(
            courseId: "course-v1-progression-test",
            identityVersion: 1,
            estimatedCenter: WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
            estimatedDistance: 30_000,
            estimatedDirection: .eastbound,
            source: .generated
        )
        let routeCandidate = RouteComparisonCandidate(
            currentWorkoutId: current.id,
            candidateWorkoutId: sameCourse.id,
            similarityScore: 0.91,
            reason: .similarRoute
        )

        let timeline = builder.build(
            current: current,
            candidateWorkouts: [sameCourse, sameDistanceDifferentRoute],
            routeCandidates: [routeCandidate],
            courseIdentity: identity
        )

        XCTAssertEqual(timeline.courseId, identity.courseId)
        XCTAssertEqual(timeline.points.map(\.workoutId), [sameCourse.id, current.id])
        XCTAssertEqual(timeline.points.first?.routeSimilarityScore, routeCandidate.similarityScore)
    }

    func testCopyAvoidsNegativeEvaluationWordsAndRecoveryCalculatorIsNotUsed() {
        let current = input(type: .swimming, distance: 1.5, duration: 34)
        let previous = input(type: .swimming, distance: 1.5, duration: 36, daysAgo: 7)

        let timeline = builder.build(current: current, candidateWorkouts: [previous])
        let copy = timeline.summary

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("실패"))
        XCTAssertFalse(copy.contains("나쁨"))
        XCTAssertEqual(timeline.points.last?.comparisonMetric, .pace)
    }

    private func input(
        type: UnifiedWorkoutType,
        distance: Double,
        duration: Int,
        speed: Double? = nil,
        daysAgo: Int = 0
    ) -> WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: UUID(),
            source: .appleHealthKit,
            workoutType: type,
            startDate: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            durationMinutes: duration,
            distanceKm: distance,
            averagePaceText: nil,
            averageSpeedKmh: speed,
            averageHeartRate: nil,
            elevationGainMeters: nil,
            activeEnergyKcal: nil
        )
    }
}
