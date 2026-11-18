import XCTest
import CoreLocation
@testable import SOOM

@MainActor final class Feed60RoutePlaybackTests: XCTestCase {
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
