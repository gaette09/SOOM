import XCTest
@testable import SOOM

final class FITRouteAttachmentServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_010_000)

    func testAttachesValidFITToHealthKitImportedNoRouteWorkout() async throws {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeFITWorkoutStore(workouts: [workout])
        let routeStore = FakeFITRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, fitData: validFITData())

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(attachment.workout.id, workout.id)
        XCTAssertEqual(attachment.workout.routeMissingReason, .none)
        XCTAssertEqual(attachment.route.workoutId, workout.id)
        XCTAssertEqual(attachment.route.source, .appleHealthKit)
        XCTAssertEqual(attachment.route.coordinates.count, 3)
        XCTAssertGreaterThan(attachment.route.totalDistanceMeters, 0)
        XCTAssertEqual(attachment.summary.workoutType, .cycling)
        XCTAssertEqual(routeStore.savedRoutes.map(\.workoutId), [workout.id])
        XCTAssertEqual(workoutStore.savedWorkouts.last?.routeMissingReason, WorkoutRouteMissingReason.none)
    }

    func testRouteIsPersistedWithExistingWorkoutId() async throws {
        let workoutID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let workout = makeWorkout(id: workoutID, routeMissingReason: .externalSourceRouteNotShared)
        let routeStore = FakeFITRouteStore()
        let service = makeService(
            workoutStore: FakeFITWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workoutID, fitData: validFITData())

        _ = try unwrapSuccess(result)
        XCTAssertEqual(routeStore.savedRoutes.first?.workoutId, workoutID)
    }

    func testInvalidFITDoesNotModifyWorkoutOrPersistRoute() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeFITWorkoutStore(workouts: [workout])
        let routeStore = FakeFITRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, fitData: Data())

        XCTAssertEqual(result.failureValue, .invalidFIT(.emptyData))
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
    }

    func testAlreadyRouteBackedWorkoutIsNotReplacedByDefault() async {
        let workout = makeWorkout(routeMissingReason: .none)
        let existingRoute = makeRoute(workoutId: workout.id, latitudeOffset: 0)
        let routeStore = FakeFITRouteStore(routes: [existingRoute])
        let service = makeService(
            workoutStore: FakeFITWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workout.id, fitData: validFITData())

        XCTAssertEqual(result.failureValue, .alreadyHasRoute)
        XCTAssertEqual(routeStore.savedRoutes, [existingRoute])
    }

    func testExplicitReplacementCanReplaceExistingRoute() async throws {
        let workout = makeWorkout(routeMissingReason: .none)
        let existingRoute = makeRoute(workoutId: workout.id, latitudeOffset: 0)
        let routeStore = FakeFITRouteStore(routes: [existingRoute])
        let service = makeService(
            workoutStore: FakeFITWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(
            to: workout.id,
            fitData: validFITData(),
            replacingExistingRoute: true
        )

        let attachment = try unwrapSuccess(result)
        XCTAssertEqual(routeStore.savedRoutes.count, 1)
        XCTAssertEqual(routeStore.savedRoutes[0], attachment.route)
        XCTAssertNotEqual(routeStore.savedRoutes[0].coordinates, existingRoute.coordinates)
    }

    func testPersistenceFailurePreservesWorkoutSummaryAndReportsError() async {
        let workout = makeWorkout(routeMissingReason: .healthKitRouteUnavailable)
        let workoutStore = FakeFITWorkoutStore(workouts: [workout])
        let routeStore = FakeFITRouteStore(saveError: FITAttachmentSampleError.storeFailed)
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, fitData: validFITData())

        XCTAssertEqual(result.failureValue, .persistenceFailed)
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts.count, 1)
        XCTAssertEqual(workoutStore.savedWorkouts[0].id, workout.id)
        XCTAssertEqual(workoutStore.savedWorkouts[0].routeMissingReason, .routePersistenceFailed)
    }

    func testProcessedWorkoutBuilderCanConsumeAttachedRoute() async throws {
        let workout = makeWorkout(distanceMeters: nil, routeMissingReason: .healthKitRouteUnavailable)
        let routeStore = FakeFITRouteStore()
        let service = makeService(
            workoutStore: FakeFITWorkoutStore(workouts: [workout]),
            routeStore: routeStore
        )

        let result = await service.attachRoute(to: workout.id, fitData: validFITData())
        let attachment = try unwrapSuccess(result)
        let processed = ProcessedWorkoutBuilder().make(from: attachment.workout, route: attachment.route)

        XCTAssertTrue(processed.hasRoute)
        XCTAssertEqual(processed.routeMissingReason, .none)
        XCTAssertEqual(processed.metricAvailability[.route], .measured)
        XCTAssertEqual(processed.metricAvailability[.distance], .derived)
        XCTAssertGreaterThan(processed.distanceMeters ?? 0, 0)
    }

    func testLocalRecordWorkoutIsNotChanged() async {
        let workout = makeWorkout(source: .soomLocal, routeMissingReason: .none)
        let workoutStore = FakeFITWorkoutStore(workouts: [workout])
        let routeStore = FakeFITRouteStore()
        let service = makeService(workoutStore: workoutStore, routeStore: routeStore)

        let result = await service.attachRoute(to: workout.id, fitData: validFITData())

        XCTAssertEqual(result.failureValue, .unsupportedSource(.soomLocal))
        XCTAssertTrue(routeStore.savedRoutes.isEmpty)
        XCTAssertEqual(workoutStore.savedWorkouts, [workout])
    }

    func testMissingWorkoutReturnsWorkoutNotFound() async {
        let workoutID = UUID()
        let service = makeService(
            workoutStore: FakeFITWorkoutStore(workouts: []),
            routeStore: FakeFITRouteStore()
        )

        let result = await service.attachRoute(to: workoutID, fitData: validFITData())

        XCTAssertEqual(result.failureValue, .workoutNotFound(workoutID))
    }

    private func makeService(
        workoutStore: FakeFITWorkoutStore,
        routeStore: FakeFITRouteStore
    ) -> FITRouteAttachmentService {
        FITRouteAttachmentService(
            workoutStore: workoutStore,
            routeStore: routeStore,
            dateProvider: { self.now }
        )
    }

    private func makeWorkout(
        id: UUID = UUID(),
        source: UnifiedDataSource = .appleHealthKit,
        distanceMeters: Double? = 10_000,
        routeMissingReason: WorkoutRouteMissingReason
    ) -> UnifiedWorkout {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(
            id: id,
            externalId: id.uuidString,
            source: source,
            workoutType: .cycling,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 520,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            routeMissingReason: routeMissingReason,
            dataQuality: .partial,
            createdAt: start,
            updatedAt: start
        )
    }

    private func validFITData() -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return FITAttachmentTestFileBuilder()
            .addRecordDefinition()
            .addRecord(
                timestamp: startedAt,
                latitude: 37.5000,
                longitude: 127.0000,
                altitudeMeters: 10,
                distanceMeters: 0
            )
            .addRecord(
                timestamp: startedAt.addingTimeInterval(60),
                latitude: 37.5010,
                longitude: 127.0010,
                altitudeMeters: 20,
                distanceMeters: 160
            )
            .addRecord(
                timestamp: startedAt.addingTimeInterval(120),
                latitude: 37.5020,
                longitude: 127.0020,
                altitudeMeters: 18,
                distanceMeters: 320
            )
            .addSessionDefinition()
            .addSession(
                sport: 2,
                startTime: startedAt,
                elapsedSeconds: 120,
                distanceMeters: 320,
                calories: 80,
                totalAscentMeters: 10
            )
            .makeData()
    }

    private func makeRoute(workoutId: UUID, latitudeOffset: Double) -> WorkoutRoute {
        WorkoutRoute(
            workoutId: workoutId,
            source: .appleHealthKit,
            coordinates: [
                WorkoutRouteCoordinate(latitude: 37.0 + latitudeOffset, longitude: 127.0),
                WorkoutRouteCoordinate(latitude: 37.1 + latitudeOffset, longitude: 127.1)
            ],
            totalDistanceMeters: 1_000,
            createdAt: now
        )
    }

    private func unwrapSuccess(
        _ result: Result<FITRouteAttachmentResult, FITRouteAttachmentError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FITRouteAttachmentResult {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Expected success, got \(error)", file: file, line: line)
            throw error
        }
    }
}

