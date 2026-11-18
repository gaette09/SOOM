import Foundation

/// Workout-scoped response only. Provider IDs and TCX are consumed during import,
/// never retained in the shared workout model or sent to the feed.
struct GoogleHealthWorkoutDetails: Decodable, Sendable {
    struct HeartRate: Decodable, Sendable { let time: String; let bpm: Double }
    struct Channel: Decodable, Sendable { let status: String; let error: String? }
    struct Interval: Decodable, Sendable {
        let start_time: String
        let end_time: String
        let meters: Double?
        let count: Double?
        let kilocalories: Double?
        let minutes: Double?
        let zone: String?
        let stroke_count: Double?
        let stroke_type: String?
    }
    struct Intervals: Decodable, Sendable {
        let distance: [Interval]?
        let steps: [Interval]?
        let energy: [Interval]?
        let elevation_gain: [Interval]?
        let active_zone_minutes: [Interval]?
        let swim_lengths: [Interval]?
    }
    let workout: GoogleHealthWorkoutPayload
    let tcx: String?
    let heart_rate: [HeartRate]
    let telemetry: Intervals
    let channels: [String: Channel]
    let next_page_tokens: [String: String]?
    let capabilities: GoogleHealthCapabilities?

    var hasRetryableFailure: Bool {
        channels.values.contains { $0.status == "unavailable" }
    }

    func makeTelemetry(for imported: UnifiedWorkout, includeSummary: Bool = true) -> WorkoutTelemetry {
        var samples: [WorkoutTelemetrySample] = []
        var tcxSplits: [WorkoutTelemetrySplit] = []
        if let tcx, let parsed = try? WorkoutTelemetryTCXParser().parse(
            data: Data(tcx.utf8), workoutID: imported.id, source: .googleHealth
        ) {
            samples = parsed.samples.filter { contains($0.timestamp, in: imported) }
            tcxSplits = parsed.splits
        }
        // Dedicated HR data has timestamps even when the exercise has no GPS.
        samples += heart_rate.compactMap { point in
            guard let time = Self.date(point.time), contains(time, in: imported),
                  point.bpm.isFinite, point.bpm > 0, point.bpm <= 300 else { return nil }
            return WorkoutTelemetrySample(timestamp: time, heartRateBPM: point.bpm)
        }
        var intervals: [WorkoutTelemetryInterval] = []
        func append(_ rows: [Interval]?, kind: WorkoutTelemetryInterval.Kind, value: (Interval) -> Double?) {
            for row in rows ?? [] {
                guard let start = Self.date(row.start_time), let end = Self.date(row.end_time),
                      start >= imported.startDate, end <= imported.endDate, end > start,
                      let amount = value(row), amount.isFinite,
                      (kind == .elevationGainMeters || amount >= 0) else { continue }
                intervals.append(.init(kind: kind, startDate: start, endDate: end, value: amount, zone: row.zone))
            }
        }
        append(telemetry.distance, kind: .distanceMeters, value: { $0.meters })
        append(telemetry.steps, kind: .steps, value: { $0.count })
        append(telemetry.energy, kind: .energyKcal, value: { $0.kilocalories })
        append(telemetry.elevation_gain, kind: .elevationGainMeters, value: { $0.meters })
        append(telemetry.active_zone_minutes, kind: .activeZoneMinutes, value: { $0.minutes })
        for row in telemetry.swim_lengths ?? [] {
            guard let start = Self.date(row.start_time), let end = Self.date(row.end_time),
                  start >= imported.startDate, end <= imported.endDate, end > start,
                  let count = row.stroke_count, count.isFinite, count >= 0 else { continue }
            intervals.append(.init(kind: .swimStrokeCount, startDate: start, endDate: end, value: count, zone: row.stroke_type))
        }

        let summary = includeSummary ? workout.exercise.metricsSummary : nil
        var zones: [WorkoutTelemetryZone] = []
        if let durations = summary?.heartRateZoneDurations {
            for (label, text) in [("가벼움", durations.lightTime), ("보통", durations.moderateTime),
                                  ("고강도", durations.vigorousTime), ("최고 강도", durations.peakTime)] {
                if let seconds = Self.duration(text), seconds >= 0 {
                    zones.append(.init(name: label, durationSeconds: seconds))
                }
            }
        }
        let sourceSplits = includeSummary ? (workout.exercise.splitSummaries?.isEmpty == false
            ? workout.exercise.splitSummaries : workout.exercise.splits) : nil
        let apiSplits: [WorkoutTelemetrySplit] = (sourceSplits ?? []).enumerated().compactMap { index, split in
            guard let start = Self.date(split.startTime), let end = Self.date(split.endTime),
                  start >= imported.startDate, end <= imported.endDate, end > start else { return nil }
            let active = Self.duration(split.activeDuration).flatMap { $0 > 0 && $0 <= end.timeIntervalSince(start) ? $0 : nil }
            return .init(label: "구간 \(index + 1)", startDate: start, endDate: end,
                         durationSeconds: active ?? end.timeIntervalSince(start),
                         distanceMeters: split.metricsSummary?.distanceMillimeters.map { $0 / 1_000 },
                         averageHeartRate: split.metricsSummary?.averageHeartRateBeatsPerMinute.flatMap(Double.init),
                         averageCadence: split.metricsSummary?.mobilityMetrics?.avgCadenceStepsPerMinute)
        }
        let splits = apiSplits.isEmpty && includeSummary ? tcxSplits : apiSplits
        var metrics: [WorkoutTelemetrySummaryMetric] = []
        func add(_ key: String, _ label: String, _ value: Double?, _ unit: String) {
            guard let value, value.isFinite, value >= 0 else { return }
            metrics.append(.init(key: key, label: label, value: value, unit: unit))
        }
        add("steps", "걸음 수", summary?.steps.flatMap(Double.init), "걸음")
        add("activeZoneMinutes", "활동 존", summary?.activeZoneMinutes.flatMap(Double.init), "분")
        add("runVo2Max", "최대산소섭취량", summary?.runVo2Max, "ml/kg/min")
        add("swimLengths", "수영 길이 수", summary?.totalSwimLengths, "회")
        if includeSummary {
            add("poolLength", "수영장 길이", workout.exercise.exerciseMetadata?.poolLengthMillimeters.flatMap(Double.init).map { $0 / 1_000 }, "m")
        }
        let mobility = summary?.mobilityMetrics
        add("runningCadence", "평균 러닝 케이던스", mobility?.avgCadenceStepsPerMinute, "spm")
        add("strideLength", "평균 보폭", mobility?.avgStrideLengthMillimeters.flatMap(Double.init).map { $0 / 1_000 }, "m")
        add("groundContact", "평균 지면 접촉 시간", Self.duration(mobility?.avgGroundContactTimeDuration).map { $0 * 1_000 }, "ms")
        add("verticalOscillation", "평균 수직 진폭", mobility?.avgVerticalOscillationMillimeters.flatMap(Double.init).map { $0 / 10 }, "cm")
        add("verticalRatio", "평균 수직 비율", mobility?.avgVerticalRatio, "%")
        let events: [WorkoutTelemetryEvent] = includeSummary ? (workout.exercise.exerciseEvents ?? []).compactMap {
            guard let time = Self.date($0.eventTime), contains(time, in: imported) else { return nil }
            return WorkoutTelemetryEvent(timestamp: time, type: $0.exerciseEventType)
        } : []
        return WorkoutTelemetry(workoutID: imported.id, source: .googleHealth, samples: samples,
                                intervals: intervals, splits: splits, heartRateZones: zones, summaryMetrics: metrics)
            .withGoogleEvents(events)
    }

