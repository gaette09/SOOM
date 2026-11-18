import Foundation
import SwiftUI
import SwiftData

/// Isolated synthetic QA fixture. No identity or session is installed in
/// Supabase; every sample health record belongs to a disposable local container.
@MainActor
enum ReviewDemoMode {
    nonisolated(unsafe) private(set) static var isActive = false
    nonisolated static let userID = UUID(uuidString: "D3000000-0000-4000-8000-000000000001")!
    fileprivate static func setActive(_ active: Bool) { isActive = active }
}

@MainActor
final class ReviewDemoController: ObservableObject {
    static let shared = ReviewDemoController()
    @Published private(set) var runtime: ReviewDemoRuntime?
    @Published var errorMessage: String?

    func start() {
        guard ReviewDemoAccessPolicy.canStart, runtime == nil else { return }
        do {
            let next = try ReviewDemoRuntime()
            ReviewDemoMode.setActive(true)
            next.activate()
            ReviewDemoAvatarStore.shared.reset()
            ReviewDemoPhotoStore.shared.reset()
            let sampleRecords = (try? next.storage.container.mainContext.fetch(
                FetchDescriptor<UnifiedWorkoutRecord>(sortBy: [SortDescriptor(\UnifiedWorkoutRecord.startDate, order: .reverse)]))) ?? []
            ReviewDemoPhotoStore.shared.seed(workoutIDs: Array(sampleRecords.prefix(6).map(\.id)))
            ReviewDemoCommunityStore.shared.reset()
            CommunitySafetyStore.shared.configureForDemo()
            runtime = next
            errorMessage = nil
        } catch {
            errorMessage = "데모 데이터를 준비하지 못했어요. 다시 시도해 주세요. / Unable to prepare demo. Please try again."
        }
    }

    func exit() {
        guard let previous = runtime else { return }
        previous.restore()
        CommunitySafetyStore.shared.restoreAfterDemo()
        ReviewDemoAvatarStore.shared.reset()
        ReviewDemoPhotoStore.shared.reset()
        ReviewDemoMode.setActive(false)
        runtime = nil
    }
}

