import SwiftData
import XCTest
@testable import SOOM

final class OwnerWorkoutFeedProjectionTests: XCTestCase {
    let owner = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!

    func workout(_ id: UUID = UUID(), date: Date = Date(timeIntervalSince1970: 1_000), source: UnifiedDataSource = .soomLocal) -> UnifiedWorkout {
        UnifiedWorkout(id: id, externalId: nil, source: source, workoutType: .running,
                       startDate: date, endDate: date.addingTimeInterval(1800), durationSeconds: 1800,
                       distanceMeters: 5000, activeEnergyKcal: nil, averageHeartRate: nil,
                       maxHeartRate: nil, averageSpeedMetersPerSecond: nil, elevationGainMeters: nil,
                       dataQuality: .complete, createdAt: date, updatedAt: date)
    }

    func testOldPrivateWorkoutAutomaticallyVisibleOnlyLocally() {
        var old = workout()
        old.sharingVisibilityRaw = "private"
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [old], ownerID: owner, scopeID: "owner")
        XCTAssertEqual(snapshot.entries.count, 1)
        let item = snapshot.entries[0].item
        XCTAssertEqual(item.sourceWorkoutId, old.id)
        XCTAssertEqual(item.authorId, owner)
        XCTAssertTrue(item.isLocalDraft) // Remote action protection remains on.
        XCTAssertTrue(item.isOwnerLocalWorkout)
        XCTAssertEqual(item.visibility, .privateOnly)
        XCTAssertNil(item.serverPostSnapshot)
        XCTAssertNil(item.recoveryCue)
        XCTAssertNil(item.caption)
    }

    func testSameCanonicalIDsAsActivityIncludingLateSource() {
        let first = workout()
        let watch = workout(source: .appleHealthKit)
        let input = [watch, first]
        let actual = OwnerWorkoutFeedProjection.make(workouts: input, ownerID: owner, scopeID: "owner")
        let expected = UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(input)
        XCTAssertEqual(actual.entries.map(\.canonicalID), expected.map(\.id))
        XCTAssertEqual(actual.entries.count, 1)
        XCTAssertEqual(actual.entries[0].sourceIDs, Set([first.id, watch.id]))
    }

    func testAccountOrScopeChangeFailsClosed() {
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [workout()], ownerID: owner, scopeID: "a")
        XCTAssertTrue(snapshot.merging(serverItems: [], currentOwnerID: UUID(), currentScopeID: "a").isEmpty)
        XCTAssertTrue(snapshot.merging(serverItems: [], currentOwnerID: owner, currentScopeID: "b").isEmpty)
        XCTAssertTrue(snapshot.merging(serverItems: [], currentOwnerID: nil, currentScopeID: "a").isEmpty)
    }

    func testExistingPostIdentityAndCommentsAreNotReplacedByProjection() {
        let work = workout()
        let local = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "a").entries[0].item
        let post = FeedItem(id: UUID(), authorName: "Owner", authorHandle: nil, authorId: owner,
                            createdAt: work.createdAt, itemType: .workoutSession, visibility: .publicFeed,
                            cardData: local.cardData, sourceWorkoutId: work.id, caption: "existing caption",
                            activityContext: "existing",
                            reactions: [FeedReaction(symbol: "heart", label: "응원")],
                            comments: [FeedComment(id: UUID(), authorId: UUID(), body: "existing reply", createdAt: work.createdAt, isViewerAuthor: false)],
                            activityDate: work.startDate)
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "a", serverItems: [post])
        XCTAssertEqual(snapshot.entries[0].item, post)
        XCTAssertEqual(snapshot.entries[0].existingServerItems, [post])
        XCTAssertEqual(snapshot.merging(serverItems: [post], currentOwnerID: owner, currentScopeID: "a"), [post])
        let refreshed = snapshot.merging(serverItems: [], currentOwnerID: owner, currentScopeID: "a")
        XCTAssertTrue(refreshed[0].isOwnerLocalWorkout)
        XCTAssertNotEqual(refreshed[0].id, post.id)
    }

    func testOtherAuthorSameSourceIDNeverSuppressesOwnerWorkout() {
        let work = workout()
        let local = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "a").entries[0].item
        let other = FeedItem(id: UUID(), authorName: "Other", authorHandle: nil, authorId: UUID(),
                             createdAt: work.createdAt, itemType: .workoutSession, visibility: .publicFeed,
                             cardData: local.cardData, sourceWorkoutId: work.id, caption: nil, activityContext: "other")
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "a", serverItems: [other])
        XCTAssertTrue(snapshot.entries[0].item.isOwnerLocalWorkout)
        XCTAssertEqual(snapshot.merging(serverItems: [other], currentOwnerID: owner, currentScopeID: "a").count, 2)
    }
    func testSecondPageLateWatchAliasNormalizationRemovesLocalDuplicate() {
        let first = workout()
        let firstSnapshot = OwnerWorkoutFeedProjection.make(workouts: [first], ownerID: owner, scopeID: "owner")
        let initialTimeline = firstSnapshot.merging(serverItems: [], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(initialTimeline.count, 1)
        let watch = workout(source: .appleHealthKit)
        let post = FeedItem(id: UUID(), authorName: "Owner", authorHandle: nil, authorId: owner,
            createdAt: watch.createdAt, itemType: .workoutSession, visibility: .publicFeed,
            cardData: initialTimeline[0].cardData, sourceWorkoutId: watch.id, caption: "existing watch post",
            activityContext: "watch", comments: [FeedComment(id: UUID(), authorId: owner,
                body: "keep this comment", createdAt: watch.createdAt, isViewerAuthor: true)], activityDate: watch.startDate)
        let refreshed = OwnerWorkoutFeedProjection.make(workouts: [watch, first], ownerID: owner, scopeID: "owner")
        let normalized = refreshed.merging(serverItems: initialTimeline + [post], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(refreshed.entries.count, 1)
        XCTAssertEqual(normalized, [post])
        XCTAssertFalse(normalized[0].isOwnerLocalWorkout)
        XCTAssertEqual(normalized[0].comments, post.comments)
        // Re-normalizing a later page does not create a second card.
        XCTAssertEqual(refreshed.merging(serverItems: normalized, currentOwnerID: owner, currentScopeID: "owner"), normalized)
    }

    func testRemoteOnlyOwnerRecordIsPreservedEvenWhenLocalActivityIsAbsent() {
        let local = workout()
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [local], ownerID: owner, scopeID: "owner")
        let remote = FeedItem(id: UUID(), authorName: "Owner", authorHandle: nil, authorId: owner,
            createdAt: local.createdAt, itemType: .workoutSession, visibility: .privateOnly,
            cardData: snapshot.entries[0].item.cardData, sourceWorkoutId: UUID(), caption: "another device",
            activityContext: "remote only", activityDate: local.startDate.addingTimeInterval(-86400))
        let merged = snapshot.merging(serverItems: [remote], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.id == remote.id }), remote)
        let empty = OwnerWorkoutFeedProjection.make(workouts: [], ownerID: owner, scopeID: "owner")
        XCTAssertEqual(empty.merging(serverItems: [remote], currentOwnerID: owner, currentScopeID: "owner"), [remote])
    }

    /// Diagnostic fixture: legacy posts without route.startedAt retain publication
    /// time, while the owner article renders its exact local workout start.
    func testLegacyLatePublicationUsesVerifiedStartWithoutChangingRemoteReceipt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let work = workout(date: start)
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "owner")
        let latePublication = start.addingTimeInterval(7 * 86400)
        let followingStart = start.addingTimeInterval(86400)
        let ownPost = FeedItem(id: UUID(), authorName: "Owner", authorHandle: nil, authorId: owner,
            createdAt: latePublication, itemType: .workoutSession, visibility: .publicFeed,
            cardData: snapshot.entries[0].localItem.cardData, sourceWorkoutId: work.id,
            caption: "preserved", activityContext: "legacy", activityDate: latePublication)
        let following = FeedItem(id: UUID(), authorName: "Following", authorHandle: nil, authorId: UUID(),
            createdAt: followingStart, itemType: .workoutSession, visibility: .publicFeed,
            cardData: snapshot.entries[0].localItem.cardData, caption: nil,
            activityContext: "public summary", activityDate: followingStart)
        let merged = snapshot.merging(serverItems: [following, ownPost], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(merged.map(\.id), [following.id, ownPost.id])
        let projected = merged[1]
        var withoutPresentation = projected; withoutPresentation.verifiedOwnerStartDate = nil
        XCTAssertEqual(withoutPresentation, ownPost, "Every remote field and receipt remains unchanged")
        XCTAssertEqual(projected.verifiedOwnerStartDate, start)
        XCTAssertEqual(projected.activityDate, latePublication, "Raw server cursor date must not be overwritten")
        XCTAssertEqual(FeedDisplayOrder.date(projected, localStart: work.startDate), start)
        XCTAssertGreaterThan(FeedDisplayOrder.date(merged[0]), FeedDisplayOrder.date(merged[1]))
        XCTAssertEqual(snapshot.merging(serverItems: merged, currentOwnerID: owner, currentScopeID: "owner"), merged)
        XCTAssertEqual(work.startDate, start)
        // Empty current snapshot strips an obsolete override instead of trusting it.
        let empty = OwnerWorkoutFeedProjection.make(workouts: [], ownerID: owner, scopeID: "owner")
        XCTAssertEqual(empty.merging(serverItems: [projected], currentOwnerID: owner, currentScopeID: "owner"), [ownPost])
        XCTAssertTrue(snapshot.merging(serverItems: merged, currentOwnerID: UUID(), currentScopeID: "owner").isEmpty)
        // Coverage still comes from raw remote dates, before display projection.
        XCTAssertEqual([ownPost, following].map { $0.activityDate ?? $0.createdAt }.min(), followingStart)
        XCTAssertEqual([projected, following].map { $0.activityDate ?? $0.createdAt }.min(), followingStart)

    }

    func testDisplayOrderUsesStableDescendingIDAndPreservesOtherAuthor() {
        let work = workout()
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "owner")
        func post(_ id: String) -> FeedItem {
            FeedItem(id: UUID(uuidString: id)!, authorName: "Other", authorHandle: nil, authorId: UUID(),
                createdAt: work.startDate, itemType: .workoutSession, visibility: .publicFeed,
                cardData: snapshot.entries[0].localItem.cardData, sourceWorkoutId: work.id,
                caption: nil, activityContext: "other", activityDate: work.startDate)
        }
        let low = post("00000000-0000-4000-8000-000000000001")
        let high = post("FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")
        XCTAssertEqual([low, high].sorted(by: FeedDisplayOrder.newestFirst).map(\.id), [high.id, low.id])
        let merged = snapshot.merging(serverItems: [low, high], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(merged.first(where: { $0.id == low.id }), low)
        XCTAssertEqual(merged.first(where: { $0.id == high.id }), high)
    }

}


