import XCTest
import SwiftData
@testable import SOOM

@MainActor
final class HealthKitWorkoutImportViewModelTests: XCTestCase {
    func testProfileModeRemovesLegacyPublishConfirmationAndKeepsSourceImportMeaning() async throws {
        let storage=try HealthAccountStorageController(inMemory:true,monitorNetwork:false,automaticallySync:false)
        try storage.switchAccount(userID:UUID());storage.setAutoPublishImportedWorkouts(true)
        let pipeline=FakeHealthKitWorkoutImportPipeline(result:.success(importedWorkouts:[],fetchedCount:0))
        let model=HealthKitWorkoutImportViewModel(pipeline:pipeline,publication:ImportedWorkoutPublication(context:storage.container.mainContext,storage:storage))
        XCTAssertEqual(model.willAutoPublish,ImportedWorkoutPublication.usesLegacyPublication)
        if !ImportedWorkoutPublication.usesLegacyPublication {
            XCTAssertEqual(model.importSharingDescription,ImportedWorkoutPublication.profileImportDescription)
            XCTAssertFalse(model.importSharingDescription.contains("개별"))
            await model.retryPublication();XCTAssertNil(model.publicationResult)
        }
        await model.importRecentWorkouts();XCTAssertEqual(model.lastResult?.fetchedCount,0)
    }
    func testAutomaticImportRequiresPriorAppleUseOrAccountOptIn() async throws {
        let storage = try HealthAccountStorageController(inMemory: true, monitorNetwork: false,
            automaticallySync: false)
        try storage.switchAccount(userID: UUID())
        let key = "SOOM.healthKitAutoImport.\(storage.scopeID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertFalse(HealthKitAutomaticImport.isEnabled(for: storage))
        try await SwiftDataUnifiedWorkoutStore(modelContext: storage.container.mainContext)
            .saveWorkout(makeUnifiedWorkout(type: .running))
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(HealthKitAutomaticImport.isEnabled(for: storage))
        HealthKitAutomaticImport.setEnabled(false, for: storage)
        XCTAssertFalse(HealthKitAutomaticImport.isEnabled(for: storage))
    }

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

    func testAutomaticSequenceCheckpointsAllBatchesBeforePublication() async {
        var events: [String] = []
        await HealthKitAutomaticImportSequence.run(isCurrent: { true }, importAndCheckpoint: {
            for batch in 1...3 { events.append("save\(batch)"); events.append("anchor\(batch)") }
            return true
        }, publishPending: { events.append("publish") })
        XCTAssertEqual(events, ["save1", "anchor1", "save2", "anchor2", "save3", "anchor3", "publish"])
    }

    func testAutomaticSequencePublicationFailureDoesNotRollBackAnchorOrBlockNextImport() async {
        var anchor = 0
        var pending = 0
        var attempts = 0
        for _ in 0..<2 {
            await HealthKitAutomaticImportSequence.run(isCurrent: { true }, importAndCheckpoint: {
                anchor += 1; pending += 1
                return true
            }, publishPending: {
                attempts += 1 // failed remote delivery leaves durable markers untouched
            })
        }
        XCTAssertEqual(anchor, 2)
        XCTAssertEqual(pending, 2)
        XCTAssertEqual(attempts, 2)
        await HealthKitAutomaticImportSequence.run(isCurrent: { true }, importAndCheckpoint: {
            true // a later empty observer batch still retries prior pending items
        }, publishPending: { pending = 0 })
        XCTAssertEqual(anchor, 2)
        XCTAssertEqual(pending, 0)
    }

    func testAutomaticSequenceLocalFailureDoesNotPublish() async {
        var published = false
        await HealthKitAutomaticImportSequence.run(isCurrent: { true },
            importAndCheckpoint: { false }, publishPending: { published = true })
        XCTAssertFalse(published)
    }

    func testAutomaticSequenceChangedAccountDoesNotPublish() async {
        var current = true
        var published = false
        await HealthKitAutomaticImportSequence.run(isCurrent: { current }, importAndCheckpoint: {
            current = false
            return true
        }, publishPending: { published = true })
        XCTAssertFalse(published)
    }

    func testAutomaticSequenceInactiveAccountDoesNotImportOrPublish() async {
        var imported = false
        var published = false
        await HealthKitAutomaticImportSequence.run(isCurrent: { false }, importAndCheckpoint: {
            imported = true; return true
        }, publishPending: { published = true })
        XCTAssertFalse(imported)
        XCTAssertFalse(published)
    }

    func testAutomaticSequenceCancellationAfterImportDoesNotPublish() async {
        var published = false
        let task = Task {
            await HealthKitAutomaticImportSequence.run(isCurrent: { true }, importAndCheckpoint: {
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }, publishPending: { published = true })
        }
        await task.value
        XCTAssertFalse(published)
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

final class HealthKitAutomaticHistoryPlanTests: XCTestCase {
    func testExistingChoiceRetainsNinetyDayNamespaceAndWindow() {
        let now=Date(timeIntervalSince1970:1_800_000_000)
        let plan=HealthKitAutomaticHistoryPlan(scope:"owner",authorizedSince:nil,now:now)
        XCTAssertEqual(plan.anchorKey,"SOOM.healthKitWorkoutAnchorV2.owner")
        XCTAssertEqual(plan.cutoff,now.addingTimeInterval(-90*86_400))
    }
    func testFullHistoryHasStableSeparateCheckpointAndIncludesOlderRecords() {
        let since=Date(timeIntervalSince1970:0)
        let first=HealthKitAutomaticHistoryPlan(scope:"owner",authorizedSince:since,now:Date())
        let resumed=HealthKitAutomaticHistoryPlan(scope:"owner",authorizedSince:since,now:Date().addingTimeInterval(86400))
        XCTAssertEqual(first,resumed)
        XCTAssertEqual(first.cutoff,since)
        XCTAssertNotEqual(first.anchorKey,HealthKitAutomaticHistoryPlan(scope:"owner",authorizedSince:nil).anchorKey)
    }
    func testOwnerAndAuthorizedLowerBoundCannotReuseOtherAnchor() {
        let a=HealthKitAutomaticHistoryPlan(scope:"a",authorizedSince:Date(timeIntervalSince1970:0))
        let b=HealthKitAutomaticHistoryPlan(scope:"b",authorizedSince:Date(timeIntervalSince1970:0))
        let changed=HealthKitAutomaticHistoryPlan(scope:"a",authorizedSince:Date(timeIntervalSince1970:100))
        XCTAssertNotEqual(a.anchorKey,b.anchorKey);XCTAssertNotEqual(a.anchorKey,changed.anchorKey)
    }
}
