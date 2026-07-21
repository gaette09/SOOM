import XCTest
@testable import SOOM

final class TCXRouteParserTests: XCTestCase {
    func testParsesSyntheticNamespacedCyclingRouteAcrossLapsInDocumentOrder() throws {
        let route = try TCXRouteParser().parse(Self.cyclingFixture)
        XCTAssertEqual(route.coordinateCount, 3)
        XCTAssertEqual(route.coordinates.map(\.latitude), [37.5, 37.501, 37.502])
        XCTAssertEqual(route.coordinates[1].timestamp, Date(timeIntervalSince1970: 1_800_000_060))
        XCTAssertEqual(route.totalDistanceMeters, 240, accuracy: 0.1)
        XCTAssertEqual(route.summary.workoutType, .cycling)
        XCTAssertEqual(route.summary.startDate, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(route.summary.durationSeconds, 90)
        XCTAssertEqual(route.summary.activeEnergyKcal, 65)
        XCTAssertEqual(route.summary.averageHeartRate ?? 0, 141.67, accuracy: 0.01)
        XCTAssertEqual(route.summary.maxHeartRate, 150)
        XCTAssertEqual(route.summary.averageCadence ?? 0, 82.67, accuracy: 0.01)
        XCTAssertEqual(route.summary.averagePower, 220)
        XCTAssertEqual(route.summary.elevationGainMeters, 9)
    }

    func testAcceptsDefaultTCXV2NamespaceAndOnlyRecognizedActivityExtensionWatts() throws {
        let route = try TCXRouteParser().parse(Self.defaultNamespaceFixture)
        XCTAssertEqual(route.coordinateCount, 2)
        XCTAssertEqual(route.summary.averagePower, 210)
    }

    func testAcceptsPrefixedTCXV2NamespaceFixture() throws {
        let route = try TCXRouteParser().parse(Self.prefixedNamespaceFixture)
        XCTAssertEqual(route.coordinateCount, 2)
        XCTAssertEqual(route.coordinates.map(\.longitude), [127, 127.001])
        XCTAssertEqual(route.summary.workoutType, .running)
    }

    func testRejectsUnsupportedAndAmbiguousDocumentShapes() {
        assertError(.emptyData, data: Data())
        assertError(
            .malformedXML,
            xml: "<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\">"
        )
        assertError(.unsupportedDocument, xml: "<TrainingCenterDatabase />")
        assertError(.missingActivity, xml: Self.document(body: "<Courses />"))
        assertError(.multipleActivities, xml: Self.document(body: "<Activities><Activity Sport=\"Running\" /><Activity Sport=\"Running\" /></Activities>"))
        assertError(.missingActivity, xml: Self.document(body: "<MultiSportSession />"))
    }

    func testFiltersInvalidCoordinatesAndRejectsTooFewValidPoints() {
        assertError(.insufficientValidCoordinates(validCount: 1), xml: Self.document(body: "<Activities><Activity Sport=\"Running\"><Lap StartTime=\"2027-01-15T08:00:00Z\"><Track><Trackpoint><Position><LatitudeDegrees>91</LatitudeDegrees><LongitudeDegrees>127</LongitudeDegrees></Position></Trackpoint><Trackpoint><Position><LatitudeDegrees>37.5</LatitudeDegrees><LongitudeDegrees>127</LongitudeDegrees></Position></Trackpoint></Track></Lap></Activity></Activities>"))
    }

    func testHonorsConfiguredFileLapAndCoordinateLimits() {
        assertError(.fileTooLarge(maximumBytes: 5), parser: TCXRouteParser(maximumFileSizeBytes: 5), xml: Self.defaultNamespaceFixture)
        assertError(.lapLimitExceeded(maximumLaps: 1), parser: TCXRouteParser(maximumLapCount: 1), xml: Self.cyclingFixture)
        assertError(.coordinateLimitExceeded(maximumCoordinates: 2), parser: TCXRouteParser(maximumCoordinateCount: 2), xml: Self.cyclingFixture)
    }

    private func assertError(_ expected: TCXRouteParserError, parser: TCXRouteParser = TCXRouteParser(), xml: String) { XCTAssertThrowsError(try parser.parse(xml)) { XCTAssertEqual($0 as? TCXRouteParserError, expected) } }
    private func assertError(_ expected: TCXRouteParserError, data: Data) { XCTAssertThrowsError(try TCXRouteParser().parse(data)) { XCTAssertEqual($0 as? TCXRouteParserError, expected) } }

    private static func document(body: String) -> String { "<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\">\(body)</TrainingCenterDatabase>" }
    private static let cyclingFixture = document(body: """
    <Activities><Activity Sport="Biking"><Id>2027-01-15T08:00:00Z</Id>
      <Lap StartTime="2027-01-15T08:00:00Z"><TotalTimeSeconds>60</TotalTimeSeconds><DistanceMeters>160</DistanceMeters><Calories>45</Calories><AverageHeartRateBpm><Value>143</Value></AverageHeartRateBpm><MaximumHeartRateBpm><Value>150</Value></MaximumHeartRateBpm><Cadence>83</Cadence><Track>
        <Trackpoint><Time>2027-01-15T08:00:00.000Z</Time><Position><LatitudeDegrees>37.5</LatitudeDegrees><LongitudeDegrees>127</LongitudeDegrees></Position><AltitudeMeters>12</AltitudeMeters><HeartRateBpm><Value>140</Value></HeartRateBpm><Cadence>82</Cadence></Trackpoint>
        <Trackpoint><Time>2027-01-15T08:01:00Z</Time><Position><LatitudeDegrees>37.501</LatitudeDegrees><LongitudeDegrees>127.001</LongitudeDegrees></Position><AltitudeMeters>18</AltitudeMeters><HeartRateBpm><Value>146</Value></HeartRateBpm><Cadence>84</Cadence><Extensions><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>220</Watts></TPX></Extensions></Trackpoint>
      </Track></Lap><Lap StartTime="2027-01-15T08:01:00Z"><TotalTimeSeconds>30</TotalTimeSeconds><DistanceMeters>80</DistanceMeters><Calories>20</Calories><AverageHeartRateBpm><Value>139</Value></AverageHeartRateBpm><Cadence>82</Cadence><Track><Trackpoint><Time>2027-01-15T08:01:30Z</Time><Position><LatitudeDegrees>37.502</LatitudeDegrees><LongitudeDegrees>127.002</LongitudeDegrees></Position><AltitudeMeters>21</AltitudeMeters></Trackpoint></Track></Lap>
    </Activity></Activities>
    """)
    private static let defaultNamespaceFixture = document(body: """
    <Activities><Activity Sport="Running"><Lap StartTime="2027-01-15T08:00:00Z"><Track>
      <Trackpoint><Position><LatitudeDegrees>37.5</LatitudeDegrees><LongitudeDegrees>127</LongitudeDegrees></Position><Extensions><Lookalike><Watts>999</Watts></Lookalike><TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Watts>210</Watts></TPX></Extensions></Trackpoint>
      <Trackpoint><Position><LatitudeDegrees>37.6</LatitudeDegrees><LongitudeDegrees>127.1</LongitudeDegrees></Position></Trackpoint>
    </Track></Lap></Activity></Activities>
    """)
    private static let prefixedNamespaceFixture = """
    <tcx:TrainingCenterDatabase xmlns:tcx="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><tcx:Activities><tcx:Activity Sport="Running"><tcx:Lap StartTime="2027-01-15T08:00:00Z"><tcx:Track>
      <tcx:Trackpoint><tcx:Position><tcx:LatitudeDegrees>37.5</tcx:LatitudeDegrees><tcx:LongitudeDegrees>127</tcx:LongitudeDegrees></tcx:Position></tcx:Trackpoint>
      <tcx:Trackpoint><tcx:Position><tcx:LatitudeDegrees>37.501</tcx:LatitudeDegrees><tcx:LongitudeDegrees>127.001</tcx:LongitudeDegrees></tcx:Position></tcx:Trackpoint>
    </tcx:Track></tcx:Lap></tcx:Activity></tcx:Activities></tcx:TrainingCenterDatabase>
    """
}
