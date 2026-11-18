import Foundation

struct RoutePrivacyMasker {
    func mask(
        route: WorkoutRoute,
        policy: RoutePrivacyMaskingPolicy = .defaultDisplay
    ) -> WorkoutRoute {
        guard policy.mode != .none, policy.distanceMeters > 0 else { return route }
        if route.privacyMaskApplied, let radius = route.privacyMaskRadiusMeters, policy.distanceMeters <= radius { return route }
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("privacyMask")
        #endif
        let source = route.coordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
        }
        var coordinates: [WorkoutRouteCoordinate] = []
        if let start = source.first, let end = source.last, source.count >= 2 {
            var previous: WorkoutRouteCoordinate?
            var segment = -1
            for point in route.coordinates {
                guard point.latitude.isFinite && point.longitude.isFinite,
                      (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else {
                    previous = nil; continue // Missing/invalid geometry must never create a connecting line.
                }
                guard (!policy.shouldMaskStart || Self.distance(from: start, to: point) >= policy.distanceMeters),
                      (!policy.shouldMaskEnd || Self.distance(from: end, to: point) >= policy.distanceMeters) else {
                    previous = nil; continue
                }
                if previous == nil || previous!.segmentIndex != point.segmentIndex
                    || Self.distance(from: previous!, to: point) > 1000
                    || (policy.shouldMaskStart && !Self.edgeClear(previous!, point, origin: start, radius: policy.distanceMeters))
                    || (policy.shouldMaskEnd && !Self.edgeClear(previous!, point, origin: end, radius: policy.distanceMeters)) {
                    segment += 1
                }
                coordinates.append(WorkoutRouteCoordinate(id: point.id, latitude: point.latitude,
                    longitude: point.longitude, altitude: point.altitude, timestamp: point.timestamp, segmentIndex: segment))
                previous = point
            }
            let groups = Dictionary(grouping: coordinates, by: \.segmentIndex)
            coordinates = coordinates.filter { (groups[$0.segmentIndex]?.count ?? 0) >= 2 }
        }
        return WorkoutRoute(
            id: route.id,
            workoutId: route.workoutId,
            source: route.source,
            coordinates: coordinates,
            totalDistanceMeters: maskedDistance(from: coordinates),
            totalElevationGain: maskedElevationGain(from: coordinates),
            createdAt: route.createdAt,
            privacyMaskApplied: policy.mode == .startAndEnd,
            privacyMaskRadiusMeters: policy.mode == .startAndEnd ? policy.distanceMeters : nil
        )
    }

    private static func edgeClear(_ a: WorkoutRouteCoordinate, _ b: WorkoutRouteCoordinate,
                                  origin: WorkoutRouteCoordinate, radius: Double) -> Bool {
        func xy(_ point: WorkoutRouteCoordinate) -> (Double, Double) {
            var longitude = point.longitude - origin.longitude
            if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
            return (longitude * .pi / 180 * 6_371_000 * cos(origin.latitude * .pi / 180),
                    (point.latitude - origin.latitude) * .pi / 180 * 6_371_000)
        }
        let p = xy(a), q = xy(b), dx = q.0-p.0, dy = q.1-p.1, length = dx*dx+dy*dy
        let t = length > 0 ? min(1, max(0, -(p.0*dx+p.1*dy)/length)) : 0
        return hypot(p.0+t*dx, p.1+t*dy) >= radius + 2
    }

    private func maskedDistance(from coordinates: [WorkoutRouteCoordinate]) -> Double {
        guard coordinates.count >= 2 else { return 0 }

        return zip(coordinates, coordinates.dropFirst()).reduce(0) { total, pair in
            total + (pair.0.segmentIndex == pair.1.segmentIndex ? Self.distance(from: pair.0, to: pair.1) : 0)
        }
    }

    private func maskedElevationGain(from coordinates: [WorkoutRouteCoordinate]) -> Double? {
        guard coordinates.count >= 2,
              coordinates.contains(where: { $0.altitude != nil })
        else {
            return nil
        }

        let gain = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            guard pair.0.segmentIndex == pair.1.segmentIndex,
                  let previous = pair.0.altitude,
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
