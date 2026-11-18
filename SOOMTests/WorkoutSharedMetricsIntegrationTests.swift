import HealthKit
import SwiftUI
import XCTest
@testable import SOOM

@MainActor
final class WorkoutSharedMetricsIntegrationTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let post = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let source = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var binding: WorkoutSharedMetricsCandidate.Binding {
        .init(postID: post, ownerID: owner, sourceWorkoutID: source, detailRevision: 3, consentRevision: 7)
    }
    private func workout(type: UnifiedWorkoutType = .swimming) -> UnifiedWorkout {
        .init(id: source, externalId: nil, source: .appleHealthKit, workoutType: type,
            startDate: start, endDate: start.addingTimeInterval(300), durationSeconds: 250,
            distanceMeters: 50, activeEnergyKcal: 88, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: start, updatedAt: start)
    }
    private func telemetry(provenance: WorkoutTelemetrySplitProvenance? = .healthKitLapEvent) -> WorkoutTelemetry {
        .init(workoutID: source, source: .appleHealthKit, splits: [
            .init(label: "랩 1", startDate: start, endDate: start.addingTimeInterval(30), durationSeconds: 30,
                  distanceMeters: 25, provenance: provenance),
            .init(label: "랩 2", startDate: start.addingTimeInterval(45), endDate: start.addingTimeInterval(90),
                  durationSeconds: 45, distanceMeters: nil, provenance: provenance)])
    }
    private func fixture(enabled: Bool = true) -> (MetricsMemoryTransport, WorkoutSharedMetricsLocalSession) {
        let transport = MetricsMemoryTransport(receipt: .init(binding: binding, viewerID: owner, workoutType: .swimming,
            disclosureVersion: 2, selected: true, canRead: true, canWrite: true, accessEpoch: 1))
        return (transport, .init(postID: post, viewerID: owner, transport: transport, enabledForLocalEvaluation: enabled))
    }
    private func item() -> FeedItem {
        var dto = FeedPostDTO(id: post, userId: owner, sourceWorkoutId: source, sport: .swimming,
            title: "합성 수영 원본", distanceMeters: 50, durationSeconds: 250, visibility: .publicPost, createdAt: start)
        dto.sharedDetailRevision = 3; dto.activityAt = start
        let v1 = WorkoutSharedDetailSnapshot(postID: post, revision: 3,
            payload: .init(durationSeconds: 250, distanceMeters: 50))
        return FeedPostBundleDTO(post: dto, sharedDetail: v1, sharedDetailContractEnabled: true).makeFeedItem(currentUserId: owner)
    }
    private func publish(_ session: WorkoutSharedMetricsLocalSession) async throws {
        try await session.publish(workout: workout(), telemetry: telemetry(), confirmedSingleWorkoutDisclosure: true)
    }
    func testHistoricalSplitDecodesWithoutProvenanceAndIsNotPromotedByLabel() throws {
        let old = WorkoutTelemetrySplit(label: "랩 99", startDate: start, endDate: start.addingTimeInterval(20), durationSeconds: 20)
        let data = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("provenance"))
        XCTAssertNil(try JSONDecoder().decode(WorkoutTelemetrySplit.self, from: data).provenance)
        let (remote, _) = fixture()
        for kind: WorkoutTelemetrySplitProvenance? in [nil, .unknown, .healthKitSegmentEvent] {
            let result = try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout(),
                telemetry: telemetry(provenance: kind), ownerID: owner, receipt: remote.current)
            XCTAssertTrue(result.payload.originalSwimmingLaps.isEmpty)
        }
    }
    func testFutureUnknownProvenanceSurvivesAsUnknownWithoutInventingLap() throws {
        let split = telemetry().splits[0]
        let data = try JSONEncoder().encode(split)
        let modified = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "healthKitLapEvent", with: "futureUnknown").utf8)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutTelemetrySplit.self, from: modified).provenance, .unknown)
    }
    func testHealthKitParserTagsLapAndSegmentAndPersistencePreservesTags() throws {
        for (kind, expected) in [(HKWorkoutEventType.lap, WorkoutTelemetrySplitProvenance.healthKitLapEvent),
                                  (.segment, .healthKitSegmentEvent)] {
            let event = HKWorkoutEvent(type: kind, dateInterval: DateInterval(start: start, duration: 30), metadata: nil)
            let raw = HKWorkout(activityType: .swimming, start: start, end: start.addingTimeInterval(300),
                workoutEvents: [event], totalEnergyBurned: nil, totalDistance: nil, metadata: nil)
            let rows = HealthKitWorkoutTelemetryFetcher.swimmingSplits(raw)
            XCTAssertEqual(rows.first?.provenance, expected)
            XCTAssertNil(rows.first?.distanceMeters)
            let restored = try JSONDecoder().decode([WorkoutTelemetrySplit].self, from: JSONEncoder().encode(rows))
            XCTAssertEqual(restored, rows)
        }
    }
    func testTCXOriginalLapDurationDefinedBoundaryAndMissingDistanceSurvive() throws {
        let xml = """
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity Sport="Other"><Id>2023-11-14T22:13:20Z</Id><Lap StartTime="2023-11-14T22:13:20Z"><TotalTimeSeconds>30</TotalTimeSeconds><Calories>10</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod></Lap></Activity></Activities></TrainingCenterDatabase>
        """
        let stream = try WorkoutTelemetryTCXParser().parse(data: Data(xml.utf8), workoutID: source, source: .googleHealth)
        XCTAssertEqual(stream.splits.first?.provenance, .tcxLapElement)
        XCTAssertEqual(stream.splits.first?.durationSeconds, 30)
        XCTAssertNil(stream.splits.first?.distanceMeters)
        let (remote, _) = fixture()
        let value = try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout(), telemetry: stream,
            ownerID: owner, receipt: remote.current)
        XCTAssertEqual(value.payload.originalSwimmingLaps.first?.origin, .tcxLapElement)
        XCTAssertEqual(value.payload.originalSwimmingLaps.first?.endSeconds, 30)
    }
    func testMergedValidatedTelemetryRetainsOriginButConflictingProvidersReject() throws {
        let original = telemetry()
        let restored = original.validated(for: workout()).merging(.init(workoutID: source, source: .googleHealth))
        XCTAssertEqual(restored.splits.map(\.provenance), [.healthKitLapEvent, .healthKitLapEvent])
        var conflict = restored; conflict.splits[1].provenance = .tcxLapElement
        let (remote, _) = fixture()
        XCTAssertThrowsError(try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout(), telemetry: conflict,
            ownerID: owner, receipt: remote.current))
    }
    func testNonSwimmingTCXLapsDoNotBlockCaloriesOrBecomeSwimmingLaps() throws {
        for type in [UnifiedWorkoutType.running, .cycling] {
            let receipt = WorkoutSharedMetricsReceipt(binding: binding, viewerID: owner, workoutType: type,
                disclosureVersion: 2, selected: true, canRead: true, canWrite: true, accessEpoch: 1)
            let result = try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout(type: type),
                telemetry: telemetry(provenance: .tcxLapElement), ownerID: owner, receipt: receipt)
            XCTAssertEqual(result.payload.activeEnergyKcal, 88)
            XCTAssertTrue(result.payload.originalSwimmingLaps.isEmpty)
        }
    }
    func testExactFreshParserEvidenceEnrichesOnlyNilProvenanceWithoutChangingHistory() {
        let old = telemetry(provenance: nil), fresh = telemetry()
        let enriched = old.merging(fresh)
        XCTAssertEqual(enriched.splits.map(\.provenance), [.healthKitLapEvent, .healthKitLapEvent])
        var stripped = enriched; stripped.splits = stripped.splits.map { var row = $0; row.provenance = nil; return row }
        XCTAssertEqual(stripped.splits, old.splits)
        for mode in 0..<4 {
            var mismatch = fresh
            if mode == 0 { mismatch.workoutID = UUID() }
            if mode == 1 { mismatch.source = .googleHealth }
            if mode == 2 { mismatch.splits[0].durationSeconds = 29; mismatch.splits[1].distanceMeters = 50 }
            if mode == 3 { mismatch.splits += fresh.splits }
            XCTAssertTrue(old.merging(mismatch).splits.allSatisfy { $0.provenance == nil })
        }
    }
    func testDefaultOffDoesNotCallTransportOrAutomaticallyShare() async throws {
        let (remote, _) = fixture()
        let session = WorkoutSharedMetricsLocalSession(postID: post, viewerID: owner, transport: remote)
        await session.refresh()
        XCTAssertEqual(remote.calls, 0)
        do { try await publish(session); XCTFail("default off") } catch { }
        XCTAssertEqual(remote.calls, 0); XCTAssertEqual(remote.writes, 0)
    }
    func testExplicitDisclosureRequiredAndOldConsentNeverUpgrades() async throws {
        let (remote, session) = fixture()
        do { try await session.publish(workout: workout(), telemetry: telemetry()); XCTFail("explicit choice required") } catch { }
        XCTAssertEqual(remote.writes, 0)
        remote.current.disclosureVersion = 1
        do { try await publish(session); XCTFail("old disclosure") } catch { }
        XCTAssertEqual(remote.writes, 0)
        remote.current.disclosureVersion = 2; remote.current.selected = false
        await session.refresh(); XCTAssertNil(session.projection)
    }
    func testPublishFetchUsesOnlyReceiptAndMapsIntoExistingSharedSections() async throws {
        let (remote, session) = fixture()
        try await publish(session)
        XCTAssertEqual(remote.writes, 1)
        let projection = try XCTUnwrap(session.projection)
        let shared = WorkoutDetailSharedRecord(item: item(), localMetricsProjection: projection)
        XCTAssertEqual(shared.presentationMetrics.last?.value, "88 kcal")
        XCTAssertEqual(shared.presentationTelemetry?.splits.map(\.durationSeconds), [30, 45])
        XCTAssertNil(shared.presentationTelemetry?.splits[1].distanceMeters)
        XCTAssertEqual(shared.presentationWorkout.activeEnergyKcal, 88)
        XCTAssertEqual(shared.presentationWorkout.durationSeconds, 250)
        XCTAssertEqual(shared.presentationWorkout.endDate.timeIntervalSince(start), 300)
        XCTAssertEqual(shared.route, WorkoutDetailSharedRecord(item: item()).route)
        XCTAssertFalse(String(decoding: try XCTUnwrap(remote.payload), as: UTF8.self).contains(source.uuidString))
    }
    func testLapStatisticsUseOnlyAuthorizedV1SamplesNeverPrivateSourceStream() async throws {
        let (_, session) = fixture()
        var sourceTelemetry = telemetry()
        sourceTelemetry.samples = [.init(timestamp: start, heartRateBPM: 190)]
        try await session.publish(workout: workout(), telemetry: sourceTelemetry, confirmedSingleWorkoutDisclosure: true)
        var sharedItem = item()
        sharedItem.sharedDetail = .init(postID: post, revision: 3,
            payload: .init(durationSeconds: 250, distanceMeters: 50, samples: [.init(seconds: 0, heartRateBPM: 110), .init(seconds: 30, heartRateBPM: 110)]))
        let shared = WorkoutDetailSharedRecord(item: sharedItem, localMetricsProjection: try XCTUnwrap(session.projection))
        let stream = try XCTUnwrap(shared.presentationTelemetry)
        XCTAssertEqual(stream.samples.compactMap(\.heartRateBPM), [110, 110])
        XCTAssertEqual(WorkoutTelemetryChartBuilder.measuredSplitDetails(stream.splits, samples: stream.samples).first?.averageHeartRate, 110)
        XCTAssertNil(stream.splits.first?.averageHeartRate)
        XCTAssertNil(WorkoutTelemetryChartBuilder.measuredSplitDetails(stream.splits, samples: Array(stream.samples.prefix(1))).first?.averageHeartRate)
    }
    func testWithdrawRevokesAlreadyRetainedProjectionAndDoesNotRepublish() async throws {
        let (remote, session) = fixture(); try await publish(session)
        let shared = WorkoutDetailSharedRecord(item: item(), localMetricsProjection: try XCTUnwrap(session.projection))
        try await session.withdraw()
        XCTAssertNil(session.projection); XCTAssertNil(remote.payload)
        XCTAssertEqual(shared.presentationMetrics.map(\.value), shared.metrics.map(\.value))
        XCTAssertTrue(shared.presentationTelemetry?.splits.isEmpty == true)
        await session.refresh(); XCTAssertNil(session.projection); XCTAssertEqual(remote.writes, 1)
    }
    func testAccessRevokedPrivateChangeAndMissingServerFailClosed() async throws {
        for mode in 0..<3 {
            let (remote, session) = fixture(); try await publish(session)
            let held = try XCTUnwrap(session.projection)
            if mode == 0 { remote.current.canRead = false; remote.current.accessEpoch += 1 }
            if mode == 1 { remote.current.selected = false }
            if mode == 2 { remote.supported = false }
            await session.refresh()
            XCTAssertNil(session.projection); XCTAssertFalse(held.applies(to: item()))
            XCTAssertEqual(remote.writes, 1)
        }
    }
    func testFetchRaceRechecksAuthoritativeReceiptAndClearsOldLease() async throws {
        let (remote, session) = fixture(); try await publish(session)
        remote.afterFetch = { remote.current.accessEpoch += 1 }
        await session.refresh(); XCTAssertNil(session.projection)
        XCTAssertNotNil(session.lastError)
    }
    func testRecreatedPostIncarnationInvalidatesInFlightResponse() async throws {
        let (remote, session) = fixture(); try await publish(session)
        remote.afterFetch = { remote.current.postIncarnation = UUID() }
        await session.refresh(); XCTAssertNil(session.projection)
        XCTAssertNotNil(session.lastError)
    }
    func testAccountChangeDuringAwaitCannotPublishIntoNewSession() async throws {
        let (remote, session) = fixture(); try await publish(session)
        remote.afterFetch = { session.invalidate(viewerID: UUID()) }
        await session.refresh(); XCTAssertNil(session.projection)
    }
    func testTamperedPayloadWrongReceiptAndNonSwimmingLapsReject() async throws {
        for mode in 0..<3 {
            let (remote, session) = fixture(); try await publish(session)
            if mode == 0 { remote.payload = Data(#"{"version":2,"elapsedSeconds":300,"activeEnergyKcal":-1,"originalSwimmingLaps":[]}"#.utf8) }
            if mode == 1 { remote.responseRevisionOffset = 1 }
            if mode == 2 { remote.returnWrongSource = true }
            await session.refresh(); XCTAssertNil(session.projection)
        }
    }
    func testInvalidatedPostV1OrSourceLinkNeverDisplaysNewFields() async throws {
        let (_, session) = fixture(); try await publish(session)
        let projection = try XCTUnwrap(session.projection)
        var unavailable = item(); unavailable.sharedDetailContractEnabled = false
        let record = WorkoutDetailSharedRecord(item: unavailable, localMetricsProjection: projection)
        XCTAssertEqual(record.presentationMetrics.map(\.value), record.metrics.map(\.value))
        XCTAssertNil(record.presentationWorkout.activeEnergyKcal)
        XCTAssertNil(record.presentationTelemetry)
    }
    func testMemoryCompareAndSwapRejectsStaleWriteAndHasNoRetry() async throws {
        let (remote, session) = fixture()
        remote.beforePut = { remote.current.accessEpoch += 1 }
        do { try await publish(session); XCTFail("stale write") } catch { }
        XCTAssertEqual(remote.writes, 0); XCTAssertNil(remote.payload)
    }
    func testSharedZoneAccessibilityHintNeverInventsPrivateMaximumOrDerivedZones() {
        XCTAssertEqual(WorkoutTelemetrySection.zoneAccessibilityHint(sharedMeasurementOnly: true,
            hasProviderZones: false, maximumHeartRate: 190), "공유된 심박 구간 정보가 없어요")
        XCTAssertEqual(WorkoutTelemetrySection.zoneAccessibilityHint(sharedMeasurementOnly: true,
            hasProviderZones: true, maximumHeartRate: 190), "공유된 원본 구간 기준")
        XCTAssertEqual(WorkoutTelemetrySection.zoneAccessibilityHint(sharedMeasurementOnly: false,
            hasProviderZones: false, maximumHeartRate: 180), "측정된 연속 구간과 최대심박 180 bpm 기준")
        XCTAssertEqual(WorkoutTelemetrySection.zoneAccessibilityHint(sharedMeasurementOnly: false,
            hasProviderZones: true, maximumHeartRate: 180), "연동 서비스가 제공한 구간 기준")
    }
    func testActualSharedDetailContentRendersInjectedMemorySnapshot() async throws {
        let demo = ReviewDemoController.shared; demo.start(); defer { demo.exit() }
        let runtime = try XCTUnwrap(demo.runtime)
        let (_, session) = fixture(); try await publish(session)
        let record = WorkoutDetailSharedRecord(item: item(), localMetricsProjection: try XCTUnwrap(session.projection))
        let content = WorkoutDetailContent(workout: record.layoutIdentity, showsHeader: true, sharedRecord: record)
            .frame(width: 393).frame(maxHeight: .infinity, alignment: .top).modelContainer(runtime.storage.container)
            .environmentObject(runtime.storage).environmentObject(runtime.auth)
            .environment(\.workoutDetailReduceMotion, true)
        let host = UIHostingController(rootView: content); host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1800))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; session.invalidate() }
        host.view.frame = window.bounds
        for _ in 0..<15 { host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertEqual(host.view.bounds.width, 393)
        XCTAssertEqual(record.presentationMetrics.last?.value, "88 kcal")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "SHARED-V2-ACTUAL-DETAIL-CONTENT"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testExistingSummaryAndLapSectionsRenderFromMemoryRoundTripAtBothTypeSizes() async throws {
        let (_, session) = fixture(); try await publish(session)
        let record = WorkoutDetailSharedRecord(item: item(), localMetricsProjection: try XCTUnwrap(session.projection))
        let stream = try XCTUnwrap(record.presentationTelemetry)
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = VStack(spacing: 20) {
                WorkoutRecordMetricsCard(metrics: record.presentationMetrics)
                WorkoutTelemetrySection(telemetry: stream,
                    workout: record.presentationWorkout, sharedMeasurementOnly: true, showsHeartRateZones: false)
            }.padding(16).frame(width: 393).background(Color.white)
                .environment(\.dynamicTypeSize, size).environment(\.workoutDetailReduceMotion, true)
            let renderer = ImageRenderer(content: view); renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 250); XCTAssertEqual(image.size.width, 393)
            let attachment = XCTAttachment(image: image); attachment.name = "SHARED-V2-LOCAL-\(size)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

@MainActor
private final class MetricsMemoryTransport: WorkoutSharedMetricsLocalTransport {
    var current: WorkoutSharedMetricsReceipt
    var payload: Data?
    var supported = true
    var calls = 0, writes = 0
    var afterFetch: (() -> Void)?
    var beforePut: (() -> Void)?
    var responseRevisionOffset: Int64 = 0
    var returnWrongSource = false
    init(receipt: WorkoutSharedMetricsReceipt) { current = receipt }
    func supportsCandidate() async throws -> Bool { calls += 1; return supported }
    func receipt(postID: UUID, viewerID: UUID) async throws -> WorkoutSharedMetricsReceipt? {
        calls += 1
        guard current.binding.postID == postID, current.viewerID == viewerID else { return nil }
        return current
    }
    func fetch(expected: WorkoutSharedMetricsReceipt) async throws -> WorkoutSharedMetricsResponse? {
        calls += 1
        guard current == expected, current.isEligible, let payload else { return nil }
        var returned = current; returned.snapshotRevision += responseRevisionOffset
        if returnWrongSource {
            returned = .init(binding: .init(postID: current.binding.postID, ownerID: current.binding.ownerID,
                sourceWorkoutID: UUID(), detailRevision: 3, consentRevision: 7), viewerID: current.viewerID,
                workoutType: current.workoutType, disclosureVersion: 2, selected: true, canRead: true,
                canWrite: true, accessEpoch: 1, snapshotRevision: current.snapshotRevision)
        }
        afterFetch?(); await Task.yield()
        return .init(receipt: returned, payload: payload)
    }
    func put(payload: Data, expected: WorkoutSharedMetricsReceipt) async throws {
        calls += 1; beforePut?()
        guard current == expected, current.isEligible, current.canWrite,
              current.viewerID == current.binding.ownerID else { throw WorkoutSharedMetricsIntegrationError.scopeChanged }
        _ = try WorkoutSharedMetricsCandidate.decode(payload, binding: current.binding, consent: current.consent,
            expectedBinding: current.binding)
        self.payload = payload; current.snapshotRevision += 1; writes += 1
    }
    func withdraw(expected: WorkoutSharedMetricsReceipt) async throws {
        calls += 1
        guard current == expected, current.canWrite else { throw WorkoutSharedMetricsIntegrationError.scopeChanged }
        payload = nil; current.snapshotRevision += 1
    }
}
