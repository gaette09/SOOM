import XCTest
@testable import SOOM

final class FITRouteParserTests: XCTestCase {
    private let parser = FITRouteParser()

    func testParsesSyntheticCyclingFITRouteAndSummary() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let data = FITTestFileBuilder()
            .addRecordDefinition()
            .addRecord(
                timestamp: startedAt,
                latitude: 37.5000,
                longitude: 127.0000,
                altitudeMeters: 12,
                heartRate: 140,
                cadence: 82,
                distanceMeters: 0,
                speedMetersPerSecond: 7.5,
                power: 210
            )
            .addRecord(
                timestamp: startedAt.addingTimeInterval(60),
                latitude: 37.5010,
                longitude: 127.0010,
                altitudeMeters: 18,
                heartRate: 145,
                cadence: 84,
                distanceMeters: 160,
                speedMetersPerSecond: 7.8,
                power: 225
            )
            .addSessionDefinition()
            .addSession(
                sport: 2,
                startTime: startedAt,
                elapsedSeconds: 60,
                distanceMeters: 160,
                calories: 45,
                averageSpeedMetersPerSecond: 7.6,
                totalAscentMeters: 6,
                averageHeartRate: 143,
                maxHeartRate: 150,
                averageCadence: 83,
                averagePower: 218
            )
            .makeData()

        let route = try parser.parse(data)

        XCTAssertEqual(route.coordinateCount, 2)
        XCTAssertEqual(route.coordinates[0].latitude, 37.5000, accuracy: 0.0001)
        XCTAssertEqual(route.coordinates[0].longitude, 127.0000, accuracy: 0.0001)
        XCTAssertEqual(route.coordinates[0].altitude ?? .nan, 12, accuracy: 0.1)
        XCTAssertEqual(route.coordinates[1].timestamp, startedAt.addingTimeInterval(60))
        XCTAssertEqual(route.totalDistanceMeters, 160, accuracy: 0.1)
        XCTAssertEqual(route.summary.workoutType, .cycling)
        XCTAssertEqual(route.summary.startDate, startedAt)
        XCTAssertEqual(route.summary.durationSeconds, 60)
        XCTAssertEqual(route.summary.distanceMeters, 160)
        XCTAssertEqual(route.summary.activeEnergyKcal, 45)
        XCTAssertEqual(route.summary.averageSpeedMetersPerSecond ?? .nan, 7.6, accuracy: 0.01)
        XCTAssertEqual(route.summary.elevationGainMeters, 6)
        XCTAssertEqual(route.summary.averageHeartRate, 143)
        XCTAssertEqual(route.summary.maxHeartRate, 150)
        XCTAssertEqual(route.summary.averageCadence, 83)
        XCTAssertEqual(route.summary.averagePower, 218)
    }

    func testDerivesSummaryFromRecordsWhenSessionIsMissing() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let data = FITTestFileBuilder()
            .addRecordDefinition()
            .addRecord(
                timestamp: startedAt,
                latitude: 37.5000,
                longitude: 127.0000,
                heartRate: 120,
                cadence: 80,
                distanceMeters: 0,
                power: 180
            )
            .addRecord(
                timestamp: startedAt.addingTimeInterval(120),
                latitude: 37.5020,
                longitude: 127.0020,
                heartRate: 140,
                cadence: 90,
                distanceMeters: 320,
                power: 220
            )
            .makeData()

        let route = try parser.parse(data)

        XCTAssertEqual(route.summary.startDate, startedAt)
        XCTAssertEqual(route.summary.durationSeconds, 120)
        XCTAssertEqual(route.summary.distanceMeters, 320)
        XCTAssertEqual(route.summary.averageHeartRate, 130)
        XCTAssertEqual(route.summary.maxHeartRate, 140)
        XCTAssertEqual(route.summary.averageCadence, 85)
        XCTAssertEqual(route.summary.averagePower, 200)
        XCTAssertEqual(route.summary.averageSpeedMetersPerSecond ?? .nan, 320.0 / 120.0, accuracy: 0.001)
    }

    func testEmptyDataFails() {
        XCTAssertThrowsError(try parser.parse(Data())) { error in
            XCTAssertEqual(error as? FITRouteParserError, .emptyData)
        }
    }

    func testNonFITHeaderFails() {
        XCTAssertThrowsError(try parser.parse(Data("not-a-fit-file".utf8))) { error in
            XCTAssertEqual(error as? FITRouteParserError, .invalidHeader)
        }
    }

    func testFileSizeLimitFailsBeforeParsing() {
        let parser = FITRouteParser(maximumFileSizeBytes: 4)
        XCTAssertThrowsError(try parser.parse(FITTestFileBuilder().makeData())) { error in
            XCTAssertEqual(error as? FITRouteParserError, .fileTooLarge(maximumBytes: 4))
        }
    }

    func testCompressedTimestampHeaderFailsCleanly() {
        let data = FITTestFileBuilder(rawDataRecords: Data([0x80])).makeData()

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(error as? FITRouteParserError, .unsupportedCompressedTimestampHeader)
        }
    }

    func testDataRecordWithoutDefinitionFailsCleanly() {
        let data = FITTestFileBuilder(rawDataRecords: Data([0x00, 0x01, 0x02])).makeData()

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(error as? FITRouteParserError, .missingDefinition(localMessageType: 0))
        }
    }

    func testFITWithoutRouteCoordinatesFails() {
        let data = FITTestFileBuilder()
            .addSessionDefinition()
            .addSession(
                sport: 2,
                startTime: Date(timeIntervalSince1970: 1_800_000_000),
                elapsedSeconds: 60,
                distanceMeters: 160
            )
            .makeData()

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(error as? FITRouteParserError, .noRouteCoordinates)
        }
    }

    func testSingleCoordinateFails() {
        let data = FITTestFileBuilder()
            .addRecordDefinition()
            .addRecord(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                latitude: 37.5000,
                longitude: 127.0000
            )
            .makeData()

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(error as? FITRouteParserError, .insufficientValidCoordinates(validCount: 1))
        }
    }

    func testCoordinateLimitFailsCleanly() {
        let data = FITTestFileBuilder()
            .addRecordDefinition()
            .addRecord(latitude: 37.5000, longitude: 127.0000)
            .addRecord(latitude: 37.5010, longitude: 127.0010)
            .addRecord(latitude: 37.5020, longitude: 127.0020)
            .makeData()
        let parser = FITRouteParser(maximumCoordinateCount: 2)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(error as? FITRouteParserError, .coordinateLimitExceeded(maximumCoordinates: 2))
        }
    }
}