private final class FakeFITWorkoutStore: UnifiedWorkoutStore {
    private(set) var savedWorkouts: [UnifiedWorkout]

    init(workouts: [UnifiedWorkout]) {
        self.savedWorkouts = workouts
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        try await saveWorkouts([workout])
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        for workout in workouts {
            if let index = savedWorkouts.firstIndex(where: { $0.id == workout.id }) {
                savedWorkouts[index] = workout
            } else {
                savedWorkouts.append(workout)
            }
        }
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        savedWorkouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.id == id }
    }

    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? {
        savedWorkouts.first { $0.externalId == externalId && $0.source == source }
    }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}

    func deleteWorkout(id: UUID) async throws {
        savedWorkouts.removeAll { $0.id == id }
    }
}

private final class FakeFITRouteStore: WorkoutRoutePersistenceStoring {
    private(set) var savedRoutes: [WorkoutRoute]
    private let saveError: Error?

    init(routes: [WorkoutRoute] = [], saveError: Error? = nil) {
        self.savedRoutes = routes
        self.saveError = saveError
    }

    func saveRoute(_ route: WorkoutRoute) async throws {
        if let saveError {
            throw saveError
        }

        if let index = savedRoutes.firstIndex(where: { $0.workoutId == route.workoutId }) {
            savedRoutes[index] = route
        } else {
            savedRoutes.append(route)
        }
    }

