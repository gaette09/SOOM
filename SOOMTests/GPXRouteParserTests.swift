import XCTest
@testable import SOOM

final class GPXRouteParserTests: XCTestCase {
    private let parser = GPXRouteParser()

    func testParsesValidGPXWithOneTrackSegment() throws {
        let route = try parser.parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="SOOMTests">
              <trk>
                <trkseg>
                  <trkpt lat="37.5000" lon="127.0000" />
                  <trkpt lat="37.5010" lon="127.0010" />
                  <trkpt lat="37.5020" lon="127.0020" />
                </trkseg>
              </trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinateCount, 3)
        XCTAssertEqual(route.coordinates[0].latitude, 37.5000, accuracy: 0.0001)
        XCTAssertEqual(route.coordinates[0].longitude, 127.0000, accuracy: 0.0001)
        XCTAssertGreaterThan(route.totalDistanceMeters, 0)
    }

    func testParsesValidGPXWithMultipleTrackSegmentsInOrder() throws {
        let route = try parser.parse(
            """
            <gpx version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="37.5000" lon="127.0000" />
                  <trkpt lat="37.5010" lon="127.0010" />
                </trkseg>
                <trkseg>
                  <trkpt lat="37.5020" lon="127.0020" />
                  <trkpt lat="37.5030" lon="127.0030" />
                </trkseg>
              </trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinateCount, 4)
        XCTAssertEqual(route.coordinates.map(\.latitude), [37.5000, 37.5010, 37.5020, 37.5030])
    }

    func testParsesOptionalElevation() throws {
        let route = try parser.parse(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="37.5000" lon="127.0000"><ele>12.5</ele></trkpt>
                <trkpt lat="37.5010" lon="127.0010"><ele>18</ele></trkpt>
              </trkseg></trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinates[0].altitude, 12.5)
        XCTAssertEqual(route.coordinates[1].altitude, 18)
    }

    func testParsesOptionalTime() throws {
        let route = try parser.parse(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="37.5000" lon="127.0000"><time>2026-07-09T00:00:00Z</time></trkpt>
                <trkpt lat="37.5010" lon="127.0010"><time>2026-07-09T00:01:00Z</time></trkpt>
              </trkseg></trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinates[0].timestamp, Date(timeIntervalSince1970: 1_783_555_200))
        XCTAssertEqual(route.coordinates[1].timestamp, Date(timeIntervalSince1970: 1_783_555_260))
    }

    func testMissingElevationAndTimeStillSucceeds() throws {
        let route = try parser.parse(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="37.5000" lon="127.0000" />
                <trkpt lat="37.5010" lon="127.0010" />
              </trkseg></trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinateCount, 2)
        XCTAssertNil(route.coordinates[0].altitude)
        XCTAssertNil(route.coordinates[0].timestamp)
    }

    func testInvalidLatitudeAndLongitudePointsAreIgnoredWhenEnoughValidPointsRemain() throws {
        let route = try parser.parse(
            """
            <gpx version="1.1">
              <trk><trkseg>
                <trkpt lat="91.0000" lon="127.0000" />
                <trkpt lat="37.5000" lon="127.0000" />
                <trkpt lat="37.5010" lon="181.0000" />
                <trkpt lat="37.5020" lon="127.0020" />
              </trkseg></trk>
            </gpx>
            """
        )

        XCTAssertEqual(route.coordinateCount, 2)
        XCTAssertEqual(route.coordinates.map(\.latitude), [37.5000, 37.5020])
    }

    func testEmptyDataFails() {
        XCTAssertThrowsError(try parser.parse(Data())) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .emptyData)
        }
    }

    func testGPXWithNoTrackPointsFails() {
        XCTAssertThrowsError(
            try parser.parse(
                """
                <gpx version="1.1">
                  <rte><rtept lat="37.5000" lon="127.0000" /></rte>
                  <wpt lat="37.5010" lon="127.0010" />
                </gpx>
                """
            )
        ) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .noTrackPoints)
        }
    }

    func testMalformedXMLFailsCleanly() {
        XCTAssertThrowsError(
            try parser.parse("<gpx><trk><trkseg><trkpt lat=\"37.5\" lon=\"127.0\"></trkseg></gpx>")
        ) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .malformedXML)
        }
    }

    func testSingleValidPointFails() {
        XCTAssertThrowsError(
            try parser.parse(
                """
                <gpx version="1.1">
                  <trk><trkseg>
                    <trkpt lat="37.5000" lon="127.0000" />
                  </trkseg></trk>
                </gpx>
                """
            )
        ) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .insufficientValidCoordinates(validCount: 1))
        }
    }

    func testFileSizeLimitFailsBeforeParsing() {
        let parser = GPXRouteParser(maximumFileSizeBytes: 10)
        XCTAssertThrowsError(try parser.parse("<gpx></gpx>")) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .fileTooLarge(maximumBytes: 10))
        }
    }

    func testCoordinateLimitFailsCleanly() {
        let parser = GPXRouteParser(maximumCoordinateCount: 2)
        XCTAssertThrowsError(
            try parser.parse(
                """
                <gpx version="1.1">
                  <trk><trkseg>
                    <trkpt lat="37.5000" lon="127.0000" />
                    <trkpt lat="37.5010" lon="127.0010" />
                    <trkpt lat="37.5020" lon="127.0020" />
                  </trkseg></trk>
                </gpx>
                """
            )
        ) { error in
            XCTAssertEqual(error as? GPXRouteParserError, .coordinateLimitExceeded(maximumCoordinates: 2))
        }
    }
}
