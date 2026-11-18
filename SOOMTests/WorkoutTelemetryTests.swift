import SwiftData
import XCTest
@testable import SOOM

@MainActor
final class WorkoutTelemetryTests: XCTestCase {
    func testSyntheticPresentationPreparationBenchmark() throws {
        let workout = workout(source: .appleHealthKit)
        let span = workout.endDate.timeIntervalSince(workout.startDate)
        let samples = (0..<5_000).map { index in
            WorkoutTelemetrySample(timestamp: workout.startDate.addingTimeInterval(span * Double(index) / 5_000),
                heartRateBPM: 120 + 25 * sin(Double(index) / 90), speedMetersPerSecond: 3.2)
        }
        let telemetry = WorkoutTelemetry(workoutID: workout.id, source: .appleHealthKit, samples: samples)
        let cache = WorkoutTelemetryPresentationCache()
        let start = ProcessInfo.processInfo.systemUptime
        _ = cache.prepare(telemetry, workout: workout, route: nil)
        let first = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        let warm = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { _ = cache.prepare(telemetry, workout: workout, route: nil) }
        let warmAverage = (ProcessInfo.processInfo.systemUptime - warm) * 10
        XCTAssertEqual(cache.preparationCount, 1)
        let result: [String: Any] = ["fixture": true, "samples": 5000, "cachedUpdates": 100,
            "firstPreparationMilliseconds": first, "cachedUpdateAverageMilliseconds": warmAverage,
            "note": "Synthetic client preparation only; no live server or GPU timing"]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "detail-preparation-fixture-benchmark.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPresentationCacheReusesUnchangedDataAndInvalidatesSameCountMeasurementEdit() {
        let workout = workout(source: .appleHealthKit)
        var telemetry = WorkoutTelemetry(workoutID: workout.id, source: .appleHealthKit,
            samples: [.init(timestamp: workout.startDate, heartRateBPM: 100),
                      .init(timestamp: workout.startDate.addingTimeInterval(10), heartRateBPM: 140)])
        let cache = WorkoutTelemetryPresentationCache()
        let first = cache.prepare(telemetry, workout: workout, route: nil)
        for _ in 0..<30 { XCTAssertEqual(cache.prepare(telemetry, workout: workout, route: nil), first) }
        XCTAssertEqual(cache.preparationCount, 1)
        telemetry.samples[1].heartRateBPM = 160
        let second = cache.prepare(telemetry, workout: workout, route: nil)
        XCTAssertEqual(cache.preparationCount, 2)
        XCTAssertEqual(second.samples[1].heartRateBPM, 160)
        XCTAssertEqual(cache.channels[.heartRate]?.map(\.value), [100, 160])
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testStepIntervalsProduceDerivedSPMButSummaryDoesNotInventCadence() {
        let id = UUID()
        let intervals = WorkoutTelemetry(workoutID: id, source: .appleHealthKit, intervals: [
            .init(kind: .steps, startDate: start, endDate: start.addingTimeInterval(30), value: 80),
            .init(kind: .steps, startDate: start.addingTimeInterval(30), endDate: start.addingTimeInterval(60), value: 85)
        ])
        let display = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: intervals, route: nil)
        XCTAssertEqual(display.samples.compactMap(\.cadencePerMinute), [160, 170])
        XCTAssertEqual(display.samples.first?.cadenceUnit, .stepsPerMinute)
        let summaryOnly = WorkoutTelemetry(workoutID: id, source: .appleHealthKit,
            summaryMetrics: [.init(key: "cadence", label: "케이던스", value: 160, unit: "spm")])
        XCTAssertTrue(WorkoutTelemetryChartBuilder.addingDerivedChannels(to: summaryOnly, route: nil).samples.isEmpty)
    }

