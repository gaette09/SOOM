import XCTest
@testable import SOOM

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
        StravaImportPipeline(store: store)
    }

    func testFileEntryImportsAsCompleteWorkoutResolvedByFilename() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "activities/999888.gpx" })
        XCTAssertEqual(workout.source, .strava)
        XCTAssertEqual(workout.dataQuality, .complete)
        XCTAssertEqual(workout.routeMissingReason, .none)
        XCTAssertEqual(workout.workoutType, .running)
        // Activity ID for this row is "70001", which appears nowhere in the
        // resolved file's own embedded number (999888) — the workout still
        // resolves correctly because the pipeline looks the file up by the
        // CSV Filename column, never by reconstructing a path from the ID.
    }

    func testEntryWithNoFileImportsAsPartialIndoorWorkout() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "strava-activity-70002" })
        XCTAssertEqual(workout.dataQuality, .partial)
        XCTAssertEqual(workout.routeMissingReason, .indoorNoLocationData)
        XCTAssertEqual(workout.workoutType, .cycling)
        XCTAssertEqual(workout.durationSeconds, 3_600)
        XCTAssertEqual(workout.distanceMeters, 0)
    }

    func testEntryWithCorruptFileImportsAsPartialUnknownWorkout() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        _ = try await makePipeline(store: store).importZip(zip)

        let workout = try XCTUnwrap(store.savedWorkouts.first { $0.externalId == "activities/broken.gpx" })
        XCTAssertEqual(workout.dataQuality, .partial)
        // A file was present but failed to parse — distinct from the
        // never-had-a-file case above, which is why this is .unknown and
        // not .indoorNoLocationData.
        XCTAssertEqual(workout.routeMissingReason, .unknown)
        XCTAssertEqual(workout.workoutType, .running)
        XCTAssertEqual(workout.durationSeconds, 1_200)
    }

    func testReimportingTheSameZipSkipsEveryRowAsADuplicate() async throws {
        let zip = try data(fromBase64: Self.fixture)
        let store = FakeStravaWorkoutStore()
        let pipeline = makePipeline(store: store)

        let firstResult = try await pipeline.importZip(zip)
        XCTAssertEqual(firstResult.totalRowCount, 3)
        XCTAssertEqual(firstResult.importedCount, 3)
        XCTAssertEqual(firstResult.skippedDuplicateCount, 0)

        let secondResult = try await pipeline.importZip(zip)
        XCTAssertEqual(secondResult.importedCount, 0)
        XCTAssertEqual(secondResult.skippedDuplicateCount, firstResult.importedCount)
        XCTAssertEqual(store.savedWorkouts.count, 3)
    }
}

private final class FakeStravaWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        upsert(workout)
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            upsert(workout)
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        savedWorkouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }

    func deleteAllWorkouts() async throws {
        savedWorkouts.removeAll()
    }

    private func upsert(_ workout: UnifiedWorkout) {
        if let externalId = workout.externalId,
           let index = savedWorkouts.firstIndex(where: { $0.externalId == externalId && $0.source == workout.source }) {
            savedWorkouts[index] = workout
        } else if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            savedWorkouts[index] = workout
        } else {
            savedWorkouts.append(workout)
        }
    }
}
