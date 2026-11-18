import XCTest
import SwiftData
@testable import SOOM

@MainActor
final class StravaImportPipelineTests: XCTestCase {
    // A real zip (built and verified with the real macOS `zip`/`unzip`
    // command-line tools, not hand-authored) whose activities.csv:
    //   Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,Filename
    //   70001,Aug 5 2026,Morning Run,Run,1800,5000,activities/999888.gpx
    //   70002,Aug 6 2026,Home Trainer Ride,Ride,3600,0,
    //   70003,Aug 7 2026,Broken File Test,Run,1200,3000,activities/broken.gpx
    // activities/999888.gpx is a valid minimal GPX file (3 trackpoints).
    // activities/broken.gpx exists in the archive but is plain text, not
    // valid GPX/TCX/FIT. Row 70002 has no attached file at all. Row 70001's
    // Activity ID (70001) does not match its file's embedded number (999888)
    // anywhere, mirroring the batch-4 fixture's Filename-not-ID proof.
    private static let fixture = "UEsDBBQAAAAIAGFSHF3DRC9hrgAAAAwBAAAOAAAAYWN0aXZpdGllcy5jc3Zdjk0OgkAMRveeogdodITwt8Sg0YUuCBcYoSGNMJBhMHJ7h5kYjYs2bfryvua14SebBS4F5p+5kIa+2032P1u1jITHTo4TNVCxPRU8GalqwhN3pCy8SYQQe8znFiIIRBDjddCKVQvlrHCtfSoERpZC6b1M0y7LsjRNt+34coLACWIvOA89QaUlK9JQckPoWhhbhUDHh45PPH/Qw4MUrB9BRZPxqYGlw7/UuyNd6htQSwMECgAAAAAAYVIcXQAAAAAAAAAAAAAAAAsAAABhY3Rpdml0aWVzL1BLAwQKAAAAAABhUhxddjHpwicAAAAnAAAAFQAAAGFjdGl2aXRpZXMvYnJva2VuLmdweHRoaXMgaXMgbm90IHhtbCBhdCBhbGwsIGp1c3QgcGxhaW4gdGV4dFBLAwQUAAAACABhUhxd2UtbYY0AAAAJAQAAFQAAAGFjdGl2aXRpZXMvOTk5ODg4LmdweLOxr8jNUShLLSrOzM+zVTLUM1BSSM1Lzk/JzEu3VQoNcdO1ULK347JJL6hAVmWopJBclJpYkl9kqxTs7+8bklpcUqxkx6WgYFNSlA2iIazi1HQIB8ItKFHISSyxVTI21zM1MABalQM2zshczwDM1cep2BBVsSFexUaoio0Qim30EY4Cs4Fe0wf6zY4LAFBLAQIeAxQAAAAIAGFSHF3DRC9hrgAAAAwBAAAOAAAAAAAAAAEAAACkgQAAAABhY3Rpdml0aWVzLmNzdlBLAQIeAwoAAAAAAGFSHF0AAAAAAAAAAAAAAAALAAAAAAAAAAAAEADtQdoAAABhY3Rpdml0aWVzL1BLAQIeAwoAAAAAAGFSHF12MenCJwAAACcAAAAVAAAAAAAAAAEAAACkgQMBAABhY3Rpdml0aWVzL2Jyb2tlbi5ncHhQSwECHgMUAAAACABhUhxd2UtbYY0AAAAJAQAAFQAAAAAAAAABAAAApIFdAQAAYWN0aXZpdGllcy85OTk4ODguZ3B4UEsFBgAAAAAEAAQA+wAAAB0CAAAAAA=="

