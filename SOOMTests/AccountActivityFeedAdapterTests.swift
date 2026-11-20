import XCTest
@testable import SOOM

@MainActor
final class AccountActivityFeedAdapterTests: XCTestCase {
    func testLinkedDetailDeletionContextDisablesOnlyLegacyDelete() {
        XCTAssertFalse(FeedPostDeletionPresentationPolicy.allows(canManage: true, legacyDeletionAllowed: false))
        XCTAssertFalse(FeedPostDeletionPresentationPolicy.allows(canManage: false, legacyDeletionAllowed: true))
        XCTAssertTrue(FeedPostDeletionPresentationPolicy.allows(canManage: true, legacyDeletionAllowed: true))
    }
    func testProfileOnlyV2KeepsCanonicalSummaryAndNeverHydratesLegacyPayload() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let page = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request)
        let item = try XCTUnwrap(page.displayItems().first)
        XCTAssertEqual(item.id, t.card)
        XCTAssertEqual(item.activityProjection?.readPolicy, .profileOnlyV2)
        XCTAssertNil(page.cards.first?.legacyItem)
        XCTAssertTrue(t.postsRequested.isEmpty)
        XCTAssertEqual(t.pagesRequested, 2)
    }
    func testV2OwnPageSkipsIrrelevantFollowingButStillRechecksPage() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.ownRowsOnly = true; t.noOwners = true
        let page = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request)
        XCTAssertEqual(page.cards.count, 1); XCTAssertEqual(t.pagesRequested, 2)
        XCTAssertEqual(t.ownerCalls, 0); XCTAssertEqual(t.calls, 2)
    }
    func testV2EmptyPageSkipsFollowingButStillRechecksPage() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.emptyPage = true
        let page = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request)
        XCTAssertTrue(page.cards.isEmpty); XCTAssertEqual(t.pagesRequested, 2); XCTAssertEqual(t.ownerCalls, 0)
    }
    func testV2OwnPageChangingToForeignIsRejectedWithoutReusingOwnAuthority() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        t.ownRowsOnly = true; t.foreignOwnerOnFinalPage = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityAdapterError, .changedDuringRead) }
        XCTAssertEqual(t.pagesRequested, 2); XCTAssertEqual(t.ownerCalls, 0)
    }
    func testProfileOnlyV2RejectsV1EnvelopeRatherThanUpgradingIt() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityContractError, .malformedPage) }
        XCTAssertTrue(t.postsRequested.isEmpty)
    }
    func testV1RejectsV2EnvelopeRatherThanDowngradingIt() async {
        let t = Fixture(); t.responseVersion = 2
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityContractError, .malformedPage) }
    }
    func testV2ProfileReadDoesNotRequireHomeFollowingMembership() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.noOwners = true
        let request = AccountActivityPageRequest(viewerID: t.viewer, scope: .profile, ownerID: t.item.authorId, before: nil, limit: 8)
        let page = try await AccountActivityFeedAdapter(syntheticTransport: t).load(request)
        XCTAssertEqual(page.cards.count, 1)
        XCTAssertEqual(t.ownerCalls, 0)
    }
    func testV2HomeRequiresFreshMembershipAndRejectsRevokedFollow() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.noOwners = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityContractError, .wrongContext) }
    }
    func testV2FinalMembershipRecheckRejectsRelationshipChange() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.revokeFollow = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityContractError, .wrongContext) }
        XCTAssertEqual(t.ownerCalls, 2)
    }
    func testV2ProductionGateCannotBeBypassedWithLegacyPreview() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        do { _ = try await AccountActivityFeedAdapter(transport: t, preview: true).load(t.request); XCTFail() } catch {}
        XCTAssertEqual(t.calls, 0)
        #if SOOM_PROFILE_ONLY_V2
        XCTAssertTrue(ProfileOnlyPrivacyReleaseGate.productionReady)
        XCTAssertEqual(AccountActivityReadPolicy.deployed, .profileOnlyV2)
        #else
        XCTAssertFalse(ProfileOnlyPrivacyReleaseGate.productionReady)
        XCTAssertEqual(AccountActivityReadPolicy.deployed, .approvedFollowersV1)
        #endif
    }
    func testV2RepositoryNeverFallsBackToLegacyEvenWhenRequested() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.includeLegacy = true
        let repository = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, legacyFallback: true)
        do { _ = try await repository.fetchFeedPage(limit: 8, offset: 0, audience: .home); XCTFail() } catch {}
        XCTAssertEqual(t.legacyCalls, 0)
        XCTAssertTrue(t.postsRequested.isEmpty)
        XCTAssertEqual(t.pagesRequested, ProfileOnlyPrivacyReleaseGate.productionReady ? 1 : 0)
        XCTAssertEqual(t.calls, ProfileOnlyPrivacyReleaseGate.productionReady ? 2 : 0)
    }
    func testV2PageFromPreviousAccountCannotReachUI() async {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.switchDuringPage = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityAdapterError, .accountChanged) }
    }
    func testV2CursorRejectsRepeatedCardInsteadOfAdvancingOffset() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let repository = AccountActivityHomeRepository(legacy: MockFeedRepository(), syntheticTransport: t)
        let first = try await repository.fetchFeedPage(limit: 1, offset: 0, audience: .home)
        XCTAssertEqual(first.first?.activityProjection?.readPolicy, .profileOnlyV2)
        do { _ = try await repository.fetchFeedPage(limit: 1, offset: 1, audience: .home); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityContractError, .invalidOrder) }
        let before = t.calls
        do { _ = try await repository.fetchFeedPage(limit: 1, offset: 2, audience: .home); XCTFail() } catch {}
        XCTAssertEqual(t.calls, before)
    }
    func testV2RPCSelectionNeverUsesV1Preview() throws {
        XCTAssertEqual(try AccountActivityReadPolicy.profileOnlyV2.pageRPC(preview: false), "soom_activity_page_candidate_v2")
        XCTAssertEqual(try AccountActivityReadPolicy.profileOnlyV2.cardRPC(preview: false), "soom_activity_card_candidate_v2")
        XCTAssertThrowsError(try AccountActivityReadPolicy.profileOnlyV2.pageRPC(preview: true))
        XCTAssertThrowsError(try AccountActivityReadPolicy.profileOnlyV2.cardRPC(preview: true))
    }
    func testV2CardValidationStampsProvenanceOnlyAfterExactVersionAndOwnerCheck() throws {
        let viewer = UUID(), owner = UUID(), card = UUID()
        let row = AccountActivityFeedRow(cardID: card, canonicalID: UUID(), ownerID: owner, sport: "running",
            activityAt: "2026-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100, revision: 1)
        let receipt = AccountActivityCardEnvelope(version: 2, viewerID: viewer, row: row, releaseReady: false)
        let valid = try receipt.validateCandidate(expectedCardID: card, requestViewerID: viewer, currentViewerID: viewer,
            requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(), expectedOwnerID: owner, expectedPolicy: .profileOnlyV2)
        XCTAssertEqual(valid?.readPolicy, .profileOnlyV2)
        XCTAssertThrowsError(try receipt.validateCandidate(expectedCardID: card, requestViewerID: viewer, currentViewerID: viewer,
            requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(), expectedOwnerID: owner))
        XCTAssertThrowsError(try receipt.validateCandidate(expectedCardID: card, requestViewerID: viewer, currentViewerID: viewer,
            requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(), expectedOwnerID: UUID(), expectedPolicy: .profileOnlyV2))
    }
    func testCardPreviewNeverInvokesFullLegacyPostLoader() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let cardEnvelope = try await t.card(t.card)
        var row = try XCTUnwrap(cardEnvelope.row); row.readPolicy = .profileOnlyV2
        var previewIDs: [UUID] = []
        let before = t.cardCalls
        let result = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadCardPreview(row: row) { id, opening in
            XCTAssertEqual(opening.viewerID, t.viewer); previewIDs.append(id)
            return .init(postID: id, ownerID: row.ownerID, presentation: .init(title: "Card title", device: "Device", location: "Region"))
        }
        XCTAssertEqual(result?.title, "Card title")
        XCTAssertEqual(previewIDs, [t.item.id]); XCTAssertTrue(t.postsRequested.isEmpty)
        XCTAssertEqual(t.cardCalls - before, 2)
    }
    func testCardPreviewRejectsRevocationOrAccountChangeWithoutFullFallback() async throws {
        for changeAccount in [false, true] {
            let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
            let cardEnvelope = try await t.card(t.card)
        var row = try XCTUnwrap(cardEnvelope.row); row.readPolicy = .profileOnlyV2
            do {
                _ = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadCardPreview(row: row) { id, _ in
                    if changeAccount { t.epoch += 1 } else { t.noLink = true }
                    return .init(postID: id, ownerID: row.ownerID, presentation: .init(title: "Must not publish"))
                }
                XCTFail("Late preview must not escape its authority")
            } catch { }
            XCTAssertTrue(t.postsRequested.isEmpty)
        }
    }
    func testUnlinkedCardDoesNotRequestPreviewOrFullDetails() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.noLink = true
        let cardEnvelope = try await t.card(t.card)
        var row = try XCTUnwrap(cardEnvelope.row); row.readPolicy = .profileOnlyV2
        let result = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadCardPreview(row: row) { _, _ in
            XCTFail("No historical source authorized"); return nil
        }
        XCTAssertNil(result); XCTAssertTrue(t.postsRequested.isEmpty)
    }

    func testV2LinkedDetailUsesOriginalLegacyPostIDAfterBothPermissionChecks() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let envelope = try await t.card(t.card)
        let row = try XCTUnwrap(try envelope.validateCandidate(expectedCardID: t.card, requestViewerID: t.viewer,
            currentViewerID: t.viewer, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(), expectedPolicy: .profileOnlyV2))
        let item = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).load(row: row)
        XCTAssertEqual(item.id, t.item.id); XCTAssertNotEqual(item.id, t.card)
        XCTAssertEqual(t.postsRequested, [t.item.id])
    }
    func testV2LinkedDetailRejectsRevokedLegacyMapping() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.revokeAfterPost = true
        let envelope = try await t.card(t.card)
        var row = try XCTUnwrap(envelope.row); row.readPolicy = .profileOnlyV2
        do { _ = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).load(row: row); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityAdapterError, .changedDuringRead) }
    }
    func testV2LinkedDetailDoesNotFetchWhenHistoricalPostIsNotAuthorized() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.noLink = true
        let envelope = try await t.card(t.card)
        var row = try XCTUnwrap(envelope.row); row.readPolicy = .profileOnlyV2
        do { _ = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).load(row: row); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityAdapterError, .unlinkedProjection) }
        XCTAssertTrue(t.postsRequested.isEmpty)
    }
    func testSingleCommentRoutePrefersFreshHistoricalThread() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let receipt = try await t.card(t.card)
        var row = try XCTUnwrap(receipt.row); row.readPolicy = .profileOnlyV2
        let result = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row)
        XCTAssertEqual(result?.id, t.item.id)
        XCTAssertEqual(t.postsRequested, [t.item.id])
    }
    func testSingleCommentRouteUsesNativeOnlyAfterFreshUnlinkedCardRecheck() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.noLink = true
        let receipt = try await t.card(t.card)
        var row = try XCTUnwrap(receipt.row); row.readPolicy = .profileOnlyV2
        let before = t.cardCalls
        let result = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row)
        XCTAssertNil(result)
        XCTAssertEqual(t.cardCalls - before, 2)
        XCTAssertTrue(t.postsRequested.isEmpty)
    }
    func testSingleCommentRouteDoesNotSwitchThreadAfterPermissionChangesDuringRead() async throws {
        let t = Fixture(); t.readPolicy = .profileOnlyV2; t.responseVersion = 2; t.revokeAfterPost = true
        let receipt = try await t.card(t.card)
        var row = try XCTUnwrap(receipt.row); row.readPolicy = .profileOnlyV2
        do { _ = try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivityAdapterError, .changedDuringRead) }
    }
    func testLegacyPhotosKeepOriginalPostBucketAndRejectWrongOrNativePaths() {
        let original = FeedMockData.items[0]
        let photoID = UUID()
        let valid = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(ownerID: original.authorId, postID: original.id, photoID: photoID))
        let native = WorkoutPhotoReference(id: photoID, storagePath: valid.storagePath, nativeCardID: original.id)
        let wrongPost = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(ownerID: original.authorId, postID: UUID(), photoID: photoID))
        let wrongOwner = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(ownerID: UUID(), postID: original.id, photoID: photoID))
        let item = FeedItem(id: original.id, authorName: original.authorName, authorHandle: nil, authorId: original.authorId,
            createdAt: original.createdAt, itemType: original.itemType, visibility: original.visibility, cardData: original.cardData,
            caption: nil, photos: [native, wrongPost, wrongOwner, valid, valid], activityContext: original.activityContext)
        XCTAssertEqual(AccountActivityLegacyMedia.photos(from: item, ownerID: original.authorId), [valid])
        XCTAssertEqual(valid.bucket, WorkoutPhotoPolicy.bucket)
        XCTAssertTrue(AccountActivityLegacyMedia.photos(from: item, ownerID: UUID()).isEmpty)
    }
    func testLegacyReadPolicyRejectsNonFollowingPrivateFollowersAndBlocked() {
        let viewer = UUID(), followed = UUID(), stranger = UUID()
        XCTAssertTrue(PreviewLegacyReadPolicy.permits(owner: followed, isPublic: true, viewer: viewer, following: [followed], blocked: false))
        XCTAssertTrue(PreviewLegacyReadPolicy.permits(owner: viewer, isPublic: false, viewer: viewer, following: [], blocked: false))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: followed, isPublic: false, viewer: viewer, following: [followed], blocked: false))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: stranger, isPublic: true, viewer: viewer, following: [followed], blocked: false))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: followed, isPublic: true, viewer: viewer, following: [followed], blocked: true))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: followed, isPublic: true, viewer: viewer, following: [], blocked: false))
    }
    func testRLSReturnedFollowersRequiresCurrentFollowingAndNoBlock() {
        let viewer = UUID(), owner = UUID()
        XCTAssertTrue(PreviewLegacyReadPolicy.permits(owner: owner, isPublic: false, isFollowers: true, viewer: viewer, following: [owner], blocked: false))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: owner, isPublic: false, isFollowers: true, viewer: viewer, following: [], blocked: false))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: owner, isPublic: false, isFollowers: true, viewer: viewer, following: [owner], blocked: true))
        XCTAssertFalse(PreviewLegacyReadPolicy.permits(owner: owner, isPublic: false, isFollowers: false, viewer: viewer, following: [owner], blocked: false))
    }
    func testLegacyMergePreservesExistingPostIdentityAndDeduplicatesExactID() {
        let t = Fixture()
        let merged = AccountActivityHomeRepository.mergePreviewAndLegacy([t.item], [t.item], limit: 20)
        XCTAssertEqual(merged, [t.item])
        XCTAssertEqual(AccountActivityHomeRepository.mergePreviewAndLegacy([], [t.item], limit: 1), [t.item])
    }
    func testPreviewEmptyProjectionsStillReturnsExistingLegacyFollowing() async throws {
        let t = Fixture(); t.emptyPage = true; t.includeLegacy = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, preview: true)
        let page = try await repo.fetchFeedPage(limit: 8, offset: 0, audience: .home)
        XCTAssertEqual(page, [t.item])
    }
    func testProjectionFailurePreservesIndependentlyAuthorizedLegacy() async throws {
        let t = Fixture(); t.includeLegacy = true; t.failPage = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, preview: true)
        let rows = try await repo.fetchFeedPage(limit: 8, offset: 0, audience: .home)
        XCTAssertEqual(rows, [t.item])
    }
    func testLegacyFallbackWorksWithProductionProjectionGateOff() async throws {
        let t = Fixture(); t.includeLegacy = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, legacyFallback: true)
        let rows = try await repo.fetchFeedPage(limit: 8, offset: 0, audience: .home)
        XCTAssertEqual(rows, [t.item])
        XCTAssertEqual(t.pagesRequested, 0)
    }
    func testBothSourcesFailNeverReturnsCachedLegacy() async {
        let t = Fixture(); t.includeLegacy = true; t.failPage = true; t.failLegacy = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, preview: true)
        do { _ = try await repo.fetchFeedPage(limit: 8, offset: 0, audience: .home); XCTFail() } catch { }
    }
    func testAccountSwitchDuringLegacyHydrationRejectsMergedPage() async {
        let t = Fixture(); t.emptyPage = true; t.includeLegacy = true; t.switchDuringLegacy = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, preview: true)
        do { _ = try await repo.fetchFeedPage(limit: 8, offset: 0, audience: .home); XCTFail() } catch {}
    }
    func testCrossPageDuplicateIsNeverReturnedAndWorkIsBounded() async throws {
        let t = Fixture(); t.emptyPage = true; t.includeLegacy = true
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), transport: t, preview: true)
        let first = try await repo.fetchFeedPage(limit: 1, offset: 0, audience: .home)
        XCTAssertEqual(first.count, 1)
        do { _ = try await repo.fetchFeedPage(limit: 1, offset: 1, audience: .home); XCTFail() } catch {}
        XCTAssertEqual(t.legacyCalls, 22)
    }
    func testExplicitPreviewSupportsValidatedFollowerPageWithoutProductionGate() async throws {
        let t = Fixture()
        let result = try await AccountActivityFeedAdapter(transport: t, preview: true).load(t.request)
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertFalse(AccountActivityFeedReleaseGate.productionReady)
    }
    func testPreviewStillRejectsRevokedFollow() async {
        let t = Fixture(); t.revokeFollow = true
        do { _ = try await AccountActivityFeedAdapter(transport: t, preview: true).load(t.request); XCTFail() } catch {}
    }
    func testProductionGatePerformsNoTransportCalls() async {
        let t = Fixture()
        do { _ = try await AccountActivityFeedAdapter(transport: t).load(t.request); XCTFail() } catch {}
        XCTAssertEqual(t.calls, 0)
    }
    func testPreservesLegacyIdentityCommentsAndPhotosWithoutReposting() async throws {
        let t = Fixture()
        let result = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request)
        XCTAssertEqual(try result.legacyFeedItems(), [t.item])
        XCTAssertNotEqual(result.cards[0].projection.cardID, result.cards[0].legacyItem?.id)
        XCTAssertEqual(t.postsRequested, [t.item.id])
        XCTAssertEqual(t.pagesRequested, 2)
    }
    func testMissingLinkIsExplicitAndNeverGuessesPostID() async throws {
        let t = Fixture(); t.noLink = true
        let result = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request)
        XCTAssertNil(result.cards.first?.legacyItem)
        XCTAssertThrowsError(try result.legacyFeedItems())
        XCTAssertTrue(t.postsRequested.isEmpty)
        let summary = result.displayItems()[0]
        XCTAssertEqual(summary.id, t.card)
        XCTAssertEqual(summary.activityProjection?.cardID, t.card)
        XCTAssertFalse(summary.isLocalDraft)
        XCTAssertTrue(summary.comments.isEmpty)
        XCTAssertTrue(summary.photos.isEmpty)
        var notification=FeedNotificationCardPresentation(item:summary,
            context:.init(viewerID:UUID(),generation:1,safetyRevision:1),opensComments:true)
        notification.presentInitialComments(current:notification.context,canUseSocial:true)
        XCTAssertFalse(notification.supportsLegacyComments)
        XCTAssertFalse(notification.commentsPresented, "A native card ID must never reach legacy comments")
    }
    func testRevocationDuringHydrationDiscardsEntirePage() async {
        let t = Fixture(); t.revokeAfterPost = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() } catch {}
    }
    func testAccountSwitchDuringHydrationDiscardsEntirePage() async {
        let t = Fixture(); t.switchAfterPost = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() } catch {}
    }
    func testWrongLegacyOwnerRejected() async {
        let t = Fixture(); t.wrongOwner = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() } catch {}
    }
    func testFollowRevokedBeforeFinalReadRejectsPage() async {
        let t = Fixture(); t.revokeFollow = true
        do { _ = try await AccountActivityFeedAdapter(syntheticTransport: t).load(t.request); XCTFail() } catch {}
    }
    func testUnknownOffsetNeverCallsNetworkOrGlobalFallback() async {
        let t = Fixture()
        let repo = AccountActivityHomeRepository(legacy: MockFeedRepository(), syntheticTransport: t)
        do { _ = try await repo.fetchFeedPage(limit: 8, offset: 8, audience: .home); XCTFail() } catch {}
        XCTAssertEqual(t.calls, 0)
    }
    func testOffsetZeroRefreshInvalidatesOlderInFlightPageAndItsCursor() async throws {
        let transport = RefreshRaceFixture()
        let repository = AccountActivityHomeRepository(legacy: MockFeedRepository(), syntheticTransport: transport)
        let first = try await repository.fetchFeedPage(limit: 1, offset: 0, audience: .home)
        XCTAssertEqual(first.first?.id, transport.oldFirst)
        let oldPage = Task { try await repository.fetchFeedPage(limit: 1, offset: 1, audience: .home) }
        await transport.waitUntilSuspended()
        transport.refreshed = true
        let replacement = try await repository.fetchFeedPage(limit: 1, offset: 0, audience: .home)
        XCTAssertEqual(replacement.first?.id, transport.newFirst)
        transport.resumeOldPage()
        do {
            _ = try await oldPage.value
            XCTFail("An old generation must not replace the refreshed timeline")
        } catch {
            XCTAssertEqual(error as? AccountActivityAdapterError, .accountChanged)
        }
        // The rejected old page must not seed offset 2 in the new cursor map.
        let callsBeforeInvalidOffset = transport.pageCalls
        do { _ = try await repository.fetchFeedPage(limit: 1, offset: 2, audience: .home); XCTFail() } catch {}
        XCTAssertEqual(transport.pageCalls, callsBeforeInvalidOffset)
        let next = try await repository.fetchFeedPage(limit: 1, offset: 1, audience: .home)
        XCTAssertEqual(next.first?.id, transport.newSecond)
        XCTAssertEqual(Array(transport.requestedBeforeIDs.suffix(2)), [transport.newFirst, transport.newFirst])
    }

}