private struct FITTestFileBuilder {
    private var records = Data()

    init(rawDataRecords: Data = Data()) {
        records = rawDataRecords
    }

    func addRecordDefinition() -> FITTestFileBuilder {
        var copy = self
        copy.records.append(0x40)
        copy.records.append(0x00)
        copy.records.append(0x00)
        copy.records.appendUInt16(20)
        copy.records.append(9)
        copy.appendField(number: 253, size: 4, baseType: 0x86)
        copy.appendField(number: 0, size: 4, baseType: 0x85)
        copy.appendField(number: 1, size: 4, baseType: 0x85)
        copy.appendField(number: 2, size: 2, baseType: 0x84)
        copy.appendField(number: 3, size: 1, baseType: 0x02)
        copy.appendField(number: 4, size: 1, baseType: 0x02)
        copy.appendField(number: 5, size: 4, baseType: 0x86)
        copy.appendField(number: 6, size: 2, baseType: 0x84)
        copy.appendField(number: 7, size: 2, baseType: 0x84)
        return copy
    }

    func addRecord(
        timestamp: Date? = nil,
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double? = nil,
        heartRate: UInt8? = nil,
        cadence: UInt8? = nil,
        distanceMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        power: UInt16? = nil
    ) -> FITTestFileBuilder {
        var copy = self
        copy.records.append(0x00)
        copy.records.appendUInt32(timestamp.map(fitTimestamp) ?? UInt32.max)
        copy.records.appendInt32(semicircles(latitude))
        copy.records.appendInt32(semicircles(longitude))
        copy.records.appendUInt16(altitudeMeters.map(encodedAltitude) ?? UInt16.max)
        copy.records.append(heartRate ?? UInt8.max)
        copy.records.append(cadence ?? UInt8.max)
        copy.records.appendUInt32(distanceMeters.map { UInt32(($0 * 100).rounded()) } ?? UInt32.max)
        copy.records.appendUInt16(speedMetersPerSecond.map { UInt16(($0 * 1_000).rounded()) } ?? UInt16.max)
        copy.records.appendUInt16(power ?? UInt16.max)
        return copy
    }

