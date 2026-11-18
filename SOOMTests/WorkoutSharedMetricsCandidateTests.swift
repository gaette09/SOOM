import XCTest
@testable import SOOM

final class WorkoutSharedMetricsCandidateTests: XCTestCase {
    private typealias Candidate = WorkoutSharedMetricsCandidate
    private let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let post = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let sourceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var binding: Candidate.Binding {
        .init(postID: post, ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 3, consentRevision: 7)
    }
    private var consent: Candidate.Consent {
        .init(binding: binding, energySelected: true, originalLapsSelected: true)
    }
    private func workout(id: UUID? = nil, energy: Double? = 123.5, elapsed: Double = 600,
                         type: UnifiedWorkoutType = .swimming) -> UnifiedWorkout {
        UnifiedWorkout(id: id ?? sourceID, externalId: "PRIVATE-EXTERNAL-ID", source: .appleHealthKit, workoutType: type,
            startDate: start, endDate: start.addingTimeInterval(elapsed), durationSeconds: 500,
            distanceMeters: 250, activeEnergyKcal: energy, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: start, updatedAt: start)
    }
    private func lap(_ begin: Double = 10, _ end: Double = 40, duration: Double = 30,
                     distance: Double? = 50) -> WorkoutTelemetrySplit {
        .init(label: "PRIVATE-LAP-LABEL", startDate: start.addingTimeInterval(begin),
              endDate: start.addingTimeInterval(end), durationSeconds: duration, distanceMeters: distance,
              averageHeartRate: 150)
    }
    private func preview(_ workout: UnifiedWorkout, rows: [WorkoutTelemetrySplit]? = nil,
                         selected: Candidate.Consent? = nil, origin: Candidate.LapOrigin = .healthKitLapEvent) throws -> Candidate.Envelope {
        try Candidate.makeLocalPreview(workout: workout, sourceOwnerID: owner, currentOwnerID: owner,
            originalLaps: rows.map { .init(ownerID: owner, workoutID: workout.id, origin: origin, rows: $0) },
            consent: selected ?? consent, expectedBinding: binding, localPreviewEnabled: true)
    }
    private func encoded(_ value: Candidate.Envelope) throws -> Data {
        try Candidate.encode(value, consent: consent, expectedBinding: binding)
    }
    private func mutate(_ value: Candidate.Envelope, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(value)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testDefaultOffAndExistingV1TransportUnchanged() throws {
        XCTAssertFalse(Candidate.transportEnabled)
        XCTAssertEqual(SupabaseWorkoutSharedDetailService.contract, "detail-v1")
        XCTAssertThrowsError(try Candidate.makeLocalPreview(workout: workout(), sourceOwnerID: owner,
            currentOwnerID: owner, consent: consent, expectedBinding: binding)) {
            XCTAssertEqual($0 as? Candidate.Failure, .previewDisabled)
        }
    }
    func testV1GoldenEncodingOmitsEveryNewHealthField() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let input = WorkoutSharedDetailInput(durationSeconds: 60, distanceMeters: 50, route: [],
            samples: [.init(seconds: 5, heartRateBPM: 120)])
        XCTAssertEqual(String(data: try encoder.encode(input), encoding: .utf8),
            #"{"distanceMeters":50,"durationSeconds":60,"route":[],"samples":[{"heartRateBPM":120,"seconds":5}],"version":1}"#)
        let value = workout()
        let telemetry = WorkoutTelemetry(workoutID: value.id, source: .appleHealthKit,
            intervals: [.init(kind: .energyKcal, startDate: start, endDate: value.endDate, value: 123)],
            splits: [lap()], events: [.init(timestamp: start, type: "lap")])
        XCTAssertEqual(WorkoutSharedDetailInput.build(workout: value, route: nil, telemetry: telemetry),
                       WorkoutSharedDetailInput.build(workout: value, route: nil, telemetry: nil))
    }
    func testSourceLapOffsetsActiveDurationAndMissingDistanceArePreserved() throws {
        let value = try preview(workout(), rows: [lap(duration: 25), lap(90, 150, duration: 45, distance: nil)], origin: .tcxLapElement)
        XCTAssertEqual(value.payload.elapsedSeconds, 600)
        XCTAssertEqual(value.payload.activeEnergyKcal, 123.5)
        XCTAssertEqual(value.payload.originalSwimmingLaps.map(\.startSeconds), [10, 90])
        XCTAssertEqual(value.payload.originalSwimmingLaps.map(\.endSeconds), [40, 150])
        XCTAssertEqual(value.payload.originalSwimmingLaps.map(\.durationSeconds), [25, 45])
        XCTAssertNil(value.payload.originalSwimmingLaps[1].distanceMeters)
        XCTAssertEqual(try Candidate.decode(encoded(value), binding: binding, consent: consent, expectedBinding: binding), value)
    }
    func testHealthKitLapDurationIsOriginalElapsedInterval() throws {
        XCTAssertEqual(try preview(workout(), rows: [lap()]).payload.originalSwimmingLaps.first?.durationSeconds, 30)
        XCTAssertThrowsError(try preview(workout(), rows: [lap(duration: 25)]))
    }
    func testSameOwnerDifferentSourceWorkoutCannotAttachToPost() throws {
        let unrelated = workout(id: UUID())
        XCTAssertThrowsError(try preview(unrelated))
        XCTAssertThrowsError(try preview(unrelated, rows: [lap()]))
    }
    func testNoSourceEvidenceMeansNoInventedLapsOrEnergy() throws {
        let source = workout(energy: nil)
        let value = try preview(source)
        XCTAssertNil(value.payload.activeEnergyKcal)
        XCTAssertTrue(value.payload.originalSwimmingLaps.isEmpty)
    }
    func testPayloadHasNoPrivateIdentifiersLabelsAbsoluteTimesOrExtraChannels() throws {
        let value = try preview(workout(), rows: [lap()])
        let data = try JSONEncoder().encode(value.payload)
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["PRIVATE", "ownerID", "postID", "workoutID", "externalId", "heartRate", "timestamp", "1700000000"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        XCTAssertEqual(Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys),
                       ["version", "elapsedSeconds", "activeEnergyKcal", "originalSwimmingLaps"])
    }
    func testSelectionIsExplicitAndRevocationRejectsExistingCandidate() throws {
        let disabled = Candidate.Consent(binding: binding)
        let empty = try preview(workout(), rows: [lap()], selected: disabled)
        XCTAssertNil(empty.payload.activeEnergyKcal)
        XCTAssertTrue(empty.payload.originalSwimmingLaps.isEmpty)
        let value = try preview(workout(), rows: [lap()])
        XCTAssertThrowsError(try Candidate.decode(encoded(value), binding: binding, consent: disabled, expectedBinding: binding))
        for selection in [Candidate.Consent(binding: binding, energySelected: true),
                          Candidate.Consent(binding: binding, originalLapsSelected: true)] {
            XCTAssertThrowsError(try Candidate.encode(value, consent: selection, expectedBinding: binding))
        }
    }
    func testOwnerAndSourceWorkoutMismatchRejectInsteadOfRebinding() throws {
        let source = workout()
        for current in [owner, UUID()] {
            XCTAssertThrowsError(try Candidate.makeLocalPreview(workout: source, sourceOwnerID: UUID(),
                currentOwnerID: current, consent: consent, expectedBinding: binding, localPreviewEnabled: true))
        }
        XCTAssertThrowsError(try Candidate.makeLocalPreview(workout: source, sourceOwnerID: owner,
            currentOwnerID: UUID(), consent: consent, expectedBinding: binding, localPreviewEnabled: true))
        for evidence in [Candidate.OriginalLaps(ownerID: UUID(), workoutID: source.id, origin: .tcxLapElement, rows: [lap()]),
                         Candidate.OriginalLaps(ownerID: owner, workoutID: UUID(), origin: .tcxLapElement, rows: [lap()])] {
            XCTAssertThrowsError(try Candidate.makeLocalPreview(workout: source, sourceOwnerID: owner, currentOwnerID: owner,
                originalLaps: evidence, consent: consent, expectedBinding: binding, localPreviewEnabled: true))
        }
    }
    func testStalePostOwnerDetailAndConsentEpochsRejectOnEncodeAndDecode() throws {
        let value = try preview(workout())
        let data = try encoded(value)
        let stale: [Candidate.Binding] = [
            .init(postID: post, ownerID: owner, sourceWorkoutID: UUID(), detailRevision: 3, consentRevision: 7),
            .init(postID: UUID(), ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 3, consentRevision: 7),
            .init(postID: post, ownerID: UUID(), sourceWorkoutID: sourceID, detailRevision: 3, consentRevision: 7),
            .init(postID: post, ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 4, consentRevision: 7),
            .init(postID: post, ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 3, consentRevision: 8),
            .init(postID: post, ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 0, consentRevision: 7),
            .init(postID: post, ownerID: owner, sourceWorkoutID: sourceID, detailRevision: 3, consentRevision: 0)]
        for changed in stale {
            let fresh = Candidate.Consent(binding: changed, energySelected: true, originalLapsSelected: true)
            XCTAssertThrowsError(try Candidate.encode(value, consent: fresh, expectedBinding: changed))
            XCTAssertThrowsError(try Candidate.decode(data, binding: binding, consent: fresh, expectedBinding: changed))
            XCTAssertThrowsError(try Candidate.decode(data, binding: binding, consent: consent, expectedBinding: changed))
        }
    }
    func testInvalidEnergyAndElapsedSpansRejectWithoutClamping() throws {
        for energy in [-1.0, .infinity, .nan, 100_001] {
            let source = workout(energy: energy)
            XCTAssertThrowsError(try preview(source))
        }
        for span in [-1.0, 604_801] {
            let source = workout(elapsed: span)
            XCTAssertThrowsError(try preview(source))
        }
        let source = workout(energy: 0)
        XCTAssertEqual(try preview(source).payload.activeEnergyKcal, 0)
    }
    func testInvalidLapsRejectWithoutSortingClippingOrInventingLengths() throws {
        let invalid: [[WorkoutTelemetrySplit]] = [
            [lap(-1, 40)], [lap(590, 610)], [lap(10, 10)], [lap(duration: 0)],
            [lap(duration: 31)], [lap(duration: .nan)], [lap(distance: -1)], [lap(distance: .infinity)],
            [lap(40, 80), lap(10, 40)], [lap(), lap()], [lap(), lap(30, 70)],
            Array(repeating: lap(), count: Candidate.maximumLaps + 1)]
        for rows in invalid { XCTAssertThrowsError(try preview(workout(), rows: rows)) }
        let run = workout(type: .running)
        XCTAssertThrowsError(try preview(run, rows: [lap()]))
    }
    func testUnknownFieldsVersionsAndLapOriginsFailClosed() throws {
        let value = try preview(workout(), rows: [lap()])
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["privateData"] = "hidden" },
            { $0["ownerID"] = "hidden" },
            { $0["events"] = [] },
            { $0["version"] = 1 },
            { var laps = $0["originalSwimmingLaps"] as! [[String: Any]];
              laps[0]["label"] = "unknown"; $0["originalSwimmingLaps"] = laps },
            { var laps = $0["originalSwimmingLaps"] as! [[String: Any]];
              laps[0]["origin"] = "derivedDistanceSplit"; $0["originalSwimmingLaps"] = laps }]
        for edit in edits {
            XCTAssertThrowsError(try Candidate.decode(mutate(value, edit), binding: binding, consent: consent, expectedBinding: binding))
        }
        XCTAssertThrowsError(try Candidate.decode(Data(repeating: 32, count: Candidate.maximumBytes + 1),
            binding: binding, consent: consent, expectedBinding: binding))
    }
    func testV1MaskRetains200MeterFenceAnd202MeterEdgeMargin() throws {
        let metersPerDegree = Double.pi * 6_371_000 / 180
        func point(_ x: Double, _ y: Double = 0) -> WorkoutSharedDetailInput.RoutePoint {
            .init(latitude: y / metersPerDegree, longitude: x / metersPerDegree, seconds: nil, altitude: nil, segment: 0)
        }
        let origin = point(0)
        XCTAssertFalse(WorkoutSharedDetailInput.edgeClear(point(-100, 201), point(100, 201), origin: origin))
        XCTAssertTrue(WorkoutSharedDetailInput.edgeClear(point(-100, 203), point(100, 203), origin: origin))
        let v1 = WorkoutSharedDetailInput(durationSeconds: 600, distanceMeters: 1000,
            route: [point(0), point(150), point(250), point(400), point(600), point(750), point(850), point(1000)])
        let before = v1.masked()
        _ = try preview(workout(), rows: [lap()])
        XCTAssertEqual(v1.masked(), before)
        XCTAssertEqual(before.route.count, 4)
        XCTAssertTrue(before.route.allSatisfy { WorkoutSharedDetailInput.distance(origin, $0) >= 200 })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(v1.masked()), try encoder.encode(before))
    }
}