    private func data(fromBase64 base64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64))
    }

    private func makePipeline(store: UnifiedWorkoutStore) -> StravaImportPipeline {
        StravaImportPipeline(store: store, routeStore: InMemoryWorkoutRouteStore())
    }

    func testFileEntryImportsAsCompleteWorkoutResolvedByFilename() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "strava-activity-70001" })
        XCTAssertEqual(workout.source, .strava)
        XCTAssertEqual(workout.dataQuality, .complete)
        XCTAssertEqual(workout.routeMissingReason, .none)
        XCTAssertEqual(workout.workoutType, .running)
        // Activity ID for this row is "70001", which appears nowhere in the
        // resolved file's own embedded number (999888) — the workout still
        // resolves correctly because the pipeline looks the file up by the
        // CSV Filename column, never by reconstructing a path from the ID.
    }

    func testAutoPublicZIPQueuesNewRowsButNotDuplicateReimports() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        let pipeline = StravaImportPipeline(store: store, routeStore: InMemoryWorkoutRouteStore(),
            autoPublishNewWorkouts: true)
        let first = try await pipeline.importZip(zip)
        XCTAssertEqual(first.importedWorkoutIDs.count, 3)
        XCTAssertTrue(store.savedWorkouts.allSatisfy {
            $0.sharingVisibilityRaw == ImportedWorkoutPublication.pendingVisibility(for:.privatePost)
        })
        let repeated = try await pipeline.importZip(zip)
        XCTAssertTrue(repeated.importedWorkoutIDs.isEmpty)
        XCTAssertEqual(repeated.skippedDuplicateCount, 3)
    }

    func testEntryWithNoFileImportsAsPartialWithoutInventingIndoorProvenance() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "strava-activity-70002" })
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertEqual(workout.routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertEqual(workout.workoutType, .cycling)
        XCTAssertEqual(workout.durationSeconds, 3_600)
        XCTAssertEqual(workout.distanceMeters, 0)
    }

    func testEntryWithCorruptFileImportsAsPartialUnknownWorkout() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "strava-activity-70003" })
        XCTAssertEqual(workout.dataQuality, .partial)
        // A file was present but failed to parse — distinct from the
        // never-had-a-file case above, which is why this is .unknown and
        // not .indoorNoLocationData.
        XCTAssertEqual(workout.routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertEqual(workout.workoutType, .running)
        XCTAssertEqual(workout.durationSeconds, 1_200)
    }

    func testReimportingTheSameZipSkipsEveryRowAsADuplicate() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        let pipeline = StravaImportPipeline(store: store, routeStore: InMemoryWorkoutRouteStore())

        let firstResult = try await pipeline.importZip(zip)
        XCTAssertEqual(firstResult.totalRowCount, 3)
        XCTAssertEqual(firstResult.importedCount, 3)
        XCTAssertEqual(firstResult.skippedDuplicateCount, 0)

        let secondResult = try await pipeline.importZip(zip)
        XCTAssertEqual(secondResult.importedCount, 0)
        XCTAssertEqual(secondResult.skippedDuplicateCount, firstResult.importedCount)
        XCTAssertEqual(store.savedWorkouts.count, 3)
    }
    func testParsedCoordinatesSurviveASecondSwiftDataContextAndReimport() async throws {
        let schema = Schema([UnifiedWorkoutRecord.self, PersistedWorkoutRoute.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let firstContext = ModelContext(container)
        let pipeline = StravaImportPipeline(store: SwiftDataUnifiedWorkoutStore(modelContext: firstContext),
            routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: firstContext))
        let zip = try singleGPXZip()
        let first = try await pipeline.importZip(zip)
        XCTAssertEqual(first.importedCount, 1)
        let id = StravaImportPipeline.stableWorkoutID(for: "strava-activity-1")

        let reopenedContext = ModelContext(container)
        let reopenedStore = SwiftDataUnifiedWorkoutStore(modelContext: reopenedContext)
        let reopenedRoutes = SwiftDataWorkoutRoutePersistenceStore(modelContext: reopenedContext)
        let saved = try await reopenedStore.fetchWorkout(id: id)
        let savedRoute = try await reopenedRoutes.fetchRoute(workoutId: id)
        XCTAssertEqual(saved?.routeMissingReason, WorkoutRouteMissingReason.none)
        XCTAssertEqual(saved?.dataQuality, .complete)
        XCTAssertEqual(savedRoute?.coordinates.count, 2)
        let repeated = try await StravaImportPipeline(store: reopenedStore, routeStore: reopenedRoutes).importZip(zip)
        XCTAssertEqual(repeated.skippedDuplicateCount, 1)
        XCTAssertEqual(repeated.importedCount, 0)
        let routeAfterRetry = try await reopenedRoutes.fetchRoute(workoutId: id)
        XCTAssertEqual(routeAfterRetry?.id, savedRoute?.id)
    }

    func testNewImportsOnDifferentStoresUseTheSameProviderIdentityUUID() async throws {
        let zip = try singleGPXZip()
        let a = FakeStravaWorkoutStore()
        let b = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: a).importZip(zip)
        _ = try await makePipeline(store: b).importZip(zip)
        XCTAssertEqual(a.savedWorkouts.first?.id, b.savedWorkouts.first?.id)
        XCTAssertNotNil(a.savedWorkouts.first?.id)
    }

    func testLegacyFilenameAndOldHistoryPreserveUUIDExclusionAndUserFieldsWhileRepairingRoute() async throws {
        let existing = makeExisting(externalID: "activities/a.gpx", source: .strava,
            date: Date(timeIntervalSince1970: 946_684_800), excluded: true)
        let store = FakeStravaWorkoutStore(workouts: [existing])
        store.hideRecentHistory = true
        let routes = FakeStravaRouteStore()
        let result = try await StravaImportPipeline(store: store, routeStore: routes).importZip(singleGPXZip())
        let saved = try XCTUnwrap(store.savedWorkouts.first)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.repairedRouteCount, 1)
        XCTAssertEqual(saved.id, existing.id)
        XCTAssertEqual(saved.externalId, existing.externalId)
        XCTAssertEqual(saved.startDate, existing.startDate)
        XCTAssertEqual(saved.durationSeconds, existing.durationSeconds)
        XCTAssertEqual(saved.isExcludedFromAnalysis, true)
        XCTAssertEqual(saved.companionNames, existing.companionNames)
        XCTAssertEqual(routes.routes[existing.id]?.coordinates.count, 2)
    }

    func testRouteSaveFailureIsReportedAndRetryRepairsSameWorkoutIdentityAndQuality() async throws {
        let store = FakeStravaWorkoutStore()
        let routes = FakeStravaRouteStore()
        routes.failWrites = true
        let pipeline = StravaImportPipeline(store: store, routeStore: routes)
        let zip = try singleGPXZip()
        let first = try await pipeline.importZip(zip)
        let pending = try XCTUnwrap(store.savedWorkouts.first)
        XCTAssertEqual(first.importedCount, 1)
        XCTAssertEqual(first.failedCount, 1)
        XCTAssertEqual(pending.routeMissingReason, .routePersistenceFailed)
        XCTAssertEqual(pending.dataQuality, .partial)
        XCTAssertTrue(first.completedEntryIDs.isEmpty)
        routes.failWrites = false
        let second = try await pipeline.importZip(zip)
        XCTAssertEqual(second.repairedRouteCount, 1)
        XCTAssertEqual(second.failedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(store.savedWorkouts.first?.id, pending.id)
        XCTAssertEqual(store.savedWorkouts.first?.routeMissingReason, WorkoutRouteMissingReason.none)
        XCTAssertEqual(store.savedWorkouts.first?.dataQuality, .complete)
    }

    func testMissingFileTimeUsesCSVDateAndUnknownDateNeverBecomesToday() async throws {
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(singleGPXZip())
        XCTAssertEqual(store.savedWorkouts.first?.startDate, StravaImportPipeline.parseActivityDate("2026-08-05T00:00:00Z"))
        let bad = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [
            ["2", "unknown", "Ride", "600", "1000", "activities/a.gpx"],
            ["3", "", "Ride", "600", "1000", ""]]), files: ["activities/a.gpx": Self.gpxWithoutTimes])
        let result = try await makePipeline(store: store).importZip(bad)
        XCTAssertEqual(result.skippedInvalidCount, 2)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 1)
    }

    func testNonFiniteOrMissingDurationIsRejectedAndUnknownDistanceIsNotZeroFilled() async throws {
        let rows = [["1", "2026-08-05", "Ride", "nan", "1000", ""],
                    ["2", "2026-08-06", "Ride", "-1", "1000", ""],
                    ["3", "2026-08-07", "Ride", "", "1000", ""],
                    ["4", "2026-08-08", "Ride", "600", "nan", ""]]
        let store = FakeStravaWorkoutStore()
        let result = try await makePipeline(store: store).importZip(StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: rows)))
        XCTAssertEqual(result.skippedInvalidCount, 3)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertNil(store.savedWorkouts.first?.distanceMeters)
        XCTAssertNil(store.savedWorkouts.first?.averageHeartRate)
    }

    func testFuzzyCandidateRequiresExplicitChoiceAndNeverDeletesTheOriginal() async throws {
        let date = try XCTUnwrap(StravaImportPipeline.parseActivityDate("2026-08-05T00:00:00Z"))
        let existing = makeExisting(externalID: "healthkit-id", source: .appleHealthKit, date: date)
        let store = FakeStravaWorkoutStore(workouts: [existing])
        let pipeline = StravaImportPipeline(store: store, routeStore: FakeStravaRouteStore())
        let zip = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [["1", "2026-08-05T00:00:00Z", "Ride", "600", "", ""]]))
        let first = try await pipeline.importZip(zip)
        XCTAssertEqual(first.reviews.count, 1)
        XCTAssertEqual(first.skippedDuplicateCount, 0)
        XCTAssertEqual(first.importedCount, 0)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        let skipped = try await pipeline.importZip(zip, decisions: ["strava-activity-1": .skip])
        XCTAssertEqual(skipped.skippedByUserCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        let accepted = try await pipeline.importZip(zip, decisions: ["strava-activity-1": .importSeparately])
        XCTAssertEqual(accepted.importedCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 2)
        XCTAssertEqual(store.savedWorkouts.first(where: { $0.id == existing.id }), existing)
    }

    func testWriteFailureKeepsOtherSuccessesAndRetrySkipsCommittedRows() async throws {
        let zip = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [
            ["1", "2026-08-05", "Ride", "600", "1000", ""],
            ["2", "2026-08-06", "Ride", "600", "1000", ""],
            ["3", "2026-08-07", "Ride", "600", "1000", ""]]))
        let store = FakeStravaWorkoutStore()
        store.failedExternalIDs = ["strava-activity-2"]
        let pipeline = makePipeline(store: store)
        let first = try await pipeline.importZip(zip)
        XCTAssertEqual(first.importedCount, 2)
        XCTAssertEqual(first.failedCount, 1)
        XCTAssertEqual(first.processedCount, 3)
        XCTAssertEqual(first.summaryOnlyCount, 2)
        store.failedExternalIDs = []
        let second = try await pipeline.importZip(zip, alreadyCompleted: first.completedEntryIDs)
        XCTAssertEqual(second.importedCount, 1)
        XCTAssertEqual(second.skippedDuplicateCount, 2)
        XCTAssertEqual(store.savedWorkouts.count, 3)
    }

    func testCancellationPreservesCommittedRowsAndAllowsRetry() async throws {
        let zip = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [
            ["1", "2026-08-05", "Ride", "600", "1000", ""],
            ["2", "2026-08-06", "Ride", "600", "1000", ""]]))
        let store = FakeStravaWorkoutStore()
        let pipeline = makePipeline(store: store)
        let task = Task {
            try await pipeline.importZip(zip) { progress in
                if progress.completedCount == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let first = try await task.value
        XCTAssertTrue(first.isCancelled)
        XCTAssertEqual(first.importedCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 1)
        let second = try await pipeline.importZip(zip, alreadyCompleted: first.completedEntryIDs)
        XCTAssertFalse(second.isCancelled)
        XCTAssertEqual(second.importedCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 2)
    }

    func testBudgetStopCanContinueWithCompletedEntryCheckpoint() async throws {
        let csv = StravaSyntheticZIP.csv(rows: [
            ["1", "2026-08-05", "Ride", "600", "1000", "activities/a.gpx"],
            ["2", "2026-08-06", "Ride", "600", "1000", "activities/b.gpx"]])
        let invalid = Data(repeating: 65, count: 100)
        let zip = try StravaSyntheticZIP.make(csv: csv, files: ["activities/a.gpx": invalid, "activities/b.gpx": invalid])
        let reader = StravaExportReader(maximumExpandedBytes: Data(csv.utf8).count + 150)
        let store = FakeStravaWorkoutStore()
        let pipeline = StravaImportPipeline(reader: reader, store: store, routeStore: FakeStravaRouteStore())
        let first = try await pipeline.importZip(zip)
        XCTAssertTrue(first.stoppedForLimit)
        XCTAssertEqual(first.importedCount, 1)
        let second = try await pipeline.importZip(zip, alreadyCompleted: first.completedEntryIDs)
        XCTAssertFalse(second.stoppedForLimit)
        XCTAssertEqual(second.importedCount, 1)
        XCTAssertEqual(store.savedWorkouts.count, 2)
    }

    func testIndoorFITRetainsSensorSummaryWithoutInventingARouteOrSpeed() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let fit = FITTestFileBuilder().addSessionDefinition().addSession(sport: 2, startTime: start,
            elapsedSeconds: 600, calories: 200, averageHeartRate: 145, averageCadence: 82, averagePower: 210).makeData()
        let zip = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [["1", "", "Ride", "", "", "activities/a.fit"]]),
            files: ["activities/a.fit": fit])
        let store = FakeStravaWorkoutStore()
        let routes = FakeStravaRouteStore()
        let result = try await StravaImportPipeline(store: store, routeStore: routes).importZip(zip)
        let saved = try XCTUnwrap(store.savedWorkouts.first)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.summaryOnlyCount, 1)
        XCTAssertEqual(saved.startDate, start)
        XCTAssertEqual(saved.averageHeartRate, 145)
        XCTAssertEqual(saved.averagePowerWatts, 210)
        XCTAssertEqual(saved.activeEnergyKcal, 200)
        XCTAssertNil(saved.averageSpeedMetersPerSecond)
        XCTAssertTrue(routes.routes.isEmpty)
        XCTAssertEqual(saved.dataQuality, .partial)
    }

    func testIndoorTCXPreservesPositionlessPowerAndHeartRate() async throws {
        let tcx = Data("""
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity Sport="Biking"><Id>2026-08-05T00:00:00Z</Id><Lap StartTime="2026-08-05T00:00:00Z"><TotalTimeSeconds>600</TotalTimeSeconds><Track><Trackpoint><HeartRateBpm><Value>145</Value></HeartRateBpm><Extensions><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>210</Watts></TPX></Extensions></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>
        """.utf8)
        let zip = try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [["1", "", "Ride", "", "", "activities/a.tcx"]]),
            files: ["activities/a.tcx": tcx])
        let store = FakeStravaWorkoutStore()
        let result = try await makePipeline(store: store).importZip(zip)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(store.savedWorkouts.first?.averageHeartRate, 145)
        XCTAssertEqual(store.savedWorkouts.first?.averagePowerWatts, 210)
    }

    private static let gpxWithoutTimes = Data("""
    <gpx version="1.1"><trk><trkseg><trkpt lat="37.5" lon="127.0"/><trkpt lat="37.501" lon="127.001"/></trkseg></trk></gpx>
    """.utf8)

    private func singleGPXZip() throws -> Data {
        try StravaSyntheticZIP.make(csv: StravaSyntheticZIP.csv(rows: [["1", "2026-08-05T00:00:00Z", "Ride", "600", "1000", "activities/a.gpx"]]),
            files: ["activities/a.gpx": Self.gpxWithoutTimes])
    }

    private func makeExisting(externalID: String, source: UnifiedDataSource, date: Date, excluded: Bool = false) -> UnifiedWorkout {
        UnifiedWorkout(id: UUID(), externalId: externalID, source: source, workoutType: .cycling,
            startDate: date, endDate: date.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: nil, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil,
            dataQuality: .complete, isExcludedFromAnalysis: excluded,
            createdAt: date, updatedAt: date, companionNames: ["테스트 동료"])
    }

}