    func makeRoute(for workout: UnifiedWorkout) -> WorkoutRoute? {
        guard let tcx, let parsed = try? TCXRouteParser(maximumLapCount: 2_000, maximumCoordinateCount: 100_000).parse(Data(tcx.utf8)),
              parsed.coordinates.count >= 2 else { return nil }
        // TCX may have positions without timestamps; do not attach another workout's route.
        if let start = parsed.summary.startDate, abs(start.timeIntervalSince(workout.startDate)) > 300 { return nil }
        guard parsed.coordinates.allSatisfy({ $0.timestamp.map { contains($0, in: workout) } ?? true }) else { return nil }
        return WorkoutRoute(workoutId: workout.id, source: .googleHealth, coordinates: parsed.coordinates,
                            totalDistanceMeters: parsed.totalDistanceMeters,
                            totalElevationGain: parsed.summary.elevationGainMeters)
    }

    private func contains(_ date: Date, in workout: UnifiedWorkout) -> Bool {
        date >= workout.startDate && date <= workout.endDate
    }
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    static func duration(_ text: String?) -> Double? {
        guard let text, text.hasSuffix("s"), let seconds = Double(text.dropLast()), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
}

private extension WorkoutTelemetry {
    func withGoogleEvents(_ events: [WorkoutTelemetryEvent]) -> WorkoutTelemetry {
        var copy = self
        copy.events = events
        return copy
    }
}

struct GoogleHealthCapabilities: Decodable, Sendable {
    let location: Bool
    let heart_rate: Bool
    let needs_reauthorization: Bool
}