extension OwnerWorkoutFeedProjectionTests {
    @MainActor
    func testOperationMemoReusesLocalSnapshotButNeverResurrectsRemotePost() {
        let work = workout()
        let memo = FeedOwnerProjectionOperationMemo<Int, OwnerWorkoutFeedProjection.Snapshot>()
        let operation = memo.begin()
        defer { memo.end(operation) }
        var scans = 0
        func read() -> OwnerWorkoutFeedProjection.Snapshot? {
            scans += 1
            return OwnerWorkoutFeedProjection.make(workouts: [work], ownerID: owner, scopeID: "owner")
        }
        let first = memo.value(for: 1, load: read)!
        let local = first.entries[0].localItem
        let remote = FeedItem(id: UUID(), authorName: "Owner", authorHandle: nil, authorId: owner,
            createdAt: work.createdAt, itemType: .workoutSession, visibility: .publicFeed,
            cardData: local.cardData, sourceWorkoutId: work.id, caption: "fresh",
            activityContext: "remote", activityDate: work.startDate)
        XCTAssertEqual(first.merging(serverItems: [remote], currentOwnerID: owner, currentScopeID: "owner"), [remote])
        let second = memo.value(for: 1, load: read)!
        XCTAssertEqual(scans, 1)
        let denied = second.merging(serverItems: [], currentOwnerID: owner, currentScopeID: "owner")
        XCTAssertEqual(denied.count, 1)
        XCTAssertTrue(denied[0].isOwnerLocalWorkout)
        XCTAssertNotEqual(denied[0].id, remote.id)
        XCTAssertTrue(second.merging(serverItems: [remote], currentOwnerID: UUID(), currentScopeID: "owner").isEmpty)
    }