@MainActor
private final class Fixture: AccountActivityFeedTransport {
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1
    var responseVersion = 1
    var noOwners = false
    var ownRowsOnly = false
    var foreignOwnerOnFinalPage = false
    var switchDuringPage = false
    var item = FeedMockData.items[0]
    let card = UUID()
    let viewer = UUID()
    var epoch = 1
    var calls = 0; var pagesRequested = 0; var ownerCalls = 0
    var postsRequested: [UUID] = []
    var noLink = false; var revokeAfterPost = false; var switchAfterPost = false
    var wrongOwner = false; var revokeFollow = false
    var emptyPage = false, includeLegacy = false, switchDuringLegacy = false
    var failPage = false, failLegacy = false
    var legacyCalls = 0
    var cardCalls = 0
    func legacyHome(_ request: AccountActivityPageRequest, postID: UUID?) async throws -> [FeedItem] {
        legacyCalls += 1; if failLegacy { throw AccountActivityAdapterError.unreleased }; if switchDuringLegacy { epoch += 1 }; return includeLegacy ? [item] : []
    }
    var context: AccountActivityReadContext? { .init(viewerID: viewer, generation: epoch, safetyRevision: 1) }
    var request: AccountActivityPageRequest { .init(viewerID: viewer, scope: .home, ownerID: nil, before: nil, limit: 8) }
    func page(_ request: AccountActivityPageRequest) async throws -> AccountActivityFeedPage {
        calls += 1; pagesRequested += 1
        if switchDuringPage { epoch += 1 }
        if failPage { throw AccountActivityAdapterError.unreleased }
        let row: [String: Any] = ["card_id":card.uuidString,"canonical_id":UUID().uuidString,
            "owner_id":(ownRowsOnly && !(foreignOwnerOnFinalPage && pagesRequested > 1) ? viewer : item.authorId).uuidString,"sport":"running","activity_at":"2026-01-01T00:00:00Z",
            "duration_seconds":1800,"distance_meters":5000,"revision":1]
        var stable = row; stable["canonical_id"] = card.uuidString
        return try JSONDecoder().decode(AccountActivityFeedPage.self, from: JSONSerialization.data(withJSONObject:
            ["version":responseVersion,"rows":emptyPage ? [] : [stable],"release_ready":false,"scope":request.scope.rawValue,"viewer_id":viewer.uuidString]))
    }
    func card(_ id: UUID) async throws -> AccountActivityCardEnvelope {
        cardCalls += 1
        return .init(version: responseVersion, viewerID: viewer, row: .init(cardID: card, canonicalID: card,
            ownerID: item.authorId, sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 1800,
            distanceMeters: 5000, revision: 1), releaseReady: false)
    }
    func approvedOwners(_ ids: [UUID]) async throws -> Set<UUID> {
        calls += 1; ownerCalls += 1
        return noOwners || (revokeFollow && ownerCalls > 1) ? [] : [item.authorId]
    }
    func legacy(cardID: UUID) async throws -> AccountActivityLegacyDetailReceipt? {
        calls += 1
        if noLink || (revokeAfterPost && !postsRequested.isEmpty) { return nil }
        return .init(version: 1, cardID: cardID, legacyPostID: item.id, releaseReady: false)
    }
    func post(id: UUID) async throws -> FeedItem? {
        calls += 1; postsRequested.append(id)
        if switchAfterPost { epoch += 1 }
        if wrongOwner { return FeedMockData.items[1] }
        return item
    }
}


