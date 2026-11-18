import Foundation

struct WorkoutTelemetryChartPoint: Identifiable {
    let seconds: Double
    let value: Double
    let segment: Int
    var id: Double { seconds }
}

enum WorkoutTelemetryChartBuilder {
    /// Time is a real axis for indoor workouts too. Never spread a summary
    /// distance uniformly over time to manufacture a distance-based graph.
    static func points(_ telemetry: WorkoutTelemetry, channel: WorkoutTelemetryChannel,
                       start: Date, end: Date? = nil) -> [WorkoutTelemetryChartPoint] {
        let readings = telemetry.samples.compactMap { sample -> (Date, Double)? in
            guard let value = sample.value(for: channel), channel.accepts(value),
                  sample.timestamp >= start, end.map({ sample.timestamp <= $0 }) ?? true else { return nil }
            return (sample.timestamp, channel == .speed ? value * 3.6 : value)
        }.sorted { $0.0 < $1.0 }
        var unique: [(Date, Double)] = []
        for reading in readings {
            if unique.last?.0 == reading.0 { continue }
            unique.append(reading)
        }
        let gaps = zip(unique, unique.dropFirst()).map { $1.0.timeIntervalSince($0.0) }.filter { $0 > 0 }.sorted()
        let gapLimit = max(5, min(300, gaps.isEmpty ? 120 : gaps[gaps.count / 2] * 4))
        var segment = 0
        return unique.enumerated().map { index, reading in
            if index > 0, reading.0.timeIntervalSince(unique[index - 1].0) > gapLimit { segment += 1 }
            return WorkoutTelemetryChartPoint(seconds: reading.0.timeIntervalSince(start),
                value: reading.1, segment: segment)
        }
    }

    /// Adds only channels that lack actual sensor readings. GPS-derived speed
    /// and interval-average speed remain visibly labelled as derived values.
    static func addingDerivedChannels(to telemetry: WorkoutTelemetry, route: WorkoutRoute?) -> WorkoutTelemetry {
        var result = telemetry
        if !telemetry.samples.contains(where: { $0.cadencePerMinute != nil }) {
            result.samples += telemetry.intervals.filter { $0.kind == .steps }.compactMap { interval in
                let duration = interval.endDate.timeIntervalSince(interval.startDate)
                guard duration > 0 else { return nil }
                let cadence = interval.value * 60 / duration
                guard cadence.isFinite, (0...400).contains(cadence) else { return nil }
                return WorkoutTelemetrySample(timestamp: interval.startDate.addingTimeInterval(duration / 2),
                    cadencePerMinute: cadence, cadenceUnit: .stepsPerMinute, source: telemetry.source)
            }
        }
        let hasSpeed = telemetry.samples.contains { $0.speedMetersPerSecond != nil }
        let hasElevation = telemetry.samples.contains { $0.elevationMeters != nil }
        let hasDistance = telemetry.samples.contains { $0.distanceMeters != nil }
        if !hasDistance {
            let intervals = telemetry.intervals.filter { $0.kind == .distanceMeters }.sorted { $0.startDate < $1.startDate }
            if let first = intervals.first {
                var total = 0.0
                result.samples.append(WorkoutTelemetrySample(timestamp: first.startDate, distanceMeters: 0,
                    source: telemetry.source))
                for interval in intervals {
                    total += interval.value
                    result.samples.append(WorkoutTelemetrySample(timestamp: interval.endDate, distanceMeters: total,
                        source: telemetry.source))
                }
            }
        }
        if !hasSpeed {
            let intervals = telemetry.intervals.filter { $0.kind == .distanceMeters }.sorted { $0.startDate < $1.startDate }
            if !intervals.isEmpty {
                result.samples += intervals.compactMap { interval in
                    let duration = interval.endDate.timeIntervalSince(interval.startDate)
                    guard duration > 0, interval.value >= 0 else { return nil }
                    let speed = interval.value / duration
                    guard speed.isFinite, speed <= 150 else { return nil }
                    return WorkoutTelemetrySample(timestamp: interval.startDate.addingTimeInterval(duration / 2),
                        speedMetersPerSecond: speed, source: telemetry.source)
                }
            }
        }
        guard let route else { return result }
        let deriveSpeed = !result.samples.contains { $0.speedMetersPerSecond != nil }
        let deriveDistance = !result.samples.contains { $0.distanceMeters != nil }
        var accumulated = 0.0
        for (index, coordinate) in route.coordinates.enumerated() {
            guard let time = coordinate.timestamp else { continue }
            var speed: Double?
            if index > 0 {
                let previous = route.coordinates[index - 1]
                if previous.segmentIndex == coordinate.segmentIndex {
                    let delta = distance(previous, coordinate)
                    accumulated += delta
                    if deriveSpeed, let previousTime = previous.timestamp {
                        let duration = time.timeIntervalSince(previousTime)
                        if duration > 0, duration <= 120, delta / duration <= 150 { speed = delta / duration }
                    }
                }
            }
            let point = WorkoutTelemetrySample(timestamp: time, distanceMeters: deriveDistance ? accumulated : nil,
                speedMetersPerSecond: speed, elevationMeters: hasElevation ? nil : coordinate.altitude,
                source: route.source)
            if point.hasMeasurement { result.samples.append(point) }
        }
        return result
    }