    @MainActor
    func testOperationMemoEndsOnCancelledTaskAndNeverReusesAcrossReturns() async {
        let memo = FeedOwnerProjectionOperationMemo<Int, Int>()
        var reads = 0
        let task = Task { @MainActor in
            let token = memo.begin()
            defer { memo.end(token) }
            _ = memo.value(for: 1) { reads += 1; return reads }
            do { try await Task.sleep(for: .seconds(60)) } catch { }
        }
        await Task.yield()
        task.cancel()
        await task.value
        _ = memo.value(for: 1) { reads += 1; return reads }
        _ = memo.value(for: 1) { reads += 1; return reads }
        XCTAssertEqual(reads, 3)
    }

    @MainActor
    func testOperationMemoInvalidatesBeforeLocalEditOrRevisionRead() {
        let memo = FeedOwnerProjectionOperationMemo<Int, Int>()
        let token = memo.begin()
        defer { memo.end(token) }
        var source = 1
        XCTAssertEqual(memo.value(for: 1) { source }, 1)
        source = 2
        memo.invalidate()
        XCTAssertEqual(memo.value(for: 1) { source }, 2)
        source = 3
        XCTAssertEqual(memo.value(for: 2) { source }, 3)
    }
}


extension OwnerWorkoutFeedProjectionTests {
    @MainActor func testActualSwiftDataProjection432ColdWarmAndReentry() throws { try benchmarkLocalProjection(count: 432) }
    @MainActor func testActualSwiftDataProjection5000ColdWarmAndReentry() throws { try benchmarkLocalProjection(count: 5000) }

