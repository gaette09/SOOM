import Foundation

/// A single point on a distance-axis chart (feed-detail-migration-plan.md batch 3).
struct WorkoutDistanceChartSample: Identifiable {
    let id = UUID()
    let distanceKilometers: Double
    let value: Double
}

/// Derives real pace samples/splits from a persisted `WorkoutRoute`'s timestamped
/// coordinates — works for any source (Record-direct or HealthKit-imported) since
/// both stamp real per-point timestamps. Heart rate is filled in only when a
/// matching HealthKit sample stream is supplied; it is never fabricated.
///
/// `speedSamples`/`elevationSamples` bucket the same route data along the distance
/// axis instead of the minute axis `samples`/`splits` use above — a different view
/// of the same points, not a second source of truth. Neither is ever used to derive
/// the "평균 속도"/"평균 페이스"/"상승 고도" figures shown elsewhere — those come
/// exclusively from `ProcessedWorkout.display` (total distance ÷ total duration).
/// These bucketed samples are for chart shape only.
enum WorkoutChartDataBuilder {
    static func samples(
        from route: WorkoutRoute,
        heartRateSamples: [HealthKitWorkoutMetricSample] = []
    ) -> [WorkoutSample] {
        let points = timestampedPoints(from: route)
        guard points.count >= 2 else { return [] }

        let startDate = points[0].timestamp
        let totalSeconds = points[points.count - 1].timestamp.timeIntervalSince(startDate)
        guard totalSeconds > 0 else { return [] }

        let bucketCount = max(1, Int(totalSeconds / 60))
        var samples: [WorkoutSample] = []

        for minuteIndex in 0..<bucketCount {
            let bucketStart = startDate.addingTimeInterval(Double(minuteIndex) * 60)
            let bucketEnd = startDate.addingTimeInterval(Double(minuteIndex + 1) * 60)
            let bucketPoints = points.filter { $0.timestamp >= bucketStart && $0.timestamp < bucketEnd }

            guard bucketPoints.count >= 2,
                  let first = bucketPoints.first,
                  let last = bucketPoints.last else { continue }

            let distance = pathDistanceMeters(bucketPoints)
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            guard distance > 0, duration > 0 else { continue }

            let paceSecondsPerKm = duration / (distance / 1_000)
            let heartRate = averageHeartRate(in: heartRateSamples, start: bucketStart, end: bucketEnd)

            samples.append(
                WorkoutSample(
                    minute: Double(minuteIndex) + 0.5,
                    heartRate: heartRate,
                    paceSeconds: paceSecondsPerKm,
                    power: nil
                )
            )
        }

        return samples
    }

    static func splits(
        from route: WorkoutRoute,
        heartRateSamples: [HealthKitWorkoutMetricSample] = []
    ) -> [WorkoutSplit] {
        guard route.totalDistanceMeters >= 1_000 else { return [] }

        let points = timestampedPoints(from: route)
        guard points.count >= 2 else { return [] }

        var splits: [WorkoutSplit] = []
        var segmentStartIndex = 0
        var cumulativeDistance = 0.0
        var nextThreshold = 1_000.0

        for index in 1..<points.count {
            cumulativeDistance += distance(points[index - 1], points[index])
            guard cumulativeDistance >= nextThreshold else { continue }

            let segment = Array(points[segmentStartIndex...index])
            guard let first = segment.first, let last = segment.last else { continue }
            let segmentDuration = last.timestamp.timeIntervalSince(first.timestamp)
            guard segmentDuration > 0 else { continue }

            let km = splits.count + 1
            let heartRate = averageHeartRate(in: heartRateSamples, start: first.timestamp, end: last.timestamp)

            splits.append(
                WorkoutSplit(
                    label: "\(km) km",
                    distance: "1.0 km",
                    time: formattedDuration(segmentDuration),
                    pace: formattedPace(secondsPerKm: segmentDuration),
                    heartRate: heartRate,
                    power: nil
                )
            )

            segmentStartIndex = index
            nextThreshold += 1_000
        }

        return splits
    }

    /// Distance-bucketed HR chart series. Unlike `speedSamples`/`elevationSamples`,
    /// the values here come from an externally supplied HealthKit stream (matched by
    /// timestamp per bucket, same `averageHeartRate(in:start:end:)` helper `samples`
    /// uses above) rather than the route itself — never fabricated when the stream
    /// is empty or a bucket has no matching sample.
    static func heartRateSamples(
        from route: WorkoutRoute,
        heartRateSamples: [HealthKitWorkoutMetricSample]
    ) -> [WorkoutDistanceChartSample] {
        guard !heartRateSamples.isEmpty else { return [] }
        let points = timestampedPoints(from: route)
        guard points.count >= 2 else { return [] }

        let totalDistance = pathDistanceMeters(points)
        guard totalDistance > 0 else { return [] }
        let bucketSize = max(200.0, totalDistance / 60)

        var samples: [WorkoutDistanceChartSample] = []
        var segmentStartIndex = 0
        var cumulativeDistance = 0.0
        var nextThreshold = bucketSize

        for index in 1..<points.count {
            cumulativeDistance += distance(points[index - 1], points[index])
            guard cumulativeDistance >= nextThreshold || index == points.count - 1 else { continue }

            let segment = Array(points[segmentStartIndex...index])
            defer {
                segmentStartIndex = index
                nextThreshold += bucketSize
            }
            guard let first = segment.first, let last = segment.last,
                  let averageBPM = averageHeartRate(in: heartRateSamples, start: first.timestamp, end: last.timestamp)
            else { continue }

            samples.append(
                WorkoutDistanceChartSample(distanceKilometers: cumulativeDistance / 1_000, value: Double(averageBPM))
            )
        }

        return samples
    }

