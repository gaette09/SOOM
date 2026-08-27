import XCTest
@testable import SOOM

final class GzipDecompressorTests: XCTestCase {
    // Plain gzip, no optional header fields (FLG byte is 0x00). Generated and
    // verified with the real `gzip` command-line tool; decompresses to
    // "hello SOOM strava gzip fixture".
    private static let fixtureA = "H4sIAAAAAAAAA8tIzcnJVwj29/dVKC4pSixLVEivyixQSMusKCktSgUAoJXIqB4AAAA="
    private static let fixtureAPlaintext = "hello SOOM strava gzip fixture"

    // gzip with the FNAME optional field present (FLG byte has bit 0x08 set,
    // header contains the literal filename "fixture_named_source.txt"
    // terminated by a NUL byte before the compressed body). Generated and
    // verified with the real `gzip` command-line tool; decompresses to
    // "hello SOOM strava gzip fixture with filename field".
    private static let fixtureB = "H4sICKG0kGoAA2ZpeHR1cmVfbmFtZWRfc291cmNlLnR4dADLSM3JyVcI9vf3VSguKUosS1RIr8osUEjLrCgpLUpVKM8syQByclLzEnNTgYzUnBQAr8vpJzIAAAA="
    private static let fixtureBPlaintext = "hello SOOM strava gzip fixture with filename field"

    private let decompressor = GzipDecompressor()

    private func data(fromBase64 base64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: base64))
    }

    func testDecodesPlainGzipWithNoOptionalFields() throws {
        let compressed = try data(fromBase64: Self.fixtureA)
        let decoded = try decompressor.decompress(compressed)
        XCTAssertEqual(String(data: decoded, encoding: .utf8), Self.fixtureAPlaintext)
    }

    func testDecodesGzipWithFNAMEField() throws {
        let compressed = try data(fromBase64: Self.fixtureB)
        let decoded = try decompressor.decompress(compressed)
        XCTAssertEqual(String(data: decoded, encoding: .utf8), Self.fixtureBPlaintext)
    }

    func testEmptyDataThrowsEmptyData() {
        XCTAssertThrowsError(try decompressor.decompress(Data())) { error in
            XCTAssertEqual(error as? GzipDecompressorError, .emptyData)
        }
    }

    func testNonGzipDataThrowsNotGzipFormat() {
        let plainText = Data("not a gzip file".utf8)
        XCTAssertThrowsError(try decompressor.decompress(plainText)) { error in
            XCTAssertEqual(error as? GzipDecompressorError, .notGzipFormat)
        }
    }

    func testTruncatedHeaderThrows() throws {
        let compressed = try data(fromBase64: Self.fixtureA)
        let truncated = compressed.prefix(5)
        XCTAssertThrowsError(try decompressor.decompress(truncated)) { error in
            XCTAssertEqual(error as? GzipDecompressorError, .truncatedHeader)
        }
    }

    func testSizeLimitExceededWhenMaximumIsSmallerThanDecompressedSize() throws {
        let compressed = try data(fromBase64: Self.fixtureA)
        let strictDecompressor = GzipDecompressor(maximumDecompressedBytes: 5)
        XCTAssertThrowsError(try strictDecompressor.decompress(compressed)) { error in
            XCTAssertEqual(error as? GzipDecompressorError, .sizeLimitExceeded(maximumBytes: 5))
        }
    }

    func testCorruptedCompressedBodyThrowsDecompressionFailed() throws {
        var bytes = [UInt8](try data(fromBase64: Self.fixtureA))
        // Fixture A has no optional header fields, so its compressed body starts
        // right after the fixed 10-byte header. Flipping the very first body
        // byte corrupts the DEFLATE block header (verified against a reference
        // DEFLATE decoder to actually trigger a structural decode error, unlike
        // most interior bytes of this short a stream, which only corrupt a
        // single output character without breaking the bitstream).
        let bodyStartOffset = 10
        bytes[bodyStartOffset] ^= 0xFF
        let corrupted = Data(bytes)

        XCTAssertThrowsError(try decompressor.decompress(corrupted)) { error in
            XCTAssertEqual(error as? GzipDecompressorError, .decompressionFailed)
        }
    }
}
