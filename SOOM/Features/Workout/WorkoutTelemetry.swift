import Foundation

/// Provider-neutral, measured workout detail. Units are explicit in property names.
/// A missing channel stays missing; a summary average never becomes a flat series.
struct WorkoutTelemetry: Codable, Equatable {
    var workoutID: UUID
    var source: UnifiedDataSource
    var samples: [WorkoutTelemetrySample] = []
    var intervals: [WorkoutTelemetryInterval] = []
    var splits: [WorkoutTelemetrySplit] = []
    var heartRateZones: [WorkoutTelemetryZone] = []
    var summaryMetrics: [WorkoutTelemetrySummaryMetric] = []
    var fetchedAt: Date = Date()
    var events: [WorkoutTelemetryEvent] = []

    var isEmpty: Bool {
        samples.isEmpty && intervals.isEmpty && splits.isEmpty && heartRateZones.isEmpty && summaryMetrics.isEmpty && events.isEmpty
    }

    /// A measured aggregate is useful even when HealthKit supplies no series.
    /// Keep it as a labelled summary, never a flat chart or invented zone time.
    func displaySummaryMetrics(for workout: UnifiedWorkout) -> [WorkoutTelemetrySummaryMetric] {
        var result = summaryMetrics
        guard !samples.contains(where: { $0.heartRateBPM != nil }) else { return result }
        for (key, label, value) in [("averageHeartRate", "평균 심박", workout.averageHeartRate),
                                    ("maxHeartRate", "최고 심박", workout.maxHeartRate)] {
            guard let value, value.isFinite, (1...300).contains(value),
                  !result.contains(where: { $0.key == key }) else { continue }
            result.append(.init(key: key, label: label, value: value, unit: "bpm"))
        }
        return result
    }

    /// TCX and the provider's dedicated channels may describe the same instant.
    /// Merge only exact timestamps from the same source, retaining earlier fields
    /// when the incoming row omits them. Different providers keep provenance.
    func coalescingSamples() -> WorkoutTelemetry {
        struct Key: Hashable { let timestamp: Date; let source: String }
        var byKey: [Key: WorkoutTelemetrySample] = [:]
        for incoming in samples {
            let effectiveSource = incoming.source ?? source
            let key = Key(timestamp: incoming.timestamp, source: effectiveSource.rawValue)
            var value = byKey[key] ?? WorkoutTelemetrySample(timestamp: incoming.timestamp, source: effectiveSource)
            value.distanceMeters = incoming.distanceMeters ?? value.distanceMeters
            value.heartRateBPM = incoming.heartRateBPM ?? value.heartRateBPM
            value.cadencePerMinute = incoming.cadencePerMinute ?? value.cadencePerMinute
            value.powerWatts = incoming.powerWatts ?? value.powerWatts
            value.speedMetersPerSecond = incoming.speedMetersPerSecond ?? value.speedMetersPerSecond
            value.elevationMeters = incoming.elevationMeters ?? value.elevationMeters
            value.cadenceUnit = incoming.cadenceUnit ?? value.cadenceUnit
            byKey[key] = value
        }
        var result = self
        result.samples = byKey.values.sorted {
            $0.timestamp == $1.timestamp ? ($0.source?.rawValue ?? "") < ($1.source?.rawValue ?? "") : $0.timestamp < $1.timestamp
        }
        return result
    }