    func testHeartRateZonesDoNotCountUnobservedLongGaps() {
        let value = workout()
        let telemetry = WorkoutTelemetry(workoutID: value.id, source: .appleHealthKit, samples: [
            .init(timestamp: start, heartRateBPM: 100),
            .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 140),
            .init(timestamp: start.addingTimeInterval(400), heartRateBPM: 150),
            .init(timestamp: start.addingTimeInterval(410), heartRateBPM: 180)
        ])
        let zones = WorkoutTelemetryChartBuilder.heartRateZones(telemetry, workout: value, maximumHeartRate: 190)
        XCTAssertEqual(zones.reduce(0) { $0 + $1.durationSeconds }, 20)
        XCTAssertEqual(zones.first?.name, "Z1")
    }

    func testExplicitChoiceSurvivesPersistenceAndPreservesPrimaryHeartRateWhileAddingPower() async throws {
        let container = try ModelContainer(for: HealthAccountStorageController.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        var local = workout(source: .soomLocal)
        var watch = workout(source: .appleHealthKit)
        local.preferredWorkoutID = watch.id
        watch.preferredWorkoutID = watch.id
        try await store.saveWorkouts([local, watch])
        let telemetry = WorkoutTelemetryStore(modelContext: context)
        try telemetry.save(.init(workoutID: watch.id, source: .appleHealthKit, samples: [
            .init(timestamp: start, heartRateBPM: 140)
        ]))
        try telemetry.save(.init(workoutID: local.id, source: .soomLocal, samples: [
            .init(timestamp: start, heartRateBPM: 99, powerWatts: 220),
            .init(timestamp: start.addingTimeInterval(5), heartRateBPM: 98, powerWatts: 230)
        ]))
        let restored = try await store.fetchWorkout(id: watch.id)
        XCTAssertEqual(restored?.preferredWorkoutID, watch.id)
        let merged = try XCTUnwrap(telemetry.resolved(for: watch))
        XCTAssertEqual(merged.samples.compactMap(\.heartRateBPM), [140])
        XCTAssertEqual(merged.samples.compactMap(\.powerWatts), [220, 230])
        let raw = try await store.fetchRecentWorkouts(days: 3_650)
        XCTAssertEqual(raw.count, 2)
    }

    func testUnconfirmedOverlapNeverBackfillsTelemetryOrGPS() async throws {
        let container = try ModelContainer(for: HealthAccountStorageController.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let local = workout(source: .soomLocal), watch = workout(source: .appleHealthKit)
        try await store.saveWorkouts([local, watch])
        let telemetry = WorkoutTelemetryStore(modelContext: context)
        try telemetry.save(.init(workoutID: watch.id, source: .appleHealthKit, samples: [
            .init(timestamp: start, heartRateBPM: 140)
        ]))
        XCTAssertNil(try telemetry.resolved(for: local))
        XCTAssertEqual(try telemetry.load(workoutID: watch.id)?.samples.compactMap(\.heartRateBPM), [140])
        let originals = try await store.fetchRecentWorkouts(days: 3650)
        XCTAssertEqual(originals.count, 2)
    }

    private func workout(id: UUID = UUID(), source: UnifiedDataSource = .googleHealth) -> UnifiedWorkout {
        UnifiedWorkout(id: id, externalId: nil, source: source, workoutType: .running,
            startDate: start, endDate: start.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: 2_000, activeEnergyKcal: nil, averageHeartRate: 140, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: start, updatedAt: start)
    }

    func testIndoorTCXPreservesActualSensorChannelsAndZeroValues() throws {
        let xml = """
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
        <Activities><Activity Sport="Running"><Id>2027-01-15T08:00:00Z</Id><Lap StartTime="2027-01-15T08:00:00Z">
        <TotalTimeSeconds>60</TotalTimeSeconds><DistanceMeters>100</DistanceMeters><Track>
        <Trackpoint><Time>2027-01-15T08:00:00Z</Time><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>123</Value></HeartRateBpm><Extensions><ns3:TPX><ns3:Watts>0</ns3:Watts><ns3:Speed>0</ns3:Speed><ns3:RunCadence>85</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
        <Trackpoint><Time>2027-01-15T08:01:00Z</Time><DistanceMeters>100</DistanceMeters><HeartRateBpm><Value>145</Value></HeartRateBpm><Extensions><ns3:TPX><ns3:Watts>212</ns3:Watts></ns3:TPX></Extensions></Trackpoint>
        </Track></Lap></Activity></Activities></TrainingCenterDatabase>
        """
        let parsed = try WorkoutTelemetryTCXParser().parse(data: Data(xml.utf8), workoutID: UUID(), source: .googleHealth)
        XCTAssertEqual(parsed.samples.count, 2)
        XCTAssertEqual(parsed.samples.map(\.heartRateBPM), [123, 145])
        XCTAssertEqual(parsed.samples.first?.cadencePerMinute, 170)
        XCTAssertEqual(parsed.samples.first?.cadenceUnit, .stepsPerMinute)
        XCTAssertEqual(parsed.samples.first?.powerWatts, 0)
        XCTAssertEqual(parsed.samples.first?.speedMetersPerSecond, 0)
        XCTAssertNil(parsed.samples.first?.elevationMeters)
        XCTAssertEqual(parsed.splits.first?.distanceMeters, 100)
        XCTAssertEqual(parsed.samples.first?.source, .googleHealth)
    }

    func testTCXPointDistancesDoNotOverwriteLapSummary() throws {
        let xml = """
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity Sport="Biking"><Lap StartTime="2027-01-15T08:00:00Z"><TotalTimeSeconds>100</TotalTimeSeconds><DistanceMeters>500</DistanceMeters><Track><Trackpoint><Time>2027-01-15T08:00:10Z</Time><DistanceMeters>40</DistanceMeters></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>
        """
        let parsed = try TCXRouteParser().parse(Data(xml.utf8), allowMissingRoute: true)
        XCTAssertEqual(parsed.summary.distanceMeters, 500)
    }

    func testSummaryAverageNeverCreatesSensorGraphOrZones() {
        let value = WorkoutTelemetry(workoutID: UUID(), source: .googleHealth,
            summaryMetrics: [.init(key: "avg_hr", label: "평균 심박", value: 145, unit: "bpm")])
        let derived = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: value, route: nil)
        XCTAssertTrue(WorkoutTelemetryChartBuilder.points(derived, channel: .heartRate, start: start).isEmpty)
        XCTAssertTrue(derived.heartRateZones.isEmpty)
        XCTAssertTrue(WorkoutTelemetryChartBuilder.derivedSplits(derived).isEmpty)
    }

    func testNoGPSHeartRateUsesRealTimeAxis() {
        let telemetry = WorkoutTelemetry(workoutID: UUID(), source: .googleHealth, samples: [
            .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 120),
            .init(timestamp: start.addingTimeInterval(20), heartRateBPM: 140)
        ])
        let points = WorkoutTelemetryChartBuilder.points(telemetry, channel: .heartRate, start: start)
        XCTAssertEqual(points.map(\.seconds), [10, 20])
        XCTAssertEqual(points.map(\.value), [120, 140])
    }

    func testSameSourceTimestampCoalescesChannelsAndIncomingNonNilValueWins() {
        let original = WorkoutTelemetry(workoutID: UUID(), source: .googleHealth, samples: [
            .init(timestamp: start, distanceMeters: 10, heartRateBPM: 120, powerWatts: 200, source: .googleHealth),
            .init(timestamp: start, heartRateBPM: 125, cadencePerMinute: 0),
            .init(timestamp: start.addingTimeInterval(1), heartRateBPM: 130)
        ])
        let result = original.coalescingSamples()
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertEqual(result.samples.first?.heartRateBPM, 125)
        XCTAssertEqual(result.samples.first?.powerWatts, 200)
        XCTAssertEqual(result.samples.first?.distanceMeters, 10)
        XCTAssertEqual(result.samples.first?.cadencePerMinute, 0)
        XCTAssertEqual(result.samples.first?.source, .googleHealth)
        XCTAssertEqual(result.coalescingSamples(), result)
    }

    func testCoalescingPreservesDistinctProviderProvenance() {
        let original = WorkoutTelemetry(workoutID: UUID(), source: .googleHealth, samples: [
            .init(timestamp: start, heartRateBPM: 120, source: .googleHealth),
            .init(timestamp: start, powerWatts: 200, source: .garmin)
        ])
        let result = original.coalescingSamples()
        XCTAssertEqual(result.samples.count, 2)
        XCTAssertEqual(result.samples.first { $0.powerWatts != nil }?.source, .garmin)
        XCTAssertEqual(result.samples.first { $0.heartRateBPM != nil }?.source, .googleHealth)
    }

    func testDistanceIntervalsDeriveSpeedWithoutInventingAbsoluteAltitude() {
        let telemetry = WorkoutTelemetry(workoutID: UUID(), source: .googleHealth, intervals: [
            .init(kind: .distanceMeters, startDate: start, endDate: start.addingTimeInterval(60), value: 120),
            .init(kind: .elevationGainMeters, startDate: start, endDate: start.addingTimeInterval(60), value: -5)
        ])
        let valid = telemetry.validated(for: workout(id: telemetry.workoutID))
        XCTAssertEqual(valid.intervals.last?.value, -5)
        let derived = WorkoutTelemetryChartBuilder.addingDerivedChannels(to: valid, route: nil)
        let points = WorkoutTelemetryChartBuilder.points(derived, channel: .speed, start: start)
        XCTAssertEqual(points.first?.value ?? 0, 7.2, accuracy: 0.001)
        XCTAssertTrue(WorkoutTelemetryChartBuilder.points(derived, channel: .elevation, start: start).isEmpty)
    }

    func testCanonicalMergeRetainsEachChannelsProvenanceAndDoesNotDoubleTotals() {
        let id = UUID()
        let google = WorkoutTelemetry(workoutID: id, source: .googleHealth,
            samples: [.init(timestamp: start, heartRateBPM: 130, source: .googleHealth)],
            intervals: [.init(kind: .distanceMeters, startDate: start, endDate: start.addingTimeInterval(60), value: 100)])
        let garmin = WorkoutTelemetry(workoutID: UUID(), source: .garmin,
            samples: [.init(timestamp: start, powerWatts: 210, source: .garmin)],
            intervals: [.init(kind: .distanceMeters, startDate: start, endDate: start.addingTimeInterval(60), value: 100)])
        let result = google.merging(garmin)
        XCTAssertEqual(result.workoutID, id)
        XCTAssertEqual(result.samples.first { $0.heartRateBPM != nil }?.source, .googleHealth)
        XCTAssertEqual(result.samples.first { $0.powerWatts != nil }?.source, .garmin)
        XCTAssertEqual(result.intervals.reduce(0) { $0 + $1.value }, 100)
    }

    func testPersistenceCloudRoundTripAndAccountSeparation() async throws {
        let controller = try HealthAccountStorageController(inMemory: true, monitorNetwork: false, automaticallySync: false)
        let account = UUID()
        try controller.switchAccount(userID: account)
        let context = controller.container.mainContext
        let value = workout()
        try await SwiftDataUnifiedWorkoutStore(modelContext: context).saveWorkout(value)
        let store = WorkoutTelemetryStore(modelContext: context)
        try store.save(WorkoutTelemetry(workoutID: value.id, source: .googleHealth,
            samples: [.init(timestamp: start, heartRateBPM: 130)]))
        let outbox = try XCTUnwrap(HealthCloudJournal.find("workout", key: value.id.uuidString.lowercased(), context: context))
        let payload = try HealthCloudPayload.decode(XCTUnwrap(outbox.payload))
        XCTAssertEqual(payload.telemetry?.samples.first?.heartRateBPM, 130)
        let restored = try ModelContainer(for: HealthAccountStorageController.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try HealthCloudJournal.apply(kind: "workout", key: value.id.uuidString.lowercased(),
            data: payload.encoded(), deleted: false, context: restored.mainContext)
        XCTAssertEqual(try WorkoutTelemetryStore(modelContext: restored.mainContext).load(workoutID: value.id)?.samples.first?.heartRateBPM, 130)
        try controller.switchAccount(userID: UUID())
        XCTAssertNil(try WorkoutTelemetryStore(modelContext: controller.container.mainContext).load(workoutID: value.id))
        try controller.switchAccount(userID: account)
        XCTAssertEqual(try WorkoutTelemetryStore(modelContext: controller.container.mainContext).load(workoutID: value.id)?.samples.count, 1)
    }

    func testPartialRefreshKeepsRicherChannelAndEqualLengthRefreshReplacesValues() async throws {
        let controller = try HealthAccountStorageController(inMemory: true, monitorNetwork: false, automaticallySync: false)
        let value = workout()
        let context = controller.container.mainContext
        try await SwiftDataUnifiedWorkoutStore(modelContext: context).saveWorkout(value)
        let store = WorkoutTelemetryStore(modelContext: context)
        try store.save(WorkoutTelemetry(workoutID: value.id, source: .googleHealth, samples: [
            .init(timestamp: start, heartRateBPM: 120), .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 130)
        ]))
        try store.save(WorkoutTelemetry(workoutID: value.id, source: .googleHealth,
            samples: [.init(timestamp: start, powerWatts: 200)]))
        XCTAssertEqual(try store.load(workoutID: value.id)?.samples.filter { $0.heartRateBPM != nil }.count, 2)
        try store.save(WorkoutTelemetry(workoutID: value.id, source: .googleHealth, samples: [
            .init(timestamp: start, heartRateBPM: 140), .init(timestamp: start.addingTimeInterval(10), heartRateBPM: 150)
        ]))
        let result = try XCTUnwrap(store.load(workoutID: value.id))
        XCTAssertEqual(result.samples.compactMap(\.heartRateBPM), [140, 150])
        XCTAssertEqual(result.samples.compactMap(\.powerWatts), [200])
    }
}