@MainActor
private final class RefreshRaceFixture: AccountActivityFeedTransport {
    let viewer = UUID()
    let oldFirst = UUID(), oldSecond = UUID(), newFirst = UUID(), newSecond = UUID()
    var refreshed = false
    var pageCalls = 0
    var requestedBeforeIDs: [UUID] = []
    private var didSuspend = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    var context: AccountActivityReadContext? { .init(viewerID: viewer, generation: 1, safetyRevision: 1) }
    func waitUntilSuspended() async {
        if didSuspend { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resumeOldPage() { release?.resume(); release = nil }
    func page(_ request: AccountActivityPageRequest) async throws -> AccountActivityFeedPage {
        pageCalls += 1
        if let before = request.before?.cardID { requestedBeforeIDs.append(before) }
        if request.before?.cardID == oldFirst && !didSuspend {
            didSuspend = true
            waiter?.resume(); waiter = nil
            await withCheckedContinuation { release = $0 }
        }
        let id: UUID
        let at: String
        if request.before?.cardID == oldFirst { id = oldSecond; at = "2026-01-03T00:00:00Z" }
        else if request.before?.cardID == newFirst { id = newSecond; at = "2026-01-05T00:00:00Z" }
        else { id = refreshed ? newFirst : oldFirst; at = refreshed ? "2026-01-06T00:00:00Z" : "2026-01-04T00:00:00Z" }
        let row = AccountActivityFeedRow(cardID: id, canonicalID: id, ownerID: viewer, sport: "running",
            activityAt: at, durationSeconds: 1800, distanceMeters: 5000, revision: 1)
        return .init(version: 1, rows: [row], releaseReady: false, scope: .home, viewerID: viewer)
    }
    func approvedOwners(_ ids: [UUID]) async throws -> Set<UUID> { [] }
    func legacy(cardID: UUID) async throws -> AccountActivityLegacyDetailReceipt? { nil }
    func post(id: UUID) async throws -> FeedItem? { XCTFail("Unlinked projection must never guess a legacy post"); return nil }
}


// Append to AccountActivityFeedAdapterTests.swift to reuse its private Fixture.
@MainActor extension AccountActivityFeedAdapterTests {
    private func detail68Row(_ t: Fixture) async throws -> AccountActivityFeedRow {
        t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let receipt = try await t.card(t.card)
        var row = try XCTUnwrap(receipt.row); row.readPolicy = .profileOnlyV2
        return row
    }
    func testDetail68LinkedNavigatesOnlyToAuthorizedLegacy() async throws {
        let t = Fixture(); let row = try await detail68Row(t)
        var legacy: UUID?, summaries = 0
        try await AccountActivityDetailNavigation.perform(
            loadIfLinked: { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) },
            isCurrent: { true }, openLegacy: { legacy = $0.id }, openSummary: { summaries += 1 })
        XCTAssertEqual(legacy, t.item.id); XCTAssertEqual(summaries, 0)
    }
    func testDetail68VerifiedNilNavigatesSummaryAfterSecondCardCheck() async throws {
        let t = Fixture(); t.noLink = true; let row = try await detail68Row(t)
        let before = t.cardCalls; var legacy = 0, summaries = 0
        try await AccountActivityDetailNavigation.perform(
            loadIfLinked: { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) },
            isCurrent: { true }, openLegacy: { _ in legacy += 1 }, openSummary: { summaries += 1 })
        XCTAssertEqual(t.cardCalls - before, 2); XCTAssertTrue(t.postsRequested.isEmpty)
        XCTAssertEqual(legacy, 0); XCTAssertEqual(summaries, 1)
    }
    func testDetail68ChangedUIKeyOrVerifiedKeyDoesNotNavigate() async throws {
        for changeVerified in [false, true] {
            var key = "opening", verified = "opening", navigations = 0
            try await AccountActivityDetailNavigation.perform(loadIfLinked: {
                if changeVerified { verified = "revoked" } else { key = "new-scope" }
                return nil
            }, isCurrent: { key == "opening" && verified == "opening" },
                openLegacy: { _ in navigations += 1 }, openSummary: { navigations += 1 })
            XCTAssertEqual(navigations, 0)
        }
    }
    func testDetail68AccountChangeAndRevocationNeverFallback() async throws {
        for accountChange in [false, true] {
            let t = Fixture(); let row = try await detail68Row(t)
            t.switchAfterPost = accountChange; t.revokeAfterPost = !accountChange
            var navigations = 0
            do {
                try await AccountActivityDetailNavigation.perform(
                    loadIfLinked: { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) },
                    isCurrent: { true }, openLegacy: { _ in navigations += 1 }, openSummary: { navigations += 1 })
                XCTFail("Changed authorization must throw")
            } catch {
                XCTAssertEqual(error as? AccountActivityAdapterError, accountChange ? .accountChanged : .changedDuringRead)
            }
            XCTAssertEqual(navigations, 0)
        }
    }
    func testDetail68NetworkFailureNeverFallback() async {
        var navigations = 0
        do {
            try await AccountActivityDetailNavigation.perform(loadIfLinked: { throw URLError(.notConnectedToInternet) },
                isCurrent: { true }, openLegacy: { _ in navigations += 1 }, openSummary: { navigations += 1 })
            XCTFail("Transport errors must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(navigations, 0)
    }
    func testDetail68CancellationAfterNoncooperativeReadNeverNavigates() async {
        var navigations = 0
        let task = Task { @MainActor in
            try await AccountActivityDetailNavigation.perform(loadIfLinked: {
                // Simulate a read which returns successfully despite cancellation.
                withUnsafeCurrentTask { $0?.cancel() }
                return nil
            }, isCurrent: { true }, openLegacy: { _ in navigations += 1 }, openSummary: { navigations += 1 })
        }
        do { try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(navigations, 0)
    }
}

@MainActor extension AccountActivityFeedAdapterTests {
    func testHistoryGalleryWithoutHintUsesFreshAuthorizedLegacyHeartRate() async throws {
        let t = Fixture()
        t.readPolicy = .profileOnlyV2; t.responseVersion = 2
        let row = try await detail68Row(t)
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        var post = FeedPostDTO(id: t.item.id, userId: t.item.authorId, sourceWorkoutId: nil, sport: .running,
            title: "Synthetic history", body: nil, distanceMeters: 5000, durationSeconds: 1800, averagePaceSecondsPerKm: nil,
            averageHeartRate: nil, routeSummary: nil, visibility: .mutual, createdAt: start, updatedAt: nil)
        post.sharedDetailRevision = 1
        t.item.serverPostSnapshot = post
        t.item.sharedDetail = .init(postID: t.item.id, revision: 1,
            payload: .init(durationSeconds: 1800, distanceMeters: 5000, samples: [
                .init(seconds: 5, heartRateBPM: 120), .init(seconds: 35, heartRateBPM: 131)
            ]))
        t.item.sharedDetailContractEnabled = true
        let pre = t.cardCalls
        let fresh = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
            expectedOwnerID: row.ownerID, existingHint: nil, isCurrent: { true }
        ) { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) }
        XCTAssertEqual(t.cardCalls - pre, 2)
        XCTAssertEqual(t.postsRequested, [t.item.id])
        let record = WorkoutDetailSharedRecord(item: try XCTUnwrap(fresh))
        let telemetry = try XCTUnwrap(record.telemetry)
        let workout = record.measurementWorkout
        let points = WorkoutTelemetryChartBuilder.points(telemetry, channel: .heartRate, start: workout.startDate, end: workout.endDate)
        XCTAssertEqual(points.map(\.value), [120.0, 131.0])
        XCTAssertTrue(telemetry.heartRateZones.isEmpty)
    }

    func testHistoryGalleryWithoutHintDoesNotLoadUnlinkedOrRevokedLegacy() async throws {
        let t = Fixture()
        let row = try await detail68Row(t)
        t.noLink = true
        let result = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
            expectedOwnerID: row.ownerID, existingHint: nil, isCurrent: { true }
        ) { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) }
        XCTAssertNil(result)
        XCTAssertTrue(t.postsRequested.isEmpty)
        t.noLink = false; t.revokeAfterPost = true
        do {
            _ = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
                expectedOwnerID: row.ownerID, existingHint: nil, isCurrent: { true }
            ) { try await AccountActivityLinkedLegacyDetailAdapter(syntheticTransport: t).loadIfLinked(row: row) }
            XCTFail("Must not expose underlying post after receipt revoked")
        } catch { XCTAssertEqual(error as? AccountActivityAdapterError, .changedDuringRead) }
    }

    func testHistoryGalleryDiscardsFreshPayloadAfterScopeChangeWrongOwnerOrChangedHint() async throws {
        let t = Fixture()
        var current = true
        let stateChange = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
            expectedOwnerID: t.item.authorId, existingHint: nil, isCurrent: { current }
        ) { current = false; return t.item }
        XCTAssertNil(stateChange)
        let wrongOwner = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
            expectedOwnerID: UUID(), existingHint: nil, isCurrent: { true }
        ) { t.item }
        XCTAssertNil(wrongOwner)
        var changedHint = t.item
        changedHint = .init(id:UUID(),authorName:t.item.authorName,authorHandle:nil,authorId:t.item.authorId,
            createdAt:t.item.createdAt,itemType:t.item.itemType,visibility:t.item.visibility,cardData:t.item.cardData,
            caption:nil, photos:[],activityContext:t.item.activityContext)
        let wrongPost = try await AccountActivityDetailFallbackPolicy.resolveFreshLegacy(
            expectedOwnerID: t.item.authorId, existingHint: changedHint, isCurrent: { true }
        ) { t.item }
        XCTAssertNil(wrongPost)
    }
}
