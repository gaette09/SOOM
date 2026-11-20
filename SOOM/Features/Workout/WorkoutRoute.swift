import Foundation

struct WorkoutRouteCoordinate: Identifiable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date?
    let segmentIndex: Int

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        timestamp: Date? = nil,
        segmentIndex: Int = 0
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.segmentIndex = segmentIndex
    }
}

struct WorkoutRouteBounds: Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double
}

struct WorkoutRoute: Identifiable, Equatable {
    let id: UUID
    let workoutId: UUID
    let source: UnifiedDataSource
    let coordinates: [WorkoutRouteCoordinate]
    let totalDistanceMeters: Double
    let totalElevationGain: Double?
    let bounds: WorkoutRouteBounds?
    let createdAt: Date
    /// Derived display geometry only; persistent source coordinates stay unchanged.
    let privacyMaskApplied: Bool
    /// Display-only metadata. Legacy/shared v1 masked routes used a 200m fence.
    let privacyMaskRadiusMeters: Double?
    /// Source-backed authorization. A locally masked preview never sets this.
    let hasAuthoritativeShareMask: Bool

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        source: UnifiedDataSource,
        coordinates: [WorkoutRouteCoordinate],
        totalDistanceMeters: Double,
        totalElevationGain: Double? = nil,
        bounds: WorkoutRouteBounds? = nil,
        createdAt: Date = Date(),
        privacyMaskApplied: Bool = false,
        privacyMaskRadiusMeters: Double? = nil,
        hasAuthoritativeShareMask: Bool = false
    ) {
        self.id = id
        self.workoutId = workoutId
        self.source = source
        self.coordinates = coordinates
        self.totalDistanceMeters = max(0, totalDistanceMeters)
        self.totalElevationGain = totalElevationGain.map { max(0, $0) }
        self.bounds = bounds ?? Self.makeBounds(from: coordinates)
        self.createdAt = createdAt
        self.privacyMaskApplied = privacyMaskApplied
        self.privacyMaskRadiusMeters = privacyMaskApplied ? (privacyMaskRadiusMeters ?? 200) : nil
        self.hasAuthoritativeShareMask = privacyMaskApplied && hasAuthoritativeShareMask
    }

    /// Contiguous segments preserve pauses and GPS interruptions without inventing connecting lines.
    var coordinateSegments: [[WorkoutRouteCoordinate]] {
        coordinates.reduce(into: []) { segments, coordinate in
            if segments.last?.last?.segmentIndex == coordinate.segmentIndex {
                segments[segments.count - 1].append(coordinate)
            } else {
                segments.append([coordinate])
            }
        }
    }

    // Future: add encoded polyline helpers when Mapbox/route rendering is connected.
    private static func makeBounds(from coordinates: [WorkoutRouteCoordinate]) -> WorkoutRouteBounds? {
        guard let first = coordinates.first else { return nil }

        return coordinates.reduce(
            WorkoutRouteBounds(
                minLatitude: first.latitude,
                maxLatitude: first.latitude,
                minLongitude: first.longitude,
                maxLongitude: first.longitude
            )
        ) { bounds, coordinate in
            WorkoutRouteBounds(
                minLatitude: min(bounds.minLatitude, coordinate.latitude),
                maxLatitude: max(bounds.maxLatitude, coordinate.latitude),
                minLongitude: min(bounds.minLongitude, coordinate.longitude),
                maxLongitude: max(bounds.maxLongitude, coordinate.longitude)
            )
        }
    }
}