@MainActor
final class WorkoutDetailReadabilityTests: XCTestCase {
    func testTwoAndHalfHourAxisEndsAtActualWorkoutEnd() {
        let start = Date(timeIntervalSince1970: 1800000000)
        let minutes = WorkoutChartDomainPolicy.minutes(start: start, end: start.addingTimeInterval(9000))
        XCTAssertEqual(minutes, 150)
        XCTAssertEqual(WorkoutChartDomainPolicy.ticks(endMinutes: minutes), [0, 60, 120, 150])
        XCTAssertEqual(WorkoutChartDomainPolicy.label(minutes: minutes), "2:30:00")
        XCTAssertEqual(WorkoutChartDomainPolicy.label(minutes: 2.5), "2:30")
    }
    func testActualMeasurementsNeverMoveToAxisEndpointsAndGapsStaySeparate() {
        let start = Date(timeIntervalSince1970: 1800000000)
        let telemetry = WorkoutTelemetry(workoutID: UUID(), source: .appleHealthKit, samples: [
            .init(timestamp: start.addingTimeInterval(-1), heartRateBPM: 120),
            .init(timestamp: start.addingTimeInterval(12), heartRateBPM: 120),
            .init(timestamp: start.addingTimeInterval(22), heartRateBPM: 130),
            .init(timestamp: start.addingTimeInterval(8000), heartRateBPM: 140),
            .init(timestamp: start.addingTimeInterval(8010), heartRateBPM: 150),
            .init(timestamp: start.addingTimeInterval(9001), heartRateBPM: 160),
            .init(timestamp: start.addingTimeInterval(50), heartRateBPM: .nan),
            .init(timestamp: start.addingTimeInterval(60), heartRateBPM: 999)
        ])
        let points = WorkoutTelemetryChartBuilder.points(telemetry, channel: .heartRate,
            start: start, end: start.addingTimeInterval(9000))
        XCTAssertEqual(points.map(\.seconds), [12,22,8000,8010])
        XCTAssertEqual(points.map(\.segment), [0,0,1,1])
        XCTAssertEqual(points.map(\.value), [120,130,140,150])
    }
    func testDenseSensorStreamKeepsShortMissingIntervalDisconnected() {
        let start=Date(timeIntervalSince1970:1800000000)
        let times=[0.0,5,10,15,80,85,90,95]
        let telemetry=WorkoutTelemetry(workoutID:UUID(),source:.appleHealthKit,samples:times.map {
            WorkoutTelemetrySample(timestamp:start.addingTimeInterval($0),heartRateBPM:140)
        })
        let points=WorkoutTelemetryChartBuilder.points(telemetry,channel:.heartRate,start:start,end:start.addingTimeInterval(100))
        XCTAssertEqual(points.map(\.seconds),times)
        XCTAssertEqual(points.map(\.segment),[0,0,0,0,1,1,1,1])
    }
    func testValueAxisKeepsValidOutlierFlatAndNegativeElevationWithoutCropping() {
        let range = WorkoutChartDomainPolicy.values([120,121,299,.nan,.infinity])
        XCTAssertLessThan(range.lowerBound,120); XCTAssertGreaterThan(range.upperBound,299)
        let flat = WorkoutChartDomainPolicy.values([140,140])
        XCTAssertLessThan(flat.lowerBound,140);XCTAssertGreaterThan(flat.upperBound,140)
        let elevation = WorkoutChartDomainPolicy.values([-40,3],allowsNegative:true)
        XCTAssertLessThan(elevation.lowerBound,-40);XCTAssertGreaterThan(elevation.upperBound,3)
        XCTAssertEqual(WorkoutChartDomainPolicy.values([.nan,.infinity]),0...1)
        XCTAssertTrue(WorkoutChartDomainPolicy.ticks(endMinutes: .nan).allSatisfy(\.isFinite))
    }
    func testRoutePlaybackDoesNotRepeatOnMicroScrollButRearmsAfterLeaving() {
        var gate = WorkoutCardRoutePlaybackGate();let now=Date()
        gate.updatePresence(true,now:now);XCTAssertTrue(gate.canPlay);gate.didStart()
        gate.updatePresence(true,now:now.addingTimeInterval(8));XCTAssertFalse(gate.canPlay)
        gate.updatePresence(false,now:now.addingTimeInterval(9))
        gate.updatePresence(true,now:now.addingTimeInterval(9.2));XCTAssertFalse(gate.canPlay)
        gate.updatePresence(false,now:now.addingTimeInterval(10))
        gate.updatePresence(false,now:now.addingTimeInterval(10.3))
        gate.updatePresence(true,now:now.addingTimeInterval(11));XCTAssertTrue(gate.canPlay)
        gate.didStart();XCTAssertFalse(gate.canPlay)
    }
    func testHorizontalMediaVisibilityReflectsClippingDuringPhotoPaging() {
        let geometry=WorkoutMediaStripGeometry(widths:[300,300],viewportWidth:330,inset:0,spacing:8)
        XCTAssertEqual(geometry.visibleFraction(at:0,offset:0),1)
        XCTAssertEqual(geometry.visibleFraction(at:0,offset:150),0.5,accuracy:0.001)
        XCTAssertEqual(geometry.visibleFraction(at:0,offset:308),0)
        XCTAssertEqual(geometry.visibleFraction(at:0,offset:.nan),0)
    }
    func testPlaybackStopsForBackgroundMotionPreferenceAndLowPower() {
        XCTAssertTrue(WorkoutCardRoutePlaybackGate.isEligible(visible:true,active:true,reduceMotion:false,lowPower:false,renderer:true,route:true))
        for disabled in 0..<6 {
            XCTAssertFalse(WorkoutCardRoutePlaybackGate.isEligible(visible:disabled != 0, active:disabled != 1,
                reduceMotion:disabled == 2, lowPower:disabled == 3, renderer:disabled != 4, route:disabled != 5))
        }
    }
    func testEmptyMediaRequiresSuccessfulCompletionAndNeverTreatsFailureAsEmpty() {
        let identity=WorkoutPhotoLoadIdentity(ownerID: UUID(),accountGeneration:1,workoutID:UUID(),revision:0,photoPaths:[])
        var state=WorkoutPhotoRowLoadState();_=state.begin(identity)
        XCTAssertFalse(state.isConfirmedEmpty(identity,hasPhotos:false))
        state.fail(identity);XCTAssertFalse(state.isConfirmedEmpty(identity,hasPhotos:false))
        XCTAssertTrue(state.complete(identity));XCTAssertTrue(state.isConfirmedEmpty(identity,hasPhotos:false))
        XCTAssertFalse(state.isConfirmedEmpty(identity,hasPhotos:true))
        let other=WorkoutPhotoLoadIdentity(ownerID:UUID(),accountGeneration:2,workoutID:identity.workoutID,revision:0,photoPaths:[])
        XCTAssertTrue(state.begin(other).resetScope)
        XCTAssertFalse(state.canDisplayLoaded(for:identity));XCTAssertFalse(state.isConfirmedEmpty(other,hasPhotos:false))
    }
}


