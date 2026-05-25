import XCTest
@testable import SOOM

final class SimilarWorkoutCandidateProviderTests: XCTestCase {
    func testCandidatesIncludeSameWorkoutTypeOnly() async throws {
        let current = makeWorkout(type: .running, daysAgo: 0, distanceMeters: 10_000)
        let running = makeWorkout(type: .running, daysAgo: 3, distanceMeters: 9_800)
        let cycling = makeWorkout(type: .cycling, daysAgo: 2, distanceMeters: 30_000)
        let provider = makeProvider(workouts: [current, running, cycling])

        let candidates = try await provider.candidates(for: current)

        XCTAssertEqual(candidates.map(\.id), [running.id])
        XCTAssertTrue(candidates.allSatisfy { $0.workoutType == .running })
    }

    func testCandidatesExcludeCurrentWorkoutAndExcludedWorkouts() async throws {
        let current = makeWorkout(type: .cycling, daysAgo: 0, distanceMeters: 30_000)
        let excluded = makeWorkout(type: .cycling, daysAgo: 2, distanceMeters: 30_500, isExcluded: true)
        let included = makeWorkout(type: .cycling, daysAgo: 4, distanceMeters: 29_700)
        let provider = makeProvider(workouts: [current, excluded, included])

        let candidates = try await provider.candidates(for: current)

        XCTAssertEqual(candidates.map(\.id), [included.id])
        XCTAssertFalse(candidates.contains { $0.id == current.id })
    }

    func testRecentCandidatesAreOrderedNewestFirst() async throws {
        let current = makeWorkout(type: .running, daysAgo: 0, distanceMeters: 10_000)
        let older = makeWorkout(type: .running, daysAgo: 8, distanceMeters: 10_100)
        let newer = makeWorkout(type: .running, daysAgo: 2, distanceMeters: 9_900)
        let provider = makeProvider(workouts: [older, current, newer])

        let candidates = try await provider.candidates(for: current)

        XCTAssertEqual(candidates.map(\.id), [newer.id, older.id])
    }

    func testDistanceFallbackChoosesClosestDistanceCandidate() async throws {
        let current = makeWorkout(type: .cycling, daysAgo: 0, distanceMeters: 40_000)
        let recentButFar = makeWorkout(type: .cycling, daysAgo: 1, distanceMeters: 55_000)
        let closest = makeWorkout(type: .cycling, daysAgo: 5, distanceMeters: 39_000)
        let provider = makeProvider(workouts: [current, recentButFar, closest])

        let result = try await provider.bestCandidate(for: current, currentRoute: nil, candidateRoutesByWorkoutId: [:])

        XCTAssertEqual(result?.baseline.id, closest.id)
        XCTAssertNil(result?.routeCandidate)
    }

    func testRouteCandidateCanRankWhenRoutesAreAvailable() async throws {
        let current = makeWorkout(type: .running, daysAgo: 0, distanceMeters: 10_000)
        let routeMatched = makeWorkout(type: .running, daysAgo: 6, distanceMeters: 10_100)
        let distanceMatched = makeWorkout(type: .running, daysAgo: 2, distanceMeters: 10_050)
        let currentRoute = makeRoute(workoutId: current.id, distance: 10_000, offset: 0)
        let routeMatchedRoute = makeRoute(workoutId: routeMatched.id, distance: 10_100, offset: 0.0003)
        let provider = makeProvider(workouts: [current, distanceMatched, routeMatched])

        let result = try await provider.bestCandidate(
            for: current,
            currentRoute: currentRoute,
            candidateRoutesByWorkoutId: [routeMatched.id: routeMatchedRoute]
        )

        XCTAssertEqual(result?.baseline.id, routeMatched.id)
        XCTAssertEqual(result?.routeCandidate?.reason, .similarRoute)
    }

    func testPersistedRouteProviderCanRankCandidateWhenRoutesAreStored() async throws {
        let current = makeWorkout(type: .running, daysAgo: 0, distanceMeters: 10_000)
        let routeMatched = makeWorkout(type: .running, daysAgo: 6, distanceMeters: 10_100)
        let distanceMatched = makeWorkout(type: .running, daysAgo: 2, distanceMeters: 10_050)
        let routeProvider = FakePersistedRouteCandidateProvider(
            result: PersistedRouteCandidateSet(
                currentRoute: makeRoute(workoutId: current.id, distance: 10_000, offset: 0),
                candidateRoutesByWorkoutId: [
                    routeMatched.id: makeRoute(workoutId: routeMatched.id, distance: 10_100, offset: 0.0003)
                ],
                currentCourseIdentity: CourseIdentityBuilder().build(
                    from: makeRoute(workoutId: current.id, distance: 10_000, offset: 0)
                )
            )
        )
        let provider = makeProvider(
            workouts: [current, distanceMatched, routeMatched],
            persistedRouteProvider: routeProvider
        )

        let result = try await provider.bestCandidate(for: current)

        XCTAssertEqual(result?.baseline.id, routeMatched.id)
        XCTAssertEqual(result?.routeCandidate?.reason, .similarRoute)
        XCTAssertNotNil(result?.currentCourseIdentity)
    }