@MainActor
final class ReviewDemoRuntime {
    let id = UUID()
    let storage: HealthAccountStorageController
    let auth: AuthViewModel
    let dashboard = DashboardViewModel(harness: MockWorkoutHarness())
    let community = CommunityViewModel(harness: MockWorkoutHarness())
    let notificationRouter = NotificationDeepLinkRouter()
    private let temporaryDirectory: URL
    private let defaultsSuite: String
    let demoDefaults: UserDefaults
    private var originalTraining: TrainingSettingsStore?
    private var originalDrafts: FileFeedShareDraftStore?
    private var demoDrafts: FileFeedShareDraftStore?
    private var originalClubKey = ""
    private var originalCheckInKey = ""
    private var didActivate = false

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SOOM-ReviewDemo-" + id.uuidString, isDirectory: true)
        defaultsSuite = "SOOM.ReviewDemo." + id.uuidString
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw CocoaError(.fileWriteUnknown)
        }
        demoDefaults = defaults
        storage = try HealthAccountStorageController(remote: nil,
            baseDirectory: temporaryDirectory, inMemory: true,
            monitorNetwork: false, automaticallySync: false)
        try storage.switchAccount(userID: ReviewDemoMode.userID)
        auth = AuthViewModel(repository: ReviewDemoAuthRepository())
        try ReviewDemoData.seed(in: storage.container.mainContext)
    }

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        originalTraining = TrainingSettingsStore.shared
        originalDrafts = FileFeedShareDraftStore.live
        originalClubKey = LocalClubPersistence.accountKey
        originalCheckInKey = MorningCheckInSkipStore.accountKey
        demoDefaults.set("today", forKey: "activityHubSelectedSection")
        let training = TrainingSettingsStore(userDefaults: demoDefaults, userID: ReviewDemoMode.userID)
        training.saveSettings(TrainingSettings(maxHeartRate: 190, cyclingFTP: 230))
        TrainingSettingsStore.useDemoScope(training)
        let drafts = FileFeedShareDraftStore(
            fileURL: storage.scopeDirectory.appendingPathComponent("feed_share_drafts.json"))
        demoDrafts = drafts
        FileFeedShareDraftStore.useDemoScope(drafts)
        LocalClubPersistence.accountKey = "soom.club.reviewDemo." + id.uuidString
        MorningCheckInSkipStore.accountKey = "soom.morningCheckIn.reviewDemo." + id.uuidString
    }

    func restore() {
        guard didActivate else { return }
        didActivate = false
        HealthCloudJournal.retire(storage.container)
        demoDrafts?.retireDemoScope()
        if let originalTraining { TrainingSettingsStore.useDemoScope(originalTraining) }
        if let originalDrafts { FileFeedShareDraftStore.useDemoScope(originalDrafts) }
        UserDefaults.standard.removeObject(forKey: LocalClubPersistence.accountKey)
        UserDefaults.standard.removeObject(forKey: MorningCheckInSkipStore.accountKey)
        LocalClubPersistence.accountKey = originalClubKey
        MorningCheckInSkipStore.accountKey = originalCheckInKey
        for prefix in ["SOOM.autoPublishImportedWorkouts.", "SOOM.googleHealthAutoImport.",
                       "SOOM.healthKitAutoImport.", "SOOM.healthKitImportNotifications."] {
            UserDefaults.standard.removeObject(forKey: prefix + storage.scopeID)
        }
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

/// In-memory profile changes exercise the same AuthViewModel without writing
/// AuthSessionStore.shared or claiming a server-authenticated identity.
private final class ReviewDemoAuthRepository: AuthRepository {
    private var session = AuthSession.localOnly(user: AppUser(
        id: ReviewDemoMode.userID, displayName: "데모 선수 / Demo Athlete", handle: "demo_athlete"))
    func loadSession() -> AuthSession { session }
    func continueAsLocalUser(displayName: String) -> AuthSession { updateDisplayName(displayName) }
    func updateDisplayName(_ displayName: String) -> AuthSession {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else {
            return .error("표시 이름은 1~80자로 입력해 주세요.", currentUser: session.currentUser)
        }
        session.currentUser?.displayName = name
        return session
    }
    func signOut() -> AuthSession { session }
}

struct ReviewDemoRootView: View {
    let runtime: ReviewDemoRuntime
    var body: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_SKELETON_QA"] == "1" {
                SOOMSkeletonQAView()
            } else if ProcessInfo.processInfo.environment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] == "1" {
                // Ordinary tab/navigation layout without the space-taking demo
                // banner. Services and all records remain isolated synthetic QA.
                RootTabView()
                    .modifier(ReviewDemoRevalidationQA())
                    .safeAreaInset(edge: .top) { EmptyView() }
                    .overlay(alignment: .bottomLeading) {
                        Text("LAYOUT QA · 합성").font(.caption2).padding(4)
                            .background(.white.opacity(0.9)).allowsHitTesting(false)
                    }
            } else {
                if ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" && ProcessInfo.processInfo.environment["SOOM_DETAIL_REVALIDATION_QA"] == "1" {
                    demoContent.modifier(ReviewDemoRevalidationQA())
                } else { demoContent }
            }
            #else
            demoContent
            #endif
        }
            .modelContainer(runtime.storage.container)
            .environmentObject(runtime.storage)
            .environmentObject(runtime.auth)
            .environmentObject(runtime.dashboard)
            .environmentObject(runtime.community)
            .environmentObject(runtime.notificationRouter)
            .defaultAppStorage(runtime.demoDefaults)
            .id(runtime.id)
    }
    private var demoContent: some View {
        VStack(spacing: 0) {
            ReviewDemoBanner()
                .fixedSize(horizontal: false, vertical: true)
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["SOOM_DETAIL_MOTION_QA"] == "1" { WorkoutDetailMotionQAView() }
                else { RootTabView() }
                #else
                RootTabView()
                #endif
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit fixture exercises the production privacy boundary and lifecycle;
/// all receipts and delays are synthetic and no real service is constructed.
private struct ReviewDemoRevalidationQA: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @StateObject private var service: PrivacyLocalQAService
    @StateObject private var model: AccountPrivacyModel
    @State private var hasSuspended = false
    private let enabled = ProcessInfo.processInfo.environment["SOOM_DETAIL_REVALIDATION_QA"] == "1"
    init() {
        let service = PrivacyLocalQAService()
        service.receipt = .init(enabled: true, accountScope: .publicAccount, workoutDefault: .publicPost, revision: 1, shareMeasurements: false,
            policyVersion: ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" ? 2 : 1,
            measurementRevision: ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" ? 0 : nil)
        _service = StateObject(wrappedValue: service)
        _model = StateObject(wrappedValue: AccountPrivacyModel(owner: ReviewDemoMode.userID, service: service, socialState: .shared))
    }
    func body(content: Content) -> some View {
        Group {
            if enabled {
                content.environment(\.soomAccountPrivacyModel, model)
                    .overlay(alignment: .topTrailing) {
                        if ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1", service.navigationFetchHeld {
                            Button("합성 권한 확인 완료") { service.releaseNavigationFetch() }
                                .accessibilityIdentifier("profile.navigation.qa.finishCheck")
                        }
                        if ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1", !model.isCheckingSocialAccess, !model.canContinue {
                            Button("합성 권한 다시 승인") { service.failLoad = false; Task { await model.load() } }
                                .accessibilityIdentifier("profile.navigation.qa.regrant")
                        }
                    }
                    .task { await model.load() }
                    .onChange(of: phase) { _, next in
                        if next == .active {
                            if hasSuspended {
                                if ProcessInfo.processInfo.environment["SOOM_PROFILE_NAVIGATION_QA"] == "1" {
                                    service.holdNextNavigationFetch = true
                                } else { service.nextFetchDelayNanoseconds = 2_000_000_000 }
                            }
                            if hasSuspended, ProcessInfo.processInfo.environment["SOOM_DETAIL_REVALIDATION_FAIL"] == "1" { service.failLoad = true }
                            Task { await model.load() }
                        } else { hasSuspended = true; model.suspendSocialAccess() }
                    }
            } else { content }
        }
    }
}
#endif

