import XCTest
@testable import SOOM

@MainActor final class Feed60LinkedCardStoreTests: XCTestCase {
    private func authority(cardID: UUID = UUID(), viewer: UUID = UUID(), batch: UUID = UUID(), grant: UUID = UUID(), epoch: Int = 1, revision: Int64 = 1) -> FeedLinkedCardAuthority {
        .init(context: .init(viewerID: viewer, accountGeneration: 2, safetyRevision: 3, returnEpoch: epoch),
              batchID: batch, grantID: grant,
              row: .init(cardID: cardID, canonicalID: UUID(), ownerID: UUID(), sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 60, distanceMeters: 100, revision: revision, readPolicy: .profileOnlyV2))
    }
    private func batch(_ a: FeedLinkedCardAuthority) -> FeedReturnBatchPresentation {
        .init(id: a.batchID, context: a.context, phase: .ready, grants: [a.row.cardID:
            .init(id: a.grantID, row: a.row, author: nil, authorRevision: nil, avatarObject: nil, photos: [], photoObjects: [:], photosAvailable: false, socialStatus: nil)])
    }
    func testRecreatedRowRestoresOnlyExactCurrentCompletedPresentation() async throws {
        let store = FeedLinkedCardStore(), a = authority(); var reads = 0
        _ = try await store.load(a, isCurrent: { true }) { reads += 1; return .init(title: "race", device: "watch", location: "masked") }
        XCTAssertEqual(store.resident(a, isCurrent: { true })?.presentation?.title, "race")
        _ = try await store.load(a, isCurrent: { true }) { reads += 1; return nil }
        XCTAssertEqual(reads, 1); XCTAssertEqual(store.startedReads, 1); XCTAssertEqual(store.hits, 1)
        XCTAssertNil(store.resident(a, isCurrent: { false }))
        let other = FeedLinkedCardAuthority(context: a.context, batchID: a.batchID, grantID: UUID(), row: a.row)
        XCTAssertNil(store.resident(other, isCurrent: { true }))
    }
    func testSuccessfulAbsenceIsCompletedAndDoesNotRefetch() async throws {
        let store = FeedLinkedCardStore(), a = authority(); var reads = 0
        _ = try await store.load(a, isCurrent: { true }) { reads += 1; return nil }
        XCTAssertNotNil(store.resident(a, isCurrent: { true }))
        XCTAssertNil(store.resident(a, isCurrent: { true })?.presentation)
        _ = try await store.load(a, isCurrent: { true }) { reads += 1; return .init(title: "wrong") }
        XCTAssertEqual(reads, 1)
    }
    func testFailureIsNotAbsenceAndCanRetry() async throws {
        let store = FeedLinkedCardStore(), a = authority()
        do { _ = try await store.load(a, isCurrent: { true }) { throw URLError(.notConnectedToInternet) }; XCTFail() } catch { }
        XCTAssertNil(store.resident(a, isCurrent: { true }))
        _ = try await store.load(a, isCurrent: { true }) { .init(title: "verified") }
        XCTAssertEqual(store.resident(a, isCurrent: { true })?.presentation?.title, "verified")
    }
    func testConcurrentWaitersJoinOneReadAndViewCancellationDoesNotEraseResult() async throws {
        let store = FeedLinkedCardStore(), a = authority(); var reads = 0
        let first = Task { try await store.load(a, isCurrent: { true }) { reads += 1; try await Task.sleep(for: .milliseconds(60)); return .init(title: "kept") } }
        await Task.yield()
        let second = Task { try await store.load(a, isCurrent: { true }) { reads += 1; return .init(title: "duplicate") } }
        first.cancel()
        let result = try await second.value
        _ = try? await first.value
        XCTAssertEqual(result.presentation?.title, "kept"); XCTAssertEqual(reads, 1)
        XCTAssertEqual(store.joinedReads, 1)
        XCTAssertEqual(store.resident(a, isCurrent: { true })?.presentation?.title, "kept")
    }
    func testRevokedReferenceFenceRejectsLateCompletion() async throws {
        let store = FeedLinkedCardStore(), a = authority(); var current = true
        let task = Task { try await store.load(a, isCurrent: { current }) {
            try await Task.sleep(for: .milliseconds(40)); return .init(title: "private")
        } }
        await Task.yield(); current = false
        do { _ = try await task.value; XCTFail("Revoked response committed") } catch { }
        XCTAssertEqual(store.count, 0)
    }
    func testClearCancelsEvenNoncooperativeLateLoader() async throws {
        let store = FeedLinkedCardStore(), a = authority()
        let task = Task { try await store.load(a, isCurrent: { true }) {
            try? await Task.sleep(for: .milliseconds(50)); return .init(title: "old")
        } }
        await Task.yield(); store.clear()
        do { _ = try await task.value; XCTFail("Cleared response committed") } catch { }
        XCTAssertEqual(store.count, 0)
    }
    func testPageMergeKeepsOldGrantButNewEpochAndDenialDiscardIt() async throws {
        let store = FeedLinkedCardStore(), a = authority()
        _ = try await store.load(a, isCurrent: { true }) { .init(title: "old") }
        store.retain(using: batch(a)); XCTAssertEqual(store.count, 1)
        var denied = batch(a); denied.denied.insert(a.row.cardID)
        store.retain(using: denied); XCTAssertEqual(store.count, 0)
        _ = try await store.load(a, isCurrent: { true }) { .init(title: "old") }
        let next = FeedReturnBatchPresentation(id: UUID(), context: a.context, phase: .pending)
        store.retain(using: next); XCTAssertEqual(store.count, 0)
    }
    func testAccountGenerationSafetyEpochAndFullRowChangeCannotReuse() async throws {
        let store = FeedLinkedCardStore(), a = authority()
        _ = try await store.load(a, isCurrent: { true }) { .init(title: "old") }
        let contexts = [FeedReturnBatchContext(viewerID: UUID(), accountGeneration: 2, safetyRevision: 3, returnEpoch: 1),
            .init(viewerID: a.context.viewerID, accountGeneration: 4, safetyRevision: 3, returnEpoch: 1),
            .init(viewerID: a.context.viewerID, accountGeneration: 2, safetyRevision: 4, returnEpoch: 1),
            .init(viewerID: a.context.viewerID, accountGeneration: 2, safetyRevision: 3, returnEpoch: 2)]
        for context in contexts { XCTAssertNil(store.resident(.init(context: context, batchID: a.batchID, grantID: a.grantID, row: a.row), isCurrent: { true })) }
        var row = a.row; row.readPolicy = .approvedFollowersV1
        XCTAssertNil(store.resident(.init(context: a.context, batchID: a.batchID, grantID: a.grantID, row: row), isCurrent: { true }))
    }
    func testEntryAndByteBudgetsDoNotExpandOnReadOrOversizedValue() async throws {
        let store = FeedLinkedCardStore(maximumCount: 2, maximumCost: 600)
        let a = authority(), b = authority(), c = authority()
        for item in [a,b,c] { _ = try await store.load(item, isCurrent: { true }) { .init(title: "short") } }
        XCTAssertEqual(store.count, 2); XCTAssertLessThanOrEqual(store.cost, 600)
        XCTAssertNil(store.resident(a, isCurrent: { true }))
        let huge = authority()
        _ = try await store.load(huge, isCurrent: { true }) { .init(title: String(repeating: "가", count: 1000)) }
        XCTAssertNil(store.resident(huge, isCurrent: { true })); XCTAssertLessThanOrEqual(store.cost, 600)
    }
    func testBatchStoreInvalidationAndFailureClearLinkedContent() async throws {
        let store = FeedReturnBatchStore(), a = authority()
        let id = store.begin(context: a.context)
        let current = FeedLinkedCardAuthority(context: a.context, batchID: id, grantID: a.grantID, row: a.row)
        XCTAssertTrue(store.publish(batch(current), expectedID: id))
        _ = try await store.linkedCards.load(current, isCurrent: { store.isCurrent(id: id, context: a.context) }) { .init(title: "value") }
        store.invalidate(); XCTAssertEqual(store.linkedCards.count, 0)
        let next = store.begin(context: a.context)
        store.fail(expectedID: next); XCTAssertEqual(store.linkedCards.count, 0)
    }
    func testCancelledNoncooperativeOperationsStillCountTowardConcurrencyBound() async throws {
        let store = FeedLinkedCardStore(maximumFlights: 2)
        var running = 0, peak = 0
        var releases: [CheckedContinuation<Void, Never>] = []
        var tasks: [Task<FeedLinkedCardStore.Completion, Error>] = []
        for _ in 0..<8 {
            let a = authority()
            tasks.append(Task { try await store.load(a, isCurrent: { true }) {
                running += 1; peak = max(peak, running)
                await withCheckedContinuation { releases.append($0) }
                running -= 1
                return .init(title: "done")
            } })
            try await Task.sleep(for: .milliseconds(3))
        }
        XCTAssertEqual(peak, 2); XCTAssertLessThanOrEqual(store.inFlightCount, 2)
        XCTAssertEqual(store.activeOperations, 2)
        while !releases.isEmpty || store.activeOperations > 0 || store.inFlightCount > 0 {
            let current = releases; releases.removeAll(); current.forEach { $0.resume() }
            try await Task.sleep(for: .milliseconds(15))
        }
        for task in tasks { _ = try? await task.value }
        XCTAssertEqual(store.maximumObservedOperations, 2); XCTAssertEqual(peak, 2)
        XCTAssertEqual(store.activeOperations, 0)
    }
    func testSameBatchGrantReplacementInvalidatesReferenceFence() async throws {
        let store = FeedReturnBatchStore(), a = authority()
        let id = store.begin(context: a.context)
        let original = FeedLinkedCardAuthority(context: a.context, batchID: id, grantID: a.grantID, row: a.row)
        XCTAssertTrue(store.publish(batch(original), expectedID: id))
        XCTAssertTrue(store.isCurrent(authority: original, context: a.context))
        let task = Task { try await store.linkedCards.load(original, isCurrent: {
            store.isCurrent(authority: original, context: a.context)
        }) {
            let replacement = FeedLinkedCardAuthority(context: a.context, batchID: id, grantID: UUID(), row: a.row)
            XCTAssertTrue(store.publish(self.batch(replacement), expectedID: id, merging: true))
            return .init(title: "old response")
        } }
        do { _ = try await task.value; XCTFail("Replaced grant returned old content") } catch { }
        XCTAssertFalse(store.isCurrent(authority: original, context: a.context))
        XCTAssertEqual(store.linkedCards.count, 0)
    }

}
