import XCTest
@testable import SOOM

@MainActor
final class HealthKitWorkoutImportViewModelTests: XCTestCase {
    func testImportSuccessSetsLastResult() async {
        let result = HealthKitWorkoutImportResult.success(
            importedWorkouts: [
                makeUnifiedWorkout(type: .running),
                makeUnifiedWorkout(type: .cycling)
            ],
            fetchedCount: 2
        )
        let pipeline = FakeHealthKitWorkoutImportPipeline(result: result)
        let viewModel = HealthKitWorkoutImportViewModel(pipeline: pipeline, limit: 12)

        await viewModel.importRecentWorkouts()

        XCTAssertEqual(viewModel.lastResult, result)
        XCTAssertEqual(pipeline.requestedLimit, 12)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isImporting)
    }

    func testEmptyImportKeepsEmptySuccessResult() async {
        let result = HealthKitWorkoutImportResult.success(
            importedWorkouts: [],
            fetchedCount: 0
        )
        let viewModel = HealthKitWorkoutImportViewModel(
            pipeline: FakeHealthKitWorkoutImportPipeline(result: result)
        )

        await viewModel.importRecentWorkouts()

        XCTAssertEqual(viewModel.lastResult?.fetchedCount, 0)
        XCTAssertEqual(viewModel.lastResult?.savedCount, 0)
        XCTAssertEqual(viewModel.lastResult?.failedCount, 0)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testImportFailureSetsErrorMessageAndFailedResult() async {
        let result = HealthKitWorkoutImportResult.failure(
            message: "HealthKit 운동 기록을 가져오지 못했어요."
        )
        let viewModel = HealthKitWorkoutImportViewModel(
            pipeline: FakeHealthKitWorkoutImportPipeline(result: result)
        )

        await viewModel.importRecentWorkouts()

        XCTAssertEqual(viewModel.lastResult, result)
        XCTAssertEqual(viewModel.errorMessage, result.message)
        XCTAssertFalse(viewModel.isImporting)
    }

    func testImportingStateChangesDuringImport() async {
        let pipeline = FakeHealthKitWorkoutImportPipeline(
            result: .success(importedWorkouts: [makeUnifiedWorkout(type: .swimming)], fetchedCount: 1),
            delayNanoseconds: 50_000_000
        )
        let viewModel = HealthKitWorkoutImportViewModel(pipeline: pipeline)

        let task = Task {
            await viewModel.importRecentWorkouts()
        }
        await Task.yield()

        XCTAssertTrue(viewModel.isImporting)

        await task.value
        XCTAssertFalse(viewModel.isImporting)
        XCTAssertEqual(viewModel.lastResult?.savedCount, 1)
    }

    private func makeUnifiedWorkout(
        id: UUID = UUID(),
        type: UnifiedWorkoutType,
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: .appleHealthKit,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 10_000,
            activeEnergyKcal: 520,
            averageHeartRate: 148,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: 2.8,
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}

private final class FakeHealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    private let result: HealthKitWorkoutImportResult
    private let delayNanoseconds: UInt64
    private(set) var requestedLimit: Int?

    init(
        result: HealthKitWorkoutImportResult,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult {
        requestedLimit = limit

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return result
    }
}
