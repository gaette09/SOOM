import HealthKit
import XCTest
@testable import SOOM

final class HealthKitImportedWorkoutSurfaceValidationTests: XCTestCase {
    private let processedBuilder = ProcessedWorkoutBuilder()
    private let shareBuilder = ShareableWorkoutCardBuilder()
    private let recoveryMapper = ProcessedWorkoutToRecoveryActivityMapper()

    func testRouteBackedHealthKitImportFeedsProcessedWorkoutSurfaces() async throws {
        let workoutID = UUID(uuidString: "71717171-7171-7171-7171-717171717171")!
        let route = makeRoute(workoutId: UUID(), distance: 24_000, elevationGain: 280)
        let importResult = await importHealthKitWorkout(
            workout: makeHealthKitWorkout(
                id: workoutID,
                type: .cycling,
                duration: 3_600,
                distance: nil,
                calories: 640
            ),
            route: route
        )
        let importedWorkout = try XCTUnwrap(importResult.importedWorkouts.first)
        let fetchedRoute = try await importResult.routeStore.fetchRoute(workoutId: workoutID)
        let storedRoute = try XCTUnwrap(fetchedRoute)
        let processed = processedBuilder.make(from: importedWorkout, route: storedRoute)

        XCTAssertEqual(importResult.result.savedCount, 1)
        XCTAssertEqual(processed.source, .appleHealthKit)
        XCTAssertEqual(processed.externalId, workoutID.uuidString)
        XCTAssertEqual(processed.route?.hasRenderableRoute, true)
        XCTAssertEqual(processed.route?.workoutId, workoutID)
        XCTAssertEqual(processed.distanceMeters, 24_000)
        XCTAssertEqual(processed.elevationGainMeters, 280)
        XCTAssertEqual(processed.metricAvailability[.distance], .derived)
        XCTAssertEqual(processed.metricAvailability[.elevation], .derived)
        XCTAssertEqual(processed.metricAvailability[.route], .measured)

        let display = processed.display
        XCTAssertEqual(display.sourceTitle, "Apple Health")
        XCTAssertEqual(display.sportTitle, "사이클")
        XCTAssertEqual(display.distanceText, "24.00 km")
        XCTAssertEqual(display.durationText, "1시간 0분")
        XCTAssertEqual(display.primaryMetricLabel, "속도")
        XCTAssertEqual(display.primaryMetricValue, "24.0 km/h")
        XCTAssertEqual(display.elevationText, "280m")
        XCTAssertEqual(display.caloriesText, "640kcal")
        XCTAssertEqual(display.averageHeartRateText, "—")
        XCTAssertEqual(display.routeBadgeLabel, "경로 저장")

        let shareCard = shareBuilder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary(workoutID: workoutID),
            recoveryImpact: recoveryImpact,
            processedWorkout: processed
        )
        XCTAssertEqual(shareCard.workoutType, .cycling)
        XCTAssertEqual(shareCard.distanceText, "24.00 km")
        XCTAssertEqual(shareCard.durationText, "1시간 0분")
        XCTAssertEqual(shareCard.averagePaceText, "24.0 km/h")
        XCTAssertEqual(shareCard.elevationGainText, "280m")
        XCTAssertNil(shareCard.averageHeartRateText)
        XCTAssertEqual(shareCard.activeEnergyText, "640kcal")
        XCTAssertEqual(shareCard.publicMetrics.map(\.label), ["거리", "속도", "시간"])

        let aggregate = makeProfileAggregator().aggregate(processedWorkouts: [processed])
        XCTAssertEqual(aggregate.workoutCount, 1)
        XCTAssertEqual(aggregate.primarySport, .cycling)
        XCTAssertEqual(aggregate.totalDistanceMeters, 24_000)
        XCTAssertEqual(aggregate.longestRideDistance, 24_000)
        XCTAssertEqual(aggregate.sportDistribution[.cycling], 1)

