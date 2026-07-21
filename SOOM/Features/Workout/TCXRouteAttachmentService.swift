import Foundation

enum TCXRouteAttachmentMismatch: Equatable {
    case sport
    case startTime
    case duration
    case distance
}

enum TCXRouteAttachmentError: Error, Equatable {
    case invalidTCX(TCXRouteParserError)
    case routeTooShort
    case workoutNotFound(UUID)
    case alreadyHasRoute
    case unsupportedSource(UnifiedDataSource)
    case incompatibleWorkout(TCXRouteAttachmentMismatch)
    case persistenceFailed
}

struct TCXRouteAttachmentResult: Equatable {
    let workout: UnifiedWorkout
    let route: WorkoutRoute
    let summary: TCXWorkoutSummary
}

struct TCXRouteAttachmentService {
    private let workoutStore: any UnifiedWorkoutStore
    private let routeStore: any WorkoutRoutePersistenceStoring
    private let parser: TCXRouteParser
    private let dateProvider: () -> Date

    private let startTimeTolerance: TimeInterval = 5 * 60
    private let durationToleranceRatio = 0.10
    private let distanceToleranceRatio = 0.15

    init(
        workoutStore: any UnifiedWorkoutStore,
        routeStore: any WorkoutRoutePersistenceStoring,
        parser: TCXRouteParser = TCXRouteParser(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.workoutStore = workoutStore
        self.routeStore = routeStore
        self.parser = parser
        self.dateProvider = dateProvider
    }

    func attachRoute(
        to workoutId: UUID,
        tcxData: Data
    ) async -> Result<TCXRouteAttachmentResult, TCXRouteAttachmentError> {
        let workout: UnifiedWorkout
        do {
            guard let fetchedWorkout = try await workoutStore.fetchWorkout(id: workoutId) else {
                return .failure(.workoutNotFound(workoutId))
            }
            workout = fetchedWorkout
        } catch {
            return .failure(.workoutNotFound(workoutId))
        }

        guard workout.source == .appleHealthKit else {
            return .failure(.unsupportedSource(workout.source))
        }

        let parsedRoute: TCXParsedRoute
        do {
            parsedRoute = try parser.parse(tcxData)
        } catch let error as TCXRouteParserError {
            return .failure(.invalidTCX(error))
        } catch {
            return .failure(.invalidTCX(.malformedXML))
        }

        guard parsedRoute.coordinates.count >= 2 else {
            return .failure(.routeTooShort)
        }

        if let mismatch = compatibilityMismatch(
            workout: workout,
            summary: parsedRoute.summary
        ) {
            return .failure(.incompatibleWorkout(mismatch))
        }

        do {
            let existingRoute = try await routeStore.fetchRoute(workoutId: workout.id)
            if existingRoute != nil {
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
            totalElevationGain: parsedRoute.summary.elevationGainMeters
                ?? totalElevationGain(from: parsedRoute.coordinates),
            createdAt: dateProvider()
        )

        do {
            try await routeStore.saveRoute(route)
        } catch {
            return .failure(.persistenceFailed)
        }

        let updatedWorkout = workout.withRouteMissingReason(.none, updatedAt: dateProvider())
        do {
            try await workoutStore.saveWorkout(updatedWorkout)
        } catch {
            return .failure(.persistenceFailed)
        }

        return .success(
            TCXRouteAttachmentResult(
                workout: updatedWorkout,
                route: route,
                summary: parsedRoute.summary
            )
        )
    }

    private func compatibilityMismatch(
        workout: UnifiedWorkout,
        summary: TCXWorkoutSummary
    ) -> TCXRouteAttachmentMismatch? {
        if let tcxType = summary.workoutType,
           tcxType != .other,
           workout.workoutType != .other,
           tcxType != workout.workoutType {
            return .sport
        }

        if let tcxStartDate = summary.startDate,
           abs(tcxStartDate.timeIntervalSince(workout.startDate)) > startTimeTolerance {
            return .startTime
        }

        if let tcxDuration = summary.durationSeconds,
           differenceRatio(tcxDuration, workout.durationSeconds) > durationToleranceRatio {
            return .duration
        }

        if let tcxDistance = summary.distanceMeters,
           let workoutDistance = workout.distanceMeters,
           differenceRatio(tcxDistance, workoutDistance) > distanceToleranceRatio {
            return .distance
        }

        return nil
    }

    private func differenceRatio(_ lhs: Double, _ rhs: Double) -> Double {
        let baseline = max(abs(lhs), abs(rhs))
        guard baseline > 0 else { return 0 }
        return abs(lhs - rhs) / baseline
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
