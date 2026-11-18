import XCTest
import SwiftUI
import SwiftData
import UIKit
import Combine
@testable import SOOM

/// Real FeedViewContainer with only network seams injected. Local projection,
/// normalization, refresh coordination, readiness and adapter publication are production code.
@MainActor final class Feed67ColdActivationTests: XCTestCase {
    private enum Failure: Error { case inactiveHost, timedOut, unsafeConfiguration }
    private enum FollowUp: Equatable { case offscreenMutation, residentReturn, sceneReturnWithDuplicateActivation }
    @MainActor private final class GateRepository: FeedRepositoryProtocol {
        let items: [FeedItem]
        private(set) var calls = 0
        private var released = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        init(rows: [AccountActivityFeedRow]) {
            items = AccountActivityHydratedPage(cards: rows.map { .init(projection: $0, legacyItem: nil) },
                nextCursor: nil, hasMore: false).displayItems()
        }
        func fetchFeed(limit: Int) async throws -> [FeedItem] { try await fetchFeedPage(limit: limit, offset: 0, audience: .home) }
        func fetchFeedPage(limit: Int, offset: Int, audience: FeedAudience) async throws -> [FeedItem] {
            calls += 1
            if !released { await withCheckedContinuation { waiting.append($0) } }
            try Task.checkCancellation()
            return Array(items.dropFirst(offset).prefix(limit))
        }
        func fetchSavedPosts() async throws -> [FeedItem] { [] }
        func fetchPost(id: UUID) async throws -> FeedItem? { items.first { $0.id == id } }
        func release() {
            released = true
            let old = waiting; waiting = []
            old.forEach { $0.resume() }
        }
    }
    @MainActor private final class State: ObservableObject {
        @Published var active = false
        @Published var scenePhase: ScenePhase = .active
        var vm: FeedViewModel?
        var batchCalls = 0
        var published: [FeedReturnBatchPresentation] = []
    }
    private struct Host: View {
        @ObservedObject var state: State
        @ObservedObject var storage: HealthAccountStorageController
        let auth: AuthViewModel
        let dependencies: FeedContainerProductionTestDependencies
        private var feed: FeedViewContainer {
            var view = FeedViewContainer(isActive: state.active)
            view.productionTestDependencies = dependencies
            return view
        }
        var body: some View {
            NavigationStack { feed }
                .environmentObject(auth)
                .environmentObject(storage)
                .modelContainer(storage.container)
                .environment(\.scenePhase, state.scenePhase)
        }
    }
    private func requireSyntheticHost() throws -> ReviewDemoRuntime {
        let env = ProcessInfo.processInfo.environment
        guard env["SOOM_SYNTHETIC_UI_TESTS"] == "1", env["SOOM_SKELETON_QA"] == "1",
              env["SOOM_SKELETON_STYLE"] == "value", env["SOOM_FEED_BATCH_QA"] == "1",
              ReviewDemoMode.isActive, AccountActivityReadPolicy.deployed == .profileOnlyV2,
              FeedReturnBatchReleaseGate.enabled,
              !AuthEnvironmentLoader().load().isSupabaseConfigured,
              ["SOOMSupabaseURL", "SOOMSupabaseAnonKey"].allSatisfy({ (Bundle.main.object(forInfoDictionaryKey: $0) as? String) == "" }),
              CommunitySafetyStore.shared.viewerID == ReviewDemoMode.userID,
              CommunitySafetyStore.shared.canUseSocial else {
            XCTFail("Requires isolated synthetic runtime, batch QA, deployed v2 path, empty service credentials and current demo account")
            throw Failure.unsafeConfiguration
        }
        return try XCTUnwrap(ReviewDemoController.shared.runtime)
    }
    private func waitUntil(_ message: String, seconds: Double = 5, predicate: () -> Bool) async throws {
        let until = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < until { try await Task.sleep(for: .milliseconds(20)) }
        if !predicate() { XCTFail(message); throw Failure.timedOut }
    }
    private func wire(_ params: FeedReturnBatchParameters, rows: [AccountActivityFeedRow], viewer: UUID) throws -> Data {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.cardID, $0) })
        let entries: [[String: Any]] = try params.p_card_ids.map { id in
            let row = try XCTUnwrap(byID[id])
            return ["card_id":row.cardID.uuidString, "allowed":true,
                "summary":["card_id":row.cardID.uuidString,"canonical_id":row.canonicalID.uuidString,
                    "owner_id":row.ownerID.uuidString,"sport":row.sport,"activity_at":row.activityAt,
                    "duration_seconds":row.durationSeconds,"distance_meters":row.distanceMeters ?? 0,"revision":row.revision],
                "author":NSNull(),"author_revision":NSNull(),"avatar":NSNull(),
                "photos":NSNull(),"social":NSNull(),"social_revision":NSNull(),
                "card_preview":["version":1,"state":"unavailable"]]
        }
        return try JSONSerialization.data(withJSONObject:["version":3,"viewer_id":viewer.uuidString,
            "scope":"home","account_generation":params.p_account_generation,"safety_revision":params.p_safety_revision,
            "return_epoch":params.p_return_epoch,"release_ready":true,"rows":entries,
            "needs_page_reload":false,"has_more":false,"membership_revision":String(repeating:"a",count:64)])
    }
    private func scenario(withdrawDuringRead: Bool, followUp: FollowUp? = nil) async throws {
        executionTimeAllowance = 30
        let runtime = try requireSyntheticHost()
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { throw Failure.inactiveHost }
        let owner = ReviewDemoMode.userID
        let storage = try HealthAccountStorageController(inMemory: true, monitorNetwork: false, automaticallySync: false)
        try storage.switchAccount(userID: owner)
        let formatter = ISO8601DateFormatter(), date = Date().addingTimeInterval(-3600)
        let own = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: owner,
            sport: "running", activityAt: formatter.string(from: date), durationSeconds: 600,
            distanceMeters: 1000, revision: 1, readPolicy: .profileOnlyV2)
        let foreign = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "cycling", activityAt: formatter.string(from: date.addingTimeInterval(-3600)), durationSeconds: 1200,
            distanceMeters: 5000, revision: 1, readPolicy: .profileOnlyV2)
        storage.container.mainContext.insert(UnifiedWorkoutRecord(id: own.canonicalID,
            sourceRaw: UnifiedDataSource.soomLocal.rawValue, workoutTypeRaw: UnifiedWorkoutType.running.rawValue,
            startDate: date, endDate: date.addingTimeInterval(600), durationSeconds: 600,
            distanceMeters: 1000, dataQualityRaw: UnifiedDataQuality.complete.rawValue))
        try storage.container.mainContext.save()
        let state = State(), repository = GateRepository(rows: [own, foreign])
        defer { repository.release() }
        let dependencies = FeedContainerProductionTestDependencies(repository: repository, readBatch: { params, rows in
            state.batchCalls += 1
            let data = try self.wire(params, rows: rows, viewer: owner)
            if withdrawDuringRead { try storage.switchAccount(userID: UUID()) }
            return data
        })
        dependencies.didCreateViewModel = { state.vm = $0 }
        dependencies.didPublishBatch = { state.published.append($0) }
        let priorKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: Host(state: state, storage: storage, auth: runtime.auth, dependencies: dependencies))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; priorKey?.makeKey() }
        try await waitUntil("Actual Container must create its production VM") { state.vm != nil }
        let baseline = ProcessInfo.processInfo.environment["SOOM_FEED67_EXPECT_OFFSCREEN_LOAD"] == "1"
        if baseline {
            try await waitUntil("Baseline should start the page while inactive") { repository.calls > 0 }
        } else {
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(repository.calls, 0, "Fixed Container must not capture an inactive full-load owner")
        }
        XCTAssertEqual(state.batchCalls, 0)
        state.active = true
        try await waitUntil("Active Container must begin a page") { repository.calls > 0 }
        // Ensure the ready edge arrives while the page result is still withheld.
        try await Task.sleep(for: .milliseconds(150))
        repository.release()
        if baseline {
            try await waitUntil("Baseline real owner projection/normalization and optional summary should finish") {
                state.vm?.readModel.weeklySnapshot != nil
            }
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertEqual(state.batchCalls, 0, "Reproduces inactive owner capture: ready preceded pending, no batch")
            XCTAssertTrue(state.published.isEmpty)
            XCTAssertEqual(state.vm?.loadedProjectionPrefix?.count, 2)
            print("FEED67_ACTUAL_CONTAINER_BASELINE: offscreen page began; active before page release; summary complete; batch=0; published=0")
        } else if withdrawDuringRead {
            try await waitUntil("Fresh batch transport must start") { state.batchCalls > 0 }
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertTrue(state.published.isEmpty, "Storage/account withdrawal must discard the completed envelope")
            print("FEED67_ACTUAL_CONTAINER_WITHDRAW: batch reached; no stale publish")
        } else {
            try await waitUntil("Actual Container must publish a freshly validated batch") { !state.published.isEmpty }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(state.batchCalls, 1)
            XCTAssertEqual(state.published.count, 1)
            let batch = try XCTUnwrap(state.published.first)
            XCTAssertEqual(batch.phase, .ready)
            XCTAssertEqual(Set(batch.grants.keys), Set([own.cardID, foreign.cardID]))
            XCTAssertEqual(batch.context.viewerID, owner)
            XCTAssertTrue(batch.grants.values.allSatisfy { $0.hasBatchCardPreview })
            print("FEED67_ACTUAL_CONTAINER_FIXED: no offscreen page; activation -> page -> batch=1; fresh own+foreign grants")
            guard let followUp else { return }
            // Start from a fully settled, actually authorized resident feed.
            try await waitUntil("Initial supplementary work must settle before lifecycle assertions") {
                state.vm?.readModel.weeklySnapshot != nil
            }
            try await Task.sleep(for: .milliseconds(300))
            let pageBefore = repository.calls
            let batchBefore = state.batchCalls
            let publishedBefore = state.published.count
            let previousEpoch = batch.context.returnEpoch
            switch followUp {
            case .offscreenMutation, .residentReturn:
                state.active = false
                try await Task.sleep(for: .milliseconds(300))
                if followUp == .offscreenMutation {
                    let records = try storage.container.mainContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
                    let record = try XCTUnwrap(records.first { $0.id == own.canonicalID })
                    record.durationSeconds = 900
                    try storage.container.mainContext.save()
                    // No passive-readback marker: exercise the actual full mutation observer.
                    NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
                    try await Task.sleep(for: .milliseconds(300))
                    XCTAssertEqual(record.durationSeconds, 900)
                }
                XCTAssertEqual(repository.calls, pageBefore, "Hidden resident must not start a remote page")
                XCTAssertEqual(state.batchCalls, batchBefore, "Hidden resident must not authorize cards")
                XCTAssertEqual(state.published.count, publishedBefore)
                state.active = true
            case .sceneReturnWithDuplicateActivation:
                state.scenePhase = .inactive
                try await Task.sleep(for: .milliseconds(300))
                XCTAssertEqual(repository.calls, pageBefore)
                XCTAssertEqual(state.batchCalls, batchBefore)
                state.scenePhase = .active
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            }
            try await waitUntil("Actual lifecycle handler must publish fresh authorization") {
                state.published.count > publishedBefore
            }
            // Catch duplicate work after the first response, including queued observers.
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(repository.calls, pageBefore + (followUp == .offscreenMutation ? 1 : 0),
                "Only a pending actual mutation should require a full remote page")
            XCTAssertEqual(state.batchCalls, batchBefore + 1, "One return should produce one fresh batch")
            XCTAssertEqual(state.published.count, publishedBefore + 1)
            let latest = try XCTUnwrap(state.published.last)
            XCTAssertEqual(latest.phase, .ready)
            XCTAssertEqual(latest.context.viewerID, owner)
            XCTAssertEqual(Set(latest.grants.keys), Set([own.cardID, foreign.cardID]))
            XCTAssertTrue(latest.grants.values.allSatisfy { $0.hasBatchCardPreview })
            if followUp == .sceneReturnWithDuplicateActivation {
                XCTAssertGreaterThan(latest.context.returnEpoch, previousEpoch,
                    "Scene suspension must advance the authority boundary")
            }
            print("FEED67_ACTUAL_CONTAINER_FOLLOWUP: \(followUp); pages_delta=\(repository.calls - pageBefore); batch_delta=\(state.batchCalls - batchBefore); fresh own+foreign grants")
        }
    }
    func testColdRetainedContainerActivationUsesCurrentOwner() async throws { try await scenario(withdrawDuringRead: false) }
    func testColdActivationRejectsAccountWithdrawalDuringBatch() async throws {
        if ProcessInfo.processInfo.environment["SOOM_FEED67_EXPECT_OFFSCREEN_LOAD"] == "1" { return }
        try await scenario(withdrawDuringRead: true)
    }
    func testOffscreenMutationDefersFullRefreshUntilActivation() async throws {
        try await scenario(withdrawDuringRead: false, followUp: .offscreenMutation)
    }
    func testReadyResidentTabReturnReauthorizesWithoutPageReload() async throws {
        try await scenario(withdrawDuringRead: false, followUp: .residentReturn)
    }
    func testSceneReturnAndDuplicateUIKitActivationCoalesce() async throws {
        try await scenario(withdrawDuringRead: false, followUp: .sceneReturnWithDuplicateActivation)
    }
}
