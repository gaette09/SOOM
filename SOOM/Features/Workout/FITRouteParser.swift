import Foundation

struct FITParsedRoute: Equatable {
    let coordinates: [WorkoutRouteCoordinate]
    let totalDistanceMeters: Double
    let summary: FITWorkoutSummary

    var coordinateCount: Int {
        coordinates.count
    }
}

struct FITWorkoutSummary: Equatable {
    let workoutType: UnifiedWorkoutType?
    let startDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let averageSpeedMetersPerSecond: Double?
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageCadence: Double?
    let averagePower: Double?
}

enum FITRouteParserError: Error, Equatable {
    case emptyData
    case fileTooLarge(maximumBytes: Int)
    case invalidHeader
    case invalidDataSize
    case unsupportedCompressedTimestampHeader
    case missingDefinition(localMessageType: UInt8)
    case malformedData
    case noRouteCoordinates
    case insufficientValidCoordinates(validCount: Int)
    case coordinateLimitExceeded(maximumCoordinates: Int)
}

struct FITRouteParser {
    let maximumFileSizeBytes: Int
    let maximumCoordinateCount: Int

    init(
        maximumFileSizeBytes: Int = 10 * 1_024 * 1_024,
        maximumCoordinateCount: Int = 20_000
    ) {
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.maximumCoordinateCount = maximumCoordinateCount
    }

    func parse(_ data: Data) throws -> FITParsedRoute {
        guard !data.isEmpty else {
            throw FITRouteParserError.emptyData
        }
        guard data.count <= maximumFileSizeBytes else {
            throw FITRouteParserError.fileTooLarge(maximumBytes: maximumFileSizeBytes)
        }

        var reader = FITDataReader(data: data)
        let header = try reader.readHeader()
        guard data.count >= header.headerSize + header.dataSize else {
            throw FITRouteParserError.invalidDataSize
        }

        let dataEnd = header.headerSize + header.dataSize
        reader.offset = header.headerSize

        var definitions: [UInt8: FITDefinitionMessage] = [:]
        var accumulator = FITRouteAccumulator(maximumCoordinateCount: maximumCoordinateCount)

        while reader.offset < dataEnd {
            let recordHeader = try reader.readUInt8(limit: dataEnd)
            guard recordHeader & 0x80 == 0 else {
                throw FITRouteParserError.unsupportedCompressedTimestampHeader
            }

            let localMessageType = recordHeader & 0x0F
            let hasDeveloperFields = recordHeader & 0x20 != 0
            let isDefinition = recordHeader & 0x40 != 0

            if isDefinition {
                definitions[localMessageType] = try reader.readDefinition(
                    hasDeveloperFields: hasDeveloperFields,
                    limit: dataEnd
                )
            } else {
                guard let definition = definitions[localMessageType] else {
                    throw FITRouteParserError.missingDefinition(localMessageType: localMessageType)
                }
                let fields = try reader.readDataMessage(definition: definition, limit: dataEnd)
                accumulator.consume(fields: fields, globalMessageNumber: definition.globalMessageNumber)
            }
        }

        return try accumulator.makeParsedRoute()
    }