extension WorkoutTelemetryTests {
    func testFeedbackHRRowsKeepFiveSlotsAndDistinguishZeroFromMissing() {
        let rows = WorkoutHeartRateZoneDisplay.rows([.init(name: "Zone 2", durationSeconds: 20), .init(name: "Z4", durationSeconds: 0)])
        XCTAssertEqual(rows.map(\.index), [1,2,3,4,5])
        XCTAssertNil(rows[0].durationSeconds)
        XCTAssertEqual(rows[1].durationSeconds, 20)
        XCTAssertEqual(rows[3].durationSeconds, 0)
        XCTAssertNil(rows[4].durationSeconds)
        XCTAssertTrue(WorkoutHeartRateZoneDisplay.rows([]).allSatisfy { $0.durationSeconds == nil })
    }
    func testFeedbackDoesNotMapProviderFourZoneLabelsIntoFiveZoneThresholds() {
        let rows = WorkoutHeartRateZoneDisplay.rows([.init(name: "고강도", durationSeconds: 20)])
        XCTAssertTrue(rows.allSatisfy { $0.durationSeconds == nil })
        XCTAssertNil(WorkoutHeartRateZoneDisplay.index(for: "고강도"))
    }
    func testFeedbackZoneRowsRejectInvalidAndAggregateSameIndexedZone() {
        let rows = WorkoutHeartRateZoneDisplay.rows([.init(name: "Z1", durationSeconds: 2), .init(name: "Zone 1", durationSeconds: 3), .init(name: "Z2", durationSeconds: .nan), .init(name: "Z3", durationSeconds: -1)])
        XCTAssertEqual(rows[0].durationSeconds, 5)
        XCTAssertNil(rows[1].durationSeconds); XCTAssertNil(rows[2].durationSeconds)
    }
    func testFeedbackDerivedHRKeepsAllFiveIncludingKnownZeroWithoutInventingMissingStream() {
        let value = workout()
        let input = WorkoutTelemetry(workoutID: value.id, source: .manual, samples: [.init(timestamp: value.startDate, heartRateBPM: 100), .init(timestamp: value.startDate.addingTimeInterval(10), heartRateBPM: 100)])
        let zones = WorkoutTelemetryChartBuilder.heartRateZones(input, workout: value, maximumHeartRate: 190)
        XCTAssertEqual(zones.count, 5)
        XCTAssertEqual(zones.map(\.durationSeconds), [10,0,0,0,0])
        XCTAssertTrue(WorkoutTelemetryChartBuilder.heartRateZones(.init(workoutID: value.id, source: .manual), workout: value, maximumHeartRate: 190).isEmpty)
    }
    func testFeedbackRunningPaceAndCyclingSpeedRespectDistanceUnits() {
        let run = WorkoutSplitDisplay(type: .running, preferredUnit: .metric)
        let ride = WorkoutSplitDisplay(type: .cycling, preferredUnit: .metric)
        XCTAssertEqual(run.text(distance: 1000, seconds: 300), "5:00/km")
        XCTAssertEqual(ride.text(distance: 1000, seconds: 300), "12.0 km/h")
        let runMiles = WorkoutSplitDisplay(type: .running, preferredUnit: .imperial)
        let rideMiles = WorkoutSplitDisplay(type: .cycling, preferredUnit: .imperial)
        XCTAssertEqual(runMiles.text(distance: 1609.344, seconds: 300), "5:00/mi")
        XCTAssertEqual(rideMiles.text(distance: 1609.344, seconds: 300), "12.0 mph")
        XCTAssertEqual(rideMiles.distanceText(1609.344), "1.00 mi")
    }
    func testFeedbackSplitZeroAndMissingNeverProduceInvalidNumbers() {
        for type in [UnifiedWorkoutType.running, .cycling] {
            let display = WorkoutSplitDisplay(type: type, preferredUnit: .metric)
            for duration in [0.0, -1, .nan, .infinity] { XCTAssertNil(display.value(distance: 1000, seconds: duration)) }
            for distance in [Double?.none, -1, .nan, .infinity] { XCTAssertNil(display.value(distance: distance, seconds: 60)) }
        }
        XCTAssertEqual(WorkoutSplitDisplay(type: .cycling, preferredUnit: .metric).text(distance: 0, seconds: 60), "0.0 km/h")
        XCTAssertEqual(WorkoutSplitDisplay(type: .running, preferredUnit: .metric).text(distance: 0, seconds: 60), "—")
        XCTAssertEqual(WorkoutSplitDisplay(type: .swimming, preferredUnit: .imperial).text(distance: 1000, seconds: 300), "5:00/km")
    }
    func testFeedbackHeartRateBuilderPreservesExplicitZeroWithoutFillingMissingZone() {
        let summary = WorkoutZoneBuilder().buildSummary(type: .heartRate, durations: [.init(zoneIndex: 1, durationSeconds: 0), .init(zoneIndex: 2, durationSeconds: 20)])
        XCTAssertEqual(summary.zones.map(\.zoneIndex), [1,2])
        XCTAssertEqual(summary.zones[0].percentage, 0)
        XCTAssertEqual(summary.zones[1].percentage, 100)
        let allZero = WorkoutZoneBuilder().buildSummary(type: .heartRate, durations: [.init(zoneIndex: 1, durationSeconds: 0)])
        XCTAssertEqual(allZero.zones.count, 1); XCTAssertNil(allZero.dominantZone)
        XCTAssertFalse(WorkoutZoneBuilder().buildSummary(type: .heartRate, durations: []).isAvailable)
    }
}