    static func derivedSplits(_ telemetry: WorkoutTelemetry, workoutType: UnifiedWorkoutType? = nil) -> [WorkoutTelemetrySplit] {
        // Pool laps require original event intervals; distance-only data is not a lap.
        if workoutType == .swimming && telemetry.splits.isEmpty { return [] }
        if !telemetry.splits.isEmpty { return measuredSplitDetails(telemetry.splits, samples: telemetry.samples) }
        let points = telemetry.samples.filter { $0.distanceMeters != nil }.sorted { $0.timestamp < $1.timestamp }
        guard let first = points.first, let initialDistance = first.distanceMeters else { return [] }
        var splitStart = first.timestamp
        var threshold = initialDistance + 1_000
        var results: [WorkoutTelemetrySplit] = []
        for pair in zip(points, points.dropFirst()) {
            guard let from = pair.0.distanceMeters, let to = pair.1.distanceMeters, to > from else { continue }
            let duration = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard duration > 0, duration <= 120 else {
                // Missing time/route continuity cannot produce a reliable split.
                return []
            }
            while to >= threshold, results.count < 2_000 {
                let crossing = pair.0.timestamp.addingTimeInterval(duration * (threshold - from) / (to - from))
                let seconds = crossing.timeIntervalSince(splitStart)
                guard seconds > 0 else { break }
                results.append(WorkoutTelemetrySplit(label: "\(results.count + 1) km", startDate: splitStart,
                    endDate: crossing, durationSeconds: seconds, distanceMeters: 1_000))
                threshold += 1_000
                splitStart = crossing
            }
        }
        return measuredSplitDetails(results, samples: telemetry.samples)
    }

    /// Preserve provider values. Fill only missing details from measured streams
    /// within the split, using the same bounded continuity as heart-rate zones.
    static func measuredSplitDetails(_ splits: [WorkoutTelemetrySplit], samples: [WorkoutTelemetrySample]) -> [WorkoutTelemetrySplit] {
        let heart = samples.filter { $0.heartRateBPM.map { $0.isFinite && (1...300).contains($0) } ?? false }.sorted { $0.timestamp < $1.timestamp }
        let altitude = samples.filter { $0.elevationMeters.map { $0.isFinite && (-1000...12000).contains($0) } ?? false }.sorted { $0.timestamp < $1.timestamp }
        func elevation(at date: Date) -> Double? {
            if let exact = altitude.first(where: { $0.timestamp == date }) { return exact.elevationMeters }
            guard let a = altitude.last(where: { $0.timestamp < date }), let b = altitude.first(where: { $0.timestamp > date }),
                  let lo = a.elevationMeters, let hi = b.elevationMeters else { return nil }
            let interval = b.timestamp.timeIntervalSince(a.timestamp)
            guard interval > 0, interval <= 120 else { return nil }
            return lo + (hi - lo) * date.timeIntervalSince(a.timestamp) / interval
        }
        return splits.map { split in
            var result = split
            if result.averageHeartRate == nil {
                var weighted = 0.0, covered = 0.0
                for (a, b) in zip(heart, heart.dropFirst()) {
                    let gap = b.timestamp.timeIntervalSince(a.timestamp)
                    guard gap > 0, gap <= 60 else { continue }
                    let seconds = min(split.endDate, b.timestamp).timeIntervalSince(max(split.startDate, a.timestamp))
                    if seconds > 0, let bpm = a.heartRateBPM { weighted += bpm * seconds; covered += seconds }
                }
                if covered > 0 { result.averageHeartRate = weighted / covered }
            }
            if result.elevationChangeMeters == nil, let start = elevation(at: split.startDate), let end = elevation(at: split.endDate) {
                result.elevationChangeMeters = end - start
            }
            return result
        }
    }