        let recoveryActivity = recoveryMapper.map(processed)
        XCTAssertEqual(recoveryActivity.workoutType.title, RecoveryWorkoutType.ride.title)
        XCTAssertEqual(recoveryActivity.durationMinutes, 60)
        XCTAssertEqual(recoveryActivity.distanceKm, 24, accuracy: 0.001)
        XCTAssertEqual(recoveryActivity.averageHeartRate, 0)
        XCTAssertGreaterThan(recoveryActivity.relativeEffort, 0)
        XCTAssertGreaterThan(recoveryActivity.trainingLoad, 0)
    }

    func testNoRouteHealthKitImportUsesFallbacksAcrossSurfaces() async throws {
        let workoutID = UUID(uuidString: "72727272-7272-7272-7272-727272727272")!
        let importResult = await importHealthKitWorkout(
            workout: makeHealthKitWorkout(
                id: workoutID,
                type: .running,
                duration: 1_800,
                distance: 5_000,
                calories: nil
            ),
            route: nil
        )
        let importedWorkout = try XCTUnwrap(importResult.importedWorkouts.first)
        let processed = processedBuilder.make(from: importedWorkout)

        XCTAssertEqual(importResult.result.savedCount, 1)
        let fetchedRoute = try await importResult.routeStore.fetchRoute(workoutId: workoutID)
        XCTAssertNil(fetchedRoute)
        XCTAssertNil(processed.route)
        XCTAssertEqual(processed.metricAvailability[.route], .missing)
        XCTAssertEqual(processed.display.distanceText, "5.00 km")
        XCTAssertEqual(processed.display.primaryMetricLabel, "페이스")
        XCTAssertEqual(processed.display.primaryMetricValue, "6:00/km")
        XCTAssertNil(processed.display.routeBadgeLabel)

        let shareCard = shareBuilder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary(workoutID: workoutID),
            recoveryImpact: recoveryImpact,
            processedWorkout: processed
        )
        XCTAssertEqual(shareCard.workoutType, .running)
        XCTAssertEqual(shareCard.distanceText, "5.00 km")
        XCTAssertEqual(shareCard.averagePaceText, "6:00/km")
        XCTAssertNil(shareCard.elevationGainText)
        XCTAssertNil(shareCard.averageHeartRateText)
        XCTAssertNil(shareCard.activeEnergyText)

        let aggregate = makeProfileAggregator().aggregate(processedWorkouts: [processed])
        XCTAssertEqual(aggregate.workoutCount, 1)
        XCTAssertEqual(aggregate.primarySport, .running)
        XCTAssertEqual(aggregate.totalDistanceMeters, 5_000)
        XCTAssertEqual(aggregate.longestRunDistance, 5_000)

        let recoveryActivity = recoveryMapper.map(processed)
        XCTAssertEqual(recoveryActivity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(recoveryActivity.durationMinutes, 30)
        XCTAssertEqual(recoveryActivity.distanceKm, 5, accuracy: 0.001)
    }

    func testMissingOptionalHealthKitMetricsStayUnavailableAcrossSurfaces() async throws {
        let workoutID = UUID(uuidString: "73737373-7373-7373-7373-737373737373")!
        let importResult = await importHealthKitWorkout(
            workout: makeHealthKitWorkout(
                id: workoutID,
                type: .walking,
                duration: 2_400,
                distance: nil,
                calories: nil,
                averageHeartRate: nil
            ),
            route: nil
        )
        let importedWorkout = try XCTUnwrap(importResult.importedWorkouts.first)
        let processed = processedBuilder.make(from: importedWorkout)

        XCTAssertEqual(processed.metricAvailability[.distance], .missing)
        XCTAssertEqual(processed.metricAvailability[.calories], .missing)
        XCTAssertEqual(processed.metricAvailability[.averageHeartRate], .missing)
        XCTAssertEqual(processed.metricAvailability[.elevation], .missing)
        XCTAssertEqual(processed.distanceMeters, nil)
        XCTAssertEqual(processed.activeEnergyKcal, nil)
        XCTAssertEqual(processed.averageHeartRate, nil)
        XCTAssertEqual(processed.elevationGainMeters, nil)
        XCTAssertEqual(processed.display.distanceText, "거리 준비 중")
        XCTAssertEqual(processed.display.primaryMetricValue, "움직임 준비 중")
        XCTAssertEqual(processed.display.caloriesText, "—")
        XCTAssertEqual(processed.display.averageHeartRateText, "—")
        XCTAssertEqual(processed.display.elevationText, "—")

        let shareCard = shareBuilder.build(
            sessionSummary: sessionSummary,
            growthSummary: growthSummary(workoutID: workoutID),
            recoveryImpact: recoveryImpact,
            processedWorkout: processed
        )
        XCTAssertEqual(shareCard.distanceText, "거리 준비 중")
        XCTAssertEqual(shareCard.averagePaceText, "움직임 준비 중")
        XCTAssertNil(shareCard.activeEnergyText)
        XCTAssertNil(shareCard.averageHeartRateText)
        XCTAssertNil(shareCard.elevationGainText)

        let aggregate = makeProfileAggregator().aggregate(processedWorkouts: [processed])
        XCTAssertEqual(aggregate.workoutCount, 1)
        XCTAssertEqual(aggregate.totalDistanceMeters, 0)
        XCTAssertNil(aggregate.longestWalkDistance)

        let recoveryActivity = recoveryMapper.map(processed)
        XCTAssertEqual(recoveryActivity.workoutType.title, RecoveryWorkoutType.run.title)
        XCTAssertEqual(recoveryActivity.distanceKm, 0)
        XCTAssertEqual(recoveryActivity.averageHeartRate, 0)
        XCTAssertGreaterThan(recoveryActivity.relativeEffort, 0)
    }

    func testDuplicateSkippedHealthKitWorkoutDoesNotReachSurfaceValidation() async {
        let workoutID = UUID(uuidString: "74747474-7474-7474-7474-747474747474")!
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let localWorkout = makeUnifiedWorkout(
            source: .soomLocal,
            type: .cycling,
            startDate: startDate,
            duration: 3_600,
            distance: 20_000
        )
        let store = SurfaceValidationUnifiedWorkoutStore(existingWorkouts: [localWorkout])
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: SurfaceValidationHealthKitWorkoutFetcher(
                workouts: [
                    makeHealthKitWorkout(
                        id: workoutID,
                        type: .cycling,
                        startDate: startDate.addingTimeInterval(60),
                        duration: 3_570,
                        distance: 20_500
                    )
                ]
            ),
            store: store,
            routeLookupProvider: SurfaceValidationHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: SurfaceValidationHealthKitWorkoutRouteFetcher(route: makeRoute(workoutId: workoutID)),
            routeStore: SurfaceValidationWorkoutRouteStore()
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)
        let processed = result.importedWorkouts.map { processedBuilder.make(from: $0) }

        XCTAssertEqual(result.fetchedCount, 1)
        XCTAssertEqual(result.savedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(processed.isEmpty)
        XCTAssertTrue(store.savedWorkouts.isEmpty)
        XCTAssertEqual(makeProfileAggregator().aggregate(processedWorkouts: processed), .empty)
        XCTAssertTrue(UnifiedWorkoutAnalysisInputSelector().selectRecoveryInputs(fromProcessedWorkouts: processed).isEmpty)
    }

    func testHealthKitOnlyWorkoutAppearsOnceAcrossProcessedSurfaces() async throws {
        let workoutID = UUID(uuidString: "75757575-7575-7575-7575-757575757575")!
        let store = SurfaceValidationUnifiedWorkoutStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: SurfaceValidationHealthKitWorkoutFetcher(
                workouts: [
                    makeHealthKitWorkout(id: workoutID, type: .running, duration: 2_700, distance: 9_000),
                    makeHealthKitWorkout(id: workoutID, type: .running, duration: 2_700, distance: 9_000)
                ]
            ),
            store: store
        )

        let result = await pipeline.importRecentWorkouts(limit: 10)
        let processed = result.importedWorkouts.map { processedBuilder.make(from: $0) }

        XCTAssertEqual(result.fetchedCount, 2)
        XCTAssertEqual(result.savedCount, 2)
        XCTAssertEqual(Set(store.savedWorkouts.map(\.id)), Set([workoutID]))
        XCTAssertEqual(store.savedWorkouts.count, 1)
        XCTAssertEqual(Set(processed.map(\.id)), Set([workoutID]))
        XCTAssertEqual(makeProfileAggregator().aggregate(processedWorkouts: Array(uniqueByID: processed)).workoutCount, 1)
    }

    private func importHealthKitWorkout(
        workout: HealthKitWorkout,
        route: WorkoutRoute?
    ) async -> (
        result: HealthKitWorkoutImportResult,
        importedWorkouts: [UnifiedWorkout],
        routeStore: SurfaceValidationWorkoutRouteStore
    ) {
        let routeStore = SurfaceValidationWorkoutRouteStore()
        let pipeline = HealthKitWorkoutImportPipeline(
            workoutFetcher: SurfaceValidationHealthKitWorkoutFetcher(workouts: [workout]),
            store: SurfaceValidationUnifiedWorkoutStore(),
            routeLookupProvider: SurfaceValidationHealthKitWorkoutLookupProvider(workout: makeHKWorkout()),
            routeFetcher: SurfaceValidationHealthKitWorkoutRouteFetcher(route: route),
            routeStore: routeStore
        )
        let result = await pipeline.importRecentWorkouts(limit: 10)

        return (result, result.importedWorkouts, routeStore)
    }

    private var sessionSummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            title: "좋은 리듬",
            summaryText: "안정적인 운동이에요.",
            highlightText: "흐름이 좋아요.",
            improvementText: "기록이 쌓이고 있어요.",
            recoveryText: "회복도 함께 챙겨요.",
            closingMotivation: "다음 운동도 이어가요.",
            icon: nil
        )
    }

    private var recoveryImpact: WorkoutRecoveryImpact {
        WorkoutRecoveryImpact(
            impactLevel: .moderate,
            title: "회복 영향",
            shortMessage: "무리하지 않아도 좋아요.",
            recommendation: "수면과 휴식을 챙겨요.",
            icon: nil
        )
    }

    private func growthSummary(workoutID: UUID) -> WorkoutGrowthSummary {
        WorkoutGrowthSummary(
            workoutId: workoutID,
            title: "기준 기록",
            shortSummary: "기준이 되는 기록이에요.",
            improvementType: .none,
            comparisonText: "비교 데이터 준비 중",
            motivationText: "오늘 기록은 다음 성장을 위한 기준점이에요.",
            insight: nil
        )
    }

    private func makeProfileAggregator() -> ProfileWorkoutAggregator {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ProfileWorkoutAggregator(
            calendar: calendar,
            referenceDate: Date(timeIntervalSince1970: 1_800_400_000)
        )
    }
}

