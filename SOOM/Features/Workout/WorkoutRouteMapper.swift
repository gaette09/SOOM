import Foundation

struct WorkoutRouteMapper {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let courseIdentityBuilder: CourseIdentityBuilder

    init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        courseIdentityBuilder: CourseIdentityBuilder = CourseIdentityBuilder()
    ) {
        self.encoder = encoder
        self.decoder = decoder
        self.courseIdentityBuilder = courseIdentityBuilder
    }

    func makeRecord(
        from route: WorkoutRoute,
        updatedAt: Date = Date()
    ) -> PersistedWorkoutRoute {
        PersistedWorkoutRoute(
            id: route.id,
            workoutId: route.workoutId,
            sourceRaw: route.source.rawValue,
            encodedCoordinates: encodeCoordinates(route.coordinates),
            coordinateCount: route.coordinates.count,
            totalDistanceMeters: route.totalDistanceMeters,
            totalElevationGain: route.totalElevationGain,
            createdAt: route.createdAt,
            updatedAt: updatedAt,
            courseIdentity: courseIdentityBuilder.build(from: route)?.courseId
        )
    }

    func update(
        _ record: PersistedWorkoutRoute,
        with route: WorkoutRoute,
        updatedAt: Date = Date()
    ) {
        record.id = route.id
        record.workoutId = route.workoutId
        record.sourceRaw = route.source.rawValue
        record.encodedCoordinates = encodeCoordinates(route.coordinates)
        record.coordinateCount = route.coordinates.count
        record.totalDistanceMeters = route.totalDistanceMeters
        record.totalElevationGain = route.totalElevationGain
        record.createdAt = route.createdAt
        record.updatedAt = updatedAt
        record.courseIdentity = courseIdentityBuilder.build(from: route)?.courseId
    }

    func makeRoute(from record: PersistedWorkoutRoute) -> WorkoutRoute {
        WorkoutRoute(
            id: record.id,
            workoutId: record.workoutId,
            source: UnifiedDataSource(rawValue: record.sourceRaw) ?? .unknown,
            coordinates: decodeCoordinates(record.encodedCoordinates),
            totalDistanceMeters: record.totalDistanceMeters,
            totalElevationGain: record.totalElevationGain,
            createdAt: record.createdAt
        )
    }

    func encodeCoordinates(_ coordinates: [WorkoutRouteCoordinate]) -> String? {
        let payload = coordinates.map(EncodedCoordinate.init)

        guard let data = try? encoder.encode(payload) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func decodeCoordinates(_ encodedCoordinates: String?) -> [WorkoutRouteCoordinate] {
        guard
            let encodedCoordinates,
            let data = encodedCoordinates.data(using: .utf8),
            let payload = try? decoder.decode([EncodedCoordinate].self, from: data)
        else {
            return []
        }

        return payload.map(\.coordinate)
    }
}

private struct EncodedCoordinate: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date?

    init(coordinate: WorkoutRouteCoordinate) {
        id = coordinate.id
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        altitude = coordinate.altitude
        timestamp = coordinate.timestamp
    }

    var coordinate: WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            id: id,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: timestamp
        )
    }
}
