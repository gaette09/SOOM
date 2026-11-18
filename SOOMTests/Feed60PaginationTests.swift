import XCTest
@testable import SOOM

final class Feed60PaginationTests: XCTestCase {
    private let ids = (0..<16).map { _ in UUID() }
    private func receipt(_ boundary: UUID, generation: Int = 1, safety: Int = 2,
                         epoch: Int = 3, wake: Int = 0) -> Feed60PaginationPrefetchReceipt {
        .init(boundaryID: boundary, accountGeneration: generation, safetyRevision: safety,
              returnEpoch: epoch, wakeRevision: wake)
    }

    func testEmptyPageDoesNotInventTailAndUsesVisibleFooter() {
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: [], visibleIDs: [ids[0]]))
        XCTAssertFalse(Feed60PaginationPolicy.hasDemand(footerVisible: false, nearTail: false, receipt: nil, previous: nil))
        XCTAssertTrue(Feed60PaginationPolicy.hasDemand(footerVisible: true, nearTail: false, receipt: nil, previous: nil))
    }

    func testOneAndTwoCardPagesOnlyPrefetchWhenActuallyVisible() {
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: [ids[0]], visibleIDs: []))
        XCTAssertTrue(Feed60PaginationPolicy.isNearTail(itemIDs: [ids[0]], visibleIDs: [ids[0]]))
        XCTAssertTrue(Feed60PaginationPolicy.isNearTail(itemIDs: Array(ids.prefix(2)), visibleIDs: [ids[0]]))
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: Array(ids.prefix(2)), visibleIDs: [ids[2]]))
    }

    func testOnlyLastTwoRowsTriggerNotLazyConstructionOrThirdLast() {
        let page = Array(ids.prefix(8))
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: page, visibleIDs: []))
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: page, visibleIDs: [ids[5]]))
        XCTAssertTrue(Feed60PaginationPolicy.isNearTail(itemIDs: page, visibleIDs: [ids[6]]))
        XCTAssertTrue(Feed60PaginationPolicy.isNearTail(itemIDs: page, visibleIDs: [ids[7]]))
    }

    func testAppendingPageStopsPrefetchUntilNewTailIsReached() {
        let visible: Set<UUID> = [ids[6], ids[7]]
        XCTAssertTrue(Feed60PaginationPolicy.isNearTail(itemIDs: Array(ids.prefix(8)), visibleIDs: visible))
        XCTAssertFalse(Feed60PaginationPolicy.isNearTail(itemIDs: ids, visibleIDs: visible))
        XCTAssertFalse(Feed60PaginationPolicy.hasDemand(footerVisible: false, nearTail: false,
            receipt: receipt(ids[15]), previous: receipt(ids[7])))
    }

    func testFilteredPageWithUnchangedTailDoesNotChainSpeculativeReads() {
        let boundary = receipt(ids[7])
        XCTAssertTrue(Feed60PaginationPolicy.hasDemand(footerVisible: false, nearTail: true,
            receipt: boundary, previous: nil))
        // The successful server-page revision is intentionally not part of
        // the boundary receipt: zero visible additions cannot trigger a loop.
        XCTAssertFalse(Feed60PaginationPolicy.hasDemand(footerVisible: false, nearTail: true,
            receipt: boundary, previous: boundary))
        XCTAssertTrue(Feed60PaginationPolicy.hasDemand(footerVisible: true, nearTail: true,
            receipt: boundary, previous: boundary), "A genuinely visible footer continues filtered pages")
    }

    func testCancellationWakeAndNewAuthorizationAllowFreshAttempt() {
        let old = receipt(ids[7])
        for next in [receipt(ids[7], wake: 1), receipt(ids[7], generation: 2),
                     receipt(ids[7], safety: 3), receipt(ids[7], epoch: 4)] {
            XCTAssertTrue(Feed60PaginationPolicy.hasDemand(footerVisible: false, nearTail: true,
                receipt: next, previous: old))
        }
    }

    func testPendingFailureInactiveRefreshInflightAndExhaustionEachStopRequest() {
        XCTAssertTrue(Feed60PaginationPolicy.canRequest(active: true, ready: true, initialLoading: false,
            pageLoading: false, hasMore: true, hasFailure: false))
        for disabled in 0..<6 {
            XCTAssertFalse(Feed60PaginationPolicy.canRequest(active: disabled != 0, ready: disabled != 1,
                initialLoading: disabled == 2, pageLoading: disabled == 3,
                hasMore: disabled != 4, hasFailure: disabled == 5))
        }
    }

    func testReadinessTransitionAndCancelledCleanupChangeTaskIdentity() {
        func key(ready: Bool = true, wake: Int = 0) -> Feed60PaginationTaskKey {
            .init(pageRevision: 1, wakeRevision: wake, accountGeneration: 1, safetyRevision: 2,
                returnEpoch: 3, boundaryID: ids[7], active: true, ready: ready,
                initialLoading: false, hasMore: true, hasFailure: false, visibilityRevision: 1)
        }
        XCTAssertNotEqual(key(ready: false), key())
        XCTAssertNotEqual(key(), key(wake: 1))
        XCTAssertEqual(key(), key(), "Page loading is deliberately not a task-identity field")
    }
    func testOldFooterObservationCannotAuthorizeAppendedPage() {
        let old = Feed60PaginationFooterReceipt(boundaryID: ids[7], pageRevision: 1)
        let appended = Feed60PaginationFooterReceipt(boundaryID: ids[15], pageRevision: 2)
        XCTAssertTrue(Feed60PaginationPolicy.footerIsCurrent(visible: old, current: old, displayIsCurrent: true))
        XCTAssertFalse(Feed60PaginationPolicy.footerIsCurrent(visible: old, current: appended, displayIsCurrent: true))
        XCTAssertFalse(Feed60PaginationPolicy.hasDemand(
            footerVisible: Feed60PaginationPolicy.footerIsCurrent(visible: old, current: appended, displayIsCurrent: true),
            nearTail: Feed60PaginationPolicy.isNearTail(itemIDs: ids, visibleIDs: [ids[6], ids[7]]),
            receipt: receipt(ids[15]), previous: receipt(ids[7])))
    }

    func testSourceAppendBeforeDisplayedStateAdoptsCannotReuseOldTailOrFooter() {
        let oldIDs = Array(ids.prefix(8))
        let old = Feed60PaginationFooterReceipt(boundaryID: ids[7], pageRevision: 2)
        let current = Feed60PaginationPolicy.displayIsCurrent(sourceIDs: ids, displayedIDs: oldIDs)
        XCTAssertFalse(current)
        XCTAssertFalse(Feed60PaginationPolicy.footerIsCurrent(visible: old, current: old, displayIsCurrent: current))
        XCTAssertFalse(Feed60PaginationPolicy.canRequest(active: true, ready: current,
            initialLoading: false, pageLoading: false, hasMore: true, hasFailure: false))
        XCTAssertTrue(Feed60PaginationPolicy.displayIsCurrent(sourceIDs: ids, displayedIDs: ids))
    }

    func testFilteredEmptyPageRequiresFreshFooterGeometryThenContinues() {
        for boundary in [Optional<UUID>.none, ids[7]] {
            let old = Feed60PaginationFooterReceipt(boundaryID: boundary, pageRevision: 1)
            let next = Feed60PaginationFooterReceipt(boundaryID: boundary, pageRevision: 2)
            XCTAssertFalse(Feed60PaginationPolicy.footerIsCurrent(visible: old, current: next, displayIsCurrent: true))
            XCTAssertTrue(Feed60PaginationPolicy.footerIsCurrent(visible: next, current: next, displayIsCurrent: true))
            XCTAssertTrue(Feed60PaginationPolicy.hasDemand(footerVisible: true, nearTail: false,
                receipt: nil, previous: nil), "Actual visible empty footer must still drain filtered pages")
        }
    }

    func testFooterAbsenceReorderingAndBoundaryChangeAreNotCurrent() {
        let footer = Feed60PaginationFooterReceipt(boundaryID: ids[7], pageRevision: 1)
        XCTAssertFalse(Feed60PaginationPolicy.footerIsCurrent(visible: nil, current: footer, displayIsCurrent: true))
        XCTAssertFalse(Feed60PaginationPolicy.displayIsCurrent(sourceIDs: ids, displayedIDs: Array(ids.reversed())))
        let changedBoundary = Feed60PaginationFooterReceipt(boundaryID: ids[15], pageRevision: 1)
        XCTAssertFalse(Feed60PaginationPolicy.footerIsCurrent(visible: footer, current: changedBoundary, displayIsCurrent: true))
    }

    func testComplete238RowPageHasNoPaginationVisibilityMutations() {
        let complete = (0..<238).map { _ in UUID() }
        for id in complete {
            XCTAssertFalse(Feed60PaginationPolicy.shouldTrack(cardID: id, itemIDs: complete, hasMore: false))
            XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [id],
                itemIDs: complete, hasMore: false, current: []))
        }
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [],
            itemIDs: complete, hasMore: false, current: []))
    }

    func testOnlyCurrentTailUpdatesVisibilityAndDuplicateCallbacksAreNoOps() {
        let firstPage = Array(ids.prefix(8))
        XCTAssertFalse(Feed60PaginationPolicy.shouldTrack(cardID: ids[5], itemIDs: firstPage, hasMore: true))
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [ids[4], ids[5]],
            itemIDs: firstPage, hasMore: true, current: []))
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [ids[5], ids[6]],
            itemIDs: firstPage, hasMore: true, current: []), Set([ids[6]]))
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [ids[6], ids[5], ids[6]],
            itemIDs: firstPage, hasMore: true, current: [ids[6]]))
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [ids[6], ids[7]],
            itemIDs: ids, hasMore: true, current: [ids[6]]), Set<UUID>(), "Old tail is discarded after append")
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [ids[13], ids[14]],
            itemIDs: ids, hasMore: true, current: []), Set([ids[14]]))
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [],
            itemIDs: ids, hasMore: true, current: [ids[14]]), Set<UUID>())
    }

    func testOuterScrollTargetObservationIgnoresNestedOrUnknownIDsAndIsBounded() {
        let unrelated = (0..<40).map { _ in UUID() }
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: unrelated,
            itemIDs: ids, hasMore: true, current: []))
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: unrelated + ids,
            itemIDs: ids, hasMore: true, current: []), Set(ids.suffix(2)))
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: Array(ids.reversed()) + unrelated,
            itemIDs: ids, hasMore: true, current: Set(ids.suffix(2))))
    }

    func testOuterScrollObservationClearsOnExhaustionWithoutRepeatedWrites() {
        XCTAssertEqual(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: ids,
            itemIDs: ids, hasMore: false, current: Set(ids.suffix(2))), Set<UUID>())
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: ids,
            itemIDs: ids, hasMore: false, current: []))
        XCTAssertNil(Feed60PaginationPolicy.targetVisibilityUpdate(visibleIDs: [],
            itemIDs: [], hasMore: true, current: []))
    }

}
