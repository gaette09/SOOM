import XCTest
@testable import SOOM

final class AccountActivityFeedContractTests: XCTestCase {
    private let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let other = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func row(_ suffix: Int = 3, owner: UUID? = nil, at: String = "2026-11-11T10:00:00+00:00", distance: Double = 5000) -> AccountActivityFeedRow {
        AccountActivityFeedRow(cardID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix))!, canonicalID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix+100))!, ownerID: owner ?? self.owner, sport: "running", activityAt: at, durationSeconds: 1800, distanceMeters: distance, revision: 1)
    }
    private func request(scope: AccountActivityScope = .home, owner: UUID? = nil, cursor: AccountActivityCursor? = nil) -> AccountActivityPageRequest {
        AccountActivityPageRequest(viewerID: self.owner, scope: scope, ownerID: owner, before: cursor, limit: 30)
    }
    private func page(_ rows: [AccountActivityFeedRow], scope: AccountActivityScope = .home) -> AccountActivityFeedPage {
        AccountActivityFeedPage(version: 1, rows: rows, releaseReady: false, scope: scope, viewerID: owner)
    }
    private func valid(_ page: AccountActivityFeedPage, request: AccountActivityPageRequest? = nil, allowed: Set<UUID> = []) throws {
        try page.validateCandidate(request: request ?? self.request(), currentViewerID: owner,
                                   allowedHomeOwners: allowed, latestPermittedDate: now)
    }
    func testPastOwnerRowsAcceptedButProductionRemainsClosed() throws {
        let p = page([row(at: "2001-01-01T00:00:00Z")])
        try valid(p)
        XCTAssertThrowsError(try p.validateForProduction(request: request(), currentViewerID: owner, allowedHomeOwners: [], latestPermittedDate: now))
    }
    func testStrictDescendingKeysetAndSameTimestampTie() throws {
        try valid(page([row(5), row(4)]))
        XCTAssertThrowsError(try valid(page([row(4), row(5)])))
        XCTAssertThrowsError(try valid(page([row(5)]), request: request(cursor: row(5).cursor)))
        try valid(page([row(4)]), request: request(cursor: row(5).cursor))
    }
    func testDuplicateCardOrOwnerCanonicalRejected() {
        XCTAssertThrowsError(try valid(page([row(), row()])))
        let first = row(5)
        let duplicate = AccountActivityFeedRow(cardID: row(4).cardID, canonicalID: first.canonicalID,
            ownerID: owner, sport: "running", activityAt: first.activityAt, durationSeconds: 1800, distanceMeters: 1, revision: 1)
        XCTAssertThrowsError(try valid(page([first, duplicate])))
    }
    func testInvalidValuesDatesAndFutureRejected() {
        for distance in [-1.0, .nan, .infinity, 10_000_001] {
            XCTAssertThrowsError(try valid(page([row(distance: distance)])))
        }
        XCTAssertThrowsError(try valid(page([row(at: "invalid")])))
        XCTAssertThrowsError(try valid(page([row(at: "2100-01-01T00:00:00Z")])))
    }
    func testHomeRequiresCurrentApprovedOwnerAndProfileDoesNotWiden() throws {
        XCTAssertThrowsError(try valid(page([row(owner: other)])))
        try valid(page([row(owner: other)]), allowed: [other])
        try valid(page([row(owner: other)], scope: .profile), request: request(scope: .profile, owner: other))
        XCTAssertThrowsError(try valid(page([row()], scope: .profile), request: request(scope: .profile, owner: other)))
    }
    func testAccountChangeAndInvalidRequestFailClosed() {
        XCTAssertThrowsError(try page([]).validateCandidate(request: request(), currentViewerID: other, allowedHomeOwners: [], latestPermittedDate: now))
        XCTAssertThrowsError(try valid(page([]), request: request(owner: other)))
        XCTAssertThrowsError(try valid(page([], scope: .profile), request: request(scope: .profile)))
    }
    func testLegacyCardAndPostIDsRemainIndependentAndContextBound() throws {
        let r = AccountActivityLegacyDetailReceipt(version: 1, cardID: row().cardID, legacyPostID: row(9).cardID, releaseReady: false)
        try r.validateCandidate(expectedCardID: row().cardID, requestViewerID: owner, currentViewerID: owner, requestGeneration: 1, currentGeneration: 1)
        XCTAssertNotEqual(r.cardID, r.legacyPostID)
        XCTAssertThrowsError(try r.validateCandidate(expectedCardID: row().cardID, requestViewerID: owner, currentViewerID: owner, requestGeneration: 1, currentGeneration: 2))
        XCTAssertThrowsError(try r.validateCandidate(expectedCardID: row(4).cardID, requestViewerID: owner, currentViewerID: owner, requestGeneration: 1, currentGeneration: 1))
        XCTAssertThrowsError(try r.validateForProduction(expectedCardID: row().cardID, requestViewerID: owner, currentViewerID: owner, requestGeneration: 1, currentGeneration: 1))
    }
    func testAllEightActivitySportsAndZeroDurationAccepted() throws {
        for sport in ["running", "cycling", "walking", "swimming", "hiking", "strength", "yoga", "other"] {
            let base = row()
            let zero = AccountActivityFeedRow(cardID: base.cardID, canonicalID: base.canonicalID,
                ownerID: owner, sport: sport, activityAt: base.activityAt, durationSeconds: 0, distanceMeters: 0, revision: 1)
            try valid(page([zero]))
        }
    }
    func testSingleCardNilIsUnavailableAndContextBound() throws {
        let unavailable = AccountActivityCardEnvelope(version: 1, viewerID: owner, row: nil, releaseReady: false)
        XCTAssertNil(try unavailable.validateCandidate(expectedCardID: row().cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now))
        XCTAssertThrowsError(try unavailable.validateCandidate(expectedCardID: row().cardID, requestViewerID: owner,
            currentViewerID: other, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now))
    }
    func testSingleCardIdentityOwnerGenerationAndGateChecked() throws {
        let target = row(owner: other)
        let card = AccountActivityCardEnvelope(version: 1, viewerID: owner, row: target, releaseReady: false)
        XCTAssertEqual(try card.validateCandidate(expectedCardID: target.cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now), target)
        XCTAssertThrowsError(try card.validateCandidate(expectedCardID: row(9).cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now))
        XCTAssertThrowsError(try card.validateCandidate(expectedCardID: target.cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 2, latestPermittedDate: now))
        XCTAssertThrowsError(try card.validateCandidate(expectedCardID: target.cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now, expectedOwnerID: owner))
        XCTAssertThrowsError(try card.validateForProduction(expectedCardID: target.cardID, requestViewerID: owner,
            currentViewerID: owner, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: now))
    }

    func testMissingDistanceRemainsNilRatherThanZero() throws {
        let base = row()
        let missing = AccountActivityFeedRow(cardID: base.cardID, canonicalID: base.canonicalID,
            ownerID: owner, sport: "strength", activityAt: base.activityAt, durationSeconds: 1800,
            distanceMeters: nil, revision: 1)
        try valid(page([missing]))
        XCTAssertNil(missing.distanceMeters)
        let json = """
        {"card_id":"\(base.cardID)","canonical_id":"\(base.canonicalID)","owner_id":"\(owner)","sport":"strength","activity_at":"2001-01-01T00:00:00Z","duration_seconds":1800,"distance_meters":null,"revision":1}
        """
        let decoded = try JSONDecoder().decode(AccountActivityFeedRow.self, from: Data(json.utf8))
        XCTAssertNil(decoded.distanceMeters)
        try valid(page([decoded]))
    }

}

