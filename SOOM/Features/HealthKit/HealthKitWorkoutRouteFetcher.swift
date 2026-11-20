import CoreLocation
import Foundation
import HealthKit

protocol HealthKitWorkoutRouteFetching {
    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute?
}

final class HealthKitWorkoutRouteFetcher: HealthKitWorkoutRouteFetching {
    private let healthStore: HKHealthStore
    private let mapper: HealthKitWorkoutRouteMapper

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        mapper: HealthKitWorkoutRouteMapper = HealthKitWorkoutRouteMapper()
    ) {
        self.healthStore = healthStore
        self.mapper = mapper
    }

    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute? {
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else { return nil }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.healthDataUnavailable
        }

        let routeSamples = try await fetchRouteSamples(for: workout)
        guard !routeSamples.isEmpty else { return nil }

        var locations: [CLLocation] = []
        for routeSample in routeSamples {
            locations.append(contentsOf: try await fetchLocations(for: routeSample))
        }

        return mapper.map(workout: workout, locations: locations)
    }

    private func fetchRouteSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let routeType = HKSeriesType.workoutRoute()
            let predicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }

            healthStore.execute(query)
        }
    }

    private func fetchLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var locations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, routeLocations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let routeLocations {
                    locations.append(contentsOf: routeLocations)
                }

                if done {
                    continuation.resume(returning: locations)
                }
            }

            healthStore.execute(query)
        }
    }
}


struct HealthKitWorkoutTelemetryResult {
    var telemetry: WorkoutTelemetry
    var failedChannels: [String] = []
}

protocol HealthKitWorkoutTelemetryFetching {
    func fetchTelemetry(for workout: HKWorkout) async throws -> HealthKitWorkoutTelemetryResult
}

/// Linked measurements take priority. Only heart rate may fall back across apps,
/// within the exact workout interval and from one unambiguous sensor stream.
enum HealthKitSampleQueryScope { case associated, workoutSource, timeWindow }

final class HealthKitWorkoutTelemetryFetcher: HealthKitWorkoutTelemetryFetching {
    private let healthStore: HKHealthStore
    private let expandOwnerHeartRateSeries: Bool
    private let sampleProvider: (@MainActor (HKQuantityTypeIdentifier, HKWorkout) async throws -> [HKQuantitySample])?
    private let queryProvider: ((HKQuantityTypeIdentifier, HKWorkout, HealthKitSampleQueryScope) async throws -> [HKQuantitySample])?
    init(healthStore: HKHealthStore = HKHealthStore(),
         queryProvider: ((HKQuantityTypeIdentifier, HKWorkout, HealthKitSampleQueryScope) async throws -> [HKQuantitySample])? = nil,
         sampleProvider: (@MainActor (HKQuantityTypeIdentifier, HKWorkout) async throws -> [HKQuantitySample])? = nil,
         expandOwnerHeartRateSeries: Bool = false) {
        self.healthStore = healthStore
        self.sampleProvider = sampleProvider
        self.queryProvider = queryProvider
        self.expandOwnerHeartRateSeries = expandOwnerHeartRateSeries
    }