    @MainActor private func benchmarkLocalProjection(count: Int) throws {
        let storage = try HealthAccountStorageController(inMemory: true, monitorNetwork: false, automaticallySync: false)
        let owner = UUID()
        try storage.switchAccount(userID: owner)
        let context = storage.container.mainContext
        let mapper = UnifiedWorkoutPersistenceMapper()
        for index in 0..<count {
            let date = Date(timeIntervalSince1970: 1_000 + Double(index) * 86_400)
            context.insert(mapper.makeRecord(from: workout(date: date)))
        }
        try context.save()
        let memo = FeedOwnerProjectionOperationMemo<Int, OwnerWorkoutFeedProjection.Snapshot>()
        var scans = 0
        func read() throws -> OwnerWorkoutFeedProjection.Snapshot? {
            scans += 1
            return try OwnerWorkoutFeedProjection.read(context: context, storage: storage,
                expectedOwnerID: owner, expectedScopeID: storage.scopeID)
        }
        func milliseconds(_ started: ContinuousClock.Instant) -> Double {
            let duration = started.duration(to: .now).components
            return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        }
        let firstOperation = memo.begin()
        let coldStart = ContinuousClock.now
        let cold = try XCTUnwrap(memo.value(for: 1, load: read))
        let coldMS = milliseconds(coldStart)
        XCTAssertEqual(cold.entries.count, count)
        let warmStart = ContinuousClock.now
        for _ in 0..<3 {
            let warm = try XCTUnwrap(memo.value(for: 1, load: read))
            XCTAssertEqual(warm.entries.count, count)
            XCTAssertEqual(warm.merging(serverItems: [], currentOwnerID: owner,
                currentScopeID: storage.scopeID).count, count)
        }
        let warmMS = milliseconds(warmStart)
        XCTAssertEqual(scans, 1)
        memo.end(firstOperation)
        let nextOperation = memo.begin()
        defer { memo.end(nextOperation) }
        let reentryStart = ContinuousClock.now
        let reentry = try XCTUnwrap(memo.value(for: 1, load: read))
        let reentryMS = milliseconds(reentryStart)
        XCTAssertEqual(reentry.entries.count, count)
        XCTAssertEqual(scans, 2)
        print("SOOM65_SYNTHETIC_SWIFTDATA count=\(count) coldMs=\(coldMS) warm3MergeMs=\(warmMS) reentryMs=\(reentryMS) scans=\(scans)")
    }
}