final class AccountActivityPhotoProvenanceTests: XCTestCase {
    func testLegacyPhotoDecodesWithoutInventingNativeIdentity() throws {
        let id = UUID()
        let value = try JSONDecoder().decode(WorkoutPhotoReference.self, from: Data("{\"id\":\"\(id)\",\"storagePath\":\"owner/workout/photo.jpg\"}".utf8))
        XCTAssertNil(value.nativeCardID)
        XCTAssertEqual(value.bucket, WorkoutPhotoPolicy.bucket)
        XCTAssertEqual(value.cacheKey, value.storagePath)
    }
    func testNativeAndLegacySamePathCannotSharePixelCacheKey() throws {
        let id = UUID(), card = UUID()
        let legacy = WorkoutPhotoReference(id: id, storagePath: "owner/\(card)/\(id).jpg")
        let native = WorkoutPhotoReference(id: id, storagePath: legacy.storagePath, nativeCardID: card)
        XCTAssertNotEqual(native.cacheKey, legacy.cacheKey)
        XCTAssertEqual(native.bucket, "activity-photos-candidate")
        let restored = try JSONDecoder().decode(WorkoutPhotoReference.self, from: JSONEncoder().encode(native))
        XCTAssertEqual(restored.nativeCardID, card)
    }
}

final class SOOMKoreanRelativeTimeTests: XCTestCase {
    func testKoreanRelativeLabelsDoNotInheritEnglishSystemLanguage() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(SOOMKoreanRelativeTime.text(now.addingTimeInterval(-20), now: now), "방금")
        let hour = SOOMKoreanRelativeTime.text(now.addingTimeInterval(-3600), now: now)
        XCTAssertTrue(hour.contains("시간"))
        XCTAssertFalse(hour.contains("ago"))
    }
}

final class AccountActivityUnreadTotalTests: XCTestCase {
    func testDistinctCountsAndOverflowFailClosed() throws {
        XCTAssertEqual(try AccountActivityUnreadTotal.combine(legacy: 4, native: 7), 11)
        XCTAssertEqual(try AccountActivityUnreadTotal.combine(legacy: 0, native: 0), 0)
        XCTAssertThrowsError(try AccountActivityUnreadTotal.combine(legacy: Int.max, native: 1))
        XCTAssertThrowsError(try AccountActivityUnreadTotal.combine(legacy: 2, native: -1))
    }
}