    func fetchTelemetry(for workout: HKWorkout) async throws -> HealthKitWorkoutTelemetryResult {
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else {
            return HealthKitWorkoutTelemetryResult(telemetry: WorkoutTelemetry(workoutID: workout.uuid, source: .appleHealthKit))
        }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitAuthorizationError.healthDataUnavailable }
        var detail = HealthKitWorkoutTelemetryResult(telemetry: WorkoutTelemetry(workoutID: workout.uuid, source: .appleHealthKit))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var exactOwnerZoneSamples: [WorkoutTelemetrySample] = []
        let speed = HKUnit.meter().unitDivided(by: .second())
        let distance: HKQuantityTypeIdentifier = workout.workoutActivityType == .cycling ? .distanceCycling
            : (workout.workoutActivityType == .swimming ? .distanceSwimming : .distanceWalkingRunning)
        var channels: [(HKQuantityTypeIdentifier, HKUnit)] = [(.heartRate, bpm), (distance, .meter()), (.activeEnergyBurned, .kilocalorie())]
        switch workout.workoutActivityType {
        case .running: channels += [(.runningPower, .watt()), (.runningSpeed, speed), (.stepCount, .count())]
        case .walking, .hiking: channels += [(.walkingSpeed, speed), (.stepCount, .count())]
        case .cycling: channels += [(.cyclingPower, .watt()), (.cyclingSpeed, speed), (.cyclingCadence, bpm)]
        case .swimming: channels += [(.swimmingStrokeCount, .count())]
        default: break
        }
        for (identifier, unit) in channels {
            try Task.checkCancellation()
            do {
                let incoming = try await samples(identifier: identifier, workout: workout)
                let readings = incoming.values
                try Task.checkCancellation()
                let useSeries = expandOwnerHeartRateSeries && identifier == .heartRate
                var groupedHR: [OwnerHeartReading] = []
                var exactOwnerHR: [OwnerHeartReading] = []
                for sample in readings {
                    // A condensed quantity is not a raw point. In this private
                    // reader never use its summary as the missing series.
                    if useSeries && sample.count > 1 { continue }
                    let value = sample.quantity.doubleValue(for: unit)
                    let start = max(sample.startDate, workout.startDate)
                    let end = min(sample.endDate, workout.endDate)
                    guard value.isFinite, value >= 0, start <= end else { continue }
                    var point = WorkoutTelemetrySample(timestamp: start.addingTimeInterval(end.timeIntervalSince(start) / 2), source: .appleHealthKit)
                    switch identifier {
                    case .heartRate: point.heartRateBPM = value
                    case .runningPower, .cyclingPower: point.powerWatts = value
                    case .runningSpeed, .walkingSpeed, .cyclingSpeed: point.speedMetersPerSecond = value
                    case .cyclingCadence: point.cadencePerMinute = value; point.cadenceUnit = .revolutionsPerMinute
                    case .stepCount:
                        // An interval step rate is derived, not an instantaneous sensor value.
                        if start == sample.startDate && end == sample.endDate && end > start {
                            detail.telemetry.intervals.append(.init(kind: .steps, startDate: start, endDate: end, value: value))
                        }
                    case .swimmingStrokeCount:
                        if start == sample.startDate && end == sample.endDate && end > start {
                            detail.telemetry.intervals.append(.init(kind: .swimStrokeCount, startDate: start, endDate: end, value: value))
                        }
                    case .activeEnergyBurned:
                        if start == sample.startDate && end == sample.endDate && end > start {
                            detail.telemetry.intervals.append(.init(kind: .energyKcal, startDate: start, endDate: end, value: value))
                        }
                    default:
                        if identifier == distance, start == sample.startDate, end == sample.endDate, end > start {
                            detail.telemetry.intervals.append(.init(kind: .distanceMeters, startDate: start, endDate: end, value: value))
                        }
                    }
                    if useSeries, let heart = point.heartRateBPM {
                        groupedHR.append(.init(time: point.timestamp, bpm: heart))
                        if sample.startDate == sample.endDate {
                            exactOwnerHR.append(.init(time: point.timestamp, bpm: heart))
                        }
                    } else if point.hasMeasurement { detail.telemetry.samples.append(point) }
                }
                if useSeries {
                    let condensed = readings.filter { $0.count > 1 }
                    if !condensed.isEmpty {
                        detail.telemetry.ownerExpandedCondensedHeartRate = true
                        do {
                            let expanded = try await ownerHeartRateSeries(condensed, workout: workout, unit: bpm)
                            groupedHR += expanded
                            exactOwnerHR += expanded
                        }
                        catch is CancellationError { throw CancellationError() }
                        catch { detail.failedChannels.append(identifier.rawValue) }
                    }
                    exactOwnerZoneSamples = (incoming.workoutLinked ? exactOwnerHR : []).map {
                        .init(timestamp: $0.time, heartRateBPM: $0.bpm, source: .appleHealthKit)
                    }
                    detail.telemetry.samples += Self.uniqueOwnerHeartReadings(groupedHR).map {
                        .init(timestamp: $0.time, heartRateBPM: $0.bpm, source: .appleHealthKit)
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { detail.failedChannels.append(identifier.rawValue) }
        }
        detail.telemetry.events = (workout.workoutEvents ?? []).compactMap { event in
            let name: String
            switch event.type { case .pause, .motionPaused: name = "pause"; case .resume, .motionResumed: name = "resume"; default: return nil }
            return WorkoutTelemetryEvent(timestamp: event.dateInterval.start, type: name)
        }
        if workout.workoutActivityType == .swimming,
           let meters = Self.lapLength(in: workout.metadata) {
            detail.telemetry.summaryMetrics.append(.init(key: "poolLengthMeters", label: "수영장 길이", value: meters, unit: "m"))
        }
        switch workout.workoutActivityType {
        case .swimming, .running, .cycling:
            detail.telemetry.splits = Self.recordedSplits(workout, distanceIntervals: detail.telemetry.intervals)
            if #available(iOS 27.0, *),
               let group = workout.zoneGroup(for: HKQuantityType(.heartRate)) {
                detail.telemetry.heartRateZones = Self.recordedHeartRateZones(
                    configurationIndices: group.configuration.zones.map(\.index),
                    durations: group.zoneDurations.map { ($0.zone.index, $0.duration) },
                    activeDuration: workout.duration)
                // Only the exact HKWorkout's captured boundaries are acceptable.
                // Only the explicit owner reread supplies validated uncondensed points.
                if expandOwnerHeartRateSeries, detail.telemetry.heartRateZones.isEmpty,
                   !detail.failedChannels.contains(HKQuantityTypeIdentifier.heartRate.rawValue) {
                    let ordered = group.configuration.zones.sorted { $0.index < $1.index }
                    let uppers = ordered.dropLast().compactMap { $0.maximum?.doubleValue(for: bpm) }
                    if ordered.count == 5, uppers.count == 4 {
                        detail.telemetry.historicalCalculatedHeartRateZones = Self.calculateHistoricalZones(
                            upperBPM: uppers, samples: exactOwnerZoneSamples, events: detail.telemetry.events,
                            start: workout.startDate, end: workout.endDate, activeDuration: workout.duration)
                    }
                }
            }
        default: break
        }
        detail.telemetry = detail.telemetry.coalescingSamples()
        return detail
    }

    struct OwnerHeartReading {
        let time: Date
        let bpm: Double
    }

    static func uniqueOwnerHeartReadings(_ readings: [OwnerHeartReading]) -> [OwnerHeartReading] {
        let grouped = Dictionary(grouping: readings.filter { $0.bpm.isFinite && (1...300).contains($0.bpm) }, by: \.time)
        return grouped.keys.sorted().compactMap { time in
            let values = Set(grouped[time, default: []].map(\.bpm))
            guard values.count == 1, let bpm = values.first else { return nil }
            return .init(time: time, bpm: bpm)
        }
    }

    static func acceptedOwnerHeartSeriesPoint(_ interval: DateInterval, workout: DateInterval,
                                               selectedSample: DateInterval, bpm: Double) -> OwnerHeartReading? {
        guard interval.start >= workout.start, interval.end <= workout.end,
              interval.start >= selectedSample.start, interval.end <= selectedSample.end,
              bpm.isFinite, (1...300).contains(bpm) else { return nil }
        return .init(time: interval.start.addingTimeInterval(interval.duration / 2), bpm: bpm)
    }

    private enum OwnerSeriesReadError: Error { case limitExceeded }

    private func ownerHeartRateSeries(_ samples: [HKQuantitySample], workout: HKWorkout,
                                      unit: HKUnit) async throws -> [OwnerHeartReading] {
        var selected: [UUID: DateInterval] = [:]
        for sample in samples where sample.startDate <= sample.endDate {
            selected[sample.uuid] = .init(start: sample.startDate, end: sample.endDate)
        }
        guard !selected.isEmpty, workout.startDate <= workout.endDate else { return [] }
        guard selected.count <= 128 else { throw OwnerSeriesReadError.limitExceeded }
        let type = HKQuantityType(.heartRate)
        let workoutSpan = DateInterval(start: workout.startDate, end: workout.endDate)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForObjects(with: Set(selected.keys)))
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(predicate: predicate, options: [.includeSample])
        var result: [OwnerHeartReading] = []
        var scanned = 0
        for try await point in descriptor.results(for: healthStore) {
            try Task.checkCancellation()
            scanned += 1
            guard scanned <= 20_000 else { throw OwnerSeriesReadError.limitExceeded }
            guard let uuid = point.sample?.uuid, let range = selected[uuid],
                  let normalized = Self.acceptedOwnerHeartSeriesPoint(point.dateInterval, workout: workoutSpan,
                      selectedSample: range, bpm: point.quantity.doubleValue(for: unit)) else { continue }
            result.append(normalized)
        }
        return result
    }

    private func samples(identifier: HKQuantityTypeIdentifier, workout: HKWorkout) async throws ->
        (values: [HKQuantitySample], workoutLinked: Bool) {
        if let sampleProvider { return (try await sampleProvider(identifier, workout), false) }
        let linked = try await read(identifier, workout: workout, scope: .associated)
        if !linked.isEmpty { return (linked, true) }
        let sameSource = matching(try await read(identifier, workout: workout, scope: .workoutSource), workout: workout)
        if !sameSource.isEmpty { return (sameSource, false) }
        // An associated stream is mandatory when estimating historical zone time.
        // A wider unique sensor stream is still useful in the ordinary graph.
        guard identifier == .heartRate else { return ([], false) }
        return (Self.unambiguousHeartRate(try await read(identifier, workout: workout, scope: .timeWindow),
                                          workout: workout), false)
    }

    private func read(_ identifier: HKQuantityTypeIdentifier, workout: HKWorkout,
                      scope: HealthKitSampleQueryScope) async throws -> [HKQuantitySample] {
        try Task.checkCancellation()
        if let queryProvider { return try await queryProvider(identifier, workout, scope) }
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let window = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate,
            options: [.strictStartDate, .strictEndDate])
        let predicate: NSPredicate
        switch scope {
        case .associated: predicate = HKQuery.predicateForObjects(from: workout)
        case .workoutSource: predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window,
            HKQuery.predicateForObjects(from: workout.sourceRevision.source)])
        case .timeWindow: predicate = window
        }
        return try await query(type: type, predicate: predicate)
    }

    static func unambiguousHeartRate(_ samples: [HKQuantitySample], workout: HKWorkout) -> [HKQuantitySample] {
        let bounded = samples.filter { $0.quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue
            && $0.startDate >= workout.startDate && $0.endDate <= workout.endDate }
        let groups = Dictionary(grouping: bounded) { sample in
            sample.sourceRevision.source.bundleIdentifier + "|" +
                (sample.device?.localIdentifier ?? sample.device?.udiDeviceIdentifier ??
                    [sample.device?.manufacturer, sample.device?.model, sample.device?.name].compactMap { $0 }.joined(separator: "|"))
        }
        if let expected = workout.device?.localIdentifier {
            let matched = groups.values.filter { $0.first?.device?.localIdentifier == expected }
            if matched.count == 1 { return matched[0] }
            if matched.count > 1 { return [] }
            // The recording phone and heart-rate sensor may be different devices.
            // A unique time-bounded sensor stream still qualifies; competing streams do not.
        }
        return groups.count == 1 ? (groups.values.first ?? []) : []
    }

    /// Only original, positive-duration lap/segment intervals become rows.
    /// Timestamp-only events are insufficient to invent a lap duration.
    static func swimmingSplits(_ workout: HKWorkout) -> [WorkoutTelemetrySplit] {
        guard workout.workoutActivityType == .swimming else { return [] }
        return recordedSplits(workout, distanceIntervals: [])
    }

    static func recordedSplits(_ workout: HKWorkout, distanceIntervals: [WorkoutTelemetryInterval]) -> [WorkoutTelemetrySplit] {
        let swimming = workout.workoutActivityType == .swimming
        guard swimming || workout.workoutActivityType == .running || workout.workoutActivityType == .cycling else { return [] }
        let events = (workout.workoutEvents ?? []).filter {
            ($0.type == .lap || $0.type == .segment) && $0.dateInterval.duration.isFinite
                && $0.dateInterval.duration > 0 && $0.dateInterval.start >= workout.startDate
                && $0.dateInterval.end <= workout.endDate
        }
        let hasLaps = events.contains { $0.type == .lap }
        let selected = events.filter { $0.type == (hasLaps ? .lap : .segment) }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }
        // Overlapping alternatives cannot be presented as sequential lengths.
        guard !zip(selected, selected.dropFirst()).contains(where: { $0.dateInterval.end > $1.dateInterval.start }) else { return [] }
        let length = swimming ? lapLength(in: workout.metadata) : nil
        let distances = distanceIntervals.filter { $0.kind == .distanceMeters }.sorted { $0.startDate < $1.startDate }
        return selected.enumerated().map { index, event in
            // A generic segment may contain multiple pool lengths. Do not confuse the
            // pool length metadata with the distance covered during a segment.
            let measured = measuredDistance(inside: event.dateInterval, from: distances)
            let distance = measured ?? ((swimming && hasLaps) ? (lapLength(in: event.metadata) ?? length) : nil)
            return WorkoutTelemetrySplit(label: (hasLaps ? "랩 " : "구간 ") + String(index + 1),
                startDate: event.dateInterval.start, endDate: event.dateInterval.end,
                durationSeconds: event.dateInterval.duration, distanceMeters: distance,
                provenance: hasLaps ? .healthKitLapEvent : .healthKitSegmentEvent)
        }
    }

    private static func lapLength(in metadata: [String: Any]?) -> Double? {
        guard let length = metadata?[HKMetadataKeyLapLength] as? HKQuantity, length.is(compatibleWith: .meter()) else { return nil }
        let value = length.doubleValue(for: .meter())
        return value.isFinite && value > 0 ? value : nil
    }

    /// An exact, nonoverlapping tiling of the event by same-source distance
    /// samples supplies measured distance. Never prorate a partial sample.
    private static func measuredDistance(inside event: DateInterval, from distances: [WorkoutTelemetryInterval]) -> Double? {
        let overlapping = distances.filter { $0.startDate < event.end && $0.endDate > event.start }
        var boundary = event.start, sum = 0.0
        for interval in overlapping {
            guard interval.startDate == boundary, interval.endDate > boundary, interval.endDate <= event.end,
                  interval.value.isFinite, interval.value >= 0 else { return nil }
            sum += interval.value
            boundary = interval.endDate
        }
        return boundary == event.end && sum.isFinite && sum > 0 ? sum : nil
    }

    /// Use HealthKit's confirmed source timings without retaining boundaries or
    /// making absent/ambiguous zone rows look like zero observations.
    static func recordedHeartRateZones(configurationIndices: [Int], durations: [(Int, Double)],
                                      activeDuration: Double) -> [WorkoutTelemetryZone] {
        let indices = configurationIndices.sorted()
        guard indices == Array(0...4) || indices == Array(1...5), durations.count == 5,
              activeDuration.isFinite, activeDuration > 0 else { return [] }
        var map: [Int: Double] = [:]
        for (index, seconds) in durations {
            guard indices.contains(index), map[index] == nil, seconds.isFinite,
                  seconds >= 0, seconds <= activeDuration else { return [] }
            map[index] = seconds
        }
        let totals = indices.compactMap { map[$0] }
        let sum = totals.reduce(0, +)
        guard totals.count == 5, sum > 0, sum <= activeDuration else { return [] }
        return totals.enumerated().map { .init(name: "Z" + String($0.offset + 1), durationSeconds: $0.element) }
    }


    /// Estimate only observed contiguous intervals; no latest settings, interpolation,
    /// unobserved endpoints, paused windows, incomplete event sequences or long gaps.
    static func calculateHistoricalZones(upperBPM: [Double], samples: [WorkoutTelemetrySample],
                                         events: [WorkoutTelemetryEvent], start: Date, end: Date,
                                         activeDuration: Double) -> [WorkoutTelemetryZone] {
        guard upperBPM.count == 4, upperBPM.allSatisfy({ $0.isFinite && (20...250).contains($0) }),
              zip(upperBPM, upperBPM.dropFirst()).allSatisfy({ $0 < $1 }),
              start < end, activeDuration.isFinite, activeDuration > 0 else { return [] }
        var pauseStart: Date?
        var pauses: [DateInterval] = []
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard (start...end).contains(event.timestamp) else { return [] }
            switch event.type {
            case "pause":
                guard pauseStart == nil else { return [] }
                pauseStart = event.timestamp
            case "resume":
                guard let began = pauseStart, began < event.timestamp else { return [] }
                pauses.append(.init(start: began, end: event.timestamp))
                pauseStart = nil
            default: continue
            }
        }
        if let pauseStart, pauseStart < end { pauses.append(.init(start: pauseStart, end: end)) }
        var sampleMap: [Date: Double] = [:]
        for sample in samples where (start...end).contains(sample.timestamp) {
            guard sample.source == .appleHealthKit, let bpm = sample.heartRateBPM,
                  bpm.isFinite, (20...250).contains(bpm) else { continue }
            if let previous = sampleMap[sample.timestamp], previous != bpm { return [] }
            sampleMap[sample.timestamp] = bpm
        }
        let ordered = sampleMap.sorted { $0.key < $1.key }
        var seconds = [Double](repeating: 0, count: 5)
        for (a,b) in zip(ordered,ordered.dropFirst()) {
            let delta = b.key.timeIntervalSince(a.key)
            guard delta > 0, delta <= 15,
                  !pauses.contains(where: { $0.start < b.key && $0.end > a.key }) else { continue }
            let zone = upperBPM.firstIndex(where: { a.value < $0 }) ?? 4
            seconds[zone] += delta
        }
        let sum = seconds.reduce(0,+)
        guard sum >= min(20, activeDuration / 2), sum <= activeDuration else { return [] }
        return seconds.enumerated().map { .init(name: "Z" + String($0.offset + 1), durationSeconds: $0.element) }
    }

    private func matching(_ samples: [HKQuantitySample], workout: HKWorkout) -> [HKQuantitySample] {
        samples.filter {
            guard $0.sourceRevision.source == workout.sourceRevision.source else { return false }
            if let expected = workout.device?.localIdentifier, let actual = $0.device?.localIdentifier { return expected == actual }
            if let expected = workout.device?.model, let actual = $0.device?.model { return expected == actual }
            return true
        }
    }

    private func query(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100_000,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
            }
            healthStore.execute(query)
        }
    }
}

