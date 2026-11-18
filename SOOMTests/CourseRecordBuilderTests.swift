import XCTest
@testable import SOOM

final class CourseRecordBuilderTests: XCTestCase {
    private let builder = CourseRecordBuilder()

    func testRunningPacePRBuildsSupportiveRecord() {
        let current = input(type: .running, distance: 10, duration: 48)
        let previous = input(type: .running, distance: 10, duration: 52, daysAgo: 7)

        let record = builder.build(
            current: current, candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: previous)]
        )

        XCTAssertEqual(record.comparisonType, .bestPace)
        XCTAssertEqual(record.workoutId, current.id)
        XCTAssertEqual(record.bestMetric.title, "페이스")
        XCTAssertTrue(record.improvementValue?.contains("초") == true)
    }

    func testCyclingSpeedPRBuildsSupportiveRecord() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 27.4)
        let previous = input(type: .cycling, distance: 30, duration: 72, speed: 25.8, daysAgo: 7)

        let record = builder.build(
            current: current, candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: previous)]
        )

        XCTAssertEqual(record.comparisonType, .bestSpeed)
        XCTAssertEqual(record.bestMetric.title, "평균 속도")
        XCTAssertTrue(record.improvementValue?.contains("km/h") == true)
    }

    func testSwimmingPacePRBuildsHundredMeterRecord() {
        let current = input(type: .swimming, distance: 1.5, duration: 33)
        let previous = input(type: .swimming, distance: 1.5, duration: 36, daysAgo: 7)

        let record = builder.build(
            current: current, candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: previous)]
        )

        XCTAssertEqual(record.comparisonType, .bestPace)
        XCTAssertEqual(record.bestMetric.title, "100m 페이스")
        XCTAssertTrue(record.bestMetric.valueText.contains("/100m"))
    }

    func testInsufficientDataWhenNoComparableWorkout() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 27)
        let running = input(type: .running, distance: 10, duration: 50, daysAgo: 7)

        let record = builder.build(
            current: current, candidateWorkouts: [running],
            routeCandidates: [routeCandidate(current: current, previous: running)]
        )

        XCTAssertEqual(record.comparisonType, .insufficientData)
    }

    func testInsufficientDataWhenRouteCandidatesAreEmpty() {
        let current = input(type: .running, distance: 10, duration: 40)
        let previous = input(type: .running, distance: 10, duration: 50, daysAgo: 7)

        let record = builder.build(current: current, candidateWorkouts: [previous], routeCandidates: [])

        XCTAssertEqual(record.comparisonType, .insufficientData)
        XCTAssertNil(record.previousMetric)
        XCTAssertNil(record.improvementValue)
    }

    func testInsufficientDataWhenRouteCandidateIDsDoNotMatchWorkouts() {
        let current = input(type: .running, distance: 10, duration: 40)
        let previous = input(type: .running, distance: 10, duration: 50, daysAgo: 7)
        let unavailableMatch = input(type: .running, distance: 10, duration: 55, daysAgo: 14)

        let record = builder.build(
            current: current, candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: unavailableMatch)]
        )

        XCTAssertEqual(record.comparisonType, .insufficientData)
        XCTAssertNil(record.previousMetric)
        XCTAssertNil(record.improvementValue)
    }

    func testRunningPaceRoundedToZeroBuildsStableRecord() {
        let previous = input(type: .running, distance: 10, duration: 50, daysAgo: 7)

        for delta in [0, 0.4, -0.4] {
            let current = input(type: .running, distance: 3000 / (300 - delta), duration: 50)
            let record = builder.build(
                current: current, candidateWorkouts: [previous],
                routeCandidates: [routeCandidate(current: current, previous: previous)]
            )

            XCTAssertEqual(record.comparisonType, .stableRhythm)
            XCTAssertNil(record.improvementValue)
            XCTAssertEqual(record.bestMetric.detailText, "이 코스에서 이전과 비슷한 리듬을 이어갔어요.")
        }
    }

    func testSwimmingPaceRoundedToZeroPerHundredMetersBuildsStableRecord() {
        let previous = input(type: .swimming, distance: 1.5, duration: 30, daysAgo: 7)

        for delta in [0, 0.4, -0.4] {
            let current = input(type: .swimming, distance: 1800 / (1200 - delta * 10), duration: 30)
            let record = builder.build(
                current: current, candidateWorkouts: [previous],
                routeCandidates: [routeCandidate(current: current, previous: previous)]
            )

            XCTAssertEqual(record.comparisonType, .stableRhythm)
            XCTAssertNil(record.improvementValue)
            XCTAssertEqual(record.bestMetric.detailText, "이 코스에서 이전과 비슷한 리듬을 이어갔어요.")
        }
    }

    func testCyclingSpeedRoundedToZeroBuildsStableRecord() {
        let previous = input(type: .cycling, distance: 25, duration: 60, speed: 25, daysAgo: 7)

        for delta in [0, 0.04, -0.04] {
            let current = input(type: .cycling, distance: 25, duration: 60, speed: 25 + delta)
            let record = builder.build(
                current: current, candidateWorkouts: [previous],
                routeCandidates: [routeCandidate(current: current, previous: previous)]
            )

            XCTAssertEqual(record.comparisonType, .stableRhythm)
            XCTAssertNil(record.improvementValue)
            XCTAssertEqual(record.bestMetric.detailText, "비슷한 코스에서 이전과 비슷한 속도를 유지했어요.")
        }
    }

    func testRouteCandidatePrioritizesSameCourseBaseline() {
        let current = input(type: .cycling, distance: 30, duration: 70, speed: 27.5)
        let recent = input(type: .cycling, distance: 30, duration: 65, speed: 29, daysAgo: 1)
        let sameCourse = input(type: .cycling, distance: 30, duration: 70, speed: 25, daysAgo: 12)
        let routeCandidate = RouteComparisonCandidate(
            currentWorkoutId: current.id,
            candidateWorkoutId: sameCourse.id,
            similarityScore: 0.9,
            reason: .similarRoute
        )

        let record = builder.build(
            current: current,
            candidateWorkouts: [recent, sameCourse],
            routeCandidates: [routeCandidate]
        )

        XCTAssertEqual(record.previousMetric?.valueText, "25.0 km/h")
    }

    func testCopyAvoidsNegativeEvaluationWordsAndRecoveryCalculatorIsNotUsed() {
        let current = input(type: .cycling, distance: 30, duration: 75, speed: 24)
        let previous = input(type: .cycling, distance: 30, duration: 70, speed: 27, daysAgo: 7)

        let record = builder.build(
            current: current, candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: previous)]
        )
        let copy = [
            record.bestMetric.detailText,
            record.previousMetric?.detailText ?? "",
            record.improvementValue ?? ""
        ].joined(separator: " ")

        XCTAssertFalse(copy.contains("못"))
        XCTAssertFalse(copy.contains("실패"))
        XCTAssertFalse(copy.contains("나쁨"))
    }


    func testCourseIdentityIsUsedWhenProvided() {
        let current = input(type: .running, distance: 10, duration: 48)
        let previous = input(type: .running, distance: 10, duration: 52, daysAgo: 7)
        let identity = CourseIdentity(
            courseId: "course-v1-stable-test",
            identityVersion: 1,
            estimatedCenter: WorkoutRouteCoordinate(latitude: 37.5, longitude: 127.0),
            estimatedDistance: 10_000,
            estimatedDirection: .northbound,
            source: .generated
        )

        let record = builder.build(
            current: current,
            candidateWorkouts: [previous],
            routeCandidates: [routeCandidate(current: current, previous: previous)],
            courseIdentity: identity
        )

        XCTAssertEqual(record.courseId, identity.courseId)
    }

    private func routeCandidate(
        current: WorkoutGrowthInput,
        previous: WorkoutGrowthInput
    ) -> RouteComparisonCandidate {
        RouteComparisonCandidate(
            currentWorkoutId: current.id,
            candidateWorkoutId: previous.id,
            similarityScore: 0.9,
            reason: .similarRoute
        )
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
            startDate: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
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
