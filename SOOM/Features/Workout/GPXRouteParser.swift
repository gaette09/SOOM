import Foundation

struct GPXParsedRoute: Equatable {
    let coordinates: [WorkoutRouteCoordinate]
    let totalDistanceMeters: Double
    let summary: GPXWorkoutSummary

    var coordinateCount: Int {
        coordinates.count
    }
}

struct GPXWorkoutSummary: Equatable {
    let startDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let elevationGainMeters: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageCadence: Double?
}

enum GPXRouteParserError: Error, Equatable {
    case emptyData
    case fileTooLarge(maximumBytes: Int)
    case malformedXML
    case noTrackPoints
    case insufficientValidCoordinates(validCount: Int)
    case coordinateLimitExceeded(maximumCoordinates: Int)
}

struct GPXRouteParser {
    let maximumFileSizeBytes: Int
    let maximumCoordinateCount: Int

    init(
        maximumFileSizeBytes: Int = 10 * 1_024 * 1_024,
        maximumCoordinateCount: Int = 20_000
    ) {
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.maximumCoordinateCount = maximumCoordinateCount
    }

    func parse(_ data: Data) throws -> GPXParsedRoute {
        guard !data.isEmpty else {
            throw GPXRouteParserError.emptyData
        }
        guard data.count <= maximumFileSizeBytes else {
            throw GPXRouteParserError.fileTooLarge(maximumBytes: maximumFileSizeBytes)
        }

        let delegate = GPXRouteParserDelegate(maximumCoordinateCount: maximumCoordinateCount)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            if let error = delegate.error {
                throw error
            }
            throw GPXRouteParserError.malformedXML
        }

        if let error = delegate.error {
            throw error
        }

        let coordinates = delegate.coordinates
        guard delegate.sawTrackPoint else {
            throw GPXRouteParserError.noTrackPoints
        }
        guard coordinates.count >= 2 else {
            throw GPXRouteParserError.insufficientValidCoordinates(validCount: coordinates.count)
        }

        let totalDistanceMeters = Self.totalDistanceMeters(for: coordinates)
        return GPXParsedRoute(
            coordinates: coordinates,
            totalDistanceMeters: totalDistanceMeters,
            summary: delegate.makeSummary(totalDistanceMeters: totalDistanceMeters)
        )
    }

    func parse(_ string: String) throws -> GPXParsedRoute {
        try parse(Data(string.utf8))
    }

    private static func totalDistanceMeters(for coordinates: [WorkoutRouteCoordinate]) -> Double {
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
        let startLatitude = start.latitude.radians
        let endLatitude = end.latitude.radians
        let deltaLatitude = (end.latitude - start.latitude).radians
        let deltaLongitude = (end.longitude - start.longitude).radians

        let a = pow(sin(deltaLatitude / 2), 2)
            + cos(startLatitude) * cos(endLatitude) * pow(sin(deltaLongitude / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}

private final class GPXRouteParserDelegate: NSObject, XMLParserDelegate {
    private let maximumCoordinateCount: Int
    private let isoFormatter = ISO8601DateFormatter()
    private var activePoint: PendingTrackPoint?
    private var activeText = ""
    private var pointHeartRates: [Double] = []
    private var pointCadences: [Double] = []

    private(set) var coordinates: [WorkoutRouteCoordinate] = []
    private(set) var sawTrackPoint = false
    private(set) var error: GPXRouteParserError?

    init(maximumCoordinateCount: Int) {
        self.maximumCoordinateCount = maximumCoordinateCount
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard error == nil else {
            parser.abortParsing()
            return
        }

        let name = normalizedName(elementName)
        switch name {
        case "trkpt":
            sawTrackPoint = true
            activePoint = PendingTrackPoint(
                latitude: Double(attributeDict["lat"] ?? ""),
                longitude: Double(attributeDict["lon"] ?? "")
            )
            activeText = ""
        case "ele", "time", "hr", "cad":
            activeText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard activePoint != nil else { return }
        activeText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard error == nil else {
            parser.abortParsing()
            return
        }

        let name = normalizedName(elementName)
        switch name {
        case "ele":
            activePoint?.altitude = Double(activeText.trimmingCharacters(in: .whitespacesAndNewlines))
            activeText = ""
        case "time":
            activePoint?.timestamp = parseDate(activeText.trimmingCharacters(in: .whitespacesAndNewlines))
            activeText = ""
        case "hr":
            activePoint?.heartRate = validHeartRate(activeText.trimmingCharacters(in: .whitespacesAndNewlines))
            activeText = ""
        case "cad":
            activePoint?.cadence = validPositive(activeText.trimmingCharacters(in: .whitespacesAndNewlines))
            activeText = ""
        case "trkpt":
            appendActivePointIfValid()
            activePoint = nil
            activeText = ""
            if coordinates.count > maximumCoordinateCount {
                error = .coordinateLimitExceeded(maximumCoordinates: maximumCoordinateCount)
                parser.abortParsing()
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = .malformedXML
        }
    }

    func makeSummary(totalDistanceMeters: Double) -> GPXWorkoutSummary {
        let elevationGain = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            guard let from = pair.0.altitude, let to = pair.1.altitude else { return total }
            return total + max(0, to - from)
        }

        return GPXWorkoutSummary(
            startDate: coordinates.first?.timestamp,
            durationSeconds: inferredDuration(),
            distanceMeters: totalDistanceMeters,
            elevationGainMeters: elevationGain.nonZero,
            averageHeartRate: pointHeartRates.average,
            maxHeartRate: pointHeartRates.max(),
            averageCadence: pointCadences.average
        )
    }

    private func appendActivePointIfValid() {
        guard
            let activePoint,
            let latitude = activePoint.latitude,
            let longitude = activePoint.longitude,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return
        }

        coordinates.append(
            WorkoutRouteCoordinate(
                latitude: latitude,
                longitude: longitude,
                altitude: activePoint.altitude,
                timestamp: activePoint.timestamp
            )
        )
        if let heartRate = activePoint.heartRate {
            pointHeartRates.append(heartRate)
        }
        if let cadence = activePoint.cadence {
            pointCadences.append(cadence)
        }
    }

    private func inferredDuration() -> TimeInterval? {
        guard
            let firstTimestamp = coordinates.first?.timestamp,
            let lastTimestamp = coordinates.last?.timestamp
        else {
            return nil
        }

        return lastTimestamp.timeIntervalSince(firstTimestamp).nonZero
    }

    private func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        let date = isoFormatter.date(from: string)
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return date
    }

    private func validPositive(_ string: String) -> Double? {
        Double(string).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private func validHeartRate(_ string: String) -> Double? {
        Double(string).flatMap { $0.isFinite && (1...300).contains($0) ? $0 : nil }
    }

    private func normalizedName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

private struct PendingTrackPoint {
    let latitude: Double?
    let longitude: Double?
    var altitude: Double?
    var timestamp: Date?
    var heartRate: Double?
    var cadence: Double?
}

private extension Double {
    var radians: Double {
        self * .pi / 180
    }

    var nonZero: Double? {
        self > 0 ? self : nil
    }
}

private extension Array where Element == Double {
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