@MainActor
final class FeedCardPreviewReadTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let post = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func metadata(revision: Int64? = 7) -> FeedCardPreviewMetadata {
        var summary = FeedRouteSummaryDTO(routeExists: true)
        summary.deviceName = "시험 기기"; summary.locationName = "시험 지역"
        return .init(id: post, ownerID: owner, title: "시험 제목", body: "시험 설명",
                     routeSummary: summary, updatedAt: date, detailRevision: revision)
    }
    private func geometry(ownerID: UUID? = nil, postID: UUID? = nil, revision: Int64 = 7,
                          points: [FeedCardPreviewGeometry.Point]? = nil) -> FeedCardPreviewGeometry {
        .init(postID: postID ?? post, ownerID: ownerID ?? owner, revision: revision,
              points: points ?? [.init(latitude: 37.1, longitude: 127.1, segment: 0),
                                .init(latitude: 37.2, longitude: 127.2, segment: 0)])
    }
    private func read(_ rows: [FeedCardPreviewGeometry], revision: Int64? = 7) throws -> FeedCardPreviewRead {
        try SupabaseFeedCardPreviewReader.validated(metadata: metadata(revision: revision), geometry: rows,
                                                   postID: post, ownerID: owner, date: date)
    }
    func testCardGeometryDecoderAndMinimalFields() throws {
        let json = """
        [{"post_id":"\(post)","owner_id":"\(owner)","revision":7,"authorized_route_geometry":[{"latitude":37.1,"longitude":127.1,"segment":0},{"latitude":37.2,"longitude":127.2,"segment":1}]}]
        """
        let rows = try JSONDecoder().decode([FeedCardPreviewGeometry].self, from: Data(json.utf8))
        let result = try read(rows)
        XCTAssertEqual(result.postID, post); XCTAssertEqual(result.ownerID, owner)
        XCTAssertEqual(result.presentation.title, "시험 제목")
        XCTAssertEqual(result.presentation.caption, "시험 설명")
        XCTAssertEqual(result.presentation.device, "시험 기기")
        XCTAssertEqual(result.presentation.location, "시험 지역")
        let route = try XCTUnwrap(result.presentation.route)
        XCTAssertTrue(route.privacyMaskApplied)
        XCTAssertEqual(route.coordinates.map(\.segmentIndex), [0, 1])
        XCTAssertTrue(route.coordinates.allSatisfy { $0.timestamp == nil && $0.altitude == nil })
        XCTAssertEqual(route.totalDistanceMeters, 0, "Never bridge masked route segments")
        let pointKeys = Set(Mirror(reflecting: rows[0].points[0]).children.compactMap(\.label))
        XCTAssertEqual(pointKeys, Set(["latitude", "longitude", "segment"]))
        XCTAssertEqual(SupabaseFeedCardPreviewReader.metadataColumns,
                       "id,user_id,title,body,route_summary,updated_at,shared_detail_revision")
    }
    func testAbsentOrEmptyRoutePreservesMetadata() throws {
        XCTAssertNil(try read([]).presentation.route)
        let result = try read([geometry(points: [])])
        XCTAssertNil(result.presentation.route)
        XCTAssertEqual(result.presentation.title, "시험 제목")
        XCTAssertEqual(result.presentation.location, "시험 지역")
        XCTAssertNil(try read([], revision: nil).presentation.route)
    }
    func testRejectsWrongOwnerPostRevisionAndDuplicateGeometry() {
        XCTAssertThrowsError(try read([geometry(ownerID: UUID())]))
        XCTAssertThrowsError(try read([geometry(postID: UUID())]))
        XCTAssertThrowsError(try read([geometry(revision: 8)]))
        XCTAssertThrowsError(try read([geometry()], revision: nil))
        XCTAssertThrowsError(try read([geometry(), geometry()]))
    }
    func testRejectsInvalidCoordinatesAndTooManyPoints() {
        for point in [FeedCardPreviewGeometry.Point(latitude: .nan, longitude: 127, segment: 0),
                      .init(latitude: 37, longitude: .infinity, segment: 0),
                      .init(latitude: 91, longitude: 127, segment: 0),
                      .init(latitude: 37, longitude: -181, segment: 0),
                      .init(latitude: 37, longitude: 127, segment: -1)] {
            XCTAssertThrowsError(try read([geometry(points: [point])]))
        }
        XCTAssertThrowsError(try read([geometry(points: Array(repeating: .init(latitude: 37, longitude: 127, segment: 0), count: 4097))]))
    }
    func testRejectsWrongMetadataIdentity() {
        let bad = FeedCardPreviewMetadata(id: UUID(), ownerID: owner, title: "wrong", body: nil,
                                           routeSummary: nil, updatedAt: nil, detailRevision: 7)
        XCTAssertThrowsError(try SupabaseFeedCardPreviewReader.validated(metadata: bad, geometry: [], postID: post, ownerID: owner, date: date))
    }
}


