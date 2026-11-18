import Foundation

/// Reads sensor channels even for indoor TCX files with no Position elements.
/// Garmin/Wahoo/Zwift-style ActivityExtension v2 values use the same SI model.
struct WorkoutTelemetryTCXParser {
    func parse(data: Data, workoutID: UUID, source: UnifiedDataSource) throws -> WorkoutTelemetry {
        guard !data.isEmpty else { throw TCXRouteParserError.emptyData }
        guard data.count <= 10 * 1_024 * 1_024 else { throw TCXRouteParserError.fileTooLarge(maximumBytes: 10 * 1_024 * 1_024) }
        // Workout exports do not require DTDs or entities.
        if let text = String(data: data, encoding: .utf8), text.uppercased().contains("<!DOCTYPE") {
            throw TCXRouteParserError.unsupportedDocument
        }
        _ = try TCXRouteParser(maximumLapCount: 2_000, maximumCoordinateCount: 100_000)
            .parse(data, allowMissingRoute: true)
        let delegate = TelemetryXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.exceededLimit else { throw TCXRouteParserError.malformedXML }
        return WorkoutTelemetry(workoutID: workoutID, source: source,
            samples: delegate.samples.map { var value = $0; value.source = source; return value },
            splits: delegate.splits)
    }
}

private final class TelemetryXMLDelegate: NSObject, XMLParserDelegate {
    private let tcx = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
    private let extensionV2 = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"
    private var stack: [String] = []
    private var text = ""
    private var point: WorkoutTelemetrySample?
    private var pointTime: Date?
    private var lapStart: Date?
    private var lapDuration: Double?
    private var lapDistance: Double?
    private var lapHR: Double?
    private var lapCadence: Double?
    private var isRunning = false
    private var count = 0
    private var lapCount = 0
    var samples: [WorkoutTelemetrySample] = []
    var splits: [WorkoutTelemetrySplit] = []
    var exceededLimit = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        stack.append(elementName)
        text = ""
        guard namespaceURI == tcx else { return }
        if elementName == "Activity" { isRunning = attributes["Sport"]?.lowercased() == "running" }
        if elementName == "Lap" {
            lapStart = date(attributes["StartTime"] ?? "")
            lapDuration = nil; lapDistance = nil; lapHR = nil; lapCadence = nil
        }
        if elementName == "Trackpoint" {
            point = WorkoutTelemetrySample(timestamp: .distantPast)
            pointTime = nil
            count += 1
            if count > 100_000 { exceededLimit = true; parser.abortParsing() }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        if namespaceURI == tcx {
            switch name {
            case "Time" where point != nil: pointTime = date(value)
            case "DistanceMeters" where parent == "Trackpoint": point?.distanceMeters = number(value, 0...10_000_000)
            case "AltitudeMeters" where point != nil: point?.elevationMeters = number(value, -1_000...12_000)
            case "Value" where parent == "HeartRateBpm": point?.heartRateBPM = number(value, 1...300)
            case "Cadence" where point != nil:
                point?.cadencePerMinute = number(value, 0...400)
                point?.cadenceUnit = isRunning ? .stepsPerMinute : .revolutionsPerMinute
            case "TotalTimeSeconds" where parent == "Lap": lapDuration = number(value, 0...604_800)
            case "DistanceMeters" where parent == "Lap": lapDistance = number(value, 0...10_000_000)
            case "Value" where parent == "AverageHeartRateBpm": lapHR = number(value, 1...300)
            case "Cadence" where parent == "Lap": lapCadence = number(value, 0...400)
            case "Trackpoint":
                if var point, let pointTime, point.hasMeasurement {
                    point.timestamp = pointTime
                    samples.append(point)
                }
                point = nil; pointTime = nil
            case "Lap":
                lapCount += 1
                if let lapStart, let duration = lapDuration, duration > 0 {
                    splits.append(WorkoutTelemetrySplit(label: "랩 \(lapCount)", startDate: lapStart,
                        endDate: lapStart.addingTimeInterval(duration), durationSeconds: duration,
                        distanceMeters: lapDistance, averageHeartRate: lapHR, averageCadence: lapCadence,
                        provenance: .tcxLapElement))
                }
            default: break
            }
        } else if namespaceURI == extensionV2, point != nil {
            switch name {
            case "Watts": point?.powerWatts = number(value, 0...5_000)
            case "Speed": point?.speedMetersPerSecond = number(value, 0...150)
            case "RunCadence":
                // TCX RunCadence is strides/minute; SOOM running cadence is steps/minute.
                point?.cadencePerMinute = number(value, 0...200).map { $0 * 2 }
                point?.cadenceUnit = .stepsPerMinute
            default: break
            }
        }
        _ = stack.popLast()
        text = ""
    }

    private func number(_ string: String, _ range: ClosedRange<Double>) -> Double? {
        Double(string).flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }
    private func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
