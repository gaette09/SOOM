import SwiftUI
import UIKit
import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutStoreTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testSaveWorkoutThenFetchRecentWorkouts() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            source: .garmin,
            type: .cycling,
            startDate: referenceDate.addingTimeInterval(-86_400)
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, workout.id)
        XCTAssertEqual(fetched.first?.source, .garmin)
        XCTAssertEqual(fetched.first?.workoutType, .cycling)
    }

    func testAveragePowerAndCadenceRoundTripThroughPersistence() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            source: .appleHealthKit,
            type: .cycling,
            startDate: referenceDate.addingTimeInterval(-3_600),
            averagePowerWatts: 93,
            averageCadence: 87
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.first?.averagePowerWatts, 93)
        XCTAssertEqual(fetched.first?.averageCadence, 87)
    }

    func testExternalIdAndSourceUpsertsExistingWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let externalId = "garmin-ride-001"
        let first = makeWorkout(
            id: UUID(),
            externalId: externalId,
            source: .garmin,
            type: .cycling,
            startDate: referenceDate,
            distanceMeters: 40_000
        )
        let updated = makeWorkout(
            id: UUID(),
            externalId: externalId,
            source: .garmin,
            type: .cycling,
            startDate: referenceDate,
            distanceMeters: 42_000
        )

        try await fixture.store.saveWorkout(first)
        try await fixture.store.saveWorkout(updated)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, first.id)
        XCTAssertEqual(fetched.first?.distanceMeters, 42_000)
    }

    func testIdBasedUpsertWhenExternalIdIsMissing() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let id = UUID()
        let first = makeWorkout(
            id: id,
            externalId: nil,
            source: .soomLocal,
            type: .running,
            startDate: referenceDate,
            distanceMeters: 5_000
        )
        let updated = makeWorkout(
            id: id,
            externalId: nil,
            source: .soomLocal,
            type: .running,
            startDate: referenceDate,
            distanceMeters: 6_200
        )

        try await fixture.store.saveWorkout(first)
        try await fixture.store.saveWorkout(updated)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, id)
        XCTAssertEqual(fetched.first?.distanceMeters, 6_200)
    }

    func testFetchByExternalIdAndSourceReturnsMatchingWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            externalId: "apple-run-001",
            source: .appleHealthKit,
            type: .running,
            startDate: referenceDate
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchByExternalId("apple-run-001", source: .appleHealthKit)

        XCTAssertEqual(fetched?.id, workout.id)
        XCTAssertEqual(fetched?.source, .appleHealthKit)
    }

    func testMarkExcludedFromAnalysisUpdatesStoredRecord() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(startDate: referenceDate)

        try await fixture.store.saveWorkout(workout)
        try await fixture.store.markExcludedFromAnalysis(id: workout.id, isExcluded: true)
        let record = try fetchRecord(id: workout.id, context: fixture.container.mainContext)

        XCTAssertEqual(record?.isExcludedFromAnalysis, true)
    }

    func testDeleteWorkoutRemovesStoredWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let deleted = makeWorkout(startDate: referenceDate)
        let remaining = makeWorkout(startDate: referenceDate.addingTimeInterval(-86_400))

        try await fixture.store.saveWorkouts([deleted, remaining])
        try await fixture.store.deleteWorkout(id: deleted.id)
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.map(\.id), [remaining.id])
    }

    func testDeleteAllWorkoutsRemovesEveryStoredWorkout() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let first = makeWorkout(startDate: referenceDate)
        let second = makeWorkout(startDate: referenceDate.addingTimeInterval(-86_400))

        try await fixture.store.saveWorkouts([first, second])
        try await fixture.store.deleteAllWorkouts()
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 30)

        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchRecentWorkoutsFiltersByDays() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let recent = makeWorkout(startDate: referenceDate.addingTimeInterval(-2 * 86_400))
        let old = makeWorkout(startDate: referenceDate.addingTimeInterval(-10 * 86_400))

        try await fixture.store.saveWorkouts([recent, old])
        let fetched = try await fixture.store.fetchRecentWorkouts(days: 7)

        XCTAssertEqual(fetched.map(\.id), [recent.id])
    }

    func testEnumRawValuesRoundTripThroughPersistence() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(referenceDate: referenceDate)
        let workout = makeWorkout(
            source: .samsungHealth,
            type: .swimming,
            startDate: referenceDate,
            dataQuality: .estimated
        )

        try await fixture.store.saveWorkout(workout)
        let fetched = try await fixture.store.fetchWorkout(id: workout.id)

        XCTAssertEqual(fetched?.source, .samsungHealth)
        XCTAssertEqual(fetched?.workoutType, .swimming)
        XCTAssertEqual(fetched?.dataQuality, .estimated)
    }

    private func makeFixture(referenceDate: Date) throws -> (
        store: SwiftDataUnifiedWorkoutStore,
        container: ModelContainer
    ) {
        let schema = Schema([UnifiedWorkoutRecord.self])
        let configuration = ModelConfiguration(
            "UnifiedWorkoutStoreTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        retainedContainers.append(container)

        return (
            SwiftDataUnifiedWorkoutStore(
                modelContext: container.mainContext,
                referenceDate: { referenceDate }
            ),
            container
        )
    }

    private func fetchRecord(id: UUID, context: ModelContext) throws -> UnifiedWorkoutRecord? {
        let workoutID = id
        var descriptor = FetchDescriptor<UnifiedWorkoutRecord>(
            predicate: #Predicate { record in
                record.id == workoutID
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    private func makeWorkout(
        id: UUID = UUID(),
        externalId: String? = UUID().uuidString,
        source: UnifiedDataSource = .appleHealthKit,
        type: UnifiedWorkoutType = .running,
        startDate: Date,
        durationSeconds: TimeInterval = 3_600,
        distanceMeters: Double? = 10_000,
        averagePowerWatts: Double? = nil,
        averageCadence: Double? = nil,
        dataQuality: UnifiedDataQuality = .partial
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: id,
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: 148,
            maxHeartRate: 174,
            averageSpeedMetersPerSecond: 2.8,
            elevationGainMeters: 72,
            averagePowerWatts: averagePowerWatts,
            averageCadence: averageCadence,
            dataQuality: dataQuality,
            createdAt: startDate,
            updatedAt: startDate.addingTimeInterval(durationSeconds)
        )
    }
}


extension UnifiedWorkoutStoreTests {
    func testR2DiskStoreCardPathPerformance() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("R2-disk-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Keep this synthetic SQLite directory until the simulator removes its temp files.
        // SwiftData and cancelled view tasks can outlive the test stack frame.
        let schema = HealthAccountStorageController.schema
        let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("fixture.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config]); retainedContainers.append(container)
        let context = container.mainContext
        var workouts: [UnifiedWorkout] = [], routes: [WorkoutRoute] = []
        let now = Date()
        for index in 0..<12 {
            var workout = makeWorkout(source: .soomLocal, startDate: now.addingTimeInterval(-Double(index + 1) * 86400), durationSeconds: 1800)
            workout.locationName = "Synthetic local fixture"
            let coordinates = (0..<1800).map { i in WorkoutRouteCoordinate(latitude: 35 + Double(i) * 0.00002,
                longitude: 128 + sin(Double(i) / 100) * 0.001, timestamp: workout.startDate.addingTimeInterval(Double(i))) }
            let route = WorkoutRoute(workoutId: workout.id, source: .soomLocal, coordinates: coordinates, totalDistanceMeters: 10000)
            context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: workout))
            context.insert(WorkoutRouteMapper().makeRecord(from: route))
            workouts.append(workout); routes.append(route)
        }
        try context.save()
        XCTAssertFalse(config.isStoredInMemoryOnly)
        WorkoutCardPerformanceProbe.start(); defer { WorkoutCardPerformanceProbe.stop() }
        let beat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime, gap = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
                let next = ProcessInfo.processInfo.systemUptime; gap = max(gap, (next - previous) * 1000); previous = next
            }
            return gap
        }
        await Task.yield()
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<2 { for i in 0..<3 {
            _ = await WorkoutCardAchievementLoader.load(workout: workouts[i], route: routes[i], context: context)
        } }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        try? await Task.sleep(for: .milliseconds(5)); beat.cancel(); let gap = await beat.value
        print("SOOM_R2_DISK elapsed_ms=\(elapsed) main_gap_ms=\(gap) counts=\(WorkoutCardPerformanceProbe.counts)")
        let storage = try HealthAccountStorageController(baseDirectory: folder, guestContainer: container,
            monitorNetwork: false, automaticallySync: false)
        let suite = "R2-auth-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults))
        WorkoutCardPerformanceProbe.start()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIHostingController(rootView: AnyView(EmptyView())); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let viewStart = ProcessInfo.processInfo.systemUptime
        for tick in 0..<3 {
            var value = workouts[0]; value.userTitle = "Synthetic render \(tick)"
            host.rootView = AnyView(ScrollView { ActivityWorkoutRow(workout: value) }
                .environmentObject(auth).environmentObject(storage).modelContainer(container))
            host.view.frame = window.bounds; window.layoutIfNeeded(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
        print("SOOM_R2_CARD elapsed_including_240ms_wait=\((ProcessInfo.processInfo.systemUptime-viewStart)*1000) counts=\(WorkoutCardPerformanceProbe.counts)")
        for index in 12..<180 {
            var value = makeWorkout(source: .soomLocal, startDate: now.addingTimeInterval(-Double(index + 1)*86400))
            value.locationName = "Synthetic local fixture"
            context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: value))
        }
        try context.save()
        func drain() async throws {
            for _ in 0..<500 {
                if (WorkoutCardPerformanceProbe.counts["activeAchievements"] ?? 0) == 0 { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("Synthetic card tasks did not finish")
        }
        try await drain()
        for surface in ["profile", "calendar", "profile"] {
            host.rootView = AnyView(EmptyView()); try await Task.sleep(for: .milliseconds(30)); try await drain()
            WorkoutCardPerformanceProbe.start()
            let started = ProcessInfo.processInfo.systemUptime
            if surface == "profile" {
                host.rootView = AnyView(ProfileIdentityView(initialSection: .activities).environmentObject(auth).environmentObject(storage).modelContainer(container))
            } else {
                host.rootView = AnyView(ActivityCalendarView().environmentObject(auth).environmentObject(storage).modelContainer(container))
            }
            window.layoutIfNeeded(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            try await drain()
            print("SOOM_R2_SURFACE name=\(surface) elapsed_including_400ms_wait=\((ProcessInfo.processInfo.systemUptime-started)*1000) counts=\(WorkoutCardPerformanceProbe.counts)")
        }
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "R2 synthetic real disk profile activity cards local map fallback"; attachment.lifetime = .keepAlways; add(attachment)
        host.rootView = AnyView(EmptyView()); try await Task.sleep(for: .milliseconds(50)); try await drain()
    }
}


extension UnifiedWorkoutStoreTests {
    func testR2RouteProjectionChecksContentsScopeDeletionAndBudget() async throws {
        let first = try makeFixture(referenceDate: Date()), second = try makeFixture(referenceDate: Date())
        let mapper = WorkoutRouteMapper(), id = UUID()
        let points = [WorkoutRouteCoordinate(latitude: 35, longitude: 128), WorkoutRouteCoordinate(latitude: 35.02, longitude: 128.02)]
        let record = mapper.makeRecord(from: WorkoutRoute(workoutId: id, source: .soomLocal, coordinates: points, totalDistanceMeters: 3000))
        let cache = WorkoutCardRouteProjection()
        WorkoutCardPerformanceProbe.start(); defer { WorkoutCardPerformanceProbe.stop() }
        XCTAssertEqual(cache.route(record, context: first.container.mainContext)?.coordinates, points)
        _ = cache.route(record, context: first.container.mainContext)
        XCTAssertEqual(WorkoutCardPerformanceProbe.counts["routeDecode"], 1)
        let changed = [WorkoutRouteCoordinate(latitude: 36, longitude: 129), WorkoutRouteCoordinate(latitude: 36.02, longitude: 129.02)]
        let unchangedTime = record.updatedAt
        record.encodedCoordinates = mapper.encodeCoordinates(changed)
        XCTAssertEqual(cache.route(record, context: first.container.mainContext)?.coordinates, changed)
        XCTAssertEqual(record.updatedAt, unchangedTime)
        XCTAssertEqual(WorkoutCardPerformanceProbe.counts["routeDecode"], 2)
        _ = cache.route(record, context: second.container.mainContext)
        XCTAssertEqual(WorkoutCardPerformanceProbe.counts["routeDecode"], 3, "Same UUID in another container cannot hit this cache")
        XCTAssertNil(cache.route(nil, context: second.container.mainContext))
        _ = cache.route(record, context: second.container.mainContext)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(cache.retainedPointCount, 0)
        let huge = Array(repeating: points[0], count: 10_001)
        record.encodedCoordinates = mapper.encodeCoordinates(huge)
        XCTAssertEqual(cache.route(record, context: first.container.mainContext)?.coordinates.count, 10_001)
        XCTAssertEqual(cache.retainedPointCount, 0)
        let before = WorkoutCardPerformanceProbe.counts["routeDecode", default: 0]
        _ = cache.route(record, context: first.container.mainContext)
        XCTAssertEqual(WorkoutCardPerformanceProbe.counts["routeDecode"], before + 1)
        let route = WorkoutRoute(workoutId: id, source: .soomLocal, coordinates: huge, totalDistanceMeters: 3000)
        XCTAssertEqual(cache.preview(route), RoutePrivacyMasker().mask(route: route))
        XCTAssertEqual(cache.retainedPointCount, 0, "Oversized input remains exact without cache retention")
    }

    func testR2AliasRouteAndAsyncAchievementsMatchExistingHistory() async throws {
        let schema = HealthAccountStorageController.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        retainedContainers.append(container)
        let context = container.mainContext, now = Date(), mapper = WorkoutRouteMapper()
        var target = makeWorkout(source: .soomLocal, startDate: now.addingTimeInterval(-3600), durationSeconds: 1800)
        target.preferredWorkoutID = target.id
        var sibling = makeWorkout(source: .strava, startDate: target.startDate, durationSeconds: 1800)
        sibling.preferredWorkoutID = target.id
        for workout in [target, sibling] { context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: workout)) }
        let points = (0..<900).map { i in WorkoutRouteCoordinate(latitude: 35 + Double(i)*0.00003, longitude: 128,
            timestamp: target.startDate.addingTimeInterval(Double(i)*2)) }
        context.insert(mapper.makeRecord(from: WorkoutRoute(workoutId: sibling.id, source: .strava, coordinates: points, totalDistanceMeters: 4000)))
        for index in 1...5 {
            let old = makeWorkout(source: .soomLocal, startDate: target.startDate.addingTimeInterval(-Double(index)*86400), durationSeconds: 1800)
            context.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from: old))
            let coordinates = points.enumerated().map { i, point in WorkoutRouteCoordinate(latitude: 35 + Double(i)*0.00002,
                longitude: point.longitude, timestamp: old.startDate.addingTimeInterval(Double(i)*2)) }
            context.insert(mapper.makeRecord(from: WorkoutRoute(workoutId: old.id, source: .soomLocal, coordinates: coordinates, totalDistanceMeters: 3000)))
        }
        try context.save()
        let resolved = try await WorkoutTelemetryStore(modelContext: context).resolvedRoute(for: target)
        let route = try XCTUnwrap(resolved)
        XCTAssertEqual(route.workoutId, target.id); XCTAssertEqual(route.coordinates, points)
        let provider = SwiftDataWorkoutAchievementHistoryProvider(workoutStore: SwiftDataUnifiedWorkoutStore(modelContext: context),
            routeStore: SwiftDataWorkoutRoutePersistenceStore(modelContext: context))
        let history = await provider.recentBestEfforts(excluding: target.id, workoutType: target.workoutType, before: target.startDate, lookbackMonths: WorkoutAchievementConfig.lookbackMonths)
        let expected = WorkoutAchievementBuilder.build(todayEfforts: WorkoutSegmentBestEffortFinder.bestEfforts(from: route), historicalEffortsByDuration: history, workoutType: target.workoutType).markers
        let actual = await WorkoutCardAchievementLoader.load(workout: target, route: route, context: context)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(actual.map(\.durationMinutes), expected.map(\.durationMinutes))
        XCTAssertEqual(actual.map(\.rank), expected.map(\.rank)); XCTAssertEqual(actual.map(\.valueText), expected.map(\.valueText))
        XCTAssertEqual(actual.map(\.coordinate), expected.map(\.coordinate))
        let cancelled = Task { await WorkoutCardAchievementLoader.load(workout: target, route: route, context: context) }
        cancelled.cancel(); let dropped = await cancelled.value; XCTAssertTrue(dropped.isEmpty)
    }
}
