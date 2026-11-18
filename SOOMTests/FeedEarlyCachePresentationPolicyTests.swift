import XCTest
@testable import SOOM

final class FeedEarlyCachePresentationPolicyTests: XCTestCase {
    private let viewer = UUID()
    private var scope: FeedEarlyCachePresentationPolicy.Scope {
        .init(viewerID: viewer, accountGeneration: 2, durableEpoch: "epoch-a", policyVersion: 1)
    }
    private func started() -> FeedEarlyCachePresentationPolicy {
        var state = FeedEarlyCachePresentationPolicy()
        XCTAssertTrue(state.begin(id: UUID(), scope: scope, authenticatedViewer: viewer, mountedViewer: viewer, uptime: 100))
        return state
    }
    private func permits(_ state: FeedEarlyCachePresentationPolicy, at: Double = 101,
                         age: Double = 100, epoch: String = "epoch-a", active: Bool = true,
                         layout: Bool = true) -> Bool {
        state.permits(scope: scope, authenticatedViewer: viewer, mountedViewer: viewer,
                      isActiveFeed: active, uptime: at, cachedAge: age,
                      persistedEpoch: epoch, layoutMatches: layout)
    }
    func testPendingEntryRequiresAuthenticatedAndMountedSameAccount() {
        var state = FeedEarlyCachePresentationPolicy()
        XCTAssertFalse(permits(state))
        XCTAssertFalse(state.begin(id: UUID(), scope: scope, authenticatedViewer: nil, mountedViewer: viewer, uptime: 100))
        XCTAssertFalse(state.begin(id: UUID(), scope: scope, authenticatedViewer: viewer, mountedViewer: UUID(), uptime: 100))
        state = started()
        XCTAssertTrue(permits(state))
        XCTAssertFalse(state.permits(scope: scope, authenticatedViewer: UUID(), mountedViewer: viewer,
                                     isActiveFeed: true, uptime: 101, cachedAge: 100,
                                     persistedEpoch: "epoch-a", layoutMatches: true))
    }
    func testRepeatedMountAndNewCallbackCannotExtendFiveSecondDeadline() {
        var state = started()
        let id = state.entry!.id
        state.update(.checking, scope: scope)
        XCTAssertTrue(state.begin(id: id, scope: scope, authenticatedViewer: viewer, mountedViewer: viewer, uptime: 104))
        XCTAssertEqual(state.deadlineUptime, 105)
        XCTAssertTrue(permits(state, at: 104.999))
        XCTAssertFalse(permits(state, at: 105))
        XCTAssertFalse(state.begin(id: UUID(), scope: scope, authenticatedViewer: viewer, mountedViewer: viewer, uptime: 106))
        XCTAssertFalse(permits(state, at: 106))
    }
    func testDenyIsIrreversibleEvenWhenLateVerificationArrives() {
        var state = started()
        state.update(.denied, scope: scope)
        for value in [FeedEarlyCachePresentationPolicy.Verification.checking, .unresolved, .authorized] {
            state.update(value, scope: scope)
            XCTAssertFalse(permits(state))
            XCTAssertTrue(state.revoked)
        }
        XCTAssertFalse(state.begin(id: state.entry!.id, scope: scope, authenticatedViewer: viewer, mountedViewer: viewer, uptime: 102))
    }
    func testStorageAgeClockAndLayoutFailClosed() {
        let state = started()
        XCTAssertTrue(permits(state, age: 86_399.99))
        for age in [86_400.0, -1, Double.nan, .infinity, -.infinity] { XCTAssertFalse(permits(state, age: age)) }
        for time in [99.0, Double.nan, .infinity, -.infinity] { XCTAssertFalse(permits(state, at: time)) }
        XCTAssertFalse(permits(state, epoch: "epoch-b"))
        XCTAssertFalse(permits(state, active: false))
        XCTAssertFalse(permits(state, layout: false))
    }
    func testUnavailableAndAuthorizedNeverUsePendingPreview() {
        for verification in [FeedEarlyCachePresentationPolicy.Verification.unavailable, .authorized] {
            var state = started()
            state.update(verification, scope: scope)
            XCTAssertFalse(permits(state))
        }
        var state = started()
        state.revoke()
        XCTAssertFalse(permits(state))
    }
}
