import Foundation

struct CourseIdentityBuilder {
    private let identityVersion = 1
    private let coordinateBucketDegrees = 0.002
    private let distanceBucketMeters: Double = 250

    func build(from route: WorkoutRoute, source: CourseIdentitySource = .generated) -> CourseIdentity? {
        guard route.totalDistanceMeters > 0,
              let bounds = route.bounds else {
            return nil
        }

        let centerLatitude = (bounds.minLatitude + bounds.maxLatitude) / 2
        let centerLongitude = (bounds.minLongitude + bounds.maxLongitude) / 2
        let normalizedCenterLatitude = bucket(centerLatitude, size: coordinateBucketDegrees)
        let normalizedCenterLongitude = bucket(centerLongitude, size: coordinateBucketDegrees)
        let normalizedDistance = bucket(route.totalDistanceMeters, size: distanceBucketMeters)
        let normalizedBounds = [
            bucket(bounds.minLatitude, size: coordinateBucketDegrees),
            bucket(bounds.maxLatitude, size: coordinateBucketDegrees),
            bucket(bounds.minLongitude, size: coordinateBucketDegrees),
            bucket(bounds.maxLongitude, size: coordinateBucketDegrees)
        ]
        .map { String(format: "%.3f", $0) }
        .joined(separator: ":")

        let courseId = [
            "course",
            "v\(identityVersion)",
            String(format: "%.3f", normalizedCenterLatitude),
            String(format: "%.3f", normalizedCenterLongitude),
            String(Int(normalizedDistance)),
            normalizedBounds
        ].joined(separator: "-")

        return CourseIdentity(
            courseId: courseId,
            identityVersion: identityVersion,
            estimatedCenter: WorkoutRouteCoordinate(
                latitude: normalizedCenterLatitude,
                longitude: normalizedCenterLongitude
            ),
            estimatedDistance: normalizedDistance,
            estimatedDirection: estimateDirection(for: route),
            source: source
        )
    }

    private func estimateDirection(for route: WorkoutRoute) -> CourseDirectionEstimate? {
        guard let start = route.coordinates.first,
              let end = route.coordinates.last else {
            return nil
        }

        let latitudeDelta = end.latitude - start.latitude
        let longitudeDelta = end.longitude - start.longitude

        if abs(latitudeDelta) < 0.001, abs(longitudeDelta) < 0.001 {
            return .loop
        }

        if abs(latitudeDelta) >= abs(longitudeDelta) {
            return latitudeDelta >= 0 ? .northbound : .southbound
        }

        return longitudeDelta >= 0 ? .eastbound : .westbound
    }

    private func bucket(_ value: Double, size: Double) -> Double {
        guard size > 0 else { return value }
        return (value / size).rounded() * size
    }
}