struct ReviewDemoBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG
    @State private var showingPrivacyQA = false
    @State private var showingNotificationQA = false
    @State private var showingPagingQA = false
    #endif
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dynamicTypeSize.isAccessibilitySize ? "DEMO" : "DEMO · 샘플 데이터").font(.caption.weight(.bold))
                    .accessibilityLabel("DEMO · 샘플 데이터. 기록·공유는 이 체험에서만 유지돼요")
                    .accessibilityIdentifier("reviewDemo.banner")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("기록·공유는 이 체험에서만 유지돼요").font(.caption2)
                }
            }
            Spacer()
            #if DEBUG
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["SOOM_PAGING_QA"] != nil && ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" {
                Button("Paging QA") { showingPagingQA = true }.accessibilityIdentifier("reviewDemo.pagingQA")
                    .fullScreenCover(isPresented: $showingPagingQA) { FeedPagingQAView() }
            }
            if ProcessInfo.processInfo.environment["SOOM_NOTIFICATION_QA"] == "1" && ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" {
                Button { showingNotificationQA=true } label: { Image(systemName:"bell.badge").frame(width:44,height:44) }
                    .accessibilityLabel("합성 알림 검증").accessibilityIdentifier("reviewDemo.notificationQA")
                    .sheet(isPresented:$showingNotificationQA) { NotificationLocalQAView() }
            }
            #endif
            Button { showingPrivacyQA = true } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "checkmark.shield").font(.system(size: 22)).frame(width: 44, height: 44)
                } else { Text("공개범위 QA") }
            }
                .accessibilityLabel("공개범위 QA")
                .accessibilityIdentifier("reviewDemo.privacyQA")
                .sheet(isPresented: $showingPrivacyQA) { PrivacyLocalQAView() }
            #endif
            Button { ReviewDemoController.shared.exit() } label: {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "xmark.circle").font(.system(size: 22)).frame(width: 44, height: 44)
                } else { Text("종료 / Exit") }
            }
                .accessibilityLabel("종료 / Exit")
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("reviewDemo.exit")
        }
        .padding(.horizontal, 16)
        .foregroundStyle(SOOMColor.accentInk)
        .background(SOOMColor.accentSurface)
    }
}