    /// Keep the richer measured stream for each channel, rather than adding two
    /// copies of one physical activity. Each sample retains its original source.
    func merging(_ other: WorkoutTelemetry) -> WorkoutTelemetry {
        var result = self
        let incomingDistance = other.samples.filter { $0.distanceMeters != nil }
        if incomingDistance.count > samples.filter({ $0.distanceMeters != nil }).count {
            result.samples = result.samples.map { var copy = $0; copy.distanceMeters = nil; return copy }
                .filter(\.hasMeasurement)
            result.samples += incomingDistance.map {
                WorkoutTelemetrySample(timestamp: $0.timestamp, distanceMeters: $0.distanceMeters,
                    source: $0.source ?? other.source)
            }
        }
        for channel in WorkoutTelemetryChannel.allCases {
            let existing = result.samples.filter { $0.value(for: channel) != nil }
            let incoming = other.samples.filter { $0.value(for: channel) != nil }
            guard incoming.count > existing.count else { continue }
            result.samples = result.samples.map { $0.removing(channel) }.filter(\.hasMeasurement)
            result.samples += incoming.map { $0.only(channel, fallbackSource: other.source) }
        }
        for kind in WorkoutTelemetryInterval.Kind.allCases {
            let existing = result.intervals.filter { $0.kind == kind }
            let incoming = other.intervals.filter { $0.kind == kind }
            if incoming.count > existing.count {
                result.intervals.removeAll { $0.kind == kind }
                result.intervals += incoming
            }
        }
        if result.splits.isEmpty { result.splits = other.splits }
        else if workoutID == other.workoutID && source == other.source {
            // A fresh parser may establish provenance for an unchanged historical
            // row. Do not infer it from labels or borrow another source's evidence.
            result.splits = result.splits.map { old in
                guard old.provenance == nil else { return old }
                let matches = other.splits.filter {
                    $0.provenance != nil && $0.provenance != .unknown
                        && $0.startDate == old.startDate && $0.endDate == old.endDate
                        && $0.durationSeconds == old.durationSeconds && $0.distanceMeters == old.distanceMeters
                }
                guard matches.count == 1 else { return old }
                var enriched = old; enriched.provenance = matches[0].provenance
                return enriched
            }
        }
        if result.heartRateZones.isEmpty { result.heartRateZones = other.heartRateZones }
        if result.events.isEmpty { result.events = other.events }
        let existingKeys = Set(result.summaryMetrics.map(\.key))
        result.summaryMetrics += other.summaryMetrics.filter { !existingKeys.contains($0.key) }
        result.fetchedAt = max(fetchedAt, other.fetchedAt)
        result.samples.sort { $0.timestamp < $1.timestamp }
        return result
    }

    /// Clamp the persisted data to the workout's own interval. Reject non-finite
    /// values and invalid ranges before serializing or plotting imported input.
    func validated(for workout: UnifiedWorkout) -> WorkoutTelemetry {
        var result = self
        result.workoutID = workout.id
        result.samples = samples.compactMap { original in
            guard original.timestamp >= workout.startDate.addingTimeInterval(-2),
                  original.timestamp <= workout.endDate.addingTimeInterval(2) else { return nil }
            var sample = original
            sample.distanceMeters = valid(original.distanceMeters, in: 0...10_000_000)
            sample.heartRateBPM = valid(original.heartRateBPM, in: 1...300)
            sample.cadencePerMinute = valid(original.cadencePerMinute, in: 0...400)
            sample.powerWatts = valid(original.powerWatts, in: 0...5_000)
            sample.speedMetersPerSecond = valid(original.speedMetersPerSecond, in: 0...150)
            sample.elevationMeters = valid(original.elevationMeters, in: -1_000...12_000)
            sample.source = original.source ?? source
            return sample.hasMeasurement ? sample : nil
        }.sorted { $0.timestamp < $1.timestamp }
        result.intervals = intervals.filter {
            $0.value.isFinite && ($0.kind == .elevationGainMeters || $0.value >= 0) && $0.startDate < $0.endDate
                && $0.startDate >= workout.startDate.addingTimeInterval(-2)
                && $0.endDate <= workout.endDate.addingTimeInterval(2)
        }
        result.splits = splits.filter {
            $0.durationSeconds.isFinite && $0.durationSeconds > 0 && $0.startDate < $0.endDate
                && $0.startDate >= workout.startDate.addingTimeInterval(-2)
                && $0.endDate <= workout.endDate.addingTimeInterval(2)
                && ($0.distanceMeters.map { $0.isFinite && $0 >= 0 } ?? true)
        }
        result.splits = result.splits.map { split in
            var next = split
            next.averageHeartRate = valid(split.averageHeartRate, in: 1...300)
            next.averagePowerWatts = valid(split.averagePowerWatts, in: 0...5_000)
            next.averageCadence = valid(split.averageCadence, in: 0...400)
            next.elevationChangeMeters = valid(split.elevationChangeMeters, in: -13_000...13_000)
            return next
        }
        result.heartRateZones = heartRateZones.filter {
            $0.durationSeconds.isFinite && $0.durationSeconds >= 0
                && $0.durationSeconds <= workout.endDate.timeIntervalSince(workout.startDate) + 2
        }
        result.summaryMetrics = summaryMetrics.filter { $0.value.isFinite }
        result.events = events.filter {
            $0.timestamp >= workout.startDate && $0.timestamp <= workout.endDate
        }
        return result
    }

