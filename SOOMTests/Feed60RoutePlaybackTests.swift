import XCTest
import CoreLocation
import SwiftUI
import UIKit
@testable import SOOM

@MainActor final class Feed60RoutePlaybackTests: XCTestCase {
    func test72HostedMapMotionDuringIncomingValidation() async throws {
        let id = UUID()
        let points = (0..<5000).map { i in WorkoutRouteCoordinate(latitude: 37 + Double(i) * 0.00001,
            longitude: 127 + sin(Double(i) / 100) * 0.001, segmentIndex: i < 2500 ? 0 : 1) }
        let raw = WorkoutRoute(workoutId: id, source: .soomLocal, coordinates: points, totalDistanceMeters: 5600)
        let route = RoutePrivacyMasker().mask(route: raw)
        let record = PersistedWorkoutRoute(workoutId: id, sourceRaw: UnifiedDataSource.soomLocal.rawValue,
            encodedCoordinates: WorkoutRouteMapper().encodeCoordinates(points), coordinateCount: points.count,
            totalDistanceMeters: 5600)
        let data = try HealthCloudPayload(route: .init(record)).encoded()
        let row = HealthCloudRemoteRecord(kind: "route", recordKey: id.uuidString,
            payloadJSON: String(data: data, encoding: .utf8), isDeleted: false, version: 1, revision: 1)
        let rows = Array(repeating: row, count: 16)
        let model = Feed72HostedMotionModel()
        let host = UIHostingController(rootView: Feed72HostedMotionView(route: route, model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .seconds(1))
        for background in [false, true] {
            let probe = Feed72HostedDisplayProbe(); probe.start()
            let motion = Task { @MainActor in
                for step in 0..<60 {
                    guard !Task.isCancelled else { return }
                    model.progress = Double(step) / 60
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }
            try await Task.sleep(for: .milliseconds(200))
            let start = CFAbsoluteTimeGetCurrent()
            if background { let result = try await HealthCloudJournal.validateBatch(rows); XCTAssertEqual(result, Array(repeating: true, count: 16)) }
            else { for value in rows { try HealthCloudJournal.validate(kind: value.kind, key: value.recordKey, data: value.payloadData, deleted: value.isDeleted) } }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            try await Task.sleep(for: .milliseconds(500))
            motion.cancel(); probe.stop()
            XCTAssertGreaterThan(probe.frames, 5)
            print("SOOM72_HOSTED_MAP_ARRIVAL background=\(background) validation_ms=\(elapsed) frames=\(probe.frames) hitches=\(probe.hitches) worst_ms=\(probe.worst * 1000) renderer=\(MapboxAccessTokenAvailability.hasUsableToken)")
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    func test72PhotoOnlyAndMapDetailsUseSameLayerButTextOnlyDoesNot() {
        let photo = WorkoutPhotoReference(id: UUID(), storagePath: "synthetic/photo.jpg")
        XCTAssertTrue(WorkoutDetailSurfacePolicy.usesMediaSheet(route: nil, photos: [photo]))
        XCTAssertTrue(WorkoutDetailSurfacePolicy.usesMediaSheet(route: route(), photos: []))
        XCTAssertTrue(WorkoutDetailSurfacePolicy.usesMediaSheet(route: route(), photos: [photo]))
        XCTAssertFalse(WorkoutDetailSurfacePolicy.usesMediaSheet(route: nil, photos: []))
    }

    func test72RenderCacheReusesFramesAndImmediatelyInvalidatesRevocationOrChangedGeometry() {
        let cache = WorkoutRouteRenderCache(), original = route()
        let first = cache.resolve(original)
        for _ in 0..<160 { XCTAssertEqual(cache.resolve(original).route, first.route) }
        XCTAssertEqual(cache.preparations, 1)
        let changed = route(offset: 0.001)
        XCTAssertEqual(cache.resolve(changed).route, changed)
        XCTAssertEqual(cache.preparations, 2)
        XCTAssertNil(cache.resolve(nil).route)
        XCTAssertTrue(cache.resolve(nil).coordinates.isEmpty)
        XCTAssertEqual(cache.preparations, 3)
        XCTAssertEqual(cache.resolve(original).route, original)
        XCTAssertEqual(cache.preparations, 4)
    }

    func test72RenderPreparationBenchmark() {
        let points = (0..<5000).map { i in
            WorkoutRouteCoordinate(latitude: 37 + Double(i) * 0.00001,
                longitude: 127 + sin(Double(i) / 100) * 0.001, segmentIndex: i < 2500 ? 0 : 1)
        }
        let source = WorkoutRoute(workoutId: UUID(), source: .soomLocal,
            coordinates: points, totalDistanceMeters: 5600)
        let frames = 120
        let before = CFAbsoluteTimeGetCurrent()
        var oldCount = 0
        for _ in 0..<frames {
            let masked = RoutePrivacyMasker().mask(route: source)
            oldCount += masked.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }.count
            oldCount += masked.coordinateSegments.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }.count
        }
        let uncached = (CFAbsoluteTimeGetCurrent() - before) * 1000
        let cache = WorkoutRouteRenderCache(), start = CFAbsoluteTimeGetCurrent()
        var newCount = 0
        for _ in 0..<frames { let value = cache.resolve(source); newCount += value.coordinates.count + value.segments.count }
        let cached = (CFAbsoluteTimeGetCurrent() - start) * 1000
        XCTAssertEqual(newCount, oldCount); XCTAssertEqual(cache.preparations, 1)
        XCTAssertEqual(cache.resolve(source).route, RoutePrivacyMasker().mask(route: source))
        print("SOOM72_RENDER_PREPARATION frames=\(frames) points=5000 uncached_ms=\(uncached) cached_ms=\(cached)")
        let alreadyMasked = RoutePrivacyMasker().mask(route: source)
        let maskedStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            let value = RoutePrivacyMasker().mask(route: alreadyMasked)
            oldCount += value.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }.count
            oldCount += value.coordinateSegments.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }.count
        }
        let maskedBefore = (CFAbsoluteTimeGetCurrent() - maskedStart) * 1000
        let maskedCache = WorkoutRouteRenderCache(), maskedAfterStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames { let value = maskedCache.resolve(alreadyMasked); newCount += value.coordinates.count + value.segments.count }
        XCTAssertEqual(newCount, oldCount)
        print("SOOM72_ALREADY_MASKED_PREPARATION frames=\(frames) uncached_ms=\(maskedBefore) cached_ms=\((CFAbsoluteTimeGetCurrent()-maskedAfterStart)*1000)")
    }

    func testOrnamentOptionsAreNotReappliedForPlaybackFrames() {
        var revision = WorkoutRouteOrnamentRevision()
        XCTAssertTrue(revision.needsUpdate(topMargin: 24, compact: false, scale: false))
        for _ in 0..<120 { XCTAssertFalse(revision.needsUpdate(topMargin: 24, compact: false, scale: false)) }
        XCTAssertTrue(revision.needsUpdate(topMargin: 36, compact: false, scale: false))
        XCTAssertTrue(revision.needsUpdate(topMargin: 36, compact: true, scale: false))
        XCTAssertTrue(revision.needsUpdate(topMargin: 36, compact: true, scale: true))
        XCTAssertFalse(revision.needsUpdate(topMargin: 36, compact: true, scale: true))
    }

    func testGeometryRevisionIgnoresRepeatedFramesButDetectsInteriorAndGapChanges() {
        var cache = WorkoutRouteGeometryRevision()
        let a = CLLocationCoordinate2D(latitude: 37, longitude: 127)
        let b = CLLocationCoordinate2D(latitude: 37.01, longitude: 127.01)
        let c = CLLocationCoordinate2D(latitude: 37.02, longitude: 127.02)
        let first = cache.update(coordinates: [a, b, c], segments: [[a, b, c]])
        for _ in 0..<120 {
            XCTAssertEqual(cache.update(coordinates: [a, b, c], segments: [[a, b, c]]), first)
        }
        let gap = cache.update(coordinates: [a, b, c], segments: [[a], [b, c]])
        XCTAssertGreaterThan(gap, first, "A GPS gap must change geometry even with identical flattened points")
        let moved = CLLocationCoordinate2D(latitude: b.latitude + 0.000001, longitude: b.longitude)
        XCTAssertGreaterThan(cache.update(coordinates: [a, moved, c], segments: [[a], [moved, c]]), gap)
        XCTAssertGreaterThan(cache.update(coordinates: [], segments: []), gap)
    }

    private let viewer = UUID()
    private let visit = UUID()
    private let workout = UUID()
    private func scope(epoch: Int = 1, generation: Int = 1) -> FeedRoutePlaybackScope {
        .init(visitID: visit, viewerID: viewer, accountGeneration: generation, safetyRevision: 1, returnEpoch: epoch)
    }
    private func route(offset: Double = 0, radius: Double = 200) -> WorkoutRoute {
        .init(workoutId: workout, source: .soomLocal,
            coordinates: [.init(latitude: 37 + offset, longitude: 127), .init(latitude: 37.01, longitude: 127.01)],
            totalDistanceMeters: 1000, privacyMaskApplied: true, privacyMaskRadiusMeters: radius)
    }
    func testSameVisitClaimsOnceIncludingRecreatedRouteAndInterruptedPlayback() {
        let history = FeedRoutePlaybackHistory()
        let first = FeedRoutePlaybackHistory.Key(route: route())
        let reconstructed = FeedRoutePlaybackHistory.Key(route: route())
        XCTAssertEqual(first, reconstructed) // Regenerated model/sample UUIDs are irrelevant.
        XCTAssertFalse(history.hasPlayed(first, scope: scope()))
        XCTAssertTrue(history.claim(first, scope: scope()))
        XCTAssertTrue(history.hasPlayed(reconstructed, scope: scope()))
        XCTAssertFalse(history.claim(reconstructed, scope: scope()))
        XCTAssertEqual(history.count, 1)
    }
    func testNewEpochOrAccountGenerationMayStartOnlyOneNewVisit() {
        let history = FeedRoutePlaybackHistory(); let key = FeedRoutePlaybackHistory.Key(route: route())
        XCTAssertTrue(history.claim(key, scope: scope()))
        XCTAssertFalse(history.hasPlayed(key, scope: scope(epoch: 2)))
        XCTAssertTrue(history.claim(key, scope: scope(epoch: 2)))
        XCTAssertFalse(history.claim(key, scope: scope(epoch: 2)))
        XCTAssertTrue(history.claim(key, scope: scope(epoch: 2, generation: 2)))
        XCTAssertEqual(history.count, 1)
    }
    func testGeometryAndMaskChangesDoNotReusePlaybackReceipt() {
        let history = FeedRoutePlaybackHistory()
        XCTAssertTrue(history.claim(.init(route: route()), scope: scope()))
        XCTAssertTrue(history.claim(.init(route: route(offset: 0.001)), scope: scope()))
        XCTAssertTrue(history.claim(.init(route: route(radius: 300)), scope: scope()))
        XCTAssertEqual(history.count, 3)
    }
    func testHistoryRemainsBoundedAndResetDropsReceipts() {
        let history = FeedRoutePlaybackHistory(maximumCount: 2)
        for i in 0..<20 { XCTAssertTrue(history.claim(.init(route: route(offset: Double(i) / 1000)), scope: scope())) }
        XCTAssertEqual(history.count, 2)
        history.reset(); XCTAssertEqual(history.count, 0)
        XCTAssertTrue(history.claim(.init(route: route()), scope: scope()))
    }
    func testActivityGateStillRearmsAfterLeaving() {
        var gate = WorkoutCardRoutePlaybackGate(); let now = Date()
        gate.didStart(); gate.updatePresence(false, now: now)
        gate.updatePresence(true, now: now.addingTimeInterval(1))
        XCTAssertTrue(gate.canPlay)
    }
}

