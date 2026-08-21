import Foundation

/// The fastest contiguous D-minute window found within one workout's route.
/// Distinct from `WorkoutChartDataBuilder`'s fixed distance buckets — this is a
/// sliding-window search for the single best segment of a given duration, not a
/// full chart series. Powers map achievement markers (feed-detail-migration-plan.md
/// batch 7), speed/pace only — no power data source exists in SOOM for any source.
struct WorkoutBestEffort: Equatable {
    let durationMinutes: Int
    /// Meters per second over the best window. Callers format as pace or speed
    /// depending on workout type (same convention as `ProcessedWorkoutBuilder`).
    let averageMetersPerSecond: Double
    let routeCoordinate: WorkoutRouteCoordinate
}

enum WorkoutSegmentBestEffortFinder {
    /// Small, curated set — this powers map markers (at most a couple shown per
    /// workout), not a full leaderboard table, so a handful of durations is enough
    /// to catch standout efforts without over-computing.
    static let candidateDurationsMinutes = [1, 5, 10]

    static func bestEfforts(from route: WorkoutRoute) -> [WorkoutBestEffort] {
        let points = timestampedPoints(from: route)
        guard points.count >= 2 else { return [] }

        return candidateDurationsMinutes.compactMap { minutes in
            bestEffort(forDurationMinutes: minutes, points: points)
        }
    }

    private static func bestEffort(
        forDurationMinutes minutes: Int,
        points: [(coordinate: WorkoutRouteCoordinate, timestamp: Date, cumulativeDistance: Double)]
    ) -> WorkoutBestEffort? {
        let targetDuration = TimeInterval(minutes * 60)

        var bestSpeed: Double = 0
        var bestMidIndex: Int?
        var windowEnd = 0

        for windowStart in 0..<points.count {
            if windowEnd < windowStart { windowEnd = windowStart }

            while windowEnd < points.count - 1,
                  points[windowEnd].timestamp.timeIntervalSince(points[windowStart].timestamp) < targetDuration {
                windowEnd += 1
            }

            let elapsed = points[windowEnd].timestamp.timeIntervalSince(points[windowStart].timestamp)
            guard elapsed >= targetDuration else { break } // route too short from here on — no more valid windows

            let distance = points[windowEnd].cumulativeDistance - points[windowStart].cumulativeDistance
            guard distance > 0 else { continue }

            let speed = distance / elapsed
            if speed > bestSpeed {
                bestSpeed = speed
                bestMidIndex = (windowStart + windowEnd) / 2
            }
        }

        guard let midIndex = bestMidIndex, bestSpeed > 0 else { return nil }

        return WorkoutBestEffort(
            durationMinutes: minutes,
            averageMetersPerSecond: bestSpeed,
            routeCoordinate: points[midIndex].coordinate
        )
    }

    private static func timestampedPoints(
        from route: WorkoutRoute
    ) -> [(coordinate: WorkoutRouteCoordinate, timestamp: Date, cumulativeDistance: Double)] {
        var result: [(coordinate: WorkoutRouteCoordinate, timestamp: Date, cumulativeDistance: Double)] = []
        var cumulative = 0.0
        var previous: WorkoutRouteCoordinate?

        for coordinate in route.coordinates {
            guard let timestamp = coordinate.timestamp else { continue }
            if let previous {
                cumulative += distance(previous, coordinate)
            }
            result.append((coordinate, timestamp, cumulative))
            previous = coordinate
        }

        return result
    }

    private static func distance(_ a: WorkoutRouteCoordinate, _ b: WorkoutRouteCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
