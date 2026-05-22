import CoreLocation
import Foundation
import HealthKit

struct HealthKitWorkoutRouteMapper {
    func map(
        workout: HKWorkout,
        locations: [CLLocation],
        createdAt: Date = Date()
    ) -> WorkoutRoute? {
        guard !locations.isEmpty else { return nil }

        let coordinates = locations.map { location in
            WorkoutRouteCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                timestamp: location.timestamp
            )
        }

        return WorkoutRoute(
            workoutId: workout.uuid,
            source: .appleHealthKit,
            coordinates: coordinates,
            totalDistanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? totalDistance(from: locations),
            totalElevationGain: totalElevationGain(from: locations),
            createdAt: createdAt
        )
    }

    private func totalDistance(from locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }

        return zip(locations, locations.dropFirst()).reduce(0) { total, pair in
            total + pair.0.distance(from: pair.1)
        }
    }

    private func totalElevationGain(from locations: [CLLocation]) -> Double? {
        guard locations.count > 1 else { return nil }

        let gain = zip(locations, locations.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1.altitude - pair.0.altitude)
        }

        return gain
    }
}
