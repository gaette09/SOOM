import XCTest
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

    private func data(fromBase64 base64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64))
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