    func addSessionDefinition() -> FITTestFileBuilder {
        var copy = self
        copy.records.append(0x41)
        copy.records.append(0x00)
        copy.records.append(0x00)
        copy.records.appendUInt16(18)
        copy.records.append(11)
        copy.appendField(number: 5, size: 1, baseType: 0x02)
        copy.appendField(number: 2, size: 4, baseType: 0x86)
        copy.appendField(number: 7, size: 4, baseType: 0x86)
        copy.appendField(number: 9, size: 4, baseType: 0x86)
        copy.appendField(number: 11, size: 2, baseType: 0x84)
        copy.appendField(number: 14, size: 2, baseType: 0x84)
        copy.appendField(number: 21, size: 2, baseType: 0x84)
        copy.appendField(number: 16, size: 1, baseType: 0x02)
        copy.appendField(number: 17, size: 1, baseType: 0x02)
        copy.appendField(number: 18, size: 1, baseType: 0x02)
        copy.appendField(number: 20, size: 2, baseType: 0x84)
        return copy
    }

    func addSession(
        sport: UInt8? = nil,
        startTime: Date? = nil,
        elapsedSeconds: Double? = nil,
        distanceMeters: Double? = nil,
        calories: UInt16? = nil,
        averageSpeedMetersPerSecond: Double? = nil,
        totalAscentMeters: UInt16? = nil,
        averageHeartRate: UInt8? = nil,
        maxHeartRate: UInt8? = nil,
        averageCadence: UInt8? = nil,
        averagePower: UInt16? = nil
    ) -> FITTestFileBuilder {
        var copy = self
        copy.records.append(0x01)
        copy.records.append(sport ?? UInt8.max)
        copy.records.appendUInt32(startTime.map(fitTimestamp) ?? UInt32.max)
        copy.records.appendUInt32(elapsedSeconds.map { UInt32(($0 * 1_000).rounded()) } ?? UInt32.max)
        copy.records.appendUInt32(distanceMeters.map { UInt32(($0 * 100).rounded()) } ?? UInt32.max)
        copy.records.appendUInt16(calories ?? UInt16.max)
        copy.records.appendUInt16(averageSpeedMetersPerSecond.map { UInt16(($0 * 1_000).rounded()) } ?? UInt16.max)
        copy.records.appendUInt16(totalAscentMeters ?? UInt16.max)
        copy.records.append(averageHeartRate ?? UInt8.max)
        copy.records.append(maxHeartRate ?? UInt8.max)
        copy.records.append(averageCadence ?? UInt8.max)
        copy.records.appendUInt16(averagePower ?? UInt16.max)
        return copy
    }

    func makeData() -> Data {
        var data = Data()
        data.append(14)
        data.append(16)
        data.appendUInt16(0)
        data.appendUInt32(UInt32(records.count))
        data.append(contentsOf: ".FIT".utf8)
        data.appendUInt16(0)
        data.append(records)
        data.appendUInt16(0)
        return data
    }

    private mutating func appendField(number: UInt8, size: UInt8, baseType: UInt8) {
        records.append(number)
        records.append(size)
        records.append(baseType)
    }
}

private func semicircles(_ degrees: Double) -> Int32 {
    Int32((degrees * 2_147_483_648.0 / 180.0).rounded())
}

private func encodedAltitude(_ meters: Double) -> UInt16 {
    UInt16(((meters + 500) * 5).rounded())
}

private func fitTimestamp(_ date: Date) -> UInt32 {
    UInt32(date.timeIntervalSince1970 - 631_065_600)
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendInt32(_ value: Int32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<Int32>.size))
    }
}
