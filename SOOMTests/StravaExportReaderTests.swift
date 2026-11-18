import XCTest
import ZIPFoundation
@testable import SOOM

final class StravaExportReaderTests: XCTestCase {
    // A real Strava-export-shaped zip, built and verified with the real macOS
    // `zip`/`unzip` command-line tools (not hand-authored zip bytes). Its
    // activities.csv:
    //   Activity ID,Activity Date,Activity Name,Activity Type,Filename
    //   55501,Aug 1 2026,"Morning Run, Easy",Run,activities/9998877.fit.gz
    //   55502,Aug 2 2026,Evening Ride,Ride,activities/1234567.gpx
    //   55503,Aug 3 2026,Missing File Test,Run,activities/9999999.fit.gz
    // The archive actually contains activities/9998877.fit.gz (ASCII bytes
    // "FIT-GZ-DUMMY-BYTES-9998877") and activities/1234567.gpx (ASCII bytes
    // "GPX-DUMMY-BYTES-1234567"). Row 55501's Activity ID does not match its
    // file's embedded number (9998877) anywhere, and row 55503's Filename
    // deliberately points at a file that was never added to the archive.
    private static let fixture = "UEsDBBQAAAAIAFdMHF2SDTtdngAAAP0AAAAOAAAAYWN0aXZpdGllcy5jc3Ztjs0KwjAQhO8+Reh5qW1q+nMstIKHepC+QNA1LGgsJi3Wp9ckFHtwD8vMwjez9dnSRHZmhwbqRTfS4s8d5X3l+nlA2NMN9fe8EUIkKdSjYinjCc8h6h5PTVqx06iBtdLMETgpA09otlVVlWVRxFeysXr7CO4jeIhoJwwJdEHwawWnPNuJvIjV8PJk5skskB0Z40j3HuvR2D/VbpbqD1BLAwQKAAAAAABXTBxdAAAAAAAAAAAAAAAACwAAAGFjdGl2aXRpZXMvUEsDBAoAAAAAAFdMHF21cwlCFwAAABcAAAAWAAAAYWN0aXZpdGllcy8xMjM0NTY3LmdweEdQWC1EVU1NWS1CWVRFUy0xMjM0NTY3UEsDBAoAAAAAAFdMHF1ymzrsGgAAABoAAAAZAAAAYWN0aXZpdGllcy85OTk4ODc3LmZpdC5nekZJVC1HWi1EVU1NWS1CWVRFUy05OTk4ODc3UEsBAh4DFAAAAAgAV0wcXZINO12eAAAA/QAAAA4AAAAAAAAAAQAAAKSBAAAAAGFjdGl2aXRpZXMuY3N2UEsBAh4DCgAAAAAAV0wcXQAAAAAAAAAAAAAAAAsAAAAAAAAAAAAQAO1BygAAAGFjdGl2aXRpZXMvUEsBAh4DCgAAAAAAV0wcXbVzCUIXAAAAFwAAABYAAAAAAAAAAQAAAKSB8wAAAGFjdGl2aXRpZXMvMTIzNDU2Ny5ncHhQSwECHgMKAAAAAABXTBxdcps67BoAAAAaAAAAGQAAAAAAAAABAAAApIE+AQAAYWN0aXZpdGllcy85OTk4ODc3LmZpdC5nelBLBQYAAAAABAAEAAABAACPAQAAAAA="

    // A second real zip (same tooling), containing one unrelated file and no
    // activities.csv at all — used to prove missing-manifest detection.
    private static let noManifestFixture = "UEsDBAoAAAAAANtMHF0pTfwQFgAAABYAAAAKAAAAcmVhZG1lLnR4dHVucmVsYXRlZCBmaWxlIGNvbnRlbnRQSwECHgMKAAAAAADbTBxdKU38EBYAAAAWAAAACgAAAAAAAAABAAAApIEAAAAAcmVhZG1lLnR4dFBLBQYAAAAAAQABADgAAAA+AAAAAAA="

