import Foundation

struct RoutePrivacyMasker {
    func mask(
        route: WorkoutRoute,
        policy: RoutePrivacyMaskingPolicy = .defaultShare
    ) -> WorkoutRoute {
        guard policy.mode != .none,
              policy.distanceMeters > 0,
              route.coordinates.count >= 2
        else {
            return route
        }

        var coordinates = route.coordinates

        if policy.shouldMaskStart {
            coordinates = removeCoordinatesNearStart(
                coordinates,
                distanceMeters: policy.distanceMeters
            )
        }

        if policy.shouldMaskEnd {
            coordinates = removeCoordinatesNearEnd(
                coordinates,
                distanceMeters: policy.distanceMeters
            )
        }

        return WorkoutRoute(
            id: route.id,
            workoutId: route.workoutId,
            source: route.source,
            coordinates: coordinates,
            totalDistanceMeters: maskedDistance(from: coordinates),
            totalElevationGain: maskedElevationGain(from: coordinates),
            createdAt: route.createdAt
        )
    }

    private func removeCoordinatesNearStart(
        _ coordinates: [WorkoutRouteCoordinate],
        distanceMeters: Double
    ) -> [WorkoutRouteCoordinate] {
        guard coordinates.count >= 2 else { return coordinates }

        let start = coordinates[0]
        let firstVisibleIndex = coordinates.firstIndex { coordinate in
            Self.distance(from: start, to: coordinate) >= distanceMeters
        }

        guard let firstVisibleIndex else { return [] }
        return Array(coordinates[firstVisibleIndex...])
    }

    private func removeCoordinatesNearEnd(
        _ coordinates: [WorkoutRouteCoordinate],
        distanceMeters: Double
    ) -> [WorkoutRouteCoordinate] {
        guard coordinates.count >= 2 else { return coordinates }

        let end = coordinates[coordinates.count - 1]
        let lastVisibleIndex = coordinates.lastIndex { coordinate in
            Self.distance(from: end, to: coordinate) >= distanceMeters
        }

        guard let lastVisibleIndex else { return [] }
        return Array(coordinates[...lastVisibleIndex])
    }

    private func maskedDistance(from coordinates: [WorkoutRouteCoordinate]) -> Double {
        guard coordinates.count >= 2 else { return 0 }

        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + Self.distance(from: pair.0, to: pair.1)
        }
    }

    private func maskedElevationGain(from coordinates: [WorkoutRouteCoordinate]) -> Double? {
        guard coordinates.count >= 2,
              coordinates.contains(where: { $0.altitude != nil })
        else {
            return nil
        }

        let gain = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            guard let previous = pair.0.altitude,
                  let current = pair.1.altitude,
                  current > previous
            else {
                return total
            }

            return total + current - previous
        }

        return gain
    }

    private static func distance(
        from start: WorkoutRouteCoordinate,
        to end: WorkoutRouteCoordinate
    ) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusMeters * c
    }
}
