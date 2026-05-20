import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class RecoveryViewModelTests: XCTestCase {
    func testLoadsLatestCheckInWhenStoreHasData() async {
        let latestDate = Date(timeIntervalSince1970: 1_800_000_000)
        let olderDate = latestDate.addingTimeInterval(-86_400)
        let latestCheckIn = makeCheckIn(date: latestDate, fatigue: 2)
        let store = FakeCheckInStore(checkIns: [
            makeCheckIn(date: olderDate, fatigue: 4),
            latestCheckIn
        ])
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: .mockToday),
            checkInStore: store
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.latestCheckIn?.date, latestDate)
        XCTAssertEqual(viewModel.latestCheckIn?.fatigueLevel, latestCheckIn.fatigueLevel)
    }

    func testCheckInFailureDoesNotFailSummaryLoad() async {
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FailingCheckInStore()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertNil(viewModel.latestCheckIn)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCheckInPresenceDoesNotChangeSummaryScore() async {
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: [makeCheckIn(date: Date(), fatigue: 5)])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
    }

    func testMorningCheckInStateIsNotCheckedInTodayWhenThereIsNoTodayCheckIn() async {
        let expectedSummary = RecoverySummary.mockToday
        let yesterday = Date().addingTimeInterval(-86_400)
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: [makeCheckIn(date: yesterday, fatigue: 3)])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.morningCheckInState, .notCheckedInToday)
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testMorningCheckInStateIsCheckedInTodayWhenLatestCheckInIsToday() async {
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: [makeCheckIn(date: Date(), fatigue: 3)])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.morningCheckInState, .checkedInToday)
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testSkipMorningCheckInSetsSkippedTodayWithoutChangingScoreStatusOrRecommendation() async {
        let expectedSummary = RecoverySummary.mockToday
        let fixture = makeMorningSkipStore(now: { Date() })
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: []),
            morningCheckInSkipStore: fixture.store
        )

        await viewModel.load()
        viewModel.skipMorningCheckIn()

        XCTAssertEqual(viewModel.morningCheckInState, .skippedToday)
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
        fixture.cleanup()
    }

    func testCheckInPersonalizationIsAppliedToSummaryWithoutChangingScore() async {
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: [makeCheckIn(date: Date(), fatigue: 5)])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertTrue(viewModel.summary?.coachMessage.message.contains("피로감") == true)
        XCTAssertEqual(viewModel.summary?.insights.first?.title, "피로감이 높게 기록됐어요")
    }

    func testLoadsLatestCheckInFromSwiftDataStoreWithoutChangingScoreStatusOrRecommendation() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCheckInStore(modelContext: container.mainContext)
        let expectedSummary = RecoverySummary.mockToday
        let storedCheckIn = RecoveryCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_200),
            fatigueLevel: 5,
            sleepQuality: 3,
            muscleSoreness: 2,
            moodLevel: 4,
            note: "SwiftData 읽기 테스트"
        )
        try await store.saveCheckIn(storedCheckIn)

        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: store
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.latestCheckIn?.id, storedCheckIn.id)
        XCTAssertEqual(viewModel.latestCheckIn?.note, storedCheckIn.note)
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testRefreshAfterCheckInDeleteUsesNextLatestCheckInWithoutChangingScoreStatusOrRecommendation() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCheckInStore(modelContext: container.mainContext)
        let expectedSummary = RecoverySummary.mockToday
        let latestCheckIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_200),
            fatigue: 5
        )
        let nextLatestCheckIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_100),
            fatigue: 2,
            sleepQuality: 1
        )
        try await store.saveCheckIn(nextLatestCheckIn)
        try await store.saveCheckIn(latestCheckIn)

        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: store
        )

        await viewModel.load()
        try await store.deleteCheckIn(id: latestCheckIn.id)
        await viewModel.refreshCheckInPersonalization()

        XCTAssertEqual(viewModel.latestCheckIn?.id, nextLatestCheckIn.id)
        XCTAssertEqual(viewModel.summary?.coachMessage.message.contains("수면감"), true)
        XCTAssertEqual(viewModel.summary?.insights.first?.title, "수면감이 낮아요")
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testRefreshAfterLastCheckInDeleteClearsLatestCheckInWithoutChangingScoreStatusOrRecommendation() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCheckInStore(modelContext: container.mainContext)
        let expectedSummary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_200),
            fatigue: 5
        )
        try await store.saveCheckIn(checkIn)

        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: store
        )

        await viewModel.load()
        try await store.deleteCheckIn(id: checkIn.id)
        await viewModel.refreshCheckInPersonalization()

        XCTAssertNil(viewModel.latestCheckIn)
        XCTAssertEqual(viewModel.summary?.coachMessage.message, expectedSummary.coachMessage.message)
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testRefreshAfterCheckInEditUsesUpdatedPersonalizationWithoutChangingScoreStatusOrRecommendation() async throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCheckInStore(modelContext: container.mainContext)
        let expectedSummary = RecoverySummary.mockToday
        let checkIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_200),
            fatigue: 5,
            sleepQuality: 3
        )
        try await store.saveCheckIn(checkIn)

        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: store
        )

        await viewModel.load()

        let updatedCheckIn = RecoveryCheckIn(
            id: checkIn.id,
            date: checkIn.date,
            fatigueLevel: 2,
            sleepQuality: 1,
            muscleSoreness: 2,
            moodLevel: 4,
            note: "수면감 낮음"
        )
        try await store.updateCheckIn(updatedCheckIn)
        await viewModel.refreshCheckInPersonalization()

        XCTAssertEqual(viewModel.latestCheckIn?.id, checkIn.id)
        XCTAssertEqual(viewModel.latestCheckIn?.sleepQuality, 1)
        XCTAssertEqual(viewModel.summary?.coachMessage.message.contains("수면감"), true)
        XCTAssertEqual(viewModel.summary?.insights.first?.title, "수면감이 낮아요")
        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
    }

    func testLoadSavesTodaySnapshotAndRefreshesTimeline() async throws {
        let container = try makeSnapshotContainer()
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshotStore = SwiftDataDailyRecoverySnapshotStore(
            modelContext: container.mainContext,
            referenceDate: { referenceDate }
        )
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: []),
            timelineBuilder: RecoveryTimelineBuilder(snapshotStore: snapshotStore),
            snapshotWriter: DailyRecoverySnapshotWriter(
                snapshotStore: snapshotStore,
                referenceDate: { referenceDate }
            )
        )

        await viewModel.load()

        let snapshots = try await snapshotStore.fetchRecentSnapshots(days: 7)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.score, expectedSummary.score)
        XCTAssertEqual(snapshots.first?.status, expectedSummary.status)
        XCTAssertEqual(snapshots.first?.recommendation, expectedSummary.recommendation)
        XCTAssertEqual(viewModel.timelineEntries.count, 1)
        XCTAssertEqual(viewModel.timelineEntries.first?.recoveryScore, expectedSummary.score)
    }

    func testReloadUpsertsSameDaySnapshot() async throws {
        let container = try makeSnapshotContainer()
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshotStore = SwiftDataDailyRecoverySnapshotStore(
            modelContext: container.mainContext,
            referenceDate: { referenceDate }
        )
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: .mockToday),
            checkInStore: FakeCheckInStore(checkIns: []),
            timelineBuilder: RecoveryTimelineBuilder(snapshotStore: snapshotStore),
            snapshotWriter: DailyRecoverySnapshotWriter(
                snapshotStore: snapshotStore,
                referenceDate: { referenceDate }
            )
        )

        await viewModel.load()
        await viewModel.reload()

        let snapshots = try await snapshotStore.fetchRecentSnapshots(days: 7)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(viewModel.timelineEntries.count, 1)
    }

    func testSnapshotSaveFailureDoesNotFailSummaryLoad() async {
        let expectedSummary = RecoverySummary.mockToday
        let viewModel = RecoveryViewModel(
            provider: FixedRecoveryDataProvider(summary: expectedSummary),
            checkInStore: FakeCheckInStore(checkIns: []),
            timelineBuilder: RecoveryTimelineBuilder(snapshotStore: FailingDailyRecoverySnapshotStore()),
            snapshotWriter: DailyRecoverySnapshotWriter(snapshotStore: FailingDailyRecoverySnapshotStore())
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.summary?.score, expectedSummary.score)
        XCTAssertEqual(viewModel.summary?.status, expectedSummary.status)
        XCTAssertEqual(viewModel.summary?.recommendation, expectedSummary.recommendation)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeCheckIn(
        date: Date,
        fatigue: Int,
        sleepQuality: Int = 3,
        muscleSoreness: Int = 2,
        mood: Int = 4
    ) -> RecoveryCheckIn {
        RecoveryCheckIn(
            date: date,
            fatigueLevel: fatigue,
            sleepQuality: sleepQuality,
            muscleSoreness: muscleSoreness,
            moodLevel: mood,
            note: nil
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([CheckInRecord.self])
        let configuration = ModelConfiguration(
            "RecoveryViewModelTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func makeSnapshotContainer() throws -> ModelContainer {
        let schema = Schema([DailyRecoverySnapshotRecord.self])
        let configuration = ModelConfiguration(
            "RecoveryViewModelSnapshotTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func makeMorningSkipStore(
        now: @escaping () -> Date
    ) -> (store: MorningCheckInSkipStore, cleanup: () -> Void) {
        let suiteName = "RecoveryViewModelMorningSkipTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)

        return (
            MorningCheckInSkipStore(userDefaults: userDefaults, now: now),
            {
                userDefaults.removePersistentDomain(forName: suiteName)
            }
        )
    }
}

private struct FixedRecoveryDataProvider: RecoveryDataProvider {
    let summary: RecoverySummary

    func fetchRecoverySummary() async throws -> RecoverySummary {
        summary
    }
}

private struct FakeCheckInStore: RecoveryCheckInStore {
    let checkIns: [RecoveryCheckIn]

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        checkIns
    }
}

private struct FailingCheckInStore: RecoveryCheckInStore {
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        throw TestError.expectedFailure
    }
}

private struct FailingDailyRecoverySnapshotStore: DailyRecoverySnapshotStore {
    func saveSnapshot(_ snapshot: DailyRecoverySnapshot) async throws {
        throw TestError.expectedFailure
    }

    func fetchRecentSnapshots(days: Int) async throws -> [DailyRecoverySnapshot] {
        throw TestError.expectedFailure
    }

    func fetchSnapshot(for date: Date) async throws -> DailyRecoverySnapshot? {
        throw TestError.expectedFailure
    }

    func deleteSnapshot(id: UUID) async throws {
        throw TestError.expectedFailure
    }
}

private enum TestError: Error {
    case expectedFailure
}
