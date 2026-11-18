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
    private let sampleProvider: (@MainActor (HKQuantityTypeIdentifier, HKWorkout) async throws -> [HKQuantitySample])?
    private let queryProvider: ((HKQuantityTypeIdentifier, HKWorkout, HealthKitSampleQueryScope) async throws -> [HKQuantitySample])?
    init(healthStore: HKHealthStore = HKHealthStore(),
         queryProvider: ((HKQuantityTypeIdentifier, HKWorkout, HealthKitSampleQueryScope) async throws -> [HKQuantitySample])? = nil,
         sampleProvider: (@MainActor (HKQuantityTypeIdentifier, HKWorkout) async throws -> [HKQuantitySample])? = nil) {
        self.healthStore = healthStore
        self.sampleProvider = sampleProvider
        self.queryProvider = queryProvider
    }

    func fetchTelemetry(for workout: HKWorkout) async throws -> HealthKitWorkoutTelemetryResult {
        guard await MainActor.run(body: { !ReviewDemoMode.isActive }) else {
            return HealthKitWorkoutTelemetryResult(telemetry: WorkoutTelemetry(workoutID: workout.uuid, source: .appleHealthKit))
        }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitAuthorizationError.healthDataUnavailable }
        var detail = HealthKitWorkoutTelemetryResult(telemetry: WorkoutTelemetry(workoutID: workout.uuid, source: .appleHealthKit))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let speed = HKUnit.meter().unitDivided(by: .second())
        let distance: HKQuantityTypeIdentifier = workout.workoutActivityType == .cycling ? .distanceCycling
            : (workout.workoutActivityType == .swimming ? .distanceSwimming : .distanceWalkingRunning)
        var channels: [(HKQuantityTypeIdentifier, HKUnit)] = [(.heartRate, bpm), (distance, .meter()), (.activeEnergyBurned, .kilocalorie())]
        switch workout.workoutActivityType {
        case .running: channels += [(.runningPower, .watt()), (.runningSpeed, speed), (.stepCount, .count())]
        case .walking, .hiking: channels += [(.walkingSpeed, speed), (.stepCount, .count())]
        case .cycling: channels += [(.cyclingPower, .watt()), (.cyclingSpeed, speed), (.cyclingCadence, bpm)]
        default: break
        }
        for (identifier, unit) in channels {
            try Task.checkCancellation()
            do {
                let readings = try await samples(identifier: identifier, workout: workout)
                try Task.checkCancellation()
                for sample in readings {
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
                    case .activeEnergyBurned:
                        if start == sample.startDate && end == sample.endDate && end > start {
                            detail.telemetry.intervals.append(.init(kind: .energyKcal, startDate: start, endDate: end, value: value))
                        }
                    default:
                        if identifier == distance, start == sample.startDate, end == sample.endDate, end > start {
                            detail.telemetry.intervals.append(.init(kind: .distanceMeters, startDate: start, endDate: end, value: value))
                        }
                    }
                    if point.hasMeasurement { detail.telemetry.samples.append(point) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { detail.failedChannels.append(identifier.rawValue) }
        }
        detail.telemetry.events = (workout.workoutEvents ?? []).compactMap { event in
            let name: String
            switch event.type { case .pause, .motionPaused: name = "pause"; case .resume, .motionResumed: name = "resume"; default: return nil }
            return WorkoutTelemetryEvent(timestamp: event.dateInterval.start, type: name)
        }
        if workout.workoutActivityType == .swimming {
            detail.telemetry.splits = Self.swimmingSplits(workout)
        }
        detail.telemetry = detail.telemetry.coalescingSamples()
        return detail
    }

    private func samples(identifier: HKQuantityTypeIdentifier, workout: HKWorkout) async throws -> [HKQuantitySample] {
        if let sampleProvider { return try await sampleProvider(identifier, workout) }
        let linked = try await read(identifier, workout: workout, scope: .associated)
        if !linked.isEmpty { return linked }
        let sameSource = matching(try await read(identifier, workout: workout, scope: .workoutSource), workout: workout)
        if !sameSource.isEmpty { return sameSource }
        // A Nike workout and Apple Watch heart samples need not have the same
        // writing app. Never apply this fallback to cumulative distance/energy.
        guard identifier == .heartRate else { return [] }
        return Self.unambiguousHeartRate(try await read(identifier, workout: workout, scope: .timeWindow), workout: workout)
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
        let length = (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity).flatMap {
            $0.is(compatibleWith: .meter()) ? $0.doubleValue(for: .meter()) : nil
        }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return selected.enumerated().map { index, event in
            WorkoutTelemetrySplit(label: (hasLaps ? "랩 " : "구간 ") + String(index + 1),
                startDate: event.dateInterval.start, endDate: event.dateInterval.end,
                durationSeconds: event.dateInterval.duration, distanceMeters: hasLaps ? length : nil,
                provenance: hasLaps ? .healthKitLapEvent : .healthKitSegmentEvent)
        }
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
        let hr = average(.heartRate, bpm, fallback: mean(.heartRate) ?? averageHeartRate)
        let maxHR = HKQuantityType.quantityType(forIdentifier: .heartRate).flatMap {
            workout.statistics(for: $0)?.maximumQuantity()?.doubleValue(for: bpm)
        } ?? telemetry?.samples.compactMap(\.heartRateBPM).max() ?? maxHeartRate
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

    static func fetch(workout: UnifiedWorkout, needsRoute: Bool) async throws -> HealthKitDetailReadResult {
        guard workout.source == .appleHealthKit, let externalID = workout.externalId,
              let raw = await HealthKitWorkoutLookupProvider().lookupWorkout(externalId: externalID) else {
            return HealthKitDetailReadResult()
        }
        try Task.checkCancellation()
        var result = HealthKitDetailReadResult(workout: raw)
        do {
            let fetched = try await HealthKitWorkoutTelemetryFetcher().fetchTelemetry(for: raw)
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