    // A third real zip (same tooling) whose activities.csv adds "Elapsed
    // Time" and "Distance" columns on top of the base column set:
    //   Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,Filename
    //   70001,Aug 5 2026,Morning Run,Run,1800,5000,activities/999888.gpx
    //   70002,Aug 6 2026,Home Trainer Ride,Ride,3600,0,
    //   70003,Aug 7 2026,Broken File Test,Run,1200,3000,activities/broken.gpx
    // Row 70002 has an empty Filename (no attached file). Used here only to
    // prove Elapsed Time / Distance parsing; batch 5's pipeline tests reuse
    // this same fixture for the file-present/no-file/corrupted-file split.
    private static let elapsedAndDistanceFixture = "UEsDBBQAAAAIAGFSHF3DRC9hrgAAAAwBAAAOAAAAYWN0aXZpdGllcy5jc3Zdjk0OgkAMRveeogdodITwt8Sg0YUuCBcYoSGNMJBhMHJ7h5kYjYs2bfryvua14SebBS4F5p+5kIa+2032P1u1jITHTo4TNVCxPRU8GalqwhN3pCy8SYQQe8znFiIIRBDjddCKVQvlrHCtfSoERpZC6b1M0y7LsjRNt+34coLACWIvOA89QaUlK9JQckPoWhhbhUDHh45PPH/Qw4MUrB9BRZPxqYGlw7/UuyNd6htQSwMECgAAAAAAYVIcXQAAAAAAAAAAAAAAAAsAAABhY3Rpdml0aWVzL1BLAwQKAAAAAABhUhxddjHpwicAAAAnAAAAFQAAAGFjdGl2aXRpZXMvYnJva2VuLmdweHRoaXMgaXMgbm90IHhtbCBhdCBhbGwsIGp1c3QgcGxhaW4gdGV4dFBLAwQUAAAACABhUhxd2UtbYY0AAAAJAQAAFQAAAGFjdGl2aXRpZXMvOTk5ODg4LmdweLOxr8jNUShLLSrOzM+zVTLUM1BSSM1Lzk/JzEu3VQoNcdO1ULK347JJL6hAVmWopJBclJpYkl9kqxTs7+8bklpcUqxkx6WgYFNSlA2iIazi1HQIB8ItKFHISSyxVTI21zM1MABalQM2zshczwDM1cep2BBVsSFexUaoio0Qim30EY4Cs4Fe0wf6zY4LAFBLAQIeAxQAAAAIAGFSHF3DRC9hrgAAAAwBAAAOAAAAAAAAAAEAAACkgQAAAABhY3Rpdml0aWVzLmNzdlBLAQIeAwoAAAAAAGFSHF0AAAAAAAAAAAAAAAALAAAAAAAAAAAAEADtQdoAAABhY3Rpdml0aWVzL1BLAQIeAwoAAAAAAGFSHF12MenCJwAAACcAAAAVAAAAAAAAAAEAAACkgQMBAABhY3Rpdml0aWVzL2Jyb2tlbi5ncHhQSwECHgMUAAAACABhUhxd2UtbYY0AAAAJAQAAFQAAAAAAAAABAAAApIFdAQAAYWN0aXZpdGllcy85OTk4ODguZ3B4UEsFBgAAAAAEAAQA+wAAAB0CAAAAAA=="

    func testOptionalDeviceColumnSurvivesLazyFileExtraction() throws {
        let csv = "Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,Filename,Device\n1,2026-08-05T00:00:00Z,Morning Run,Run,1800,5000,activities/one.gpx,Apple Watch Series 6\n"
        let archive = try StravaExportReader().open(StravaSyntheticZIP.make(csv: csv, files: ["activities/one.gpx": Data("test route".utf8)]))
        XCTAssertEqual(archive.entries.first?.deviceName, "Apple Watch Series 6")
        XCTAssertEqual(try archive.readEntry(at: 0).deviceName, "Apple Watch Series 6")
        let oldCSV = StravaSyntheticZIP.csv(rows: [["2", "2026-08-05", "Ride", "60", "100", ""]])
        XCTAssertNil(try StravaExportReader().open(StravaSyntheticZIP.make(csv: oldCSV)).entries.first?.deviceName)
    }

    func testArchiveOpensMetadataWithoutExtractingActivityFiles() throws {
        let csv = StravaSyntheticZIP.csv(rows: [["1", "2026-08-05T00:00:00Z", "Ride", "60", "100", "activities/one.fit"]])
        let zip = try StravaSyntheticZIP.make(csv: csv, files: ["activities/one.fit": Data(repeating: 1, count: 128)])
        let archive = try StravaExportReader().open(zip)
        XCTAssertEqual(archive.expandedBytes, Data(csv.utf8).count)
        XCTAssertTrue(archive.entries.allSatisfy { $0.data == nil })
        XCTAssertEqual(try archive.readEntry(at: 0).data?.count, 128)
        XCTAssertEqual(archive.expandedBytes, Data(csv.utf8).count + 128)
    }