private final class SurfaceValidationHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    private let workouts: [HealthKitWorkout]

    init(workouts: [HealthKitWorkout]) {
        self.workouts = workouts
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        Array(workouts.prefix(max(limit, 1)))
    }
}

private final class SurfaceValidationHealthKitWorkoutLookupProvider: HealthKitWorkoutLookingUp {
    private let workout: HKWorkout?

    init(workout: HKWorkout?) {
        self.workout = workout
    }

    func lookupWorkout(externalId: String) async -> HKWorkout? {
        workout
    }
}

private final class SurfaceValidationHealthKitWorkoutRouteFetcher: HealthKitWorkoutRouteFetching {
    private let route: WorkoutRoute?

    init(route: WorkoutRoute?) {
        self.route = route
    }

    func fetchRoute(for workout: HKWorkout) async throws -> WorkoutRoute? {
        route
    }
}

private final class SurfaceValidationUnifiedWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout] = []
    private var existingWorkouts: [UnifiedWorkout]

    init(existingWorkouts: [UnifiedWorkout] = []) {
        self.existingWorkouts = existingWorkouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try await saveWorkouts([workout])
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            if let index = savedWorkouts.firstIndex(where: { $0.externalId == workout.externalId && $0.source == workout.source }) {
                savedWorkouts[index] = workout
            } else {
                savedWorkouts.append(workout)
            }
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        existingWorkouts + savedWorkouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        (existingWorkouts + savedWorkouts).first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        (existingWorkouts + savedWorkouts).first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
        existingWorkouts.removeAll { $0.id == id }
    }
}