    func testPersistedRouteProviderFailureFallsBackToDistanceCandidate() async throws {
        let current = makeWorkout(type: .cycling, daysAgo: 0, distanceMeters: 40_000)
        let routeMatched = makeWorkout(type: .cycling, daysAgo: 7, distanceMeters: 44_000)
        let closestDistance = makeWorkout(type: .cycling, daysAgo: 2, distanceMeters: 39_500)
        let provider = makeProvider(
            workouts: [current, routeMatched, closestDistance],
            persistedRouteProvider: FakePersistedRouteCandidateProvider(error: SampleError.routeFailed)
        )

        let result = try await provider.bestCandidate(for: current)

        XCTAssertEqual(result?.baseline.id, closestDistance.id)
        XCTAssertNil(result?.routeCandidate)
    }

    func testInsufficientDataReturnsNil() async throws {
        let current = makeWorkout(type: .swimming, daysAgo: 0, distanceMeters: 1_500)
        let provider = makeProvider(workouts: [current])

        let result = try await provider.bestCandidate(for: current, currentRoute: nil, candidateRoutesByWorkoutId: [:])

        XCTAssertNil(result)
    }

    func testProviderDoesNotUseRecoveryCalculator() async throws {
        let current = makeWorkout(type: .running, daysAgo: 0, distanceMeters: 10_000)
        let previous = makeWorkout(type: .running, daysAgo: 3, distanceMeters: 9_900)
        let provider = makeProvider(workouts: [current, previous])

        let result = try await provider.bestCandidate(for: current, currentRoute: nil, candidateRoutesByWorkoutId: [:])

        XCTAssertEqual(result?.baseline.id, previous.id)
    }

    private func makeProvider(
        workouts: [UnifiedWorkout],
        persistedRouteProvider: (any PersistedRouteCandidateProviding)? = nil
    ) -> SimilarWorkoutCandidateProvider {
        SimilarWorkoutCandidateProvider(
            store: SimilarWorkoutCandidateFakeStore(workouts: workouts),
            persistedRouteProvider: persistedRouteProvider,
            recentDays: 90,
            maxCandidateCount: 20
        )
    }

    private func makeWorkout(
        id: UUID = UUID(),
        type: UnifiedWorkoutType,
        daysAgo: Int,
        distanceMeters: Double?,
        isExcluded: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .minute, value: 60, to: startDate) ?? startDate
        return UnifiedWorkout(
            id: id,
            externalId: nil,
            source: .appleHealthKit,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 60 * 60,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: 142,
            maxHeartRate: 166,
            averageSpeedMetersPerSecond: distanceMeters.map { $0 / (60 * 60) },
            elevationGainMeters: 100,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcluded,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeRoute(workoutId: UUID, distance: Double, offset: Double) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.5000 + offset, longitude: 127.0000 + offset),
                WorkoutRouteCoordinate(latitude: 37.5050 + offset, longitude: 127.0060 + offset)
            ],
            totalDistanceMeters: distance
        )
    }
}

private final class SimilarWorkoutCandidateFakeStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]

    init(workouts: [UnifiedWorkout]) {
        self.workouts = workouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        workouts.sorted { $0.startDate > $1.startDate }
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        workouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}


private enum SampleError: Error {
    case routeFailed
}

private struct FakePersistedRouteCandidateProvider: PersistedRouteCandidateProviding {
    let result: PersistedRouteCandidateSet?
    let error: Error?

    init(result: PersistedRouteCandidateSet? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func routes(
        currentWorkoutId: UUID,
        candidateWorkoutIds: [UUID]
    ) async throws -> PersistedRouteCandidateSet {
        if let error { throw error }
        return result ?? PersistedRouteCandidateSet(
            currentRoute: nil,
            candidateRoutesByWorkoutId: [:],
            currentCourseIdentity: nil
        )
    }
}