extension WorkoutTelemetryTests {
    func testBarScaleSeparatesLabelAndKeepsZeroNineAndHundredPercentProportional() {
        for width in [240.0, 320, 430] {
            let zero = WorkoutBarGeometry(width: width, label: 56, statistics: 92, fraction: 0, progress: 1)
            let nine = WorkoutBarGeometry(width: width, label: 56, statistics: 92, fraction: 0.09, progress: 1)
            let full = WorkoutBarGeometry(width: width, label: 56, statistics: 92, fraction: 1, progress: 1)
            XCTAssertEqual(zero.valueWidth, 0)
            XCTAssertEqual(nine.valueWidth, full.valueWidth * 0.09, accuracy: 0.00001)
            XCTAssertEqual(nine.valueX, nine.labelWidth + nine.valueWidth + 8)
            XCTAssertLessThanOrEqual(full.valueX + 92, width + 0.001)
            let halfway = WorkoutBarGeometry(width: width, label: 56, statistics: 92, fraction: 1, progress: 0.5)
            XCTAssertEqual(halfway.valueWidth, full.valueWidth * 0.5, accuracy: 0.00001)
            XCTAssertEqual(halfway.valueX - zero.valueX, halfway.valueWidth, accuracy: 0.00001)
        }
    }
    func testMeasuredSplitDetailsUseTimeWeightedHeartAndSignedAltitudeWithoutFillingGaps() {
        let start = Date(timeIntervalSince1970: 1000)
        let split = WorkoutTelemetrySplit(label: "1 km", startDate: start, endDate: start.addingTimeInterval(60), durationSeconds: 60, distanceMeters: 1000)
        let samples: [WorkoutTelemetrySample] = [
            .init(timestamp: start, heartRateBPM: 100, elevationMeters: 30),
            .init(timestamp: start.addingTimeInterval(20), heartRateBPM: 160, elevationMeters: 28),
            .init(timestamp: start.addingTimeInterval(60), heartRateBPM: 180, elevationMeters: 25)
        ]
        let measured = WorkoutTelemetryChartBuilder.measuredSplitDetails([split], samples: samples)[0]
        XCTAssertEqual(measured.averageHeartRate ?? 0, 140, accuracy: 0.0001)
        XCTAssertEqual(measured.elevationChangeMeters, -5)
        let missing = WorkoutTelemetryChartBuilder.measuredSplitDetails([split], samples: [samples[1]])[0]
        XCTAssertNil(missing.averageHeartRate); XCTAssertNil(missing.elevationChangeMeters)
        var provider = split; provider.averageHeartRate = 150; provider.elevationChangeMeters = 8
        XCTAssertEqual(WorkoutTelemetryChartBuilder.measuredSplitDetails([provider], samples: samples)[0], provider)
    }
    func testInvalidHeartSamplesNeverClassifiedAndUnknownProviderZoneRemainsSeparate() {
        let value = workout(source: .appleHealthKit)
        let input = WorkoutTelemetry(workoutID: value.id, source: .appleHealthKit, samples: [
            .init(timestamp: value.startDate, heartRateBPM: .nan),
            .init(timestamp: value.startDate.addingTimeInterval(10), heartRateBPM: 0),
            .init(timestamp: value.startDate.addingTimeInterval(20), heartRateBPM: 900)
        ])
        XCTAssertTrue(WorkoutTelemetryChartBuilder.heartRateZones(input, workout: value, maximumHeartRate: 190).isEmpty)
        let rows = WorkoutHeartRateZoneDisplay.rows([.init(name: "Z1", durationSeconds: 0), .init(name: "Z2", durationSeconds: 9), .init(name: "fat burn", durationSeconds: 91)])
        XCTAssertEqual(rows.count, 5); XCTAssertEqual(rows[0].durationSeconds, 0)
        XCTAssertNil(rows[2].durationSeconds)
        XCTAssertNil(WorkoutHeartRateZoneDisplay.index(for: "fat burn"))
    }
}