private final class SurfaceValidationWorkoutRouteStore: WorkoutRoutePersistenceStoring {
    private var routesByWorkoutID: [UUID: WorkoutRoute] = [:]

    func saveRoute(_ route: WorkoutRoute) async throws {
        routesByWorkoutID[route.workoutId] = route
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        routesByWorkoutID[workoutId]
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        workoutIds.compactMap { routesByWorkoutID[$0] }
    }

    func deleteRoute(workoutId: UUID) async throws {
        routesByWorkoutID.removeValue(forKey: workoutId)
    }
}

private func makeHealthKitWorkout(
    id: UUID,
    type: HealthKitWorkoutType,
    startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
    duration: TimeInterval = 3_600,
    distance: Double? = 10_000,
    calories: Double? = 500,
    averageHeartRate: Double? = nil
) -> HealthKitWorkout {
    HealthKitWorkout(
        id: id,
        workoutType: type,
        startDate: startDate,
        endDate: startDate.addingTimeInterval(duration),
        duration: duration,
        distance: distance,
        averageHeartRate: averageHeartRate,
        calories: calories
    )
}

private func makeUnifiedWorkout(
    id: UUID = UUID(),
    source: UnifiedDataSource,
    type: UnifiedWorkoutType,
    startDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
    duration: TimeInterval = 3_600,
    distance: Double? = 10_000
) -> UnifiedWorkout {
    UnifiedWorkout(
        id: id,
        externalId: source == .appleHealthKit ? id.uuidString : nil,
        source: source,
        workoutType: type,
        startDate: startDate,
        endDate: startDate.addingTimeInterval(duration),
        durationSeconds: duration,
        distanceMeters: distance,
        activeEnergyKcal: 500,
        averageHeartRate: nil,
        maxHeartRate: nil,
        averageSpeedMetersPerSecond: nil,
        elevationGainMeters: nil,
        dataQuality: .partial,
        createdAt: startDate,
        updatedAt: startDate
    )
}

private func makeRoute(
    workoutId: UUID,
    distance: Double = 10_000,
    elevationGain: Double? = 80
) -> WorkoutRoute {
    WorkoutRoute(
        workoutId: workoutId,
        source: .appleHealthKit,
        coordinates: [
            WorkoutRouteCoordinate(latitude: 37.500, longitude: 127.000),
            WorkoutRouteCoordinate(latitude: 37.505, longitude: 127.005)
        ],
        totalDistanceMeters: distance,
        totalElevationGain: elevationGain,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

private func makeHKWorkout() -> HKWorkout {
    HKWorkout(
        activityType: .cycling,
        start: Date(timeIntervalSince1970: 1_800_000_000),
        end: Date(timeIntervalSince1970: 1_800_003_600),
        duration: 3_600,
        totalEnergyBurned: nil,
        totalDistance: nil,
        metadata: nil
    )
}

private extension Array where Element == ProcessedWorkout {
    init(uniqueByID workouts: [ProcessedWorkout]) {
        var seen = Set<UUID>()
        self = workouts.filter { seen.insert($0.id).inserted }
    }
}