import Foundation
import CoreLocation
private enum Build67PlaybackReference {
    static func showsFinishMarker(progress: Double?) -> Bool {
        progress.map { $0 >= 1 } ?? true
    }

    struct Frame {
        let segments: [[CLLocationCoordinate2D]]
        let position: CLLocationCoordinate2D?
    }

    /// Reveals the route by distance, preserving GPS pause gaps between segments.
    static func frame(segments: [[CLLocationCoordinate2D]], progress: Double) -> Frame {
        let segments = segments.filter { $0.count >= 2 }
        guard let first = segments.first?.first else { return Frame(segments: [], position: nil) }
        let lengths = segments.map { segment in
            zip(segment, segment.dropFirst()).map { distance($0, $1) }
        }
        let total = lengths.flatMap { $0 }.reduce(0, +)
        guard total > 0 else { return Frame(segments: [], position: first) }
        var remaining = total * min(max(progress, 0), 1)
        var drawn: [[CLLocationCoordinate2D]] = []
        var position = first

        for (segment, legLengths) in zip(segments, lengths) {
            var revealed = [segment[0]]
            position = segment[0]
            for (index, legLength) in legLengths.enumerated() {
                if remaining >= legLength {
                    revealed.append(segment[index + 1])
                    position = segment[index + 1]
                    remaining -= legLength
                } else {
                    if remaining > 0, legLength > 0 {
                        let fraction = remaining / legLength
                        let end = segment[index + 1]
                        position = CLLocationCoordinate2D(
                            latitude: position.latitude + (end.latitude - position.latitude) * fraction,
                            longitude: position.longitude + (end.longitude - position.longitude) * fraction
                        )
                        revealed.append(position)
                    }
                    remaining = 0
                    break
                }
            }
            if revealed.count >= 2 { drawn.append(revealed) }
            if remaining <= 0 { break }
        }
        return Frame(segments: drawn, position: position)
    }