extension WorkoutTelemetryTests {
    func testCompactBarsPreserveRealRatiosAndZeroWithoutOverlappingStatistics() {
        for width in [240.0, 320, 430] {
            let full = WorkoutCompactBarGeometry(width: width, label: 24, statistics: 116, fraction: 1, progress: 1)
            for fraction in [0.0, 0.01, 0.09, 0.5, 1] {
                let bar = WorkoutCompactBarGeometry(width: width, label: 24, statistics: 116, fraction: fraction, progress: 1)
                XCTAssertEqual(bar.barWidth, full.barWidth * fraction, accuracy: 0.00001)
                XCTAssertGreaterThanOrEqual(bar.valuesX, 32)
                XCTAssertLessThanOrEqual(bar.valuesX + 116, width)
            }
            XCTAssertEqual(WorkoutCompactBarGeometry(width: width, label: 24, statistics: 116, fraction: .nan, progress: 1).barWidth, 0)
        }
    }
    func testDetailVisitRevealClaimsSurviveScrollAndDataRefreshButNewVisitStartsFresh() {
        let id = UUID(), visit = WorkoutDetailPresentationStore()
        for key in ["charts.heartRate", "zones.1", "splits.0"] {
            XCTAssertFalse(visit.hasRevealed(id, key: key), "Offscreen content must not claim on construction")
            XCTAssertTrue(visit.claimReveal(id, key: key))
            for _ in 0..<10 { XCTAssertFalse(visit.claimReveal(id, key: key)) }
            XCTAssertTrue(WorkoutDetailPresentationStore().claimReveal(id, key: key))
        }
        XCTAssertTrue(visit.claimReveal(id, key: "charts.power"), "A later arriving channel gets its own first reveal")
    }
}