@MainActor
final class FeedBatchCardPreviewWireTests: XCTestCase {
    private let post = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let owner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private var fixture: [String: Any] {
        ["version": 1, "state": "ready", "post_id": post.uuidString, "owner_id": owner.uuidString,
         "post_revision": "2026-11-17T12:34:56.123Z", "snapshot_revision": 2, "consent_revision": 3,
         "serializer_version": 1, "title": "한강 달리기", "caption": "천천히 달렸어요",
         "device_name": "Apple Watch", "location_name": "한강", "route_state": "ready",
         "authorized_route_geometry": [["latitude": 37.5, "longitude": 127.0, "segment": 0],
                                        ["latitude": 37.6, "longitude": 127.1, "segment": 1]]]
    }
    private func decode(_ raw: [String: Any]) throws -> FeedBatchCardPreviewWire {
        try JSONDecoder().decode(FeedBatchCardPreviewWire.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func validate(_ raw: [String: Any]) throws -> FeedLinkedCardPresentation? {
        try decode(raw).validated(postID: post, ownerID: owner, date: Date(timeIntervalSince1970: 1_700_000_000))
    }
    func testPreservesMapMetadataAndMaskedSegmentBoundary() throws {
        let value = try XCTUnwrap(validate(fixture))
        XCTAssertEqual(value.title, "한강 달리기")
        XCTAssertEqual(value.caption, "천천히 달렸어요")
        XCTAssertEqual(value.device, "Apple Watch")
        XCTAssertEqual(value.location, "한강")
        let route = try XCTUnwrap(value.route)
        XCTAssertTrue(route.privacyMaskApplied)
        XCTAssertEqual(route.coordinates.count, 2)
        XCTAssertEqual(route.totalDistanceMeters, 0)
        XCTAssertTrue(route.coordinates.allSatisfy { $0.timestamp == nil && $0.altitude == nil })
    }
    func testDeniedAndMetadataWithoutRoute() throws {
        XCTAssertNil(try validate(["version": 1, "state": "unavailable"]))
        var raw = fixture
        raw["route_state"] = "unavailable"; raw["authorized_route_geometry"] = []
        XCTAssertThrowsError(try validate(raw))
        raw["snapshot_revision"] = NSNull(); raw["consent_revision"] = NSNull()
        let value = try XCTUnwrap(validate(raw))
        XCTAssertNil(value.route)
        XCTAssertEqual(value.title, "한강 달리기")
        XCTAssertEqual(value.location, "한강")
        raw["title"] = NSNull(); raw["caption"] = NSNull()
        raw["device_name"] = NSNull(); raw["location_name"] = NSNull()
        XCTAssertNotNil(try validate(raw))
    }
    func testRejectsUnknownMissingAndMalformedFields() throws {
        var raw = fixture; raw["heart_rate"] = [120]
        XCTAssertThrowsError(try validate(raw))
        raw = fixture; raw.removeValue(forKey: "caption")
        XCTAssertThrowsError(try validate(raw))
        raw = fixture; raw["version"] = 2
        XCTAssertThrowsError(try validate(raw))
        raw = fixture; raw["serializer_version"] = 2
        XCTAssertThrowsError(try validate(raw))
        raw = fixture; raw["post_revision"] = "yesterday"
        XCTAssertThrowsError(try validate(raw))
        raw = fixture; raw["title"] = String(repeating: "가", count: 513)
        XCTAssertNotNil(try validate(raw))
        XCTAssertThrowsError(try validate(["version": 1, "state": "unavailable", "title": "leak"]))
    }
    func testRejectsWrongIdentityAndRevisions() throws {
        for key in ["owner_id", "post_id"] {
            var raw = fixture; raw[key] = UUID().uuidString
            XCTAssertThrowsError(try validate(raw))
        }
        for key in ["snapshot_revision", "consent_revision"] {
            for value in [0, -1, NSNull()] as [Any] {
                var raw = fixture; raw[key] = value
                XCTAssertThrowsError(try validate(raw))
            }
        }
    }
    func testRejectsUnsafeGeometryAndUnexpectedMeasurement() throws {
        let bad: [[[String: Any]]] = [
            [["latitude": 91, "longitude": 0, "segment": 0], ["latitude": 0, "longitude": 0, "segment": 0]],
            [["latitude": 0, "longitude": 181, "segment": 0], ["latitude": 0, "longitude": 0, "segment": 0]],
            [["latitude": 0, "longitude": 0, "segment": -1], ["latitude": 0, "longitude": 0, "segment": 0]],
            [["latitude": 0, "longitude": 0, "segment": 1], ["latitude": 0, "longitude": 0, "segment": 0]],
            [["latitude": 0, "longitude": 0, "segment": 0, "timestamp": 123], ["latitude": 0, "longitude": 0, "segment": 0]],
            [], Array(repeating: ["latitude": 0, "longitude": 0, "segment": 0], count: 4097)
        ]
        for points in bad {
            var raw = fixture; raw["authorized_route_geometry"] = points
            XCTAssertThrowsError(try validate(raw))
        }
        var raw = fixture; raw["route_state"] = "unavailable"
        XCTAssertThrowsError(try validate(raw))
    }
}
