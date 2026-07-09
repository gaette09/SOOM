import Foundation

enum GPXRouteAttachmentError: Error, Equatable {
    case invalidGPX(GPXRouteParserError)
    case routeTooShort
    case workoutNotFound(UUID)
    case alreadyHasRoute
    case unsupportedSource(UnifiedDataSource)
    case persistenceFailed
}

struct GPXRouteAttachmentResult: Equatable {
    let workout: UnifiedWorkout
    let route: WorkoutRoute
}

struct GPXRouteAttachmentService {
    private let workoutStore: any UnifiedWorkoutStore
    private let routeStore: any WorkoutRoutePersistenceStoring
    private let parser: GPXRouteParser
    private let dateProvider: () -> Date

    init(
        workoutStore: any UnifiedWorkoutStore,
        routeStore: any WorkoutRoutePersistenceStoring,
        parser: GPXRouteParser = GPXRouteParser(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.workoutStore = workoutStore
        self.routeStore = routeStore
        self.parser = parser
        self.dateProvider = dateProvider
    }

    func attachRoute(
        to workoutId: UUID,
        gpxData: Data,
        replacingExistingRoute: Bool = false
    ) async -> Result<GPXRouteAttachmentResult, GPXRouteAttachmentError> {
        let workout: UnifiedWorkout
        do {
            guard let fetchedWorkout = try await workoutStore.fetchWorkout(id: workoutId) else {
                return .failure(.workoutNotFound(workoutId))
            }
            workout = fetchedWorkout
        } catch {
            return .failure(.workoutNotFound(workoutId))
        }

        guard isSupported(workout) else {
            return .failure(.unsupportedSource(workout.source))
        }

        let parsedRoute: GPXParsedRoute
        do {
            parsedRoute = try parser.parse(gpxData)
        } catch let error as GPXRouteParserError {
            return .failure(.invalidGPX(error))
        } catch {
            return .failure(.invalidGPX(.malformedXML))
        }

        guard parsedRoute.coordinates.count >= 2 else {
            return .failure(.routeTooShort)
        }

        do {
            let existingRoute = try await routeStore.fetchRoute(workoutId: workout.id)
            if existingRoute != nil && !replacingExistingRoute {
                return .failure(.alreadyHasRoute)
            }
        } catch {
            return .failure(.persistenceFailed)
        }

        let route = WorkoutRoute(
            workoutId: workout.id,
            source: workout.source,
            coordinates: parsedRoute.coordinates,
            totalDistanceMeters: parsedRoute.totalDistanceMeters,
            totalElevationGain: totalElevationGain(from: parsedRoute.coordinates),
            createdAt: dateProvider()
        )

        do {
            try await routeStore.saveRoute(route)
        } catch {
            await markRoutePersistenceFailedIfNeeded(workout)
            return .failure(.persistenceFailed)
        }

        let updatedWorkout = workout.withRouteMissingReason(.none, updatedAt: dateProvider())
        do {
            try await workoutStore.saveWorkout(updatedWorkout)
        } catch {
            return .failure(.persistenceFailed)
        }

        return .success(
            GPXRouteAttachmentResult(
                workout: updatedWorkout,
                route: route
            )
        )
    }

    private func isSupported(_ workout: UnifiedWorkout) -> Bool {
        workout.source == .appleHealthKit
    }

    private func markRoutePersistenceFailedIfNeeded(_ workout: UnifiedWorkout) async {
        guard workout.routeMissingReason != .none else { return }
        let updatedWorkout = workout.withRouteMissingReason(.routePersistenceFailed, updatedAt: dateProvider())
        try? await workoutStore.saveWorkout(updatedWorkout)
    }

    private func totalElevationGain(from coordinates: [WorkoutRouteCoordinate]) -> Double? {
        let altitudes = coordinates.compactMap(\.altitude)
        guard altitudes.count > 1 else { return nil }

        let gain = zip(altitudes, altitudes.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1 - pair.0)
        }

        return gain > 0 ? gain : nil
    }
}