    static func heartRateZones(_ telemetry: WorkoutTelemetry, workout: UnifiedWorkout,
                               maximumHeartRate: Double) -> [WorkoutTelemetryZone] {
        guard maximumHeartRate.isFinite, maximumHeartRate > 0 else { return [] }
        let points = telemetry.samples.filter { $0.heartRateBPM.map { $0.isFinite && (1...300).contains($0) } ?? false }.sorted { $0.timestamp < $1.timestamp }
        var seconds = [Double](repeating: 0, count: 5)
        for pair in zip(points, points.dropFirst()) {
            let start = max(workout.startDate, pair.0.timestamp)
            let end = min(workout.endDate, pair.1.timestamp)
            let duration = end.timeIntervalSince(start)
            // Do not classify unobserved long gaps as if HR stayed constant.
            guard duration > 0, duration <= 60, let bpm = pair.0.heartRateBPM else { continue }
            let ratio = bpm / maximumHeartRate
            let index = ratio < 0.6 ? 0 : (ratio < 0.7 ? 1 : (ratio < 0.8 ? 2 : (ratio < 0.9 ? 3 : 4)))
            seconds[index] += duration
        }
        guard seconds.reduce(0, +) > 0 else { return [] }
        return seconds.enumerated().map { index, duration in
            WorkoutTelemetryZone(name: "Z\(index + 1)", durationSeconds: duration)
        }
    }

    private static func distance(_ a: WorkoutRouteCoordinate, _ b: WorkoutRouteCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let lat = lat2 - lat1, lon = (b.longitude - a.longitude) * .pi / 180
        let h = min(1, max(0, pow(sin(lat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(lon / 2), 2)))
        return 6_371_000 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}

/// Axis bounds change the viewport, never the recorded samples or their timestamps.
enum WorkoutChartDomainPolicy {
    static func minutes(start: Date, end: Date) -> Double {
        let seconds = end.timeIntervalSince(start)
        return seconds.isFinite && seconds > 0 ? seconds / 60 : 0
    }
    static func ticks(endMinutes: Double) -> [Double] {
        guard endMinutes.isFinite, endMinutes > 0 else { return [0] }
        let target = endMinutes / 4
        let step = [1.0, 2, 5, 10, 15, 30, 60, 120, 240, 480, 1440].first { $0 >= target } ?? target
        return [0] + stride(from: step, to: endMinutes, by: step).filter { endMinutes - $0 > 0.000001 } + [endMinutes]
    }
    static func label(minutes: Double) -> String {
        guard minutes.isFinite, minutes >= 0, minutes < Double(Int.max / 60) else { return "—" }
        let seconds = Int((minutes * 60).rounded())
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    static func values(_ values: [Double], allowsNegative: Bool = false) -> ClosedRange<Double> {
        let valid = values.filter { $0.isFinite && (allowsNegative || $0 >= 0) }
        guard let low = valid.min(), let high = valid.max() else { return 0...1 }
        let padding = max((high - low) * 0.08, max(abs(high) * 0.01, 1))
        let lower = allowsNegative ? low - padding : max(0, low - padding)
        let upper = high + padding
        guard lower.isFinite, upper.isFinite, lower < upper else { return 0...1 }
        return lower...upper
    }
}
private extension WorkoutTelemetryChannel {
    func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .heartRate: return (1...300).contains(value)
        case .cadence: return (0...400).contains(value)
        case .power: return (0...5000).contains(value)
        case .speed: return (0...150).contains(value)
        case .elevation: return (-1000...12000).contains(value)
        }
    }
}