/// Byte-for-byte JSON results from local PostgreSQL RPC calls, using only
/// sdk-contract-v2 synthetic identities. No production account data.
@MainActor final class ActualProfileV2SQLContractTests: XCTestCase {
    private func cases() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(actualProfileV2SQLMatrix.utf8)) as? [[String: Any]])
    }
    private func data(_ endpoint: String) throws -> Data {
        let item = try XCTUnwrap(try cases().first { $0["mode"] as? String == "active" && $0["endpoint"] as? String == endpoint })
        XCTAssertTrue(item["passed"] as? Bool == true)
        return try JSONSerialization.data(withJSONObject: item["result"]!, options: [.fragmentsAllowed, .sortedKeys])
    }
    private func object(_ endpoint: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(endpoint)) as? [String: Any])
    }
    private func card() throws -> AccountActivityCardEnvelope {
        try JSONDecoder().decode(AccountActivityCardEnvelope.self, from: data("soom_activity_card_candidate_v2"))
    }
    private func variant(_ label: String) throws -> Data {
        let container = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(actualProfileV2SQLVariants.utf8)) as? [String: Any])
        let rows = try XCTUnwrap(container["variants"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 16)
        let value = try XCTUnwrap(rows.first { $0["label"] as? String == label })
        return try JSONSerialization.data(withJSONObject: value["result"]!, options: [.fragmentsAllowed])
    }
    func testActualNullAndEmptyResultsNeverBecomeFabricatedRows() throws {
        let card = try JSONDecoder().decode(AccountActivityCardEnvelope.self, from: variant("card_null"))
        XCTAssertNil(card.row); XCTAssertTrue(card.releaseReady)
        let verified = try card.validateCandidate(expectedCardID: UUID(), requestViewerID: card.viewerID,
            currentViewerID: card.viewerID, requestGeneration: 1, currentGeneration: 1,
            latestPermittedDate: Date(timeIntervalSince1970: 2_000_000_000), expectedPolicy: .profileOnlyV2)
        XCTAssertNil(verified)
        let mapping = try JSONDecoder().decode(AccountActivityLegacyDetailReceipt?.self, from: variant("legacy_mapping_null"))
        XCTAssertNil(mapping)
        for label in ["owner_lookup_null", "source_lookup_null"] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: variant(label)) as? [String: Any])
            XCTAssertTrue(object["row"] is NSNull)
            XCTAssertEqual(object["summary_authorized"] as? Bool, false)
            XCTAssertEqual(object["profile_revision"] as? Int, 2)
        }
        let inbox = try AccountActivityNativeInboxEnvelope.decode(variant("inbox_empty"))
        XCTAssertTrue(try inbox.validated(viewer: inbox.viewerID, limit: 50, fixture: false,
            now: Date(timeIntervalSince1970: 2_000_000_000), expectedPolicy: .profileOnlyV2).isEmpty)
        let page = try JSONDecoder().decode(AccountActivityFeedPage.self, from: variant("page_empty"))
        XCTAssertTrue(page.rows.isEmpty); XCTAssertTrue(page.releaseReady)
    }
    func testActualKeysetPagesPassCursorAndPeopleDateDecoding() throws {
        let first = try JSONDecoder().decode(AccountActivityFeedPage.self, from: variant("page_first"))
        let second = try JSONDecoder().decode(AccountActivityFeedPage.self, from: variant("page_second"))
        let cursor = try XCTUnwrap(first.rows.first?.cursor)
        let owner = try XCTUnwrap(first.rows.first?.ownerID)
        try second.validateCandidate(request: .init(viewerID: first.viewerID, scope: .profile, ownerID: owner, before: cursor, limit: 1),
            currentViewerID: first.viewerID, allowedHomeOwners: [], latestPermittedDate: Date(timeIntervalSince1970: 2_000_000_000), expectedPolicy: .profileOnlyV2)
        XCTAssertNotEqual(first.rows.first?.cardID, second.rows.first?.cardID)
        let people1 = try AccountActivityNativeInboxEnvelope.decoder().decode(ProfileOnlySocialEnvelope<SocialPerson>.self, from: variant("people_page1"))
        let people2 = try AccountActivityNativeInboxEnvelope.decoder().decode(ProfileOnlySocialEnvelope<SocialPerson>.self, from: variant("people_page2"))
        let person1 = try XCTUnwrap(people1.rows.first), person2 = try XCTUnwrap(people2.rows.first)
        XCTAssertGreaterThan(person1.followedAt, person2.followedAt)
        XCTAssertTrue(person1.isFollowing); XCTAssertFalse(person1.followsViewer)
        XCTAssertNil(person1.handle); XCTAssertNil(person1.avatarPath)
        XCTAssertNotEqual(person1.id, person2.id)
        let emptyPeople = try AccountActivityNativeInboxEnvelope.decoder().decode(ProfileOnlySocialEnvelope<SocialPerson>.self, from: variant("people_empty"))
        XCTAssertTrue(emptyPeople.rows.isEmpty)
        let states = try JSONDecoder().decode(ProfileOnlySocialEnvelope<ApprovedFollowReceipt>.self, from: variant("states_empty"))
        XCTAssertTrue(states.rows.isEmpty)
    }
    func testActualEmptyCommentsAndAbsentUnavailableReceiptsPassProductionAdapter() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else { throw XCTSkip("Requires release-mode v2 adapter") }
        let card = try card(); let row = try XCTUnwrap(card.row)
        for (label, expected) in [("comment_request_absent", AccountActivityCommentResolution.absent), ("comment_request_unavailable", .unavailable)] {
            let transport = ActualSQLInteractionTransport(responses: [
                "soom_activity_interaction_status_candidate_v2": try data("soom_activity_interaction_status_candidate_v2"),
                "soom_activity_native_comments_candidate_v2": try variant("comments_empty"),
                "soom_activity_comment_request_status_candidate_v2": try variant(label)])
            let adapter = AccountActivityInteractionAdapter(transport: transport, context: {
                .init(viewerID: card.viewerID, generation: 1, safetyRevision: 1, storageScopeID: card.viewerID.uuidString.lowercased())
            }, journal: MemoryAccountActivityCommentJournal())
            let target = AccountActivityInteractionTarget.native(cardID: row.cardID, ownerID: row.ownerID)
            let comments = try await adapter.loadComments(target)
            XCTAssertTrue(comments.isEmpty)
            let result = try await adapter.resolve(target, request: .init(id: UUID(), body: "synthetic", mentions: [], parentID: nil))
            XCTAssertEqual(result, expected)
        }
    }
    func testActualExistingDetailLookupAndRefreshPassServiceCASValidation() async throws {
        let lookup = try JSONDecoder().decode(WorkoutExistingDetailLookup.self, from: data("soom_existing_detail_refresh_lookup_v2"))
        let receipt = try JSONDecoder().decode(WorkoutExistingDetailRefreshReceipt.self, from: data("soom_refresh_existing_detail_candidate_v2"))
        let transport = ActualSQLDetailTransport(lookupValue: lookup, receiptValue: receipt)
        let service = WorkoutExistingDetailRefreshService(transport: transport)
        var inputReads = 0
        let count = try await service.refresh(sourceID: lookup.source_id, ownerID: lookup.owner_id, validate: {}, loadInput: {
            inputReads += 1
            return .init(durationSeconds: 600, distanceMeters: 1000)
        })
        XCTAssertEqual(count, 1); XCTAssertEqual(inputReads, 1); XCTAssertEqual(transport.writes, 1)
        let empty = try JSONDecoder().decode(WorkoutExistingDetailLookup.self, from: variant("detail_lookup_empty"))
        let noGrant = ActualSQLDetailTransport(lookupValue: empty, receiptValue: receipt)
        let skipped = try await WorkoutExistingDetailRefreshService(transport: noGrant).refresh(sourceID: empty.source_id, ownerID: empty.owner_id, validate: {}, loadInput: {
            XCTFail("A missing existing grant must not read route or measurement input")
            return .init(durationSeconds: 0, distanceMeters: nil)
        })
        XCTAssertEqual(skipped, 0); XCTAssertEqual(noGrant.writes, 0)
    }
    func testActualCatalogMatrixCoversEveryEndpointActiveKillAndDrift() throws {
        let values = try cases()
        XCTAssertEqual(values.count, 81)
        XCTAssertEqual(Set(values.compactMap { $0["endpoint"] as? String }).count, 27)
        XCTAssertTrue(values.allSatisfy { $0["passed"] as? Bool == true })
        for mode in ["active", "kill", "hash_drift"] { XCTAssertEqual(values.filter { $0["mode"] as? String == mode }.count, 27) }
        let photos = try XCTUnwrap(values.first { $0["mode"] as? String == "active" && $0["endpoint"] as? String == "soom_activity_photos_candidate_v2" })
        XCTAssertEqual(photos["error_code"] as? String, "42501")
    }
    func testActualPrivacyReadSaveWithdrawalDecodeWithMeasurementRevision() throws {
        var values: [ProfileOnlyPrivacyReceipt] = []
        for endpoint in ["soom_profile_privacy_candidate_v2", "soom_set_profile_privacy_candidate_v2", "soom_withdraw_measurements_candidate_v2"] {
            let value = try JSONDecoder().decode(ProfileOnlyPrivacyReceipt.self, from: data(endpoint))
            try value.validate(owner: value.ownerID)
            XCTAssertEqual(value.releaseReady, true)
            XCTAssertNotNil(value.measurementRevision)
            values.append(value)
        }
        XCTAssertEqual(values[0].measurementRevision, 1)
        XCTAssertEqual(values[1].measurementRevision, 1)
        XCTAssertEqual(values[2].measurementRevision, 2)
        XCTAssertFalse(values[2].shareMeasurements)
        XCTAssertEqual(values[1].workoutAudience, .mutual)
    }
    func testActualPageCardMappingAndFollowingDecodeWithoutIdentityCoercion() throws {
        let receipt = try card()
        let row = try XCTUnwrap(receipt.row)
        let viewer = receipt.viewerID
        let verified = try receipt.validateCandidate(expectedCardID: row.cardID, requestViewerID: viewer,
            currentViewerID: viewer, requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(timeIntervalSince1970: 2_000_000_000), expectedOwnerID: row.ownerID, expectedPolicy: .profileOnlyV2)
        XCTAssertEqual(verified?.readPolicy, .profileOnlyV2)
        let page = try JSONDecoder().decode(AccountActivityFeedPage.self, from: data("soom_activity_page_candidate_v2"))
        try page.validateCandidate(request: .init(viewerID: viewer, scope: .profile, ownerID: row.ownerID, before: nil, limit: 30), currentViewerID: viewer, allowedHomeOwners: [], latestPermittedDate: Date(timeIntervalSince1970: 2_000_000_000), expectedPolicy: .profileOnlyV2)
        XCTAssertTrue(page.releaseReady)
        let mapping = try JSONDecoder().decode(AccountActivityLegacyDetailReceipt.self, from: data("soom_activity_legacy_detail_candidate_v2"))
        try mapping.validateCandidate(expectedCardID: row.cardID, requestViewerID: viewer, currentViewerID: viewer, requestGeneration: 1, currentGeneration: 1)
        XCTAssertTrue(mapping.releaseReady)
        XCTAssertEqual(mapping.version, 1)
        XCTAssertNotEqual(mapping.legacyPostID, row.cardID)
        _ = try JSONDecoder().decode([UUID].self, from: data("soom_activity_following_candidate_v2"))
    }
    func testActualStageAndOwnerLookupRowsDecodeDatesArraysAndGrant() throws {
        let stage = try JSONDecoder().decode(AccountActivityStageReceipt.self, from: data("soom_activity_stage_candidate_v2"))
        XCTAssertEqual(stage.version, 2); XCTAssertTrue(stage.release_ready); XCTAssertEqual(stage.summary_authorized, true)
        for endpoint in ["soom_activity_owner_lookup_candidate_v2", "soom_activity_owner_source_lookup_candidate_v2"] {
            let value = try object(endpoint)
            XCTAssertEqual(value["profile_revision"] as? Int, 2)
            XCTAssertEqual(value["summary_authorized"] as? Bool, true)
            let rowData = try JSONSerialization.data(withJSONObject: value["row"]!)
            let row = try AccountActivityNativeInboxEnvelope.decoder().decode(AccountActivityStageLookup.self, from: rowData)
            XCTAssertTrue(row.source_ids.contains(row.canonical_id)); XCTAssertFalse(row.deleted)
        }
    }
    func testActualInboxAndEventStateDecodeAndValidate() throws {
        let envelope = try AccountActivityNativeInboxEnvelope.decode(data("soom_activity_native_inbox_candidate_v2"))
        let rows = try envelope.validated(viewer: envelope.viewerID, limit: 50, fixture: false, now: Date(timeIntervalSince1970: 2_000_000_000), expectedPolicy: .profileOnlyV2)
        XCTAssertEqual(rows.count, 1)
        let state = try AccountActivityNativeInboxEnvelope.decoder().decode(AccountActivityNativeInboxStateReceipt.self, from: data("soom_activity_native_event_state_candidate_v2"))
        XCTAssertEqual(state.eventID, rows[0].eventID); XCTAssertEqual(state.commentID, rows[0].commentID)
        XCTAssertEqual(state.sourceKind, "activity_native_v2"); XCTAssertEqual(state.version, 2); XCTAssertTrue(state.releaseReady)
        XCTAssertNotNil(state.readAt); XCTAssertNil(state.hiddenAt)
    }
    func testActualCommentsStatusAndRequestReceiptPassProductionAdapter() async throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else { throw XCTSkip("Requires release-mode v2 adapter") }
        let card = try card(); let row = try XCTUnwrap(card.row)
        let transport = ActualSQLInteractionTransport(responses: [
            "soom_activity_interaction_status_candidate_v2": try data("soom_activity_interaction_status_candidate_v2"),
            "soom_activity_native_comments_candidate_v2": try data("soom_activity_native_comments_candidate_v2"),
            "soom_activity_comment_request_status_candidate_v2": try data("soom_activity_comment_request_status_candidate_v2")])
        let adapter = AccountActivityInteractionAdapter(transport: transport, context: {
            .init(viewerID: card.viewerID, generation: 1, safetyRevision: 1, storageScopeID: card.viewerID.uuidString.lowercased())
        }, journal: MemoryAccountActivityCommentJournal())
        let target = AccountActivityInteractionTarget.native(cardID: row.cardID, ownerID: row.ownerID)
        let comments = try await adapter.loadComments(target)
        XCTAssertEqual(comments.count, 2)
        let mine = try XCTUnwrap(comments.first { $0.author_id == card.viewerID })
        let resolution = try await adapter.resolve(target, request: .init(id: mine.id, body: mine.body, mentions: mine.mentions, parentID: mine.reply_to_id))
        XCTAssertEqual(resolution, .found)
        for name in ["soom_activity_native_add_comment_candidate_v2", "soom_activity_add_reply_candidate_v2"] { _ = try JSONDecoder().decode(UUID.self, from: data(name)) }
        for name in ["soom_activity_native_delete_comment_candidate_v2", "soom_activity_delete_reply_candidate_v2"] { XCTAssertTrue(try JSONDecoder().decode(Bool.self, from: data(name))) }
    }
    func testActualRankingAndSocialEnvelopesPassProductionValidation() throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady else { throw XCTSkip("Requires release-mode v2 adapter") }
        let viewer = try card().viewerID
        let ranking = try JSONDecoder().decode(AccountActivityRankingWire.self, from: data("soom_activity_ranking_totals_candidate_v2"))
        _ = try AccountActivityRankingAdapter.validate(ranking, request: .init(p_period: "week", p_sport: "running", p_metric: "distance"), viewer: viewer, isFixture: false, expectedPolicy: .profileOnlyV2)
        let summary = try JSONDecoder().decode(ProfileOnlySocialEnvelope<SocialSummary>.self, from: data("soom_social_summary_candidate_v2"))
        XCTAssertEqual(try summary.validated(viewer: viewer, currentViewer: viewer).count, 1)
        let people = try AccountActivityNativeInboxEnvelope.decoder().decode(ProfileOnlySocialEnvelope<SocialPerson>.self, from: data("soom_social_people_candidate_v2"))
        XCTAssertTrue(try people.validated(viewer: viewer, currentViewer: viewer).isEmpty)
        for endpoint in ["soom_follow_state_candidate_v2", "soom_request_follow_candidate_v2"] {
            let value = try JSONDecoder().decode(ProfileOnlySocialEnvelope<ApprovedFollowReceipt>.self, from: data(endpoint))
            let rows = try value.validated(viewer: viewer, currentViewer: viewer)
            XCTAssertEqual(rows.count, 1); XCTAssertNil(rows[0].requestID); XCTAssertNotNil(rows[0].edgeRevision)
            XCTAssertNotNil(rows[0].followsViewer); XCTAssertNotNil(rows[0].legacyPending); XCTAssertNotEqual(rows[0].state, .pending)
        }
    }
}
@MainActor private final class ActualSQLInteractionTransport: AccountActivityInteractionTransport {
    let readPolicy: AccountActivityReadPolicy = .profileOnlyV2
    let responses: [String: Data]
    init(responses: [String: Data]) { self.responses = responses }
    func call(_ name: String, params: AccountActivityInteractionParameters) async throws -> Data {
        guard let data = responses[name] else { throw AccountActivityInteractionError.invalidRequest }
        return data
    }
}

