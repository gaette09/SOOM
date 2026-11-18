import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class LocalAccountDataEraserTests: XCTestCase {
    func testEraseAllCallsEveryStoreErasureClosure() async {
        var workoutsErased = false
        var routesErased = false
        var draftsErased = false
        var checkInsErased = false
        var recoverySnapshotsErased = false
        var trainingSettingsErased = false
        var clubDataErased = false
        var deviceTokenErased = false
        var checkInSkipErased = false

        let eraser = LocalAccountDataEraser(
            eraseWorkouts: { workoutsErased = true },
            eraseWorkoutRoutes: { routesErased = true },
            eraseFeedDrafts: { draftsErased = true },
            eraseCheckIns: { checkInsErased = true },
            eraseRecoverySnapshots: { recoverySnapshotsErased = true },
            eraseTrainingSettings: { trainingSettingsErased = true },
            eraseClubData: { clubDataErased = true },
            eraseDeviceToken: { deviceTokenErased = true },
            eraseCheckInSkip: { checkInSkipErased = true }
        )

        let result = await eraser.eraseAll()

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.failedStores.isEmpty)
        XCTAssertTrue(deviceTokenErased)
        XCTAssertTrue(checkInSkipErased)
        XCTAssertTrue(workoutsErased)
        XCTAssertTrue(routesErased)
        XCTAssertTrue(draftsErased)
        XCTAssertTrue(checkInsErased)
        XCTAssertTrue(recoverySnapshotsErased)
        XCTAssertTrue(trainingSettingsErased)
        XCTAssertTrue(clubDataErased)
    }

    func testEraseAllContinuesPastAFailingStore() async {
        var routesErased = false
        var checkInsErased = false
        var recoverySnapshotsErased = false
        var trainingSettingsErased = false

        let eraser = LocalAccountDataEraser(
            eraseWorkouts: { throw SampleError.failed },
            eraseWorkoutRoutes: { routesErased = true },
            eraseFeedDrafts: { throw SampleError.failed },
            eraseCheckIns: { checkInsErased = true },
            eraseRecoverySnapshots: { recoverySnapshotsErased = true },
            eraseTrainingSettings: { trainingSettingsErased = true },
            eraseClubData: {}
        )

        let result = await eraser.eraseAll()

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.failedStores, [.workouts, .feedDrafts])
        XCTAssertTrue(routesErased)
        XCTAssertTrue(checkInsErased)
        XCTAssertTrue(recoverySnapshotsErased)
        XCTAssertTrue(trainingSettingsErased)
    }

    func testEraseAllContinuesAfterCheckInAndSnapshotFailures() async {
        var snapshotsAttempted = false
        var trainingSettingsErased = false
        var clubDataErased = false
        let eraser = LocalAccountDataEraser(
            eraseWorkouts: {},
            eraseWorkoutRoutes: {},
            eraseFeedDrafts: {},
            eraseCheckIns: { throw SampleError.failed },
            eraseRecoverySnapshots: {
                snapshotsAttempted = true
                throw SampleError.failed
            },
            eraseTrainingSettings: { trainingSettingsErased = true },
            eraseClubData: { clubDataErased = true }
        )

        let result = await eraser.eraseAll()

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.failedStores, [.checkIns, .recoverySnapshots])
        XCTAssertTrue(snapshotsAttempted)
        XCTAssertTrue(trainingSettingsErased)
        XCTAssertTrue(clubDataErased)
    }

    func testLiveErasureRemovesAllCheckInsAndRecoverySnapshotsFromPersistence() async throws {
        let schema = Schema([
            CheckInRecord.self,
            DailyRecoverySnapshotRecord.self,
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ])
        let configuration = ModelConfiguration(
            "LocalAccountDataEraserTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        // Include records far outside the recent-history window so a reset
        // cannot leave older personal notes or derived recovery data behind.
        for date in [referenceDate, referenceDate.addingTimeInterval(-800 * 86_400)] {
            let checkIn = CheckInRecord(
                date: date,
                fatigueLevel: 4,
                sleepQuality: 2,
                muscleSoreness: 3,
                moodLevel: 2,
                note: "Private recovery note"
            )
            context.insert(checkIn)
            context.insert(DailyRecoverySnapshotRecord(
                date: date,
                score: 62,
                status: "회복 필요",
                recommendation: "가볍게 쉬기",
                coachMessage: "피로를 살펴보세요",
                explanation: "체크인 기반 회복 기록",
                dataQuality: "estimated",
                activityCount: 1,
                checkInId: checkIn.id
            ))
        }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CheckInRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyRecoverySnapshotRecord>()), 2)

        let suiteName = "LocalAccountDataEraserTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let draftsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAccountDataEraserTests-\(UUID().uuidString).json")
        let deviceTokenStore = DeviceTokenStore(userDefaults: userDefaults)
        let checkInSkipStore = MorningCheckInSkipStore(userDefaults: userDefaults)
        deviceTokenStore.cache(tokenHex: "test-cached-device-token")
        checkInSkipStore.markSkippedToday()
        let eraser = LocalAccountDataEraser.live(
            modelContext: context,
            trainingSettingsStore: TrainingSettingsStore(userDefaults: userDefaults),
            clubPersistence: LocalClubPersistence(userDefaults: userDefaults),
            feedShareDraftStore: FileFeedShareDraftStore(fileURL: draftsURL),
            deviceTokenStore: deviceTokenStore,
            morningCheckInSkipStore: checkInSkipStore
        )

        let result = await eraser.eraseAll()

        XCTAssertTrue(result.isComplete)
        XCTAssertNil(DeviceTokenStore(userDefaults: userDefaults).cachedTokenHex)
        XCTAssertNil(userDefaults.object(forKey: "soom.morningCheckIn.skippedDate"))
        // A fresh context checks saved deletion, not just objects removed
        // from the original context's pending changes.
        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<CheckInRecord>()), 0)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<DailyRecoverySnapshotRecord>()), 0)
    }

    func testEveryFailedStoreIsReportedWithoutSkippingLaterStores() async {
        let eraser = LocalAccountDataEraser(
            eraseWorkouts: { throw SampleError.failed },
            eraseWorkoutRoutes: { throw SampleError.failed },
            eraseFeedDrafts: { throw SampleError.failed },
            eraseCheckIns: { throw SampleError.failed },
            eraseRecoverySnapshots: { throw SampleError.failed },
            eraseTrainingSettings: { throw SampleError.failed },
            eraseClubData: { throw SampleError.failed },
            eraseDeviceToken: { throw SampleError.failed },
            eraseCheckInSkip: { throw SampleError.failed }
        )

        let result = await eraser.eraseAll()

        XCTAssertEqual(result.failedStores, LocalAccountDataStore.allCases)
        XCTAssertFalse(result.isComplete)
    }

    func testRetryCanCompleteAfterAStoreRecovers() async {
        var shouldFail = true
        var checkInAttempts = 0
        let eraser = LocalAccountDataEraser(
            eraseWorkouts: {},
            eraseWorkoutRoutes: {},
            eraseFeedDrafts: {},
            eraseCheckIns: {
                checkInAttempts += 1
                if shouldFail { throw SampleError.failed }
            },
            eraseRecoverySnapshots: {},
            eraseTrainingSettings: {},
            eraseClubData: {}
        )

        let first = await eraser.eraseAll()
        shouldFail = false
        let retry = await eraser.eraseAll()

        XCTAssertEqual(first.failedStores, [.checkIns])
        XCTAssertTrue(retry.isComplete)
        XCTAssertEqual(checkInAttempts, 2)
    }

    private enum SampleError: Error {
        case failed
    }
}