extension UnifiedWorkout {
    /// Re-import updates provider measurements but retains the card identity,
    /// owner edits, public visibility and every original source record.
    func withHealthKitDetails(_ workout: HKWorkout, telemetry: WorkoutTelemetry?, updatedAt overrideDate: Date? = nil) -> UnifiedWorkout {
        func average(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit, fallback: Double?) -> Double? {
            HKQuantityType.quantityType(forIdentifier: identifier).flatMap {
                workout.statistics(for: $0)?.averageQuantity()?.doubleValue(for: unit)
            } ?? fallback
        }
        func mean(_ channel: WorkoutTelemetryChannel) -> Double? {
            let readings = telemetry?.samples.compactMap { $0.value(for: channel) } ?? []
            return readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? distanceMeters
        let running = workout.workoutActivityType == .running
        let power = average(running ? .runningPower : .cyclingPower, .watt(), fallback: mean(.power) ?? averagePowerWatts)
        let privateExpanded = telemetry?.ownerExpandedCondensedHeartRate == true
        let hr = average(.heartRate, bpm, fallback: privateExpanded ? averageHeartRate : (mean(.heartRate) ?? averageHeartRate))
        let maxHR = HKQuantityType.quantityType(forIdentifier: .heartRate).flatMap {
            workout.statistics(for: $0)?.maximumQuantity()?.doubleValue(for: bpm)
        } ?? (privateExpanded ? nil : telemetry?.samples.compactMap(\.heartRateBPM).max()) ?? maxHeartRate
        let cadence = running ? averageCadence : average(.cyclingCadence, bpm, fallback: mean(.cadence) ?? averageCadence)
        let elevation = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) ?? elevationGainMeters
        let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned).flatMap {
            workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        } ?? workout.totalEnergyBurned.flatMap {
            let value = $0.doubleValue(for: .kilocalorie())
            return value.isFinite && value >= 0 ? value : nil
        } ?? activeEnergyKcal
        let speed = distance.flatMap { workout.duration > 0 ? $0 / workout.duration : nil }
        let changed = workout.startDate != startDate || workout.endDate != endDate || workout.duration != durationSeconds
            || distance != distanceMeters || hr != averageHeartRate || maxHR != maxHeartRate
            || power != averagePowerWatts || cadence != averageCadence || speed != averageSpeedMetersPerSecond
            || elevation != elevationGainMeters || energy != activeEnergyKcal
        var result = UnifiedWorkout(id: id, externalId: externalId, source: source, workoutType: workoutType,
            startDate: workout.startDate, endDate: workout.endDate, durationSeconds: workout.duration,
            distanceMeters: distance, activeEnergyKcal: energy,
            averageHeartRate: hr, maxHeartRate: maxHR,
            averageSpeedMetersPerSecond: speed,
            elevationGainMeters: elevation, averagePowerWatts: power,
            averageCadence: cadence,
            routeMissingReason: routeMissingReason, dataQuality: dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis, createdAt: createdAt, updatedAt: changed ? (overrideDate ?? Date()) : updatedAt,
            companionNames: companionNames, userTitle: userTitle, userDescription: userDescription,
            sharingVisibilityRaw: sharingVisibilityRaw, isBookmarked: isBookmarked,
            deviceName: deviceName, locationName: locationName)
        result.preferredWorkoutID = preferredWorkoutID
        result.keepSeparate = keepSeparate
        result.resolutionRequestID = resolutionRequestID
        return result
    }
}