struct ReviewDemoEntryCard: View {
    @ObservedObject private var controller = ReviewDemoController.shared
    var body: some View {
        if ReviewDemoAccessPolicy.canStart || ReviewDemoMode.isActive {
        SOOMCard {
            Text(ReviewDemoMode.isActive ? "데모 체험 중 / Demo mode" : "데모 체험 / Try Demo")
                .font(.headline)
            Text("계정이나 건강·위치 권한 없이 샘플 운동, 회복, 피드, 클럽을 직접 둘러보세요. 변경은 체험을 종료하면 초기화됩니다.")
                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            Text("Explore sample workouts, recovery, feed and clubs. No login or permissions required.")
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            Button(ReviewDemoMode.isActive ? "데모 종료 / Exit Demo" : "데모 체험 / Try Demo") {
                if ReviewDemoMode.isActive { controller.exit() } else { controller.start() }
            }
            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            .accessibilityIdentifier(ReviewDemoMode.isActive ? "reviewDemo.exitSettings" : "reviewDemo.start")
            if let error = controller.errorMessage {
                Text(error).font(.footnote).foregroundStyle(SOOMColor.warning)
            }
        }
        }
    }
}

/// An interactive import of synthetic data through the ordinary local stores.
/// Hardware authorization and OAuth remain available after leaving demo mode.
struct ReviewDemoIntegrationView: View {
    let title: String
    @Environment(\.modelContext) private var modelContext
    @State private var imported = false
    @State private var isImporting = false
    @State private var message: String?
    var body: some View {
        SOOMScreen {
            SOOMCard {
                Text("DEMO · " + title).font(.title2.weight(.semibold))
                Text("샘플 운동을 가져오고 실제 활동·상세 분석 화면에서 확인하세요. 건강 앱·외부 계정에는 연결하지 않습니다.")
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                Text("Import a sample workout, then open it in Activities. Demo data stays inside this session.")
                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                Button(imported ? "샘플 가져오기 완료 / Imported" : "샘플 운동 가져오기 / Import Sample") {
                    isImporting = true
                    Task { @MainActor in
                        do {
                            try await ReviewDemoData.importSample(in: modelContext)
                            imported = true
                            message = "샘플 러닝과 심박·경로를 저장했어요. 활동에서 바로 확인할 수 있어요."
                        } catch { message = "샘플 가져오기를 마치지 못했어요. 다시 시도해 주세요." }
                        isImporting = false
                    }
                }
                .font(.headline).frame(minHeight: 48)
                .disabled(imported || isImporting)
                .accessibilityIdentifier("reviewDemo.importSample")
                if let message { Text(message).font(.footnote) }
                NavigationLink("활동에서 확인 / View Activities") { UnifiedWorkoutLibraryViewContainer() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("reviewDemo.importedActivities")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// This is a simulator test fixture switch, not an administrator identity.
/// Release and physical-device builds cannot enable the fixture through URLs,
/// process environment, or the ordinary product entry points.
enum ReviewDemoAccessPolicy {
    static var canStart: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1"
            || NSClassFromString("XCTestCase") != nil
        #else
        return false
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
// Synthetic-only harness: real FeedView footer and FeedViewModel pagination,
// no network, credentials, persistence, or production account changes.
@MainActor private final class FeedPagingQAService: FeedLoading {
    let mode: String
    let own: [FeedItem]
    let following: [FeedItem]
    var calls = 0
    init(mode: String) {
        self.mode = mode
        func row(_ index: Int, following: Bool) -> FeedItem {
            let date = Date(timeIntervalSince1970: 1_800_000_000 - Double(index + (following ? 100 : 0)))
            return FeedItem(id: UUID(uuidString: String(format: "D4900000-0000-4000-8000-%012d", index + (following ? 100 : 1)))!,
                authorName: following ? "Paging following" : "Paging owner", authorHandle: nil,
                authorId: UUID(uuidString: following ? "D4900000-0000-4000-8000-000000009999" : "D4900000-0000-4000-8000-000000008888")!,
                isLocalDraft: true, createdAt: date, itemType: .workoutSession, visibility: .publicFeed,
                cardData: FeedMockData.items[0].cardData, sourceWorkoutId: nil, caption: nil,
                activityContext: "Synthetic paging", activityDate: date)

        }
        own = (0..<8).map { row($0, following: false) }
        following = (0..<8).map { row($0, following: true) }
    }
    func loadFeed(limit: Int) async -> FeedLoadResult { await loadFeedPage(limit: limit, offset: 0) }
    func loadPost(id: UUID) async -> FeedItem? { (own + following).first { $0.id == id } }
    func loadFeedPage(limit: Int, offset: Int) async -> FeedLoadResult {
        calls += 1
        if mode == "cancel" && offset == 8 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { continuation.resume() }
            }
        }
        if mode == "start-order" {
            func datedCard(id: String, title: String, raw: String, canonical: String?) -> FeedItem {
                let formatter = ISO8601DateFormatter()
                var item = FeedItem(id: UUID(uuidString: id)!, authorName: title, authorHandle: nil,
                    authorId: UUID(uuidString: "D4900000-0000-4000-8000-000000008888")!,
                    isLocalDraft: true, createdAt: formatter.date(from: raw)!, itemType: .workoutSession, visibility: .publicFeed,
                    cardData: .workoutSession(ShareableWorkoutCardModel(id: UUID(uuidString: id)!, workoutType: .running,
                        title: title, distanceText: "5.00 km", durationText: "30분", primaryMessage: "Synthetic", growthMessage: "", recoveryMessage: "", footerText: "Synthetic only", visibility: .publicFeed)),
                    sourceWorkoutId: nil, caption: nil, activityContext: "Synthetic start-date order", activityDate: formatter.date(from: raw))
                // Canonical matching itself is covered separately by projection
                // unit tests. This fixture exercises its resulting UI field.
                item.verifiedOwnerStartDate = canonical.flatMap { formatter.date(from: $0) }
                return item
            }
            let delayedOwner = datedCard(id: "D5000000-0000-4000-8000-000000000001", title: "Older owner start",
                raw: "2026-11-12T09:00:00Z", canonical: "2026-11-10T09:00:00Z")
            let newerFollowing = datedCard(id: "D5000000-0000-4000-8000-000000000002", title: "Newer following start",
                raw: "2026-11-11T09:00:00Z", canonical: nil)
            return FeedLoadResult(items: [delayedOwner, newerFollowing], hasMore: false)
        }
        if mode == "empty" { return FeedLoadResult(items: offset < 16 ? [] : following, hasMore: offset < 16) }
        if mode == "same" { return FeedLoadResult(items: offset < 16 ? own : following, hasMore: offset < 16) }
        return FeedLoadResult(items: offset == 0 ? own : following, hasMore: offset == 0)
    }
}
private struct FeedPagingQAProvider: FeedWeeklyProgressProviding, FeedRecoveryPreviewProviding, FeedStreakWorkoutDatesProviding {
    enum Unavailable: Error { case synthetic }
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress { throw Unavailable.synthetic }
    func fetchPreviewSummary() async throws -> UnifiedWorkoutRecoveryPreviewResult { throw Unavailable.synthetic }
    func fetchRecentWorkoutDates(days: Int) async throws -> [Date] { [] }
}
private struct FeedPagingQAView: View {
    @StateObject private var model: FeedViewModel
    private let service: FeedPagingQAService
    @State private var active = true
    init() {
        let service = FeedPagingQAService(mode: ProcessInfo.processInfo.environment["SOOM_PAGING_QA"] ?? "normal")
        self.service = service
        _model = StateObject(wrappedValue: FeedViewModel(feedLoader: service, weeklyProgressProvider: FeedPagingQAProvider(), recoveryPreviewProvider: FeedPagingQAProvider(), streakDatesProvider: FeedPagingQAProvider(), initialAudience: .home))
    }
    var body: some View {
        let state = model.readModel
        VStack(spacing: 0) {
            HStack {
                Text("Synthetic pages \(state.paginationRevision) following \(state.items.filter { $0.authorName == "Paging following" }.count) busy \(state.isLoadingMore) calls \(service.calls)")
                    .accessibilityIdentifier("pagingQA.status")
                Button(active ? "Leave" : "Return") { active.toggle() }.accessibilityIdentifier("pagingQA.toggle")
                Button("Bounce") {
                    Task { active = false; try? await Task.sleep(for: .milliseconds(150)); active = true }
                }.accessibilityIdentifier("pagingQA.bounce")
            }.font(.caption).padding(6)
            FeedView(audience: .home, items: state.items, isLoading: state.isLoading, hasMore: state.hasMore, paginationRevision: state.paginationRevision, paginationWakeRevision: state.paginationWakeRevision, isLoadingMore: state.isLoadingMore, loadMoreFailure: state.loadMoreFailure, onLoadMore: { await model.loadMore() }, onRetryLoadMore: { await model.retryLoadMore() })
                .environment(\.soomFeedIsActive, active)
        }.task { await model.load() }
    }
}
#endif