    private func valid(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }
}

enum WorkoutTelemetryCadenceUnit: String, Codable {
    case stepsPerMinute, revolutionsPerMinute
    var symbol: String { self == .stepsPerMinute ? "spm" : "rpm" }
}

enum WorkoutTelemetryChannel: String, CaseIterable, Identifiable {
    case heartRate, cadence, power, speed, elevation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .heartRate: "심박수"
        case .cadence: "케이던스"
        case .power: "파워"
        case .speed: "속도"
        case .elevation: "고도"
        }
    }
    var unit: String {
        switch self {
        case .heartRate: "bpm"
        case .cadence: "rpm"
        case .power: "W"
        case .speed: "km/h"
        case .elevation: "m"
        }
    }
}

struct WorkoutTelemetrySample: Codable, Equatable {
    var timestamp: Date
    var distanceMeters: Double? = nil
    var heartRateBPM: Double? = nil
    var cadencePerMinute: Double? = nil
    var powerWatts: Double? = nil
    var speedMetersPerSecond: Double? = nil
    var elevationMeters: Double? = nil
    var cadenceUnit: WorkoutTelemetryCadenceUnit? = nil
    var source: UnifiedDataSource? = nil

    var hasMeasurement: Bool {
        distanceMeters != nil || WorkoutTelemetryChannel.allCases.contains { value(for: $0) != nil }
    }
    func value(for channel: WorkoutTelemetryChannel) -> Double? {
        switch channel {
        case .heartRate: heartRateBPM
        case .cadence: cadencePerMinute
        case .power: powerWatts
        case .speed: speedMetersPerSecond
        case .elevation: elevationMeters
        }
    }
    func removing(_ channel: WorkoutTelemetryChannel) -> Self {
        var copy = self
        switch channel {
        case .heartRate: copy.heartRateBPM = nil
        case .cadence: copy.cadencePerMinute = nil
        case .power: copy.powerWatts = nil
        case .speed: copy.speedMetersPerSecond = nil
        case .elevation: copy.elevationMeters = nil
        }
        return copy
    }
    func only(_ channel: WorkoutTelemetryChannel, fallbackSource: UnifiedDataSource) -> Self {
        var copy = self
        for other in WorkoutTelemetryChannel.allCases where other != channel { copy = copy.removing(other) }
        copy.source = source ?? fallbackSource
        return copy
    }
}

struct WorkoutTelemetryInterval: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case distanceMeters, steps, energyKcal, elevationGainMeters, activeZoneMinutes, swimStrokeCount
    }
    var kind: Kind
    var startDate: Date
    var endDate: Date
    var value: Double
    var zone: String? = nil
}

/// Recorded parser provenance; missing historical values remain nil/unknown.
/// A label or provider summary is never sufficient evidence of a source lap.
enum WorkoutTelemetrySplitProvenance: String, Codable {
    case healthKitLapEvent, healthKitSegmentEvent, tcxLapElement, unknown
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .unknown
    }
}

