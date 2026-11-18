import XCTest
import Combine
@testable import SOOM

@MainActor
final class FeedPostManagementTests: XCTestCase {
    func testPageGeometrySurvivesRowRecreationButNotScopeOrLayoutChanges() {
        let store = FeedCardGeometryStore(maximumCount: 2)
        let scope = FeedCardGeometryScope(viewerID: UUID(), generation: 1, safetyRevision: 2)
        let key = FeedCardGeometryKey(cardID: UUID(), width: 393, font: "large", kind: "projection")
        XCTAssertNil(store.height(for: key, scope: scope))
        XCTAssertTrue(store.record(600, for: key, scope: scope))
        store.reset(to: scope) // Host may receive its initial callback after the row.
        XCTAssertEqual(store.height(for: key, scope: scope), 600)
        XCTAssertFalse(store.record(600.25, for: key, scope: scope))
        XCTAssertFalse(store.record(43, for: key, scope: scope))
        let legacy = FeedCardGeometryKey(cardID: key.cardID, width: 393, font: "large", kind: "legacy")
        XCTAssertNil(store.height(for: legacy, scope: scope))
        XCTAssertNil(store.height(for: .init(cardID: key.cardID, width: 852, font: "large", kind: "projection"), scope: scope))
        XCTAssertNil(store.height(for: .init(cardID: key.cardID, width: 393, font: "accessibility", kind: "projection"), scope: scope))
        let changed = FeedCardGeometryScope(viewerID: scope.viewerID, generation: 1, safetyRevision: 3)
        store.reset(to: changed)
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.record(600, for: key, scope: scope))
        XCTAssertNil(store.height(for: key, scope: changed))
    }

    func testBurstOfCardsAndDuplicateWaiterShareOneAuthoritativeBatch() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope(), gate = FeedAccessTestGate()
        let ids = (0..<8).map { _ in UUID() }
        var queries = 0
        let load: @MainActor ([UUID]) async throws -> [FeedPostAccess] = { rows in
            queries += 1
            await gate.wait()
            return rows.map { FeedPostAccess(id: $0, authorID: scope.viewerID, visibility: .publicPost) }
        }
        let cards = ids.map { id in Task { try await batcher.receipt(for: id, scope: scope, load: load) } }
        while !gate.started { await Task.yield() }
        let duplicate = Task { try await batcher.receipt(for: ids[0], scope: scope, load: load) }
        while batcher.statistics.joinedRequests == 0 { await Task.yield() }
        gate.resume()
        for (id, card) in zip(ids, cards) { let receipt = try await card.value; XCTAssertEqual(receipt?.id, id) }
        let duplicateReceipt = try await duplicate.value
        XCTAssertEqual(duplicateReceipt?.id, ids[0])
        XCTAssertEqual(queries, 1)
        XCTAssertEqual(batcher.statistics.requests, 9)
        XCTAssertEqual(batcher.statistics.joinedRequests, 1)
        XCTAssertEqual(batcher.statistics.requestedRows, 8)
        XCTAssertEqual(batcher.inFlightCount, 0)
    }

    func testCompletedReceiptIsNeverReusedForNextAppearance() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope(), id = UUID()
        var queries = 0
        let first = try await batcher.receipt(for: id, scope: scope) { rows in
            queries += 1
            return rows.map { FeedPostAccess(id: $0, authorID: scope.viewerID, visibility: .publicPost) }
        }
        XCTAssertNotNil(first)
        let revoked = try await batcher.receipt(for: id, scope: scope) { _ in queries += 1; return [] }
        XCTAssertNil(revoked)
        XCTAssertEqual(queries, 2)
        XCTAssertEqual(batcher.statistics.batches, 2)
    }

    func testBatchScopesSeparateViewerGenerationSafetyAndClient() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope(), id = UUID(), anotherClient = NSObject()
        let scopes = [scope,
            FeedPostAccessScope(clientIdentity: scope.clientIdentity, viewerID: UUID(), accountGeneration: 0, safetyRevision: 0),
            FeedPostAccessScope(clientIdentity: scope.clientIdentity, viewerID: scope.viewerID, accountGeneration: 1, safetyRevision: 0),
            FeedPostAccessScope(clientIdentity: scope.clientIdentity, viewerID: scope.viewerID, accountGeneration: 0, safetyRevision: 1),
            FeedPostAccessScope(clientIdentity: ObjectIdentifier(anotherClient), viewerID: scope.viewerID, accountGeneration: 0, safetyRevision: 0)]
        var queries = 0
        let checks = scopes.map { key in Task {
            try await batcher.receipt(for: id, scope: key) { rows in
                queries += 1
                return rows.map { FeedPostAccess(id: $0, authorID: key.viewerID, visibility: .publicPost) }
            }
        } }
        for check in checks { _ = try await check.value }
        XCTAssertEqual(queries, 5)
        XCTAssertEqual(batcher.statistics.joinedRequests, 0)
        withExtendedLifetime(anotherClient) {}
    }

    func testBatchBoundDeliversAllRowsWithoutUnboundedQuery() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope()
        let ids = (0..<40).map { _ in UUID() }
        var sizes: [Int] = []
        let checks = ids.map { id in Task {
            try await batcher.receipt(for: id, scope: scope) { rows in
                sizes.append(rows.count)
                return rows.map { FeedPostAccess(id: $0, authorID: scope.viewerID, visibility: .publicPost) }
            }
        } }
        for (id, check) in zip(ids, checks) { let result = try await check.value; XCTAssertEqual(result?.id, id) }
        XCTAssertEqual(sizes, [32, 8])
        XCTAssertEqual(batcher.statistics.requestedRows, 40)
        XCTAssertEqual(batcher.inFlightCount, 0)
    }

    func testFailedBatchFailsEveryWaiterAndLaterRequestRechecks() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope()
        let ids = (0..<3).map { _ in UUID() }
        let checks = ids.map { id in Task {
            try await batcher.receipt(for: id, scope: scope) { _ in throw TestFailure.offline }
        } }
        for check in checks {
            do { _ = try await check.value; XCTFail("Failed authorization cannot return content") }
            catch TestFailure.offline {} catch { XCTFail("Unexpected: \(error)") }
        }
        XCTAssertEqual(batcher.statistics.failedBatches, 1)
        XCTAssertEqual(batcher.inFlightCount, 0)
        let retry = try await batcher.receipt(for: ids[0], scope: scope) { rows in
            rows.map { FeedPostAccess(id: $0, authorID: scope.viewerID, visibility: .publicPost) }
        }
        XCTAssertNotNil(retry)
        XCTAssertEqual(batcher.statistics.batches, 2)
    }

    func testDuplicateServerRowsRejectAmbiguousPermission() async {
        let batcher = FeedPostAccessBatcher(), scope = accessScope(), id = UUID()
        do {
            _ = try await batcher.receipt(for: id, scope: scope) { _ in
                let receipt = FeedPostAccess(id: id, authorID: scope.viewerID, visibility: .publicPost)
                return [receipt, receipt]
            }
            XCTFail("An ambiguous response cannot authorize content")
        } catch {}
        XCTAssertEqual(batcher.statistics.failedBatches, 1)
        XCTAssertEqual(batcher.inFlightCount, 0)
    }

    func testRowsAppearingDuringLiveBatchWaitForTheirOwnFreshRead() async throws {
        let batcher = FeedPostAccessBatcher(), scope = accessScope(), gate = FeedAccessTestGate()
        let firstID = UUID(), laterID = UUID()
        var queries = 0
        let load: @MainActor ([UUID]) async throws -> [FeedPostAccess] = { rows in
            queries += 1
            if queries == 1 { await gate.wait() }
            return rows.map { FeedPostAccess(id: $0, authorID: scope.viewerID, visibility: .publicPost) }
        }
        let first = Task { try await batcher.receipt(for: firstID, scope: scope, load: load) }
        while !gate.started { await Task.yield() }
        let later = Task { try await batcher.receipt(for: laterID, scope: scope, load: load) }
        await Task.yield()
        gate.resume()
        let firstReceipt = try await first.value, laterReceipt = try await later.value
        XCTAssertEqual(firstReceipt?.id, firstID)
        XCTAssertEqual(laterReceipt?.id, laterID)
        XCTAssertEqual(queries, 2)
    }

    func testInitialListSnapshotIsLayoutOnlyUntilFreshServerReceipt() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        setup.remote.onAccess = { await gate.wait() }
        let first = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        XCTAssertTrue(setup.model.canRetainArticle)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.showsAccessProgress)
        gate.resume(); await first.value
        XCTAssertTrue(setup.model.canDisplayContent)
        XCTAssertTrue(setup.remote.fetchOwners.isEmpty)
    }

    func testChangedFullRowWithoutUpdatedAtChangeRequiresFreshArticle() async {
        let setup = makeSetup(authorID: UUID())
        setup.remote.replace(title: "타임스탬프 없이 변경된 제목", body: "새 본문")
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(setup.model.title, "타임스탬프 없이 변경된 제목")
        XCTAssertEqual(setup.model.description, "새 본문")
        XCTAssertEqual(setup.remote.accessOwners.count, 1)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertEqual(setup.model.appearanceStatistics.listSnapshotsReused, 0)
    }

    func testMissingSnapshotProvenanceRequiresOriginalFullRead() async {
        let setup = makeSetup(authorID: UUID())
        var item = setup.model.item
        item.serverPostSnapshot = nil
        let model = FeedPostManagement(item: item, remote: setup.remote, safetyStore: setup.safety)
        XCTAssertFalse(model.canRetainArticle)
        await model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertTrue(model.canDisplayContent)
        XCTAssertTrue(model.canRetainArticle)
    }

    func testInitialDeniedRowDoesNotHydrateOrDisplayListSnapshot() async {
        let setup = makeSetup(authorID: UUID())
        setup.remote.post = nil
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertTrue(setup.model.hasLoaded, "Failed checks must finish and expose retry UI, not spin forever")
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertTrue(setup.remote.fetchOwners.isEmpty)
    }

    func testFastRepeatCheckPublishesOnlyAccessGateTransitions() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        var publications = 0
        let observation = setup.model.objectWillChange.sink { publications += 1 }
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(publications, 2, "Avoid no-op progress reset/loaded/article updates on a fast check")
        withExtendedLifetime(observation) {}
    }

    func testInsetArticleMeasurementReservesHeightInViewportCoordinates() {
        var layout = SOOMFeedCardLayoutReservation<String>()
        XCTAssertTrue(layout.record(CGSize(width: 328, height: 350), viewportWidth: 360, layoutToken: "normal"))
        XCTAssertEqual(layout.height(forViewportWidth: 360, layoutToken: "normal"), 350)
        XCTAssertFalse(layout.record(CGSize(width: 328, height: 350.2), viewportWidth: 360, layoutToken: "normal"))
        XCTAssertEqual(layout.height(forViewportWidth: 360, layoutToken: "normal"), 350)
        XCTAssertNil(layout.height(forViewportWidth: 390, layoutToken: "normal"))
        XCTAssertNil(layout.height(forViewportWidth: 360, layoutToken: "accessibility"))
    }

    func testInvalidLayoutCannotAssociateOldHeightWithNewTextSize() {
        var layout = SOOMFeedCardLayoutReservation<String>()
        _ = layout.record(CGSize(width: 328, height: 350), viewportWidth: 360, layoutToken: "normal")
        XCTAssertFalse(layout.record(CGSize(width: 328, height: CGFloat.nan), viewportWidth: 360, layoutToken: "accessibility"))
        XCTAssertNil(layout.height(forViewportWidth: 360, layoutToken: "accessibility"))
        XCTAssertTrue(layout.record(CGSize(width: 328, height: 430), viewportWidth: 360, layoutToken: "accessibility"))
        XCTAssertEqual(layout.height(forViewportWidth: 360, layoutToken: "accessibility"), 430)
    }

    func testMountedPresentationScrollReentryDoesNotReadAgain() async {
        let setup = makeSetup(authorID: UUID())
        for _ in 0..<30 { await setup.model.refreshForVisiblePresentation(revalidationRevision: 7) }
        XCTAssertEqual(setup.remote.accessOwners.count, 1)
        XCTAssertEqual(setup.remote.fetchOwners.count, 0)
        XCTAssertTrue(setup.model.canDisplayContent)
        await setup.model.refreshForVisiblePresentation(revalidationRevision: 8)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1, "Real return must revalidate")
        setup.model.invalidateAppearanceVerification()
        await setup.model.refreshForVisiblePresentation(revalidationRevision: 8)
        XCTAssertEqual(setup.remote.fetchOwners.count, 2)
    }

    func testPresentationNeverReusesDeniedOrRevokedState() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForVisiblePresentation(revalidationRevision: 1)
        setup.remote.post = nil
        setup.model.invalidateAppearanceVerification()
        await setup.model.refreshForVisiblePresentation(revalidationRevision: 1)
        XCTAssertFalse(setup.model.canDisplayContent)
        let count = setup.remote.fetchOwners.count
        await setup.model.refreshForVisiblePresentation(revalidationRevision: 1)
        XCTAssertGreaterThan(setup.remote.fetchOwners.count, count, "Failure can explicitly retry")
    }

    func testScrollReappearancesUseFreshAccessReadsWithoutReloadingArticle() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        for _ in 0..<3 { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        XCTAssertEqual(setup.remote.fetchOwners.count, 0)
        XCTAssertEqual(setup.remote.accessOwners.count, 4)
        XCTAssertEqual(setup.model.appearanceStatistics.listSnapshotsReused, 1)
        XCTAssertTrue(setup.model.hasLoaded)
        XCTAssertTrue(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.showsAccessProgress)
    }

    func testPendingAccessKeepsArticleStateButCannotDisplayOldPermission() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let check = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        XCTAssertTrue(setup.model.isAvailable, "Stored article state is not reinitialized by scrolling")
        XCTAssertTrue(setup.model.hasLoaded)
        XCTAssertFalse(setup.model.canDisplayContent, "Old permission cannot display content during a live check")
        XCTAssertFalse(setup.model.showsAccessProgress)
        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertTrue(setup.model.showsAccessProgress)
        gate.resume()
        await check.value
        XCTAssertTrue(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.showsAccessProgress)
    }

    func testAccessDeniedOrDeletedNeverFallsBackToVerifiedArticle() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.post = nil
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertEqual(setup.remote.fetchOwners.count, 0)
        XCTAssertEqual(setup.remote.accessOwners.count, 2)
        XCTAssertTrue(setup.model.canRetainArticle)
    }

    func testNewlyPrivateOtherAuthorIsHiddenOnReappearance() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.replace(visibility: .privatePost)
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertEqual(setup.remote.fetchOwners.count, 0)
    }

    func testOwnerVisibilityChangeReloadsArticleForPublicOnlySurface() async {
        let setup = makeSetup()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.replace(visibility: .privatePost)
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(setup.model.item.visibility, .privateOnly)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertTrue(setup.model.canDisplayContent, "Owner can read private content; public-only card must reject this visibility")
    }

    func testFeedReturnRevisionRequiresFullRevalidation() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.replace(title: "복귀 후 제목")
        await setup.model.refreshForAppearance(revalidationRevision: 1)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertEqual(setup.remote.accessOwners.count, 1)
        XCTAssertEqual(setup.model.title, "복귀 후 제목")
    }

    func testMutationInvalidationImmediatelyHidesAndRequiresFullRead() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.model.invalidateAppearanceVerification()
        XCTAssertFalse(setup.model.canDisplayContent)
        setup.remote.replace(title: "변경된 제목")
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertEqual(setup.model.title, "변경된 제목")
    }

    func testLogoutDuringAccessCannotRestoreOldArticle() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let check = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        setup.safety.setViewerID(nil)
        setup.remote.sessionUserID = nil
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.canRetainArticle)
        gate.resume(); await check.value
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canDisplayContent)
    }

    func testAtoBtoAAccessReceiptCannotRestorePreviousGeneration() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let check = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        setup.safety.setViewerID(UUID())
        setup.safety.setViewerID(setup.owner)
        gate.resume(); await check.value
        XCTAssertFalse(setup.model.canDisplayContent)
        XCTAssertFalse(setup.model.isAvailable)
    }

    func testSDKSessionChangeDuringAccessIsRejected() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let check = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        setup.remote.sessionUserID = UUID()
        gate.resume(); await check.value
        XCTAssertFalse(setup.model.canDisplayContent)
    }

    func testExplicitInvalidationRejectsLateReceiptEvenWithSameAccount() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let check = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        setup.model.invalidateAppearanceVerification()
        gate.resume(); await check.value
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canDisplayContent)
    }

    func testSimultaneousReappearanceChecksShareOneLiveRead() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let first = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        let second = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        await Task.yield()
        gate.resume(); await first.value; await second.value
        XCTAssertEqual(setup.remote.accessOwners.count, 2)
        XCTAssertTrue(setup.model.canDisplayContent)
    }

    func testAccessFailureHidesCachedArticleAndRetryUsesFullRead() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.accessError = TestFailure.offline
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertFalse(setup.model.canDisplayContent)
        setup.remote.accessError = nil
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertTrue(setup.model.canDisplayContent)
    }

    func testNewFeedRevisionDuringAccessWaitsThenPerformsFullRead() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let first = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        setup.remote.replace(title: "새 피드 세대")
        let next = Task { await setup.model.refreshForAppearance(revalidationRevision: 1) }
        await Task.yield()
        gate.resume(); await first.value; await next.value
        XCTAssertEqual(setup.remote.accessOwners.count, 2)
        XCTAssertEqual(setup.remote.fetchOwners.count, 2)
        XCTAssertEqual(setup.model.title, "새 피드 세대")
        XCTAssertTrue(setup.model.canDisplayContent)
    }

    func testScrollTaskCancellationDoesNotRestartItsInFlightCheck() async {
        let setup = makeSetup(authorID: UUID()), gate = FeedAccessTestGate()
        await setup.model.refreshForAppearance(revalidationRevision: 0)
        setup.remote.onAccess = { await gate.wait() }
        let departed = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        while !gate.started { await Task.yield() }
        departed.cancel()
        let returned = Task { await setup.model.refreshForAppearance(revalidationRevision: 0) }
        await Task.yield()
        XCTAssertFalse(setup.model.canDisplayContent)
        gate.resume(); await departed.value; await returned.value
        XCTAssertEqual(setup.remote.accessOwners.count, 2)
        XCTAssertTrue(setup.model.canDisplayContent)
    }

    func testOwnerMustRefreshBeforeManagementAndRefreshedContentIsUsed() async {
        let setup = makeSetup()
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canManage)
        setup.remote.replace(title: "서버 제목", body: "서버 설명")
        await setup.model.refresh()
        XCTAssertTrue(setup.model.hasLoaded)
        XCTAssertTrue(setup.model.isAvailable)
        XCTAssertTrue(setup.model.canManage)
        XCTAssertTrue(setup.model.canBookmark)
        XCTAssertEqual(setup.model.title, "서버 제목")
        XCTAssertEqual(setup.model.description, "서버 설명")
        XCTAssertEqual(setup.remote.fetchOwners, [setup.owner])
    }

    func testOtherAuthorCannotEditChangeVisibilityOrDeleteButCanBookmark() async {
        let setup = makeSetup(authorID: UUID())
        await setup.model.refresh()
        XCTAssertFalse(setup.model.canManage)
        XCTAssertTrue(setup.model.canBookmark)
        let edited = await setup.model.edit(title: "바꾼 제목", description: "설명")
        await setup.model.setVisibility(.privatePost)
        await setup.model.delete()
        XCTAssertFalse(edited)
        XCTAssertTrue(setup.remote.edits.isEmpty)
        XCTAssertTrue(setup.remote.visibilityChanges.isEmpty)
        XCTAssertTrue(setup.remote.deletions.isEmpty)
        XCTAssertFalse(setup.model.isDeleted)
        await setup.model.toggleBookmark()
        XCTAssertTrue(setup.model.isBookmarked)
        XCTAssertTrue(setup.remote.isBookmarked)
        XCTAssertEqual(setup.remote.bookmarkOwners, [setup.owner])
    }

    func testRLSMissingContentHidesPriorSnapshotWithoutClaimingDeletion() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.remote.post = nil
        await setup.model.refresh()
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canManage)
        XCTAssertFalse(setup.model.canBookmark)
        XCTAssertFalse(setup.model.isDeleted)
        XCTAssertNotNil(setup.model.errorMessage)
        XCTAssertNil(setup.model.notice)
    }

    func testUnexpectedPrivateOtherAuthorSnapshotIsRejected() async {
        let setup = makeSetup(authorID: UUID())
        setup.remote.replace(visibility: .privatePost)
        await setup.model.refresh()
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canBookmark)
        XCTAssertNotNil(setup.model.errorMessage)
        await setup.model.toggleBookmark()
        XCTAssertTrue(setup.remote.bookmarkOwners.isEmpty)
    }

    func testRefreshFailureHidesContentAndRetryRestoresIt() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.remote.fetchError = TestFailure.offline
        await setup.model.refresh()
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertNotNil(setup.model.errorMessage)
        setup.remote.fetchError = nil
        await setup.model.refresh()
        XCTAssertTrue(setup.model.isAvailable)
        XCTAssertNil(setup.model.errorMessage)
    }

    func testAtoBtoAAccountGenerationCannotReuseOpenedManagement() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.safety.setViewerID(UUID())
        setup.safety.setViewerID(setup.owner)
        await setup.model.refresh()
        let edited = await setup.model.edit(title: "바뀐 계정", description: "")
        XCTAssertFalse(edited)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertEqual(setup.remote.fetchOwners.count, 1)
        XCTAssertTrue(setup.remote.edits.isEmpty)
        XCTAssertNil(setup.model.notice)
    }

    func testSDKSessionMismatchIsRejectedEvenIfSafetyCacheStillNamesOldAccount() async {
        let setup = makeSetup()
        setup.remote.sessionUserID = UUID()
        await setup.model.refresh()
        await setup.model.toggleBookmark()
        XCTAssertTrue(setup.remote.fetchOwners.isEmpty)
        XCTAssertTrue(setup.remote.bookmarkOwners.isEmpty)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertNotNil(setup.model.errorMessage)
    }

    func testAccountChangeDuringFetchDoesNotAdoptLateContent() async {
        let setup = makeSetup()
        let initialTitle = setup.model.title
        setup.remote.replace(title: "늦게 도착한 제목", body: "")
        setup.remote.onFetch = { _ in
            let next = UUID()
            setup.safety.setViewerID(next)
            setup.remote.sessionUserID = next
        }
        await setup.model.refresh()
        XCTAssertEqual(setup.model.title, initialTitle)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertFalse(setup.model.canManage)
    }

    func testAccountChangeAfterEditCannotPublishSuccessOrAdoptResult() async {
        let setup = makeSetup()
        await setup.model.refresh()
        let initialTitle = setup.model.title
        setup.remote.onEdit = {
            let next = UUID()
            setup.safety.setViewerID(next)
            setup.remote.sessionUserID = next
        }
        let edited = await setup.model.edit(title: "저장 시도", description: "")
        XCTAssertFalse(edited)
        XCTAssertEqual(setup.remote.edits.map(\.ownerID), [setup.owner])
        XCTAssertEqual(setup.model.title, initialTitle)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertNil(setup.model.notice)
    }

    func testBookmarkPersistsAcrossNewManagementAndCanBeRemoved() async {
        let setup = makeSetup()
        await setup.model.refresh()
        await setup.model.toggleBookmark()
        XCTAssertTrue(setup.model.isBookmarked)
        XCTAssertNotNil(setup.model.notice)
        let reopened = FeedPostManagement(item: setup.model.item, remote: setup.remote, safetyStore: setup.safety)
        await reopened.refresh()
        XCTAssertTrue(reopened.isBookmarked)
        await reopened.toggleBookmark()
        XCTAssertFalse(reopened.isBookmarked)
        XCTAssertFalse(setup.remote.isBookmarked)
    }

    func testBookmarkFailureDoesNotOptimisticallyClaimSaved() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.remote.bookmarkError = TestFailure.offline
        await setup.model.toggleBookmark()
        XCTAssertFalse(setup.model.isBookmarked)
        XCTAssertFalse(setup.remote.isBookmarked)
        XCTAssertNil(setup.model.notice)
        XCTAssertNotNil(setup.model.errorMessage)
    }

    func testEditLimitsCountSpacesAndPersistExactDescriptionAcrossRefresh() async {
        let setup = makeSetup()
        await setup.model.refresh()
        let description = String(repeating: "가 ", count: 50)
        let accepted = await setup.model.edit(title: "  새 운동 제목  ", description: description)
        XCTAssertTrue(accepted)
        XCTAssertEqual(setup.model.title, "새 운동 제목")
        XCTAssertEqual(setup.model.description, description)
        let longDescription = await setup.model.edit(title: "제목", description: description + " ")
        let longTitle = await setup.model.edit(title: String(repeating: "가", count: 81), description: "")
        let blankTitle = await setup.model.edit(title: "   ", description: "")
        XCTAssertFalse(longDescription)
        XCTAssertFalse(longTitle)
        XCTAssertFalse(blankTitle)
        XCTAssertEqual(setup.remote.edits.count, 1)
        let reopened = FeedPostManagement(item: setup.model.item, remote: setup.remote, safetyStore: setup.safety)
        await reopened.refresh()
        XCTAssertEqual(reopened.title, "새 운동 제목")
        XCTAssertEqual(reopened.description, description)
    }

    func testVisibilityRequiresConfirmedPublicOrPrivateReadback() async {
        let setup = makeSetup()
        await setup.model.refresh()
        await setup.model.setVisibility(.privatePost)
        XCTAssertEqual(setup.model.visibility, .privatePost)
        XCTAssertTrue(setup.model.isAvailable)
        XCTAssertNotNil(setup.model.notice)
        await setup.model.setVisibility(.publicPost)
        XCTAssertEqual(setup.model.visibility, .publicPost)
        await setup.model.setVisibility(.followers)
        XCTAssertEqual(setup.remote.visibilityChanges.count, 3)
        XCTAssertEqual(setup.model.visibility, .privatePost)
        XCTAssertNotNil(setup.model.errorMessage)
    }

    func testUnconfirmedEditReadbackDoesNotClaimSuccessAndRetryIsAllowed() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.remote.appliesEdits = false
        let first = await setup.model.edit(title: "새 제목", description: "새 설명")
        XCTAssertFalse(first)
        XCTAssertNil(setup.model.notice)
        XCTAssertFalse(setup.model.isAvailable)
        setup.remote.appliesEdits = true
        let retry = await setup.model.edit(title: "새 제목", description: "새 설명")
        XCTAssertTrue(retry)
        XCTAssertEqual(setup.model.title, "새 제목")
    }

    func testDeletionFailureKeepsStateAndOnlyConfirmedDeletionInvokesDeletedState() async {
        let setup = makeSetup()
        await setup.model.refresh()
        setup.remote.deleteError = TestFailure.offline
        await setup.model.delete()
        XCTAssertFalse(setup.model.isDeleted)
        XCTAssertNotNil(setup.remote.post)
        XCTAssertNil(setup.model.notice)
        setup.remote.deleteError = nil
        await setup.model.delete()
        XCTAssertTrue(setup.model.isDeleted)
        XCTAssertFalse(setup.model.isAvailable)
        XCTAssertNil(setup.remote.post)
        XCTAssertEqual(setup.remote.deletions.map(\.ownerID), [setup.owner, setup.owner])
    }

    func testLocalDraftNeverMakesRemoteRequests() async {
        let setup = makeSetup()
        let seed = setup.model.item
        let draft = FeedItem(id: seed.id, authorName: "나", authorHandle: nil, authorId: setup.owner,
                             isLocalDraft: true, createdAt: seed.createdAt, itemType: seed.itemType,
                             visibility: seed.visibility, cardData: seed.cardData, caption: seed.caption,
                             activityContext: seed.activityContext)
        let model = FeedPostManagement(item: draft, remote: setup.remote, safetyStore: setup.safety)
        await model.refresh()
        await model.toggleBookmark()
        await model.delete()
        XCTAssertFalse(model.canManage)
        XCTAssertFalse(model.canBookmark)
        XCTAssertTrue(setup.remote.fetchOwners.isEmpty)
        XCTAssertTrue(setup.remote.bookmarkOwners.isEmpty)
        XCTAssertTrue(setup.remote.deletions.isEmpty)
    }

    func testOwnerMutualVisibilityUsesConfirmedReadbackAndPeerCannotChangeIt() async {
        let owner = makeSetup()
        await owner.model.refresh()
        await owner.model.setVisibility(.mutual)
        XCTAssertEqual(owner.model.visibility, .mutual)
        XCTAssertEqual(owner.remote.visibilityChanges.count, 1)
        XCTAssertTrue(owner.model.isAvailable)
        XCTAssertEqual(owner.model.notice, "게시물을 맞팔공개로 변경했어요.")
        let peer = makeSetup(authorID: UUID())
        peer.remote.replace(visibility: .mutual)
        await peer.model.refresh()
        await peer.model.setVisibility(.publicPost)
        await peer.model.delete()
        XCTAssertFalse(peer.model.canManage)
        XCTAssertTrue(peer.remote.visibilityChanges.isEmpty)
        XCTAssertTrue(peer.remote.deletions.isEmpty)
    }

    private func accessScope() -> FeedPostAccessScope {
        FeedPostAccessScope(clientIdentity: ObjectIdentifier(self), viewerID: UUID(), accountGeneration: 0, safetyRevision: 0)
    }

    func testNewServerConfirmsApprovedFollowersAndLegacyRowStaysRestricted() async {
        let setup = makeSetup(); setup.remote.supportsApprovedFollowers = true
        await setup.model.refresh(); await setup.model.setVisibility(.followers)
        XCTAssertEqual(setup.model.visibility,.followers)
        XCTAssertEqual(setup.model.item.serverPostSnapshot?.audienceContract,1)
        XCTAssertNil(setup.model.errorMessage)
        XCTAssertTrue(setup.model.isAvailable)
    }
    func testUnchangedParentCannotKeepSharedChartAfterFreshConsentRevocation() async {
        let setup = makeSetup(authorID:UUID())
        setup.remote.post?.sharedDetailRevision = 1
        let post = setup.remote.post!
        let payload = WorkoutSharedDetailInput(durationSeconds:100,distanceMeters:nil,route:[],samples:[.init(seconds:0,heartRateBPM:120)])
        let snapshot = WorkoutSharedDetailSnapshot(postID:post.id,revision:1,payload:payload)
        setup.remote.sharedDetail = snapshot;setup.remote.sharedDetailEnabled = true;setup.remote.sharedDetailAuthorized = true
        let cached = FeedPostBundleDTO(post:post,sharedDetail:snapshot,sharedDetailContractEnabled:true).makeFeedItem(currentUserId:setup.owner)
        let first = FeedPostManagement(item:cached,remote:setup.remote,safetyStore:setup.safety)
        await first.refreshForAppearance(revalidationRevision:0)
        XCTAssertNotNil(first.item.permittedSharedDetail)
        setup.remote.sharedDetailAuthorized = false
        let next = FeedPostManagement(item:first.item,remote:setup.remote,safetyStore:setup.safety)
        await next.refreshForAppearance(revalidationRevision:0)
        XCTAssertEqual(next.item.serverPostSnapshot,post)
        XCTAssertNil(next.item.permittedSharedDetail)
        XCTAssertTrue(next.canDisplayContent)
        XCTAssertGreaterThanOrEqual(setup.remote.fetchOwners.count,1)
    }

    private func makeSetup(authorID: UUID? = nil) -> Setup {
        let owner = UUID()
        let remote = FakeFeedPostManagementRemote(sessionUserID: owner, authorID: authorID ?? owner)
        let safety = CommunitySafetyStore(client: nil, viewerID: owner)
        let model = FeedPostManagement(item: remote.post!.makeItem(viewerID: owner), remote: remote, safetyStore: safety)
        return Setup(owner: owner, remote: remote, safety: safety, model: model)
    }
    func testLockedSocialCannotDisplayRetainedArticleOrWriteAndReconnectMustReadAgain() async throws {
        let owner=UUID(), remote=FakeFeedPostManagementRemote(sessionUserID:UUID(),authorID:UUID())
        remote.sessionUserID=owner
        let safety=CommunitySafetyStore(client:nil,viewerID:owner,requiresSocialVerification:true)
        safety.setSocialVerified(true,owner:owner)
        let model=FeedPostManagement(item:remote.post!.makeItem(viewerID:owner),remote:remote,safetyStore:safety)
        await model.refresh();XCTAssertTrue(model.canDisplayContent)
        let reads=remote.fetchOwners.count
        safety.setSocialVerified(false,owner:owner)
        XCTAssertFalse(model.canDisplayContent);XCTAssertFalse(model.canRetainArticle)
        XCTAssertFalse(model.canBookmark);await model.toggleBookmark()
        XCTAssertTrue(remote.bookmarkOwners.isEmpty)
        await model.refresh();XCTAssertEqual(remote.fetchOwners.count,reads)
        safety.setSocialVerified(true,owner:owner);XCTAssertFalse(model.canDisplayContent)
        await model.refresh();XCTAssertTrue(model.canDisplayContent);XCTAssertGreaterThan(remote.fetchOwners.count,reads)
        safety.setViewerID(UUID());safety.setViewerID(owner)
        XCTAssertFalse(safety.canUseSocial);XCTAssertFalse(model.canDisplayContent)
        safety.setSocialVerified(true,owner:owner);await model.refresh();XCTAssertFalse(model.canDisplayContent)
    }

    private struct Setup {
        let owner: UUID
        let remote: FakeFeedPostManagementRemote
        let safety: CommunitySafetyStore
        let model: FeedPostManagement
    }
    private enum TestFailure: Error { case offline }
}

