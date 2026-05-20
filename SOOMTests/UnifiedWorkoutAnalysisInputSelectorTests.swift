import XCTest
@testable import SOOM

final class UnifiedWorkoutAnalysisInputSelectorTests: XCTestCase {
    private let selector = UnifiedWorkoutAnalysisInputSelector()

    func testSelectIncludedWorkoutsRemovesExcludedWorkouts() {
        let included = makeWorkout(id: UUID(), type: .running)
        let excluded = makeWorkout(id: UUID(), type: .cycling, isExcluded: true)

        let selected = selector.selectIncludedWorkouts([included, excluded])

        XCTAssertEqual(selected, [included])
    }

    func testSelectIncludedWorkoutsKeepsIncludedWorkouts() {
        let running = makeWorkout(id: UUID(), type: .running)
        let swimming = makeWorkout(id: UUID(), type: .swimming)

        let selected = selector.selectIncludedWorkouts([running, swimming])

        XCTAssertEqual(selected, [running, swimming])
    }

    func testSelectRecoveryInputsExcludesExcludedWorkoutsBeforeMapping() {
        let included = makeWorkout(id: UUID(), type: .cycling, distanceMeters: 41_700)
        let excluded = makeWorkout(id: UUID(), type: .running, distanceMeters: 10_000, isExcluded: true)

        let recoveryInputs = selector.selectRecoveryInputs(from: [included, excluded])

        XCTAssertEqual(recoveryInputs.count, 1)
        XCTAssertEqual(recoveryInputs.first?.workoutType, .ride)
        XCTAssertEqual(recoveryInputs.first?.distanceKm ?? 0, 41.7, accuracy: 0.01)
    }

    func testSelectGrowthInputsExcludesExcludedWorkoutsBeforeMapping() {
        let included = makeWorkout(id: UUID(), type: .running, distanceMeters: 10_000)
        let excluded = makeWorkout(id: UUID(), type: .swimming, distanceMeters: 1_500, isExcluded: true)

        let growthInputs = selector.selectGrowthInputs(from: [included, excluded])

        XCTAssertEqual(growthInputs.count, 1)
        XCTAssertEqual(growthInputs.first?.id, included.id)
        XCTAssertEqual(growthInputs.first?.workoutType, .running)
    }

    func testAllExcludedWorkoutsReturnEmptyInputs() {
        let workouts = [
            makeWorkout(id: UUID(), type: .running, isExcluded: true),
            makeWorkout(id: UUID(), type: .cycling, isExcluded: true)
        ]

        XCTAssertTrue(selector.selectIncludedWorkouts(workouts).isEmpty)
        XCTAssertTrue(selector.selectRecoveryInputs(from: workouts).isEmpty)
        XCTAssertTrue(selector.selectGrowthInputs(from: workouts).isEmpty)
    }

    func testSelectorPreservesOriginalOrderOfIncludedWorkouts() {
        let first = makeWorkout(id: UUID(), type: .running)
        let excluded = makeWorkout(id: UUID(), type: .cycling, isExcluded: true)
        let second = makeWorkout(id: UUID(), type: .swimming)

        let selected = selector.selectIncludedWorkouts([first, excluded, second])

        XCTAssertEqual(selected.map(\.id), [first.id, second.id])
    }

    func testSelectorDoesNotCallRecoveryCalculatorOrGrowthSummaryBuilder() {
        let workout = makeWorkout(id: UUID(), type: .running)

        let recoveryInputs = selector.selectRecoveryInputs(from: [workout])
        let growthInputs = selector.selectGrowthInputs(from: [workout])

        XCTAssertEqual(recoveryInputs.count, 1)
        XCTAssertEqual(growthInputs.count, 1)
    }

    private func makeWorkout(
        id: UUID,
        type: UnifiedWorkoutType,
        distanceMeters: Double? = 10_000,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let endDate = startDate.addingTimeInterval(45 * 60)

        return UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: .appleHealthKit,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 45 * 60,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 420,
            averageHeartRate: 148,
            maxHeartRate: 170,
            averageSpeedMetersPerSecond: 3.7,
            elevationGainMeters: 64,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}