@MainActor
private final class FakeStravaWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout]
    var failedExternalIDs: Set<String> = []
    var hideRecentHistory = false
    init(workouts: [UnifiedWorkout] = []) { savedWorkouts = workouts }
    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        if let key = workout.externalId, failedExternalIDs.contains(key) { throw StravaTestFailure.storage }
        if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id || ($0.source == workout.source && $0.externalId == workout.externalId) }) {
            savedWorkouts[index] = workout
        } else { savedWorkouts.append(workout) }
    }
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws { for workout in workouts { try await saveWorkout(workout) } }
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] { hideRecentHistory ? [] : savedWorkouts }
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { savedWorkouts.first { $0.id == id } }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws { savedWorkouts.removeAll { $0.id == id } }
    func deleteAllWorkouts() async throws { savedWorkouts.removeAll() }
}

@MainActor
private final class FakeStravaRouteStore: WorkoutRouteStore {
    var routes: [UUID: WorkoutRoute] = [:]
    var failWrites = false
    func saveRoute(_ route: WorkoutRoute) async throws {
        if failWrites { throw StravaTestFailure.storage }
        routes[route.workoutId] = route
    }
    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? { routes[workoutId] }
}
private enum StravaTestFailure: Error { case storage }

@MainActor
final class WorkoutFileImportServiceTests: XCTestCase {
    private let datedGPX = Data("""
        <gpx version="1.1"><trk><trkseg>
        <trkpt lat="37.5000" lon="127.0000"><time>2026-09-20T09:00:00Z</time></trkpt>
        <trkpt lat="37.5010" lon="127.0010"><time>2026-09-20T09:05:00Z</time></trkpt>
        </trkseg></trk></gpx>
        """.utf8)