    fileprivate static func totalDistanceMeters(for coordinates: [WorkoutRouteCoordinate]) -> Double {
        guard coordinates.count > 1 else { return 0 }

        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + distanceMeters(from: pair.0, to: pair.1)
        }
    }

    private static func distanceMeters(
        from start: WorkoutRouteCoordinate,
        to end: WorkoutRouteCoordinate
    ) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = radians(start.latitude)
        let endLatitude = radians(end.latitude)
        let deltaLatitude = radians(end.latitude - start.latitude)
        let deltaLongitude = radians(end.longitude - start.longitude)

        let a = pow(sin(deltaLatitude / 2), 2)
            + cos(startLatitude) * cos(endLatitude) * pow(sin(deltaLongitude / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

private struct FITHeader {
    let headerSize: Int
    let dataSize: Int
}

private struct FITDefinitionMessage {
    let architecture: FITEndian
    let globalMessageNumber: UInt16
    let fields: [FITFieldDefinition]
    let developerFields: [FITDeveloperFieldDefinition]
}

private struct FITFieldDefinition {
    let number: UInt8
    let size: Int
    let baseType: UInt8
}

private struct FITDeveloperFieldDefinition {
    let size: Int
}

private enum FITEndian {
    case little
    case big
}

private enum FITFieldValue: Equatable {
    case uint8(UInt8)
    case sint8(Int8)
    case uint16(UInt16)
    case sint16(Int16)
    case uint32(UInt32)
    case sint32(Int32)
    case bytes(Data)
}

private struct FITDataReader {
    let data: Data
    var offset = 0

    mutating func readHeader() throws -> FITHeader {
        guard data.count >= 12 else {
            throw FITRouteParserError.invalidHeader
        }

        let headerSize = Int(try readUInt8(limit: data.count))
        guard headerSize == 12 || headerSize == 14 else {
            throw FITRouteParserError.invalidHeader
        }
        guard data.count >= headerSize else {
            throw FITRouteParserError.invalidHeader
        }

        _ = try readUInt8(limit: data.count)
        _ = try readUInt16(endian: .little, limit: data.count)
        let dataSize = Int(try readUInt32(endian: .little, limit: data.count))
        let magic = try readData(count: 4, limit: data.count)
        guard String(data: magic, encoding: .ascii) == ".FIT" else {
            throw FITRouteParserError.invalidHeader
        }

        if headerSize == 14 {
            _ = try readUInt16(endian: .little, limit: data.count)
        }

        return FITHeader(headerSize: headerSize, dataSize: dataSize)
    }

    mutating func readDefinition(
        hasDeveloperFields: Bool,
        limit: Int
    ) throws -> FITDefinitionMessage {
        _ = try readUInt8(limit: limit)
        let architectureByte = try readUInt8(limit: limit)
        let endian: FITEndian = architectureByte == 0 ? .little : .big
        let globalMessageNumber = try readUInt16(endian: endian, limit: limit)
        let fieldCount = try readUInt8(limit: limit)
        var fields: [FITFieldDefinition] = []

        for _ in 0..<fieldCount {
            let fieldNumber = try readUInt8(limit: limit)
            let size = Int(try readUInt8(limit: limit))
            let baseType = try readUInt8(limit: limit)
            fields.append(FITFieldDefinition(number: fieldNumber, size: size, baseType: baseType))
        }

        var developerFields: [FITDeveloperFieldDefinition] = []
        if hasDeveloperFields {
            let developerFieldCount = try readUInt8(limit: limit)
            for _ in 0..<developerFieldCount {
                _ = try readUInt8(limit: limit)
                let size = Int(try readUInt8(limit: limit))
                _ = try readUInt8(limit: limit)
                developerFields.append(FITDeveloperFieldDefinition(size: size))
            }
        }

        return FITDefinitionMessage(
            architecture: endian,
            globalMessageNumber: globalMessageNumber,
            fields: fields,
            developerFields: developerFields
        )
    }

    mutating func readDataMessage(
        definition: FITDefinitionMessage,
        limit: Int
    ) throws -> [UInt8: FITFieldValue] {
        var values: [UInt8: FITFieldValue] = [:]

        for field in definition.fields {
            let fieldData = try readData(count: field.size, limit: limit)
            values[field.number] = decode(fieldData, baseType: field.baseType, endian: definition.architecture)
        }

        for field in definition.developerFields {
            _ = try readData(count: field.size, limit: limit)
        }

        return values
    }

    mutating func readUInt8(limit: Int) throws -> UInt8 {
        guard offset + 1 <= limit else {
            throw FITRouteParserError.malformedData
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16(endian: FITEndian, limit: Int) throws -> UInt16 {
        let fieldData = try readData(count: 2, limit: limit)
        return fieldData.withUnsafeBytes { rawBuffer in
            let value = rawBuffer.loadUnaligned(as: UInt16.self)
            return endian == .little ? UInt16(littleEndian: value) : UInt16(bigEndian: value)
        }
    }

    mutating func readUInt32(endian: FITEndian, limit: Int) throws -> UInt32 {
        let fieldData = try readData(count: 4, limit: limit)
        return fieldData.withUnsafeBytes { rawBuffer in
            let value = rawBuffer.loadUnaligned(as: UInt32.self)
            return endian == .little ? UInt32(littleEndian: value) : UInt32(bigEndian: value)
        }
    }

    mutating func readData(count: Int, limit: Int) throws -> Data {
        guard count >= 0, offset + count <= limit else {
            throw FITRouteParserError.malformedData
        }
        let fieldData = data.subdata(in: offset..<(offset + count))
        offset += count
        return fieldData
    }

    private func decode(_ fieldData: Data, baseType: UInt8, endian: FITEndian) -> FITFieldValue {
        let type = baseType & 0x1F
        switch type {
        case 0x00, 0x02, 0x0A:
            return fieldData.first.map(FITFieldValue.uint8) ?? .bytes(fieldData)
        case 0x01:
            return fieldData.first.map { .sint8(Int8(bitPattern: $0)) } ?? .bytes(fieldData)
        case 0x03:
            return fieldData.withInteger(endian: endian, as: Int16.self).map(FITFieldValue.sint16) ?? .bytes(fieldData)
        case 0x04, 0x0B:
            return fieldData.withInteger(endian: endian, as: UInt16.self).map(FITFieldValue.uint16) ?? .bytes(fieldData)
        case 0x05:
            return fieldData.withInteger(endian: endian, as: Int32.self).map(FITFieldValue.sint32) ?? .bytes(fieldData)
        case 0x06, 0x0C:
            return fieldData.withInteger(endian: endian, as: UInt32.self).map(FITFieldValue.uint32) ?? .bytes(fieldData)
        default:
            return .bytes(fieldData)
        }
    }
}

private struct FITRouteAccumulator {
    private let maximumCoordinateCount: Int
    private var coordinates: [WorkoutRouteCoordinate] = []
    private var summary = MutableFITWorkoutSummary()
    private var sawPosition = false
    private var recordDistances: [Double] = []
    private var recordHeartRates: [Double] = []
    private var recordCadences: [Double] = []
    private var recordPowers: [Double] = []

    init(maximumCoordinateCount: Int) {
        self.maximumCoordinateCount = maximumCoordinateCount
    }

    mutating func consume(fields: [UInt8: FITFieldValue], globalMessageNumber: UInt16) {
        switch globalMessageNumber {
        case 20:
            consumeRecord(fields)
        case 18:
            consumeSession(fields)
        default:
            break
        }
    }

    func makeParsedRoute() throws -> FITParsedRoute {
        guard sawPosition else {
            throw FITRouteParserError.noRouteCoordinates
        }
        guard coordinates.count >= 2 else {
            throw FITRouteParserError.insufficientValidCoordinates(validCount: coordinates.count)
        }
        guard coordinates.count <= maximumCoordinateCount else {
            throw FITRouteParserError.coordinateLimitExceeded(maximumCoordinates: maximumCoordinateCount)
        }

        let distance = summary.distanceMeters
            ?? recordDistances.last
            ?? FITRouteParser.totalDistanceMeters(for: coordinates)
        let startedAt = summary.startDate ?? coordinates.compactMap(\.timestamp).first
        let duration = summary.durationSeconds ?? durationFromCoordinateTimestamps()
        let averageHeartRate = summary.averageHeartRate ?? average(recordHeartRates)
        let maxHeartRate = summary.maxHeartRate ?? recordHeartRates.max()
        let averageCadence = summary.averageCadence ?? average(recordCadences)
        let averagePower = summary.averagePower ?? average(recordPowers)
        let averageSpeed = summary.averageSpeedMetersPerSecond
            ?? averageSpeed(distanceMeters: distance, durationSeconds: duration)

        return FITParsedRoute(
            coordinates: coordinates,
            totalDistanceMeters: distance,
            summary: FITWorkoutSummary(
                workoutType: summary.workoutType,
                startDate: startedAt,
                durationSeconds: duration,
                distanceMeters: summary.distanceMeters ?? recordDistances.last,
                averageSpeedMetersPerSecond: averageSpeed,
                activeEnergyKcal: summary.activeEnergyKcal,
                elevationGainMeters: summary.elevationGainMeters,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                averageCadence: averageCadence,
                averagePower: averagePower
            )
        )
    }

    private mutating func consumeRecord(_ fields: [UInt8: FITFieldValue]) {
        let latitude = fields[0]?.semicirclesDegrees
        let longitude = fields[1]?.semicirclesDegrees

        if latitude != nil || longitude != nil {
            sawPosition = true
        }

        guard
            let latitude,
            let longitude,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return
        }

        let distanceMeters = fields[5]?.uint32Meters(scale: 100)
        if let distanceMeters {
            recordDistances.append(distanceMeters)
        }
        if let heartRate = fields[3]?.uint8Double {
            recordHeartRates.append(heartRate)
        }
        if let cadence = fields[4]?.uint8Double {
            recordCadences.append(cadence)
        }
        if let power = fields[7]?.uint16Double {
            recordPowers.append(power)
        }

        coordinates.append(
            WorkoutRouteCoordinate(
                latitude: latitude,
                longitude: longitude,
                altitude: fields[2]?.altitudeMeters,
                timestamp: fields[253]?.fitTimestampDate
            )
        )
    }

    private mutating func consumeSession(_ fields: [UInt8: FITFieldValue]) {
        if let sport = fields[5]?.uint8Value {
            summary.workoutType = UnifiedWorkoutType(fitSport: sport)
        }
        summary.startDate = fields[2]?.fitTimestampDate ?? summary.startDate
        summary.durationSeconds = fields[7]?.uint32Seconds(scale: 1_000)
            ?? fields[8]?.uint32Seconds(scale: 1_000)
            ?? summary.durationSeconds
        summary.distanceMeters = fields[9]?.uint32Meters(scale: 100) ?? summary.distanceMeters
        summary.activeEnergyKcal = fields[11]?.uint16Double ?? summary.activeEnergyKcal
        if let averageSpeed = fields[14]?.uint16Double {
            summary.averageSpeedMetersPerSecond = averageSpeed / 1_000
        }
        summary.elevationGainMeters = fields[21]?.uint16Double ?? summary.elevationGainMeters
        summary.averageHeartRate = fields[16]?.uint8Double ?? summary.averageHeartRate
        summary.maxHeartRate = fields[17]?.uint8Double ?? summary.maxHeartRate
        summary.averageCadence = fields[18]?.uint8Double ?? summary.averageCadence
        summary.averagePower = fields[20]?.uint16Double ?? summary.averagePower
    }

    private func durationFromCoordinateTimestamps() -> TimeInterval? {
        let timestamps = coordinates.compactMap(\.timestamp)
        guard let first = timestamps.first, let last = timestamps.last, last >= first else {
            return nil
        }
        return last.timeIntervalSince(first)
    }

    private func averageSpeed(distanceMeters: Double?, durationSeconds: TimeInterval?) -> Double? {
        guard let distanceMeters, let durationSeconds, distanceMeters > 0, durationSeconds > 0 else {
            return nil
        }
        return distanceMeters / durationSeconds
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct MutableFITWorkoutSummary {
    var workoutType: UnifiedWorkoutType?
    var startDate: Date?
    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var averageSpeedMetersPerSecond: Double?
    var activeEnergyKcal: Double?
    var elevationGainMeters: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var averageCadence: Double?
    var averagePower: Double?
}

private extension FITFieldValue {
    var uint8Value: UInt8? {
        guard case .uint8(let value) = self, value != UInt8.max else { return nil }
        return value
    }

    var uint8Double: Double? {
        uint8Value.map(Double.init)
    }

    var uint16Value: UInt16? {
        guard case .uint16(let value) = self, value != UInt16.max else { return nil }
        return value
    }

    var uint16Double: Double? {
        uint16Value.map(Double.init)
    }

    var uint32Value: UInt32? {
        guard case .uint32(let value) = self, value != UInt32.max else { return nil }
        return value
    }

    var sint32Value: Int32? {
        guard case .sint32(let value) = self, value != Int32.max else { return nil }
        return value
    }

    var semicirclesDegrees: Double? {
        sint32Value.map { Double($0) * 180.0 / 2_147_483_648.0 }
    }

    var altitudeMeters: Double? {
        uint16Value.map { Double($0) / 5.0 - 500.0 }
    }

    var fitTimestampDate: Date? {
        uint32Value.map { Date(timeIntervalSince1970: Double($0) + 631_065_600) }
    }

    func uint32Meters(scale: Double) -> Double? {
        uint32Value.map { Double($0) / scale }
    }

    func uint32Seconds(scale: Double) -> Double? {
        uint32Value.map { Double($0) / scale }
    }
}

private extension UnifiedWorkoutType {
    init?(fitSport: UInt8) {
        switch fitSport {
        case 1:
            self = .running
        case 2:
            self = .cycling
        case 5:
            self = .swimming
        case 11:
            self = .walking
        case 17:
            self = .hiking
        default:
            return nil
        }
    }
}

private extension Data {
    func withInteger<T: FixedWidthInteger>(endian: FITEndian, as type: T.Type) -> T? {
        guard count == MemoryLayout<T>.size else { return nil }
        let value = withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: T.self)
        }

        switch endian {
        case .little:
            return T(littleEndian: value)
        case .big:
            return T(bigEndian: value)
        }
    }
}