struct WorkoutTelemetrySplit: Codable, Equatable {
    var label: String
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double? = nil
    var averageHeartRate: Double? = nil
    var averagePowerWatts: Double? = nil
    var averageCadence: Double? = nil
    /// Signed end-minus-start altitude; not cumulative ascent. Nil means unmeasured.
    var elevationChangeMeters: Double? = nil
    var provenance: WorkoutTelemetrySplitProvenance? = nil
}

struct WorkoutTelemetryZone: Codable, Equatable {
    var name: String
    var durationSeconds: Double
}

struct WorkoutTelemetrySummaryMetric: Codable, Equatable, Identifiable {
    var key: String
    var label: String
    var value: Double
    var unit: String
    var id: String { key }
}

struct WorkoutTelemetryEvent: Codable, Equatable {
    var timestamp: Date
    var type: String
}


struct WorkoutHeartRateZoneDisplay: Identifiable, Equatable {
    let index: Int
    let durationSeconds: Double?
    var id: Int { index }
    static func index(for name: String) -> Int? {
        let normalized = name.lowercased().replacingOccurrences(of: "zone", with: "z").replacingOccurrences(of: " ", with: "")
        guard normalized.first == "z", let index = Int(normalized.dropFirst()), (1...5).contains(index) else { return nil }
        return index
    }
    static func rows(_ input: [WorkoutTelemetryZone]) -> [Self] {
        var values: [Int: Double] = [:]
        for zone in input where zone.durationSeconds.isFinite && zone.durationSeconds >= 0 {
            guard let index = index(for: zone.name) else { continue }
            values[index, default: 0] += zone.durationSeconds
        }
        return (1...5).map { .init(index: $0, durationSeconds: values[$0]) }
    }
}

/// Split-only formatting. Sensor/zone calculations and other sports stay intact.
struct WorkoutSplitDisplay {
    let type: UnifiedWorkoutType
    let preferredUnit: TrainingPreferredUnit
    var showsLapDuration = false
    var isCycling: Bool { type == .cycling }
    var isRunning: Bool { type == .running }
    var isSwimming: Bool { type == .swimming }
    var isLapTiming: Bool { isSwimming && showsLapDuration }
    var title: String { isLapTiming ? "랩 시간" : (isCycling ? "평균 속도" : "페이스") }
    var metersPerUnit: Double { preferredUnit == .imperial ? 1609.344 : 1000 }
    var unit: String { isLapTiming ? "" : isCycling ? (preferredUnit == .imperial ? "mph" : "km/h") : (isRunning && preferredUnit == .imperial ? "/mi" : "/km") }
    func value(distance: Double?, seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0, let distance, distance.isFinite, distance >= 0 else { return nil }
        let result: Double
        if isCycling { result = distance / metersPerUnit / (seconds / 3600) }
        else {
            guard distance > 0 else { return nil }
            result = seconds / (distance / (isRunning ? metersPerUnit : 1000))
        }
        return result.isFinite ? result : nil
    }
    func text(distance: Double?, seconds: Double) -> String {
        if isLapTiming { return seconds.isFinite && seconds > 0 ? Self.duration(seconds) : "—" }
        guard let value = value(distance: distance, seconds: seconds), value.isFinite else { return "—" }
        return isCycling ? String(format: "%.1f %@", value, unit) : Self.duration(value) + unit
    }
    func distanceText(_ meters: Double?) -> String? {
        guard let meters, meters.isFinite, meters >= 0 else { return nil }
        if isLapTiming { return String(format: "%.0f m", meters) }
        let useImperial = (isCycling || isRunning) && preferredUnit == .imperial
        return String(format: "%.2f %@", meters / (useImperial ? 1609.344 : 1000), useImperial ? "mi" : "km")
    }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 2) else { return "—" }
        let total = Int(seconds.rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total/3600,total/60%60,total%60) : String(format: "%d:%02d",total/60,total%60)
    }
}