    static func speedSamples(from route: WorkoutRoute) -> [WorkoutDistanceChartSample] {
        let points = timestampedPoints(from: route)
        guard points.count >= 2 else { return [] }

        let totalDistance = pathDistanceMeters(points)
        guard totalDistance > 0 else { return [] }
        let bucketSize = max(200.0, totalDistance / 60)

        var samples: [WorkoutDistanceChartSample] = []
        var segmentStartIndex = 0
        var cumulativeDistance = 0.0
        var nextThreshold = bucketSize

        for index in 1..<points.count {
            cumulativeDistance += distance(points[index - 1], points[index])
            guard cumulativeDistance >= nextThreshold || index == points.count - 1 else { continue }

            let segment = Array(points[segmentStartIndex...index])
            guard let first = segment.first, let last = segment.last else { continue }
            let segmentDuration = last.timestamp.timeIntervalSince(first.timestamp)
            let segmentDistance = pathDistanceMeters(segment)
            guard segmentDuration > 0, segmentDistance > 0 else { continue }

            let kilometersPerHour = (segmentDistance / segmentDuration) * 3.6
            samples.append(
                WorkoutDistanceChartSample(distanceKilometers: cumulativeDistance / 1_000, value: kilometersPerHour)
            )

            segmentStartIndex = index
            nextThreshold += bucketSize
        }

        return samples
    }

    static func elevationSamples(from route: WorkoutRoute) -> [WorkoutDistanceChartSample] {
        let points = altitudePoints(from: route)
        guard points.count >= 2 else { return [] }

        let totalDistance = points.last?.distanceMeters ?? 0
        guard totalDistance > 0 else { return [] }
        let bucketSize = max(200.0, totalDistance / 60)

        var samples: [WorkoutDistanceChartSample] = []
        var bucketPoints: [(distanceMeters: Double, altitude: Double)] = []
        var nextThreshold = bucketSize

        for point in points {
            bucketPoints.append(point)
            guard point.distanceMeters >= nextThreshold || point.distanceMeters == totalDistance else { continue }

            let averageAltitude = bucketPoints.map(\.altitude).reduce(0, +) / Double(bucketPoints.count)
            samples.append(
                WorkoutDistanceChartSample(distanceKilometers: point.distanceMeters / 1_000, value: averageAltitude)
            )

            bucketPoints = []
            nextThreshold += bucketSize
        }

        return samples
    }

    private static func altitudePoints(
        from route: WorkoutRoute
    ) -> [(distanceMeters: Double, altitude: Double)] {
        var result: [(distanceMeters: Double, altitude: Double)] = []
        var cumulativeDistance = 0.0
        var previous: WorkoutRouteCoordinate?

        for coordinate in route.coordinates {
            if let previous {
                cumulativeDistance += distance(
                    lat1: previous.latitude, lon1: previous.longitude,
                    lat2: coordinate.latitude, lon2: coordinate.longitude
                )
            }
            if let altitude = coordinate.altitude {
                result.append((distanceMeters: cumulativeDistance, altitude: altitude))
            }
            previous = coordinate
        }

        return result
    }

    private static func timestampedPoints(
        from route: WorkoutRoute
    ) -> [(latitude: Double, longitude: Double, timestamp: Date)] {
        route.coordinates.compactMap { coordinate in
            guard let timestamp = coordinate.timestamp else { return nil }
            return (coordinate.latitude, coordinate.longitude, timestamp)
        }
    }

    private static func pathDistanceMeters(
        _ points: [(latitude: Double, longitude: Double, timestamp: Date)]
    ) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    private static func distance(
        _ a: (latitude: Double, longitude: Double, timestamp: Date),
        _ b: (latitude: Double, longitude: Double, timestamp: Date)
    ) -> Double {
        distance(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
    }

    private static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let rlat1 = lat1 * .pi / 180
        let rlat2 = lat2 * .pi / 180
        let deltaLat = (lat2 - lat1) * .pi / 180
        let deltaLon = (lon2 - lon1) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(rlat1) * cos(rlat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    private static func averageHeartRate(
        in samples: [HealthKitWorkoutMetricSample],
        start: Date,
        end: Date
    ) -> Int? {
        let matching = samples.filter { $0.sampleType == .heartRate && $0.startDate >= start && $0.startDate < end }
        guard matching.isEmpty == false else { return nil }
        let average = matching.map(\.value).reduce(0, +) / Double(matching.count)
        return Int(average.rounded())
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }

    private static func formattedPace(secondsPerKm: TimeInterval) -> String {
        let totalSeconds = Int(secondsPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))/km"
    }
}