/// This read-through cache is intentionally memory-only: opening private detail
/// must not journal newly read HealthKit measurements to cloud/shared records.
struct HealthKitDetailReadResult {
    var workout: HKWorkout?
    var telemetry: WorkoutTelemetry?
    var route: WorkoutRoute?
    var failedChannels: [String] = []
}

@MainActor
final class HealthKitDetailReadCache {
    static let shared = HealthKitDetailReadCache()
    struct Key: Hashable {
        let scope: String
        let workoutID: UUID
        let externalID: String
        let revision: Date
        let needsRoute: Bool
        var expandsOwnerHeartRateSeries: Bool = false
    }
    private struct Entry { let result: HealthKitDetailReadResult; let expires: Date }
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: (UUID, Task<HealthKitDetailReadResult, Error>)] = [:]
    private var currentScope: String?
    private let now: () -> Date
    init(now: @escaping () -> Date = Date.init) { self.now = now }

    static let measurementsChanged=Notification.Name("SOOM.HealthKit.privateMeasurementsCached")
    /// Read-only reuse within the exact owner/workout/revision and original TTL.
    /// Does not query HealthKit, renew expiry, persist data or switch cache owner.
    func cachedResult(for key:Key)->HealthKitDetailReadResult? {
        guard currentScope == key.scope,let entry=entries[key],entry.expires > now() else{return nil}
        return entry.result
    }

    func read(key: Key, force: Bool = false,
              loader: @escaping @MainActor () async throws -> HealthKitDetailReadResult) async throws -> HealthKitDetailReadResult {
        try Task.checkCancellation()
        if currentScope != key.scope {
            entries.removeAll()
            flights.values.forEach { $0.1.cancel() }
            flights.removeAll()
            currentScope = key.scope
        }
        if !force, let cached = entries[key], cached.expires > now() { return cached.result }
        // Even an explicit retry joins an outstanding read instead of duplicating it.
        if let flight = flights[key] {
            let result = try await flight.1.value
            try Task.checkCancellation()
            return result
        }
        let id = UUID()
        let task = Task { try await loader() }
        flights[key] = (id, task)
        do {
            let result = try await task.value
            if currentScope == key.scope, flights[key]?.0 == id {
                flights[key] = nil
                if entries.count >= 20 { entries.removeAll() }
                // Empty/partial reads are not a durable negative cache. New Health
                // samples/routes can arrive later, and permission changes are opaque.
                let incomplete = result.workout == nil || !(result.failedChannels.isEmpty)
                    || result.telemetry?.isEmpty != false || (key.needsRoute && result.route == nil)
                entries[key] = Entry(result: result, expires: now().addingTimeInterval(incomplete ? 30 : 300))
                NotificationCenter.default.post(name:Self.measurementsChanged,object:key.scope)
            }
            try Task.checkCancellation()
            return result
        } catch {
            if flights[key]?.0 == id { flights[key] = nil }
            throw error
        }
    }

    static func needsMeasurements(_ workout: UnifiedWorkout, telemetry: WorkoutTelemetry?) -> Bool {
        guard workout.source == .appleHealthKit else { return false }
        guard let telemetry else { return true }
        return workout.activeEnergyKcal == nil || !telemetry.samples.contains { $0.heartRateBPM != nil }
            || (workout.workoutType == .swimming && telemetry.splits.isEmpty)
            || ((workout.distanceMeters ?? 0) > 0 && telemetry.splits.isEmpty
                && !telemetry.intervals.contains { $0.kind == .distanceMeters }
                && !telemetry.samples.contains { $0.distanceMeters != nil })
    }

    /// Optional data can arrive after an older import has enough for the base
    /// card. This is a private, TTL-bound read, not a missing-permissions alert.
    static func shouldEnrichOwnerDetail(_ workout: UnifiedWorkout, telemetry: WorkoutTelemetry?,
                                         canReadRecordedZones: Bool) -> Bool {
        guard workout.source == .appleHealthKit, let telemetry else { return false }
        let has = { (channel: WorkoutTelemetryChannel) in telemetry.samples.contains { $0.value(for: channel) != nil } }
        let interval = { (kind: WorkoutTelemetryInterval.Kind) in telemetry.intervals.contains { $0.kind == kind } }
        switch workout.workoutType {
        case .running:
            return (canReadRecordedZones && telemetry.heartRateZones.isEmpty)
                || !has(.power) || !has(.speed) || (!has(.cadence) && !interval(.steps))
        case .cycling:
            return (canReadRecordedZones && telemetry.heartRateZones.isEmpty)
                || !has(.power) || !has(.speed) || !has(.cadence)
        case .swimming:
            return (canReadRecordedZones && telemetry.heartRateZones.isEmpty)
                || !interval(.swimStrokeCount) || telemetry.splits.contains { $0.distanceMeters == nil }
                || !telemetry.summaryMetrics.contains { $0.key == "poolLengthMeters" }
        default:
            return false
        }
    }

    static func mergingOwnerEnrichment(_ incoming: WorkoutTelemetry, into stored: WorkoutTelemetry) -> WorkoutTelemetry {
        guard incoming.workoutID == stored.workoutID, incoming.source == .appleHealthKit else { return stored }
        var supplement = incoming
        for channel in WorkoutTelemetryChannel.allCases where stored.samples.contains(where: { $0.value(for: channel) != nil }) {
            supplement.samples = supplement.samples.map { $0.removing(channel) }.filter(\.hasMeasurement)
        }
        if stored.samples.contains(where: { $0.distanceMeters != nil }) {
            supplement.samples = supplement.samples.map { var x = $0; x.distanceMeters = nil; return x }.filter(\.hasMeasurement)
        }
        let kinds = Set(stored.intervals.map(\.kind))
        supplement.intervals.removeAll { kinds.contains($0.kind) }
        var result = stored.merging(supplement)
        if stored.source == .appleHealthKit {
            result.splits = result.splits.map { old in
                guard old.distanceMeters == nil else { return old }
                let matches = incoming.splits.filter {
                    ($0.provenance == .healthKitLapEvent || $0.provenance == .healthKitSegmentEvent)
                        && (old.provenance == nil || old.provenance == $0.provenance)
                        && $0.startDate == old.startDate && $0.endDate == old.endDate
                        && $0.durationSeconds == old.durationSeconds && ($0.distanceMeters ?? 0) > 0
                }
                guard matches.count == 1 else { return old }
                var filled = old; filled.distanceMeters = matches[0].distanceMeters
                filled.provenance = matches[0].provenance
                return filled
            }
        }
        return result.coalescingSamples()
    }

    static func fetch(workout: UnifiedWorkout, needsRoute: Bool,
                      expandOwnerHeartRateSeries: Bool = false) async throws -> HealthKitDetailReadResult {
        guard workout.source == .appleHealthKit, let externalID = workout.externalId,
              let raw = await HealthKitWorkoutLookupProvider().lookupWorkout(externalId: externalID) else {
            return HealthKitDetailReadResult()
        }
        try Task.checkCancellation()
        var result = HealthKitDetailReadResult(workout: raw)
        do {
            let fetched = try await HealthKitWorkoutTelemetryFetcher(expandOwnerHeartRateSeries: expandOwnerHeartRateSeries).fetchTelemetry(for: raw)
            result.telemetry = fetched.telemetry.validated(for: workout)
            result.failedChannels = fetched.failedChannels
        } catch is CancellationError { throw CancellationError() }
        catch { result.failedChannels.append("measurements") }
        if needsRoute {
            do {
                if let route = try await HealthKitWorkoutRouteFetcher().fetchRoute(for: raw) {
                    result.route = WorkoutRoute(id: route.id, workoutId: workout.id, source: workout.source,
                        coordinates: route.coordinates, totalDistanceMeters: route.totalDistanceMeters,
                        totalElevationGain: route.totalElevationGain, createdAt: route.createdAt)
                }
            }
            catch is CancellationError { throw CancellationError() }
            catch { result.failedChannels.append("route") }
        }
        try Task.checkCancellation()
        return result
    }
}

struct HealthKitDetailReadPresentation {
    let message: String
    var isLoading = false
    var retry: (@MainActor () async -> Void)?
}