    func testCSVAndCompressedArchiveHaveIndependentBounds() throws {
        let csv = StravaSyntheticZIP.csv(rows: [["1", "2026-08-05", "Ride", "60", "100", ""]])
        let zip = try StravaSyntheticZIP.make(csv: csv)
        XCTAssertThrowsError(try StravaExportReader(maximumArchiveBytes: zip.count - 1).open(zip)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .archiveTooLarge(maximumBytes: zip.count - 1))
        }
        XCTAssertThrowsError(try StravaExportReader(maximumCSVBytes: 16).open(zip)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .csvTooLarge(maximumBytes: 16))
        }
    }

    func testCumulativeExpansionLimitStopsBeforeNextFile() throws {
        let csv = StravaSyntheticZIP.csv(rows: [
            ["1", "2026-08-05", "Ride", "60", "100", "activities/a.fit"],
            ["2", "2026-08-06", "Ride", "60", "100", "activities/b.fit"]])
        let zip = try StravaSyntheticZIP.make(csv: csv, files: ["activities/a.fit": Data(repeating: 1, count: 100), "activities/b.fit": Data(repeating: 2, count: 100)])
        let limit = Data(csv.utf8).count + 150
        let archive = try StravaExportReader(maximumExpandedBytes: limit).open(zip)
        XCTAssertEqual(try archive.readEntry(at: 0).data?.count, 100)
        XCTAssertThrowsError(try archive.readEntry(at: 1)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .expansionLimitExceeded(maximumBytes: limit))
        }
    }

    func testNestedManifestResolvesItsRelativeActivityPath() throws {
        let csv = StravaSyntheticZIP.csv(rows: [["1", "2026-08-05", "Ride", "60", "100", "activities/a.gpx"]])
        let zip = try StravaSyntheticZIP.make(csv: csv, files: ["activities/a.gpx": Data("synthetic".utf8)], prefix: "export/")
        XCTAssertEqual(try StravaExportReader().open(zip).readEntry(at: 0).data, Data("synthetic".utf8))
    }

    func testUnsafeRowPathsAndAmbiguousManifestsAreRejected() throws {
        let csv = StravaSyntheticZIP.csv(rows: [["1", "2026-08-05", "Ride", "60", "100", "../outside.gpx"]])
        let zip = try StravaSyntheticZIP.make(csv: csv)
        XCTAssertThrowsError(try StravaExportReader().open(zip).readEntry(at: 0)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .unsafePath)
        }
        let ambiguous = try StravaSyntheticZIP.make(csv: csv, files: ["nested/activities.csv": Data(csv.utf8)])
        XCTAssertThrowsError(try StravaExportReader().open(ambiguous)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .ambiguousManifest)
        }
    }

    func testRepeatedMetricHeadersUseTrailingRawValuesWithoutRejectingManifest() throws {
        let csv = "Activity ID,Activity Date,Activity Type,Elapsed Time,Distance,Filename,Elapsed Time,Distance\n1,2026-08-05,Ride,60,0.1,,60,100\n"
        let entry = try XCTUnwrap(StravaExportReader().open(StravaSyntheticZIP.make(csv: csv)).entries.first)
        XCTAssertEqual(entry.distanceMeters, 100)
        XCTAssertEqual(entry.elapsedTimeSeconds, 60)
    }

    func testManifestChecksumMismatchIsRejected() throws {
        let csv = StravaSyntheticZIP.csv(rows: [["1", "2026-08-05", "Ride", "60", "100", ""]])
        var zip = try StravaSyntheticZIP.make(csv: csv)
        let directory = try XCTUnwrap(zip.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        // Change the declared CRC, leaving the valid compressed payload intact.
        zip[directory.lowerBound + 16] ^= 0xff
        XCTAssertThrowsError(try StravaExportReader().open(zip)) {
            XCTAssertEqual($0 as? StravaExportReaderError, .corruptEntry)
        }
    }

    private func data(fromBase64 base64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64))
    }

    func testParsesElapsedTimeAndDistanceColumns() throws {
        let zip = try data(fromBase64: Self.elapsedAndDistanceFixture)
        let entries = try StravaExportReader().readEntries(from: zip)

        XCTAssertEqual(entries[0].elapsedTimeSeconds, 1_800)
        XCTAssertEqual(entries[0].distanceMeters, 5_000)
    }

    func testElapsedTimeAndDistanceAreNilWhenRowHasNoFile() throws {
        let zip = try data(fromBase64: Self.elapsedAndDistanceFixture)
        let entries = try StravaExportReader().readEntries(from: zip)

        XCTAssertNil(entries[1].filename)
        XCTAssertEqual(entries[1].elapsedTimeSeconds, 3_600)
        XCTAssertEqual(entries[1].distanceMeters, 0)
    }

    func testElapsedTimeAndDistanceAreNilOnOlderFixtureWithoutThoseColumns() throws {
        let zip = try data(fromBase64: Self.fixture)
        let entries = try StravaExportReader().readEntries(from: zip)

        XCTAssertNil(entries[0].elapsedTimeSeconds)
        XCTAssertNil(entries[0].distanceMeters)
    }

    func testReadsAllThreeEntriesInOrder() throws {
        let zip = try data(fromBase64: Self.fixture)
        let entries = try StravaExportReader().readEntries(from: zip)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.activityId), ["55501", "55502", "55503"])
    }

    func testFirstEntryUsesFilenameColumnNotActivityId() throws {
        let zip = try data(fromBase64: Self.fixture)
        let entries = try StravaExportReader().readEntries(from: zip)
        let entry = entries[0]

        XCTAssertEqual(entry.activityId, "55501")
        XCTAssertEqual(entry.activityName, "Morning Run, Easy")
        XCTAssertEqual(entry.filename, "activities/9998877.fit.gz")
        XCTAssertEqual(entry.data, Data("FIT-GZ-DUMMY-BYTES-9998877".utf8))
    }

    func testSecondEntryResolvesGPXFile() throws {
        let zip = try data(fromBase64: Self.fixture)
        let entries = try StravaExportReader().readEntries(from: zip)
        let entry = entries[1]

        XCTAssertEqual(entry.filename, "activities/1234567.gpx")
        XCTAssertEqual(entry.data, Data("GPX-DUMMY-BYTES-1234567".utf8))
    }

    func testThirdEntryHasDanglingFilenameButNilDataAndDoesNotThrow() throws {
        let zip = try data(fromBase64: Self.fixture)
        let entries = try StravaExportReader().readEntries(from: zip)
        let entry = entries[2]

        XCTAssertEqual(entry.filename, "activities/9999999.fit.gz")
        XCTAssertNil(entry.data)
    }

    func testEmptyDataThrowsEmptyData() {
        XCTAssertThrowsError(try StravaExportReader().readEntries(from: Data())) { error in
            XCTAssertEqual(error as? StravaExportReaderError, .emptyData)
        }
    }

    func testNonZipDataThrowsNotAZipArchive() {
        let plainText = Data("not a zip".utf8)
        XCTAssertThrowsError(try StravaExportReader().readEntries(from: plainText)) { error in
            XCTAssertEqual(error as? StravaExportReaderError, .notAZipArchive)
        }
    }

    func testZipWithoutActivitiesCSVThrowsMissingActivitiesCSV() throws {
        let zip = try data(fromBase64: Self.noManifestFixture)
        XCTAssertThrowsError(try StravaExportReader().readEntries(from: zip)) { error in
            XCTAssertEqual(error as? StravaExportReaderError, .missingActivitiesCSV)
        }
    }

    func testEntryCountLimitExceeded() throws {
        let zip = try data(fromBase64: Self.fixture)
        let strictReader = StravaExportReader(maximumEntryCount: 2)
        XCTAssertThrowsError(try strictReader.readEntries(from: zip)) { error in
            XCTAssertEqual(error as? StravaExportReaderError, .entryCountLimitExceeded(maximumEntries: 2))
        }
    }

    func testFileTooLargeThrows() throws {
        let zip = try data(fromBase64: Self.fixture)
        let strictReader = StravaExportReader(maximumFileBytes: 10)
        XCTAssertThrowsError(try strictReader.readEntries(from: zip)) { error in
            guard case .fileTooLarge = error as? StravaExportReaderError else {
                XCTFail("expected .fileTooLarge, got \(error)")
                return
            }
        }
    }
}

// Every byte is generated from test-owned strings; no user export files are read.
enum StravaSyntheticZIP {
    static func csv(rows: [[String]]) -> String {
        let header = "Activity ID,Activity Date,Activity Type,Elapsed Time,Distance,Filename"
        return header + "\n" + rows.map { row in
            row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    static func make(csv: String, files: [String: Data] = [:], prefix: String = "") throws -> Data {
        let archive = try Archive(accessMode: .create)
        var contents = files
        contents["activities.csv"] = Data(csv.utf8)
        for path in contents.keys.sorted() {
            let bytes = contents[path]!
            try archive.addEntry(with: prefix + path, type: .file, uncompressedSize: Int64(bytes.count),
                                 modificationDate: Date(timeIntervalSince1970: 1_600_000_000), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<min(Int(position) + size, bytes.count))
            }
        }
        return try XCTUnwrap(archive.data)
    }
}