extension OwnerWorkoutFeedProjectionTests {
    @MainActor func testSyntheticExternalTelemetryNewContextFetch64MiB() throws {
        for populated in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOOM65TelemetryBenchmark-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let schema = Schema([UnifiedWorkoutRecord.self])
            let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("synthetic.store"), cloudKitDatabase: .none)
            try autoreleasepool {
                let container = try ModelContainer(for: schema, configurations: [config])
                for index in 0..<64 {
                    let record = UnifiedWorkoutPersistenceMapper().makeRecord(from: workout(
                        date: Date(timeIntervalSince1970: 1_000 + Double(index) * 86_400)))
                    if populated { record.telemetryData = Data(repeating: UInt8(index), count: 1_024 * 1_024) }
                    container.mainContext.insert(record)
                }
                try container.mainContext.save()
            }
            // New container/context, but OS file cache is NOT flushed. This
            // measures fresh model materialization, not a cold physical disk.
            let container = try ModelContainer(for: schema, configurations: [config])
            let start = ContinuousClock.now
            let records = try container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))
            let fetched = ContinuousClock.now
            // Do not touch telemetryData: same scalar mapper used by feed.
            let workouts = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
            let mapped = ContinuousClock.now
            let snapshot = OwnerWorkoutFeedProjection.make(workouts: workouts, ownerID: UUID(), scopeID: "synthetic")
            let finished = ContinuousClock.now
            func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double {
                let duration = a.duration(to: b).components
                return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
            }
            XCTAssertEqual(snapshot.entries.count, 64)
            print("SOOM65_SYNTHETIC_TELEMETRY populated=\(populated) payloadMiB=\(populated ? 64 : 0) fetchMs=\(ms(start,fetched)) mapMs=\(ms(fetched,mapped)) projectionMs=\(ms(mapped,finished)) newContext=true osCacheCold=false")
        }
    }
}


extension OwnerWorkoutFeedProjectionTests {
    @MainActor func test5000LocalCardsAndEightFreshRemoteItemsMergeMatchesOriginal() {
        let workouts = (0..<5000).map { workout(date: Date(timeIntervalSince1970: 1_000 + Double($0) * 86_400)) }
        let snapshot = OwnerWorkoutFeedProjection.make(workouts: workouts, ownerID: owner, scopeID: "synthetic")
        let locals = snapshot.entries.map(\.localItem)
        let foreignOwner = UUID()
        let remote = (0..<8).map { index in
            FeedItem(id: UUID(), authorName: "Synthetic", authorHandle: nil,
                authorId: index.isMultiple(of: 2) ? owner : foreignOwner,
                createdAt: workouts[index].createdAt, itemType: .workoutSession, visibility: .publicFeed,
                cardData: locals[index].cardData, sourceWorkoutId: workouts[index].id,
                caption: "fresh", activityContext: "synthetic", activityDate: workouts[index].startDate)
        }
        let input = locals + remote
        func originalMerge() -> [FeedItem] {
            let serverItems = input.map { item in var fresh = item; fresh.verifiedOwnerStartDate = nil; return fresh }
            let aliases = snapshot.entries.reduce(into: Set<UUID>()) { $0.formUnion($1.sourceIDs) }
            let unmatched = serverItems.filter { !($0.authorId == owner && $0.sourceWorkoutId.map(aliases.contains) == true) }
            let ownerItems = snapshot.entries.map { entry in
                let current = serverItems.filter {
                    !$0.isLocalDraft && $0.authorId == owner && $0.sourceWorkoutId.map(entry.sourceIDs.contains) == true
                }.sorted { a,b in
                    let first = a.sourceWorkoutId == entry.canonicalID
                    let second = b.sourceWorkoutId == entry.canonicalID
                    if first != second { return first }
                    return a.id.uuidString < b.id.uuidString
                }
                guard var matched = current.first else { return entry.localItem }
                if let start = entry.localItem.activityDate, start.timeIntervalSince1970.isFinite,
                   start != (matched.activityDate ?? matched.createdAt) { matched.verifiedOwnerStartDate = start }
                return matched
            }
            return (ownerItems + unmatched).sorted(by: FeedDisplayOrder.newestFirst)
        }
        func ms(_ started: ContinuousClock.Instant) -> Double {
            let duration = started.duration(to: .now).components
            return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        }
        let originalStart = ContinuousClock.now
        let expected = originalMerge()
        let originalMS = ms(originalStart)
        let candidateStart = ContinuousClock.now
        let actual = snapshot.merging(serverItems: input, currentOwnerID: owner, currentScopeID: "synthetic")
        let candidateMS = ms(candidateStart)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 5004)
        XCTAssertEqual(actual.filter { $0.authorId == foreignOwner }.count, 4)
        let denied = snapshot.merging(serverItems: locals, currentOwnerID: owner, currentScopeID: "synthetic")
        XCTAssertEqual(denied.count, 5000)
        XCTAssertTrue(denied.allSatisfy(\.isOwnerLocalWorkout))
        print("SOOM65_SYNTHETIC_MERGE locals=5000 freshRemote=8 originalMs=\(originalMS) candidateMs=\(candidateMS) equal=true")
    }
}
