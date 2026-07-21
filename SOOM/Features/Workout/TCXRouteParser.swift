import Foundation

struct TCXParsedRoute: Equatable {
    let coordinates: [WorkoutRouteCoordinate]
    let totalDistanceMeters: Double
    let summary: TCXWorkoutSummary

    var coordinateCount: Int { coordinates.count }
}

struct TCXWorkoutSummary: Equatable {
    let workoutType: UnifiedWorkoutType?
    let startDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let averageSpeedMetersPerSecond: Double?
    let elevationGainMeters: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let averageCadence: Double?
    let averagePower: Double?
}

enum TCXRouteParserError: Error, Equatable {
    case emptyData
    case fileTooLarge(maximumBytes: Int)
    case malformedXML
    case unsupportedDocument
    case missingActivity
    case multipleActivities
    case lapLimitExceeded(maximumLaps: Int)
    case noTrackPoints
    case insufficientValidCoordinates(validCount: Int)
    case coordinateLimitExceeded(maximumCoordinates: Int)
}

struct TCXRouteParser {
    let maximumFileSizeBytes: Int
    let maximumLapCount: Int
    let maximumCoordinateCount: Int

    init(
        maximumFileSizeBytes: Int = 10 * 1_024 * 1_024,
        maximumLapCount: Int = 100,
        maximumCoordinateCount: Int = 20_000
    ) {
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.maximumLapCount = maximumLapCount
        self.maximumCoordinateCount = maximumCoordinateCount
    }

    func parse(_ data: Data) throws -> TCXParsedRoute {
        guard !data.isEmpty else { throw TCXRouteParserError.emptyData }
        guard data.count <= maximumFileSizeBytes else {
            throw TCXRouteParserError.fileTooLarge(maximumBytes: maximumFileSizeBytes)
        }

        let delegate = TCXRouteParserDelegate(
            maximumLapCount: maximumLapCount,
            maximumCoordinateCount: maximumCoordinateCount
        )
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.error == nil else {
            throw delegate.error ?? .malformedXML
        }
        guard delegate.sawAcceptedRoot else { throw TCXRouteParserError.unsupportedDocument }
        guard delegate.activityCount > 0 else { throw TCXRouteParserError.missingActivity }
        guard delegate.activityCount == 1 else { throw TCXRouteParserError.multipleActivities }
        guard delegate.sawTrackPoint else { throw TCXRouteParserError.noTrackPoints }
        guard delegate.coordinates.count >= 2 else {
            throw TCXRouteParserError.insufficientValidCoordinates(validCount: delegate.coordinates.count)
        }
        return delegate.makeParsedRoute()
    }

    func parse(_ string: String) throws -> TCXParsedRoute { try parse(Data(string.utf8)) }
}

private final class TCXRouteParserDelegate: NSObject, XMLParserDelegate {
    private static let tcxNamespace = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
    private static let activityExtensionNamespace = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"

    private let maximumLapCount: Int
    private let maximumCoordinateCount: Int
    private let isoFormatter = ISO8601DateFormatter()
    private var elementStack: [(name: String, namespace: String?)] = []
    private var activeText = ""
    private var activePoint: PendingTCXTrackPoint?
    private var activeLap: PendingTCXLap?
    private var activityStartDate: Date?
    private var workoutType: UnifiedWorkoutType?
    private var lapSummaries: [TCXLapSummary] = []
    private var pointHeartRates: [Double] = []
    private var pointCadences: [Double] = []
    private var pointPowers: [Double] = []
    private var activityExtensionDepth = 0

    private(set) var coordinates: [WorkoutRouteCoordinate] = []
    private(set) var sawAcceptedRoot = false
    private(set) var activityCount = 0
    private(set) var sawTrackPoint = false
    private(set) var error: TCXRouteParserError?