    func testGPXCreatesWorkoutAndRouteAndSkipsIdenticalRetry() async throws {
        let schema = Schema([UnifiedWorkoutRecord.self, PersistedWorkoutRoute.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let routes = SwiftDataWorkoutRoutePersistenceStore(modelContext: context)
        let importer = WorkoutFileImportService(store: store, routeStore: routes)
        let first = try await importer.importFile(datedGPX, filename: "ride.gpx", sport: .cycling,
                                                  deviceName: "Wahoo", autoPublish: true)
        guard case .imported(let id, let routeSaved) = first else {
            return XCTFail("expected a newly imported workout")
        }
        XCTAssertTrue(routeSaved)
        let fetched = try await store.fetchWorkout(id: id)
        let saved = try XCTUnwrap(fetched)
        XCTAssertEqual(saved.workoutType, .cycling)
        XCTAssertEqual(saved.deviceName, "Wahoo")
        XCTAssertEqual(saved.sharingVisibilityRaw, ImportedWorkoutPublication.pendingVisibility(for:.privatePost))
        let route = try await routes.fetchRoute(workoutId: id)
        XCTAssertEqual(route?.coordinates.count, 2)

        let repeated = try await importer.importFile(datedGPX, filename: "renamed.gpx", sport: .running,
                                                     deviceName: "Other", autoPublish: true)
        guard case .duplicate = repeated else { return XCTFail("renamed identical file must not create a second workout") }
        let workoutAfterRetry = try await store.fetchWorkout(id: id)
        XCTAssertEqual(workoutAfterRetry?.workoutType, .cycling)
    }

    func testIndoorFITAndTCXImportSensorSummariesWithoutRoutes() async throws {
        let fitStart = Date(timeIntervalSince1970: 1_800_000_000)
        let fit = FITTestFileBuilder().addSessionDefinition().addSession(sport: 2, startTime: fitStart,
            elapsedSeconds: 600, calories: 200, averageHeartRate: 145,
            averageCadence: 82, averagePower: 210).makeData()
        let tcx = Data("""
            <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity Sport="Biking"><Id>2026-08-05T00:00:00Z</Id><Lap StartTime="2026-08-05T00:00:00Z"><TotalTimeSeconds>600</TotalTimeSeconds><Track><Trackpoint><HeartRateBpm><Value>151</Value></HeartRateBpm><Extensions><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>225</Watts></TPX></Extensions></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>
            """.utf8)
        let store = FakeStravaWorkoutStore()
        let routes = FakeStravaRouteStore()
        let importer = WorkoutFileImportService(store: store, routeStore: routes)
        let fitResult = try await importer.importFile(fit, filename: "indoor.fit", sport: .other,
                                                      deviceName: "Garmin", autoPublish: false)
        guard case .imported(_, let fitRouteSaved) = fitResult else { return XCTFail("FIT should import") }
        XCTAssertFalse(fitRouteSaved)
        let fitWorkout = try XCTUnwrap(store.savedWorkouts.first)
        XCTAssertEqual(fitWorkout.workoutType, .cycling)
        XCTAssertEqual(fitWorkout.averagePowerWatts, 210)
        XCTAssertEqual(fitWorkout.averageHeartRate, 145)

        let tcxResult = try await importer.importFile(tcx, filename: "indoor.tcx", sport: .other,
                                                      deviceName: "Wahoo", autoPublish: false)
        guard case .imported(_, let tcxRouteSaved) = tcxResult else { return XCTFail("TCX should import") }
        XCTAssertFalse(tcxRouteSaved)
        let tcxWorkout = try XCTUnwrap(store.savedWorkouts.first(where: { $0.deviceName == "Wahoo" }))
        XCTAssertEqual(tcxWorkout.workoutType, .cycling)
        XCTAssertEqual(tcxWorkout.averagePowerWatts, 225)
        XCTAssertEqual(tcxWorkout.averageHeartRate, 151)
        XCTAssertTrue(routes.routes.isEmpty)
    }

    func testGPXWithoutTimesCannotCreateWorkout() async throws {
        let schema = Schema([UnifiedWorkoutRecord.self, PersistedWorkoutRoute.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let importer = WorkoutFileImportService(
            store: SwiftDataUnifiedWorkoutStore(modelContext: context),
            routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: context))
        let data = Data("<gpx version=\"1.1\"><trk><trkseg><trkpt lat=\"37.5\" lon=\"127.0\"/><trkpt lat=\"37.6\" lon=\"127.1\"/></trkseg></trk></gpx>".utf8)
        do {
            _ = try await importer.importFile(data, filename: "no-time.gpx", sport: .running,
                                              deviceName: "Unknown", autoPublish: false)
            XCTFail("missing workout dates must not be invented")
        } catch WorkoutFileImportError.missingSummary {
            // A route alone is not a completed workout.
        }
    }
}