@MainActor
private final class FakeFeedPostManagementRemote: FeedPostRemoteManaging {
    struct Mutation { let postID: UUID; let ownerID: UUID }
    var sessionUserID: UUID?
    var post: FeedPostDTO?
    var isBookmarked = false
    var supportsApprovedFollowers = false
    var sharedDetail: WorkoutSharedDetailSnapshot?
    var sharedDetailEnabled = false
    var sharedDetailAuthorized = false
    var appliesEdits = true
    var fetchError: Error?
    var accessError: Error?
    var bookmarkError: Error?
    var deleteError: Error?
    var onFetch: ((Int) -> Void)?
    var onAccess: (() async -> Void)?
    var onEdit: (() -> Void)?
    var fetchOwners: [UUID] = []
    var accessOwners: [UUID] = []
    var bookmarkOwners: [UUID] = []
    var edits: [Mutation] = []
    var visibilityChanges: [Mutation] = []
    var deletions: [Mutation] = []

    init(sessionUserID: UUID, authorID: UUID) {
        self.sessionUserID = sessionUserID
        post = FeedPostDTO(id: UUID(), userId: authorID, sport: .running, title: "시험 운동", body: "기존 설명",
                           visibility: .publicPost, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
    func fetchPost(id: UUID, viewerID: UUID) async throws -> FeedItem? {
        fetchOwners.append(viewerID)
        onFetch?(fetchOwners.count)
        if let fetchError { throw fetchError }
        var item = post?.makeItem(viewerID: viewerID)
        item?.viewerHasSaved = isBookmarked
        item?.sharedDetail = sharedDetailAuthorized ? sharedDetail : nil
        item?.sharedDetailContractEnabled = sharedDetailEnabled
        return item
    }
    func fetchAccess(id: UUID, viewerID: UUID) async throws -> FeedPostAccess? {
        accessOwners.append(viewerID)
        await onAccess?()
        if let accessError { throw accessError }
        guard let post else { return nil }
        return FeedPostAccess(id: post.id, authorID: post.userId, visibility: post.visibility, post: post,sharedDetailContractEnabled:sharedDetailEnabled,sharedDetailAuthorized:sharedDetailAuthorized)
    }
    func setBookmark(postID: UUID, viewerID: UUID, isSaved: Bool) async throws {
        bookmarkOwners.append(viewerID)
        if let bookmarkError { throw bookmarkError }
        isBookmarked = isSaved
    }
    func editPost(id: UUID, ownerID: UUID, title: String, description: String) async throws {
        edits.append(Mutation(postID: id, ownerID: ownerID))
        if appliesEdits { replace(title: title, body: description) }
        onEdit?()
    }
    func setVisibility(postID: UUID, ownerID: UUID, visibility: FeedPostVisibility) async throws {
        visibilityChanges.append(Mutation(postID: postID, ownerID: ownerID))
        replace(visibility: visibility)
        if supportsApprovedFollowers && visibility == .followers { post?.audienceContract = 1 }
    }
    func deletePost(id: UUID, ownerID: UUID) async throws {
        deletions.append(Mutation(postID: id, ownerID: ownerID))
        if let deleteError { throw deleteError }
        post = nil
    }
    func replace(title: String? = nil, body: String? = nil, visibility: FeedPostVisibility? = nil) {
        guard let original = post else { return }
        post = FeedPostDTO(id: original.id, userId: original.userId, sport: original.sport,
                           title: title ?? original.title, body: body ?? original.body,
                           visibility: visibility ?? original.visibility, createdAt: original.createdAt)
    }
}

@MainActor
private final class FeedAccessTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        await withCheckedContinuation { continuation = $0; started = true }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

private extension FeedPostDTO {
    func makeItem(viewerID: UUID) -> FeedItem {
        FeedPostBundleDTO(post: self).makeFeedItem(authorName: "합성 사용자", currentUserId: viewerID)
    }
}

final class FeedCommentDeletePolicyTests: XCTestCase {
    func testOnlyCommentAuthorCanSeeDeleteEvenOnOwnedPost() {
        let author = UUID(), owner = UUID(), stranger = UUID()
        XCTAssertTrue(FeedCommentDeletePolicy.allows(viewerID: author, commentAuthorID: author, postAuthorID: owner, canUseSocial: true))
        XCTAssertFalse(FeedCommentDeletePolicy.allows(viewerID: owner, commentAuthorID: author, postAuthorID: owner, canUseSocial: true))
        XCTAssertFalse(FeedCommentDeletePolicy.allows(viewerID: stranger, commentAuthorID: author, postAuthorID: owner, canUseSocial: true))
        XCTAssertFalse(FeedCommentDeletePolicy.allows(viewerID: nil, commentAuthorID: author, postAuthorID: owner, canUseSocial: true))
        XCTAssertFalse(FeedCommentDeletePolicy.allows(viewerID: author, commentAuthorID: author, postAuthorID: owner, canUseSocial: false))
    }
}