    init(maximumLapCount: Int, maximumCoordinateCount: Int) {
        self.maximumLapCount = maximumLapCount
        self.maximumCoordinateCount = maximumCoordinateCount
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard error == nil else { parser.abortParsing(); return }
        let name = normalizedName(qName ?? elementName)
        let parent = elementStack.last
        elementStack.append((name, namespaceURI))
        activeText = ""

        if elementStack.count == 1 {
            guard name == "TrainingCenterDatabase", namespaceURI == Self.tcxNamespace else {
                fail(.unsupportedDocument, parser: parser)
                return
            }
            sawAcceptedRoot = true
        }
        guard sawAcceptedRoot else { return }

        if namespaceURI == Self.activityExtensionNamespace { activityExtensionDepth += 1 }
        guard namespaceURI == Self.tcxNamespace else { return }
        switch name {
        case "Activity" where parent?.name == "Activities":
            activityCount += 1
            if activityCount > 1 { fail(.multipleActivities, parser: parser); return }
            workoutType = mapSport(attributeDict["Sport"])
        case "Lap" where activeLap == nil:
            if lapSummaries.count >= maximumLapCount { fail(.lapLimitExceeded(maximumLaps: maximumLapCount), parser: parser); return }
            activeLap = PendingTCXLap(startDate: parseDate(attributeDict["StartTime"] ?? ""))
        case "Trackpoint" where activeLap != nil:
            sawTrackPoint = true
            activePoint = PendingTCXTrackPoint()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { activeText += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalizedName(qName ?? elementName)
        let text = activeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = elementStack.dropLast().last
        if namespaceURI == Self.tcxNamespace {
            switch name {
            case "Id" where parent?.name == "Activity": activityStartDate = parseDate(text)
            case "TotalTimeSeconds": activeLap?.durationSeconds = validNonnegative(text)
            case "DistanceMeters": activeLap?.distanceMeters = validNonnegative(text)
            case "Calories": activeLap?.calories = validPositive(text)
            case "Value" where parent?.name == "AverageHeartRateBpm": activeLap?.averageHeartRate = validHeartRate(text)
            case "Value" where parent?.name == "MaximumHeartRateBpm": activeLap?.maxHeartRate = validHeartRate(text)
            case "Cadence" where activePoint == nil: activeLap?.averageCadence = validPositive(text)
            case "LatitudeDegrees": activePoint?.latitude = Double(text)
            case "LongitudeDegrees": activePoint?.longitude = Double(text)
            case "AltitudeMeters": activePoint?.altitude = Double(text).flatMap { $0.isFinite ? $0 : nil }
            case "Time": activePoint?.timestamp = parseDate(text)
            case "Value" where parent?.name == "HeartRateBpm": activePoint?.heartRate = validHeartRate(text)
            case "Cadence" where activePoint != nil: activePoint?.cadence = validPositive(text)
            case "Trackpoint": appendActivePointIfValid(parser)
            case "Lap": appendActiveLap()
            default: break
            }
        } else if namespaceURI == Self.activityExtensionNamespace, name == "Watts", activityExtensionDepth > 0 {
            activePoint?.power = validPositive(text)
        }

        if namespaceURI == Self.activityExtensionNamespace { activityExtensionDepth -= 1 }
        _ = elementStack.popLast()
        activeText = ""
        if error != nil { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil { error = .malformedXML }
    }

    func makeParsedRoute() -> TCXParsedRoute {
        let routeDistance = Self.totalDistanceMeters(for: coordinates)
        let duration = lapSummaries.compactMap(\.durationSeconds).reduce(0, +)
        let summaryDistance = lapSummaries.compactMap(\.distanceMeters).reduce(0, +)
        let elevationGain = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            guard let from = pair.0.altitude, let to = pair.1.altitude else { return total }
            return total + max(0, to - from)
        }
        let startDate = activityStartDate ?? lapSummaries.compactMap(\.startDate).first ?? coordinates.compactMap(\.timestamp).first
        let usableDistance = summaryDistance.nonZero
        return TCXParsedRoute(
            coordinates: coordinates,
            totalDistanceMeters: usableDistance ?? routeDistance,
            summary: TCXWorkoutSummary(
                workoutType: workoutType,
                startDate: startDate,
                durationSeconds: duration.nonZero ?? inferredDuration(),
                distanceMeters: usableDistance,
                activeEnergyKcal: lapSummaries.compactMap(\.calories).reduce(0, +).nonZero,
                averageSpeedMetersPerSecond: duration.nonZero.map { summaryDistance / $0 },
                elevationGainMeters: elevationGain.nonZero,
                averageHeartRate: weightedAverage(lapSummaries.compactMap { guard let duration = $0.durationSeconds, let value = $0.averageHeartRate else { return nil }; return (duration, value) }) ?? pointHeartRates.average,
                maxHeartRate: lapSummaries.compactMap(\.maxHeartRate).max() ?? pointHeartRates.max(),
                averageCadence: weightedAverage(lapSummaries.compactMap { guard let duration = $0.durationSeconds, let value = $0.averageCadence else { return nil }; return (duration, value) }) ?? pointCadences.average,
                averagePower: pointPowers.average
            )
        )
    }

    private func appendActivePointIfValid(_ parser: XMLParser) {
        defer { activePoint = nil }
        guard let point = activePoint, let latitude = point.latitude, let longitude = point.longitude,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }
        coordinates.append(WorkoutRouteCoordinate(latitude: latitude, longitude: longitude, altitude: point.altitude, timestamp: point.timestamp))
        if let value = point.heartRate { pointHeartRates.append(value) }
        if let value = point.cadence { pointCadences.append(value) }
        if let value = point.power { pointPowers.append(value) }
        if coordinates.count > maximumCoordinateCount { fail(.coordinateLimitExceeded(maximumCoordinates: maximumCoordinateCount), parser: parser) }
    }

    private func appendActiveLap() { if let activeLap { lapSummaries.append(activeLap.summary) }; activeLap = nil }
    private func inferredDuration() -> TimeInterval? {
        guard let first = coordinates.compactMap(\.timestamp).first, let last = coordinates.compactMap(\.timestamp).last else { return nil }
        return max(0, last.timeIntervalSince(first)).nonZero
    }
    private func fail(_ value: TCXRouteParserError, parser: XMLParser) { error = value; parser.abortParsing() }
    private func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        defer { isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
        return isoFormatter.date(from: string)
    }
    private func validNonnegative(_ string: String) -> Double? { Double(string).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
    private func validPositive(_ string: String) -> Double? { Double(string).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
    private func validHeartRate(_ string: String) -> Double? { Double(string).flatMap { $0.isFinite && (1...300).contains($0) ? $0 : nil } }
    private func normalizedName(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
    private func mapSport(_ value: String?) -> UnifiedWorkoutType? { switch value?.lowercased() { case "biking": .cycling; case "running": .running; case "walking": .walking; case "hiking": .hiking; case "swimming": .swimming; default: .other } }
    private func weightedAverage(_ values: [(Double, Double)]) -> Double? { let weight = values.reduce(0) { $0 + $1.0 }; return weight > 0 ? values.reduce(0) { $0 + $1.0 * $1.1 } / weight : nil }
    private static func totalDistanceMeters(for coordinates: [WorkoutRouteCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            let a = pair.0.latitude * .pi / 180, b = pair.1.latitude * .pi / 180
            let dLat = b - a, dLon = (pair.1.longitude - pair.0.longitude) * .pi / 180
            let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLon / 2), 2)
            return total + 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
        }
    }
}

private struct PendingTCXTrackPoint { var latitude: Double?; var longitude: Double?; var altitude: Double?; var timestamp: Date?; var heartRate: Double?; var cadence: Double?; var power: Double? }
private struct PendingTCXLap { let startDate: Date?; var durationSeconds: Double?; var distanceMeters: Double?; var calories: Double?; var averageHeartRate: Double?; var maxHeartRate: Double?; var averageCadence: Double?; var summary: TCXLapSummary { TCXLapSummary(startDate: startDate, durationSeconds: durationSeconds, distanceMeters: distanceMeters, calories: calories, averageHeartRate: averageHeartRate, maxHeartRate: maxHeartRate, averageCadence: averageCadence) } }
private struct TCXLapSummary { let startDate: Date?; let durationSeconds: Double?; let distanceMeters: Double?; let calories: Double?; let averageHeartRate: Double?; let maxHeartRate: Double?; let averageCadence: Double? }
private extension Double { var nonZero: Double? { self > 0 ? self : nil } }
private extension Array where Element == Double { var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) } }