    private static func distance(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }
}


@MainActor extension Feed60RoutePlaybackTests {
    func test68PreparedPlaybackMatches67EveryFrameWithoutBridgingSegments() {
        let points = (0..<1000).map { CLLocationCoordinate2D(latitude:37 + Double($0) * 0.00001, longitude:127) }
        let variants: [[[CLLocationCoordinate2D]]] = [[], [[]], [[points[0]]], [[points[0],points[0]]], [Array(points.prefix(500)),Array(points.suffix(500))]]
        for segments in variants {
            let prepared = WorkoutRoutePlayback.Prepared(segments)
            for n in -1...121 {
                let progress = Double(n) / 120
                let old = Build67PlaybackReference.frame(segments: segments, progress: progress)
                let new = WorkoutRoutePlayback.frame(prepared: prepared, progress: progress)
                XCTAssertEqual(old.segments.map { $0.count }, new.segments.map { $0.count })
                for (a,b) in zip(old.segments.flatMap { $0 }, new.segments.flatMap { $0 }) {
                    XCTAssertEqual(a.latitude,b.latitude,accuracy:1e-9); XCTAssertEqual(a.longitude,b.longitude,accuracy:1e-9)
                }
                XCTAssertEqual(old.position == nil,new.position == nil)
                if let a = old.position, let b = new.position {
                    XCTAssertEqual(a.latitude,b.latitude,accuracy:1e-9)
                    XCTAssertEqual(a.longitude,b.longitude,accuracy:1e-9)
                }
            }
        }
    }
}

@MainActor private final class Feed72HostedMotionModel: ObservableObject { @Published var progress = 0.0 }
private struct Feed72HostedMotionView: View {
    let route: WorkoutRoute
    @ObservedObject var model: Feed72HostedMotionModel
    var body: some View {
        WorkoutDetailMapView(route: route, fallbackStyle: StaticRouteFallbackStyle(workoutType: .running),
            tint: SOOMColor.accent, playbackProgress: model.progress).frame(width: 390, height: 600)
    }
}
@MainActor private final class Feed72HostedDisplayProbe: NSObject {
    private var display: CADisplayLink?
    private var last: Double?
    var frames = 0, hitches = 0
    var worst = 0.0
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common); display = link
    }
    func stop() { display?.invalidate(); display = nil }
    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard let last else { return }
        let gap = link.timestamp - last; frames += 1; worst = max(worst, gap)
        if gap > max(1.0 / 120, link.targetTimestamp - link.timestamp) * 1.5 { hitches += 1 }
    }
}