    func fetchRoute(workoutId: UUID) async throws -> WorkoutRoute? {
        savedRoutes.first { $0.workoutId == workoutId }
    }

    func fetchRoutes(workoutIds: [UUID]) async throws -> [WorkoutRoute] {
        savedRoutes.filter { workoutIds.contains($0.workoutId) }
    }

    func deleteRoute(workoutId: UUID) async throws {
        savedRoutes.removeAll { $0.workoutId == workoutId }
    }
}

private enum FITAttachmentSampleError: Error {
    case storeFailed
}

private extension Result where Success == FITRouteAttachmentResult, Failure == FITRouteAttachmentError {
    var failureValue: FITRouteAttachmentError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}

private struct FITAttachmentTestFileBuilder {
    private var records = Data()

    func addRecordDefinition() -> FITAttachmentTestFileBuilder {
        var copy = self
        copy.records.append(0x40)
        copy.records.append(0x00)
        copy.records.append(0x00)
        copy.records.appendUInt16(20)
        copy.records.append(6)
        copy.appendField(number: 253, size: 4, baseType: 0x86)
        copy.appendField(number: 0, size: 4, baseType: 0x85)
        copy.appendField(number: 1, size: 4, baseType: 0x85)
        copy.appendField(number: 2, size: 2, baseType: 0x84)
        copy.appendField(number: 5, size: 4, baseType: 0x86)
        copy.appendField(number: 7, size: 2, baseType: 0x84)
        return copy
    }

    func addRecord(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double,
        distanceMeters: Double
    ) -> FITAttachmentTestFileBuilder {
        var copy = self
        copy.records.append(0x00)
        copy.records.appendUInt32(fitAttachmentTimestamp(timestamp))
        copy.records.appendInt32(fitAttachmentSemicircles(latitude))
        copy.records.appendInt32(fitAttachmentSemicircles(longitude))
        copy.records.appendUInt16(fitAttachmentEncodedAltitude(altitudeMeters))
        copy.records.appendUInt32(UInt32((distanceMeters * 100).rounded()))
        copy.records.appendUInt16(UInt16.max)
        return copy
    }

    func addSessionDefinition() -> FITAttachmentTestFileBuilder {
        var copy = self
        copy.records.append(0x41)
        copy.records.append(0x00)
        copy.records.append(0x00)
        copy.records.appendUInt16(18)
        copy.records.append(6)
        copy.appendField(number: 5, size: 1, baseType: 0x02)
        copy.appendField(number: 2, size: 4, baseType: 0x86)
        copy.appendField(number: 7, size: 4, baseType: 0x86)
        copy.appendField(number: 9, size: 4, baseType: 0x86)
        copy.appendField(number: 11, size: 2, baseType: 0x84)
        copy.appendField(number: 21, size: 2, baseType: 0x84)
        return copy
    }

    func addSession(
        sport: UInt8,
        startTime: Date,
        elapsedSeconds: Double,
        distanceMeters: Double,
        calories: UInt16,
        totalAscentMeters: UInt16
    ) -> FITAttachmentTestFileBuilder {
        var copy = self
        copy.records.append(0x01)
        copy.records.append(sport)
        copy.records.appendUInt32(fitAttachmentTimestamp(startTime))
        copy.records.appendUInt32(UInt32((elapsedSeconds * 1_000).rounded()))
        copy.records.appendUInt32(UInt32((distanceMeters * 100).rounded()))
        copy.records.appendUInt16(calories)
        copy.records.appendUInt16(totalAscentMeters)
        return copy
    }

    func makeData() -> Data {
        var data = Data()
        data.append(14)
        data.append(16)
        data.appendUInt16(0)
        data.appendUInt32(UInt32(records.count))
        data.append(contentsOf: ".FIT".utf8)
        data.appendUInt16(0)
        data.append(records)
        data.appendUInt16(0)
        return data
    }

    private mutating func appendField(number: UInt8, size: UInt8, baseType: UInt8) {
        records.append(number)
        records.append(size)
        records.append(baseType)
    }
}

private func fitAttachmentSemicircles(_ degrees: Double) -> Int32 {
    Int32((degrees * 2_147_483_648.0 / 180.0).rounded())
}

private func fitAttachmentEncodedAltitude(_ meters: Double) -> UInt16 {
    UInt16(((meters + 500) * 5).rounded())
}

private func fitAttachmentTimestamp(_ date: Date) -> UInt32 {
    UInt32(date.timeIntervalSince1970 - 631_065_600)
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendInt32(_ value: Int32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<Int32>.size))
    }
}