// Source SQL response file SHA256: 31b9b8d0db22a347acbf473702290d0cd680018a31b024c88e868c63251532d7
private let actualProfileV2SQLMatrix = #"""
[{"mode":"active","passed":true,"result":"cbe880d7-d373-1f7e-8c57-68be6242f02e","endpoint":"soom_activity_add_reply_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"row":{"sport":"running","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"activity_at":"2026-11-13T11:10:40.262693+09:00","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","distance_meters":1000,"duration_seconds":600},"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_card_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"state":"found","backing":"native","receipt":{"id":"4951ad00-b17f-7407-bf74-2011d3764103","body":"synthetic owner comment","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","mentions":[],"author_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","parent_id":null,"created_at":"2026-11-13T11:10:40.267515+09:00","deleted_at":null,"reply_to_id":null},"version":2,"release_ready":true},"endpoint":"soom_activity_comment_request_status_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":true,"endpoint":"soom_activity_delete_reply_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":[],"endpoint":"soom_activity_following_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"state":"native_ready","backing":"native","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","version":2,"release_ready":true},"endpoint":"soom_activity_interaction_status_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","version":1,"release_ready":true,"legacy_post_id":"9ebdb93d-70c1-9d41-3d65-a81dd3fee596"},"endpoint":"soom_activity_legacy_detail_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":"8cb894b4-2fe0-1ac5-e13b-e0c472c63bd8","endpoint":"soom_activity_native_add_comment_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"id":"4951ad00-b17f-7407-bf74-2011d3764103","body":"synthetic owner comment","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","mentions":[],"author_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","parent_id":null,"created_at":"2026-11-13T11:10:40.267515+09:00","is_deleted":false,"reply_to_id":null},{"id":"dfc326c3-d95d-02e5-cc23-3ac93739080f","body":"synthetic recipient event","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","mentions":[],"author_id":"34a3ebca-68ef-4d55-0290-d32df561988a","parent_id":null,"created_at":"2026-11-13T11:10:40.267515+09:00","is_deleted":false,"reply_to_id":null}],"backing":"native","version":2,"release_ready":true},"endpoint":"soom_activity_native_comments_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":true,"endpoint":"soom_activity_native_delete_comment_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"read_at":"2026-11-13T11:10:40.27709+09:00","version":2,"event_id":"8961a6cb-0311-40d5-89c7-f1e2731cce68","hidden_at":null,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","comment_id":"dfc326c3-d95d-02e5-cc23-3ac93739080f","source_kind":"activity_native_v2","release_ready":true},"endpoint":"soom_activity_native_event_state_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"reason":"comment","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","read_at":null,"actor_id":"34a3ebca-68ef-4d55-0290-d32df561988a","event_id":"8961a6cb-0311-40d5-89c7-f1e2731cce68","comment_id":"dfc326c3-d95d-02e5-cc23-3ac93739080f","created_at":"2026-11-13T11:10:40.267945+09:00"}],"backing":"native","version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","source_kind":"activity_native_v2","unread_count":1,"push_delivery":"candidate_disabled","release_ready":true},"endpoint":"soom_activity_native_inbox_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"row":{"sport":"running","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","deleted":false,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"source_ids":["1dc8a6b8-6539-2d73-09ef-83728d2f82c4"],"activity_at":"2026-11-13T11:10:40.262693+09:00","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","distance_meters":1000,"duration_seconds":600},"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true,"profile_revision":2,"summary_authorized":true},"endpoint":"soom_activity_owner_lookup_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"row":{"sport":"running","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","deleted":false,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"source_ids":["1dc8a6b8-6539-2d73-09ef-83728d2f82c4"],"activity_at":"2026-11-13T11:10:40.262693+09:00","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","distance_meters":1000,"duration_seconds":600},"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true,"profile_revision":2,"summary_authorized":true},"endpoint":"soom_activity_owner_source_lookup_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"sport":"running","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"activity_at":"2026-11-13T11:10:40.262693+09:00","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","distance_meters":1000,"duration_seconds":600}],"scope":"profile","version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_page_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":null,"endpoint":"soom_activity_photos_candidate_v2","error_code":"42501"},{"mode":"active","passed":true,"result":{"top":[{"rank":1,"badge":null,"value":1500,"user_id":"27a6c86b-7430-c8d7-fac1-2d8ffe3f7cdb","display_name":"SOOM \uc0ac\uc6a9\uc790"},{"rank":2,"badge":null,"value":1000,"user_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","display_name":"SOOM \uc0ac\uc6a9\uc790"}],"unit":"meters","as_of":"2026-11-13T11:10:40.27709+09:00","scope":"public_profile_v2_auto","sport":"running","total":2,"metric":"distance","period":"week","my_rank":2,"version":2,"around_me":[{"rank":1,"badge":null,"value":1500,"user_id":"27a6c86b-7430-c8d7-fac1-2d8ffe3f7cdb","display_name":"SOOM \uc0ac\uc6a9\uc790"},{"rank":2,"badge":null,"value":1000,"user_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","display_name":"SOOM \uc0ac\uc6a9\uc790"}],"time_zone":"Asia/Seoul","viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","period_end":"2026-11-16T00:00:00+09:00","period_start":"2026-11-09T00:00:00+09:00","deduplication":"canonical_workout_group","release_ready":true,"measurement_verification":"profile_v2_summary_grant"},"endpoint":"soom_activity_ranking_totals_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"staged":true,"card_id":"87602770-b330-41a8-8c77-63de9f30e093","version":2,"revision":1,"canonical_id":"4cfca124-b230-240d-9450-0b46eb3c1eba","release_ready":true,"profile_revision":2,"summary_authorized":true},"endpoint":"soom_activity_stage_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"post_id":"9ebdb93d-70c1-9d41-3d65-a81dd3fee596","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","detail_revision":0}],"version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","source_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","release_ready":true,"profile_revision":2,"measurement_revision":1},"endpoint":"soom_existing_detail_refresh_lookup_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"state":"none","user_id":"34a3ebca-68ef-4d55-0290-d32df561988a","revision":0,"request_id":null,"account_scope":"public","follows_viewer":false,"legacy_pending":false}],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_follow_state_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"enabled":true,"version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":2,"account_scope":"public","release_ready":true,"share_measurements":true,"measurement_revision":1},"endpoint":"soom_profile_privacy_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"post_id":"9ebdb93d-70c1-9d41-3d65-a81dd3fee596","version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","refreshed":true,"source_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","release_ready":true,"detail_revision":0,"profile_revision":2,"measurement_revision":1},"endpoint":"soom_refresh_existing_detail_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"state":"accepted","user_id":"34a3ebca-68ef-4d55-0290-d32df561988a","revision":1,"request_id":null,"account_scope":"public","follows_viewer":false,"legacy_pending":false}],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_request_follow_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"enabled":true,"version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":3,"account_scope":"private","release_ready":true,"share_measurements":true,"measurement_revision":1},"endpoint":"soom_set_profile_privacy_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_social_people_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"rows":[{"post_count":1,"follower_count":0,"following_count":0}],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_social_summary_candidate_v2","error_code":null},{"mode":"active","passed":true,"result":{"enabled":true,"version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":2,"account_scope":"public","release_ready":true,"share_measurements":false,"measurement_revision":2},"endpoint":"soom_withdraw_measurements_candidate_v2","error_code":null},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_add_reply_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_card_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":{"state":"unavailable"},"endpoint":"soom_activity_comment_request_status_candidate_v2","error_code":null},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_delete_reply_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_following_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_interaction_status_candidate_v2","error_code":null},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_legacy_detail_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_native_add_comment_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_native_comments_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_native_delete_comment_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_native_event_state_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_native_inbox_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_owner_lookup_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_owner_source_lookup_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_page_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_photos_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_ranking_totals_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_activity_stage_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_existing_detail_refresh_lookup_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_follow_state_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_profile_privacy_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_refresh_existing_detail_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_request_follow_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_set_profile_privacy_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_social_people_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_social_summary_candidate_v2","error_code":"42501"},{"mode":"hash_drift","passed":true,"result":null,"endpoint":"soom_withdraw_measurements_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_add_reply_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_card_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":{"state":"unavailable"},"endpoint":"soom_activity_comment_request_status_candidate_v2","error_code":null},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_delete_reply_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_following_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_interaction_status_candidate_v2","error_code":null},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_legacy_detail_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_native_add_comment_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_native_comments_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_native_delete_comment_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_native_event_state_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_native_inbox_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_owner_lookup_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_owner_source_lookup_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_page_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_photos_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_ranking_totals_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_activity_stage_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_existing_detail_refresh_lookup_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_follow_state_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_profile_privacy_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_refresh_existing_detail_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_request_follow_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_set_profile_privacy_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_social_people_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_social_summary_candidate_v2","error_code":"42501"},{"mode":"kill","passed":true,"result":null,"endpoint":"soom_withdraw_measurements_candidate_v2","error_code":"42501"}]
"""#

// Source actual SQL variants SHA256: bd8a5676dcd13bfd860d6b4edf61f7946d440218f8a577ae3b632407d7deb18a
private let actualProfileV2SQLVariants = #"""
{"variants":[{"label":"card_null","result":{"row":null,"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_card_candidate_v2"},{"label":"comment_request_absent","result":{"state":"absent","backing":"native","version":2,"release_ready":true},"endpoint":"soom_activity_comment_request_status_candidate_v2"},{"label":"comment_request_unavailable","result":{"state":"unavailable"},"endpoint":"soom_activity_comment_request_status_candidate_v2"},{"label":"comments_empty","result":{"rows":[],"backing":"native","version":2,"release_ready":true},"endpoint":"soom_activity_native_comments_candidate_v2"},{"label":"detail_lookup_empty","result":{"rows":[],"version":2,"owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","source_id":"cab4c3e8-7a52-cf71-54c1-d2073ad25803","release_ready":true,"profile_revision":2,"measurement_revision":1},"endpoint":"soom_existing_detail_refresh_lookup_v2"},{"label":"inbox_empty","result":{"rows":[],"backing":"native","version":2,"viewer_id":"34a3ebca-68ef-4d55-0290-d32df561988a","source_kind":"activity_native_v2","unread_count":0,"push_delivery":"candidate_disabled","release_ready":true},"endpoint":"soom_activity_native_inbox_candidate_v2"},{"label":"legacy_mapping_null","result":null,"endpoint":"soom_activity_legacy_detail_candidate_v2"},{"label":"owner_lookup_null","result":{"row":null,"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true,"profile_revision":2,"summary_authorized":false},"endpoint":"soom_activity_owner_lookup_candidate_v2"},{"label":"page_empty","result":{"rows":[],"scope":"profile","version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_page_candidate_v2"},{"label":"page_first","result":{"rows":[{"sport":"running","card_id":"0f2b93f3-582e-4b9c-acbc-d45a9269587a","owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"activity_at":"2026-11-13T11:10:40.262693+09:00","canonical_id":"1dc8a6b8-6539-2d73-09ef-83728d2f82c4","distance_meters":1000,"duration_seconds":600}],"scope":"profile","version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_page_candidate_v2"},{"label":"page_second","result":{"rows":[{"sport":"running","card_id":"9cf8f871-b809-45f9-a3aa-ed6de89a4f1f","owner_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","revision":1,"activity_at":"2020-01-02T00:00:00+09:00","canonical_id":"4cfca124-b230-240d-9450-0b46eb3c1eba","distance_meters":200,"duration_seconds":120}],"scope":"profile","version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_activity_page_candidate_v2"},{"label":"people_empty","result":{"rows":[],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_social_people_candidate_v2"},{"label":"people_page1","result":{"rows":[{"id":"34a3ebca-68ef-4d55-0290-d32df561988a","handle":null,"avatar_path":null,"followed_at":"2020-01-02T00:00:00+09:00","display_name":"SOOM \uc0ac\uc6a9\uc790","is_following":true,"follows_viewer":false}],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_social_people_candidate_v2"},{"label":"people_page2","result":{"rows":[{"id":"4881e8b1-8020-8be6-a663-e96a3d093d6b","handle":null,"avatar_path":null,"followed_at":"2020-01-01T00:00:00+09:00","display_name":"SOOM \uc0ac\uc6a9\uc790","is_following":true,"follows_viewer":false}],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_social_people_candidate_v2"},{"label":"source_lookup_null","result":{"row":null,"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true,"profile_revision":2,"summary_authorized":false},"endpoint":"soom_activity_owner_source_lookup_candidate_v2"},{"label":"states_empty","result":{"rows":[],"version":2,"viewer_id":"f0a54e95-b84e-b6b2-bb00-47f06d6e9eb8","release_ready":true},"endpoint":"soom_follow_state_candidate_v2"}]}
"""#

@MainActor private final class ActualSQLDetailTransport: WorkoutExistingDetailRefreshTransport {
    let lookupValue: WorkoutExistingDetailLookup
    let receiptValue: WorkoutExistingDetailRefreshReceipt
    var ownerID: UUID? { lookupValue.owner_id }
    var writes = 0
    init(lookupValue: WorkoutExistingDetailLookup, receiptValue: WorkoutExistingDetailRefreshReceipt) {
        self.lookupValue = lookupValue; self.receiptValue = receiptValue
    }
    func lookup(sourceID: UUID) async throws -> WorkoutExistingDetailLookup {
        XCTAssertEqual(sourceID, lookupValue.source_id)
        return lookupValue
    }
    func refresh(_ parameters: WorkoutExistingDetailRefreshParameters) async throws -> WorkoutExistingDetailRefreshReceipt {
        XCTAssertEqual(parameters.p_post_id, lookupValue.rows.first?.post_id)
        XCTAssertEqual(parameters.p_source_id, lookupValue.source_id)
        XCTAssertEqual(parameters.p_expected_profile_revision, lookupValue.profile_revision)
        XCTAssertEqual(parameters.p_expected_measurement_revision, lookupValue.measurement_revision)
        XCTAssertEqual(parameters.p_expected_detail_revision, lookupValue.rows.first?.detail_revision)
        writes += 1
        return receiptValue
    }
}
