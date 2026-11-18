import SwiftUI
import Charts
import SwiftData

enum ProfileSection: String, CaseIterable, Identifiable {
    case progress, activities, gallery, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .progress: return "진행"
        case .activities: return "활동"
        case .gallery: return "갤러리"
        case .more: return "더보기"
        }
    }
    var icon: String {
        switch self {
        case .progress: return "chart.bar.xaxis"
        case .activities: return "waveform.path"
        case .gallery: return "square.grid.2x2"
        case .more: return "line.3.horizontal"
        }
    }
}
private enum ProfileSportFilter: String, CaseIterable, Identifiable {
    case all, running, cycling
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "전체"
        case .running: return "러닝"
        case .cycling: return "자전거"
        }
    }
    func includes(_ workout: UnifiedWorkout) -> Bool {
        switch self {
        case .all: return true
        case .running: return workout.workoutType == .running
        case .cycling: return workout.workoutType == .cycling
        }
    }
}
private struct ProfileWeekPoint: Identifiable {
    let week: Date
    let distanceKilometers: Double
    let durationSeconds: TimeInterval
    let workoutCount: Int
    var id: Date { week }
}
private struct ProfileGalleryEntry: Identifiable {
    let workout: UnifiedWorkout
    let photos: [WorkoutPhotoReference]
    var id: UUID { workout.id }
}

struct ProfileIdentityView: View {
    init(initialSection: ProfileSection = .progress) { _selectedTab = State(initialValue: initialSection) }
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var localDataPresence: LocalDataPresence = .empty
    @State private var profileIdentity = ProfileWorkoutAggregator().profileIdentity(from: [])
    @State private var isPresentingProfileEditor = false
    @State private var loadError: String?
    @State private var isLoadingProfile = false
    @State private var hasLoadedProfile = false
    @State private var workouts: [UnifiedWorkout] = []
    @State private var selectedTab: ProfileSection = .progress
    @State private var sportFilter: ProfileSportFilter = .all
    @State private var selectedWeek: Date?
    @State private var gallery: [ProfileGalleryEntry] = []
    @State private var galleryLoading = false
    @State private var galleryError: String?
    @State private var galleryLimit = 30
    @State private var galleryRequest = UUID()
    @State private var galleryAttempts = 0
    #if DEBUG && targetEnvironment(simulator)
    @State private var galleryReadCount = 0
    #endif
    @State private var galleryQARetry = false
    @State private var showingSharedPosts = false
    @State private var pendingRequestCount: Int?
    @ObservedObject private var socialSafety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var isSignedIn: Bool { authViewModel.session.currentUser?.authProvider == .supabase }

    var body: some View {
        SOOMScreen(tracksTabBarScroll: true) {
            settingsEntryRow
            SOOMCard {
                identityHeader
                if let userID = ReviewDemoMode.isActive ? ReviewDemoMode.userID : authViewModel.session.currentUser?.id, isSignedIn || ReviewDemoMode.isActive {
                    Divider()
                    ProfileSocialStatsView(userID: userID, onPosts: { showingSharedPosts = true }).id(userID).protectsSocialAccess()
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("profile.identityGroup")
            profileTabs
            if let loadError {
                SOOMCard {
                    Text(loadError).foregroundStyle(SOOMColor.secondaryInk)
                    Button("다시 불러오기") { Task { await refreshProfile() } }
                        .frame(minHeight: 44)
                }
            }
            if isLoadingProfile && !hasLoadedProfile {
                SOOMSkeleton(layout: .summary, label: "프로필 운동 요약 불러오는 중")
                SOOMSkeleton(layout: selectedTab == .activities ? .workout : .chart, label: "프로필 데이터 불러오는 중")
            } else {
            switch selectedTab {
            case .progress: progressContent
            case .activities: activitiesContent
            case .gallery: galleryContent
            case .more: detailEntries
            }
            }
        }
        .environment(\.soomFeedPhotoPresentationID, nil)
        .independentFeedReturnScope()
        .toolbar(.hidden, for: .navigationBar)
        .suspendsSOOMTabBarScrollMotion(when: isPresentingProfileEditor)
        .navigationDestination(isPresented: $showingSharedPosts) {
            if let userID = authViewModel.session.currentUser?.id {
                SOOMProfileDestination(userID: userID, initialSection: .activities)
            }
        }
        .sheet(isPresented: $isPresentingProfileEditor) {
            ProfileEditView(auth: authViewModel)
        }
        .task(id: healthStorage.dataRevision) { await refreshProfile() }
        .task(id: "gallery:\(selectedTab.rawValue):\(galleryLimit)") {
            if selectedTab == .gallery { await refreshGallery() }
        }
        .task(id: "requests:\(socialSafety.accountGeneration):\(socialSafety.revision)") { await refreshPendingRequests() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshPendingRequests() } } }
        .onReceive(NotificationCenter.default.publisher(for: WorkoutRecordManagement.didChange)) { _ in
            Task { await refreshProfile() }
        }
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .topTrailing) {
            if ReviewDemoMode.isActive,
               ProcessInfo.processInfo.environment["SOOM_UX_GALLERY_LOADING_COUNTER"] == "1" {
                VStack {
                    Text("attempts=\(galleryAttempts) reads=\(galleryReadCount) rows=\(min(galleryLimit, workouts.count)) loading=\(galleryLoading ? 1 : 0)")
                        .font(.system(size: 9)).accessibilityIdentifier("profile.gallery.qa.counts")
                    Button("QA 변경 알림") {
                        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
                    }.accessibilityIdentifier("profile.gallery.qa.mutation")
                }.padding(4).background(.white)
            }
        }
        #endif
    }

    private var settingsEntryRow: some View {
        HStack {
            Text("프로필")
                .font(SOOMFont.displayMedium(28, relativeTo: .title))
                .foregroundStyle(SOOMColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink { SettingsView() } label: {
                Image(soom: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SOOMColor.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
            .accessibilityIdentifier("profile.settings")
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProfilePublicIdentityHeader(
                userID: authViewModel.session.currentUser?.id,
                avatarPath: authViewModel.session.currentUser?.avatarPath,
                displayName: authViewModel.session.currentUser?.displayName ?? "게스트",
                handle: isSignedIn ? authViewModel.session.currentUser?.handle : nil,
                subtitle: ReviewDemoMode.isActive ? "DEMO · 로컬 체험 프로필" : (isSignedIn ? "로그인됨" : "로그인하지 않음"),
                workoutCountLabel: "\(workouts.count)개의 운동",
                subtitleIcon: isSignedIn ? "checkmark.circle" : "person.crop.circle",
                onEdit: (isSignedIn || ReviewDemoMode.isActive) ? { isPresentingProfileEditor = true } : nil,
                compact: true
            )
            if !isSignedIn && !ReviewDemoMode.isActive {
                Text("이 기기의 기록을 사용 중이에요.")
                    .font(.subheadline)
                    .foregroundStyle(SOOMColor.secondaryInk)
                NavigationLink { SettingsView(category: .account) } label: {
                    Text("로그인")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(SOOMColor.white)
                        .background(SOOMColor.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.login")
                if authViewModel.session.currentUser != nil {
                    Button("이 기기에서 사용하는 이름 수정") { isPresentingProfileEditor = true }
                        .font(.subheadline)
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var profileTabs: some View {
        ProfileSectionTabs(selection: $selectedTab, pendingRequests: pendingRequestCount, compact: true)
    }

    private var selectedWeekIndex: Int {
        weeklyPoints.firstIndex(where: { $0.week == selectedWeekPoint?.week }) ?? max(weeklyPoints.count - 1, 0)
    }
    private func moveWeek(_ delta: Int) {
        let points = weeklyPoints
        guard !points.isEmpty else { return }
        selectedWeek = points[min(max(selectedWeekIndex + delta, 0), points.count - 1)].week
    }

    private var filteredWorkouts: [UnifiedWorkout] {
        workouts.filter { !$0.isExcludedFromAnalysis && sportFilter.includes($0) }
    }

    private var sportSelectorLayout: AnyLayout { dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout()) }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            SOOMCard {
                Text("주간 활동")
                    .font(.headline).accessibilityIdentifier("profile.weeklyGroup")
                Text("운동 성향 · " + profileIdentity.hero.identityTitle)
                    .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                sportSelectorLayout {
                    ForEach(ProfileSportFilter.allCases) { filter in
                        Button { sportFilter = filter } label: {
                            Text(filter.title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(sportFilter == filter ? SOOMColor.white : SOOMColor.ink)
                                .padding(.horizontal, 13).frame(minHeight: 44)
                                .background(sportFilter == filter ? SOOMColor.accent : SOOMColor.surfaceMuted, in: Capsule())
                        }.accessibilityAddTraits(sportFilter == filter ? .isSelected : [])
                    }
                }.buttonStyle(.plain)
                HStack {
                    Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("이전 주").accessibilityIdentifier("profile.week.previous")
                        .disabled(selectedWeekIndex == 0)
                    Text(selectedWeekTitle).font(.headline).accessibilityIdentifier("profile.week.title").frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("다음 주").accessibilityIdentifier("profile.week.next")
                        .disabled(selectedWeekIndex == weeklyPoints.count - 1)
                }
                HStack(alignment: .top, spacing: 12) {
                    progressMetric("거리", value: distanceText(kilometers: selectedWeekPoint?.distanceKilometers ?? 0))
                    progressMetric("시간", value: durationText(seconds: selectedWeekPoint?.durationSeconds ?? 0))
                    progressMetric("운동", value: "\(selectedWeekPoint?.workoutCount ?? 0)회")
                }
                Text("최근 12주 거리")
                    .font(.footnote)
                    .foregroundStyle(SOOMColor.secondaryInk)
                Chart {
                    ForEach(weeklyPoints) { point in
                        AreaMark(x: .value("주", point.week), y: .value("거리", point.distanceKilometers))
                            .foregroundStyle(SOOMColor.accent.opacity(0.13))
                        LineMark(x: .value("주", point.week), y: .value("거리", point.distanceKilometers))
                            .foregroundStyle(SOOMColor.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("주", point.week), y: .value("거리", point.distanceKilometers))
                            .foregroundStyle(SOOMColor.accent)
                            .symbolSize(selectedWeekPoint?.week == point.week ? 95 : 35)
                    }
                    if let point = selectedWeekPoint {
                        RuleMark(x: .value("선택한 주", point.week))
                            .foregroundStyle(SOOMColor.accent.opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .frame(height: 170)
                .chartYAxisLabel("km")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let x = gesture.location.x - geometry[plotFrame].origin.x
                                    guard let date = proxy.value(atX: x, as: Date.self) else { return }
                                    selectedWeek = weeklyPoints.min {
                                        abs($0.week.timeIntervalSince(date)) < abs($1.week.timeIntervalSince(date))
                                    }?.week
                                })
                    }
                }
                .accessibilityLabel("최근 12주 운동 거리")
                .accessibilityValue(selectedWeekTitle)
                .accessibilityAdjustableAction { direction in
                    switch direction { case .increment: moveWeek(1); case .decrement: moveWeek(-1); @unknown default: break }
                }
            }
            workoutSummary
            HStack(alignment: .top, spacing: 10) {
                SOOMCard {
                    Text("운동을 이어간 주").font(.subheadline.weight(.semibold))
                    Text("\(consecutiveWeeks)주")
                        .font(.title2.weight(.bold))
                    Text("이번 주부터 연속으로 운동한 주")
                        .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                }
                SOOMCard {
                    Text("이번 달 운동").font(.subheadline.weight(.semibold))
                    Text("\(currentMonthWorkouts.count)회")
                        .font(.title2.weight(.bold))
                    Text(durationText(currentMonthWorkouts))
                        .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                }
            }
            SOOMCard {
                Text("대표 기록").font(.headline)
                ForEach(profileIdentity.personalBests) { best in ProfileBestRow(best: best) }
            }
            SOOMCard {
                Text("기록 출처").font(.headline)
                Text("최근 30일에 저장된 운동의 기기 또는 가져오기 경로")
                    .font(.footnote).foregroundStyle(SOOMColor.secondaryInk)
                if recentSources.isEmpty {
                    Text("아직 표시할 기록이 없어요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                } else {
                    ForEach(recentSources, id: \.name) { source in
                        HStack {
                            Image(systemName: "sensor.tag.radiowaves.forward")
                            VStack(alignment: .leading) {
                                Text(source.name).font(.subheadline.weight(.semibold))
                                Text("\(source.count)개 운동 · 마지막 \(source.lastUsed.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func progressMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                .lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedWeekPoint: ProfileWeekPoint? {
        let points = weeklyPoints
        return points.first(where: { $0.week == selectedWeek }) ?? points.last
    }
    private var selectedWeekTitle: String {
        guard let point = selectedWeekPoint else { return "이번 주" }
        if Calendar.current.isDate(point.week, equalTo: Date(), toGranularity: .weekOfYear) {
            return "이번 주"
        }
        return "\(point.week.formatted(.dateTime.month().day())) 주"
    }
    private var currentMonthWorkouts: [UnifiedWorkout] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else { return [] }
        return workouts.filter { !$0.isExcludedFromAnalysis && interval.contains($0.startDate) }
    }
    private var weeklyPoints: [ProfileWeekPoint] {
        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<12).reversed().compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { return nil }
            let items = filteredWorkouts.filter { $0.startDate >= week && $0.startDate < next }
            return ProfileWeekPoint(
                week: week,
                distanceKilometers: items.compactMap(\.distanceMeters).reduce(0, +) / 1_000,
                durationSeconds: items.map(\.durationSeconds).reduce(0, +),
                workoutCount: items.count
            )
        }
    }
    private var consecutiveWeeks: Int {
        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        var count = 0
        for offset in 0..<520 {
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week),
                  workouts.contains(where: { !$0.isExcludedFromAnalysis && $0.startDate >= week && $0.startDate < next }) else { break }
            count += 1
        }
        return count
    }
    private var recentSources: [(name: String, count: Int, lastUsed: Date)] {
        let threshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recent = workouts.filter { $0.startDate >= threshold }
        let grouped = Dictionary(grouping: recent) { workout in
            let device = workout.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let device, !device.isEmpty { return device }
            switch workout.source {
            case .appleHealthKit: return "Apple 건강"
            case .strava: return "Strava ZIP"
            case .googleHealth: return "Google Health"
            default: return "SOOM 기록"
            }
        }
        return grouped.compactMap { key, values in
            guard let last = values.map(\.startDate).max() else { return nil }
            return (name: key, count: values.count, lastUsed: last)
        }
        .sorted { $0.lastUsed > $1.lastUsed }
    }
    private func distanceText(_ items: [UnifiedWorkout]) -> String {
        distanceText(kilometers: items.compactMap(\.distanceMeters).reduce(0, +) / 1_000)
    }
    private func distanceText(kilometers: Double) -> String {
        return kilometers >= 100 ? "\(Int(kilometers.rounded())) km" : String(format: "%.1f km", kilometers)
    }
    private func durationText(_ items: [UnifiedWorkout]) -> String {
        durationText(seconds: items.map(\.durationSeconds).reduce(0, +))
    }
    private func durationText(seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(minutes)분"
    }

    private var activitiesContent: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("내 운동").font(.title2.weight(.bold))
            Text("이 기기의 개인 운동 보관함이에요. 비공개 운동도 포함하며, 이 목록을 보는 것만으로 공개되지 않아요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            if workouts.isEmpty {
                SOOMCard { Text("아직 운동 기록이 없어요.").foregroundStyle(SOOMColor.secondaryInk) }
            } else {
                ForEach(workouts.prefix(40)) { workout in
                    ActivityWorkoutRow(workout: workout)
                }
                NavigationLink("전체 활동 보기") { UnifiedWorkoutLibraryViewContainer() }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var galleryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("운동 사진").font(.title2.weight(.bold))
            Text("최근 \(min(galleryLimit, workouts.count))개 운동에서 사진을 확인해요.").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
            if galleryLoading && gallery.isEmpty { SOOMSkeleton(layout: .photo, label: "사진을 확인하는 중").frame(height: 180).accessibilityIdentifier("profile.gallery.loading") }
            if let error = galleryError {
                SOOMCard {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline).accessibilityIdentifier("profile.gallery.error")
                    Button { galleryQARetry = true; Task { await refreshGallery() } } label: { Text("사진 다시 불러오기").frame(minHeight: 44) }
                        .accessibilityIdentifier("profile.gallery.retry")
                }
            }
            if gallery.isEmpty && !galleryLoading && galleryError == nil {
                SOOMCard {
                    Text("운동에 추가한 사진이 여기에 표시돼요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Button("활동 보기") { selectedTab = .activities }
                        .frame(minHeight: 44)
                }
            } else {
                ForEach(gallery) { entry in
                    NavigationLink { UnifiedWorkoutDetailDestination(unifiedWorkout: entry.workout) } label: {
                        SOOMCard {
                            Text(entry.workout.userTitle ?? entry.workout.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline).foregroundStyle(SOOMColor.ink)
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(entry.photos) { photo in
                                        WorkoutPhotoImage(photo: photo)
                                            .frame(width: 160, height: 160)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if galleryLimit < workouts.count {
                Button("이전 운동 사진 더 확인하기") { galleryLimit += 30 }.frame(minHeight: 44).disabled(galleryLoading)
                    .accessibilityIdentifier("profile.gallery.more")
            }
        }
    }

    @MainActor
    private func refreshGallery() async {
        guard selectedTab == .gallery else { return }
        let request = UUID(); galleryRequest = request
        let scope = healthStorage.scopeID
        let ownerID = authViewModel.session.currentUser?.id
        galleryLoading = true; galleryError = nil
        galleryAttempts += 1
        #if DEBUG && targetEnvironment(simulator)
        if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1",
           ProcessInfo.processInfo.environment["SOOM_UX_GALLERY_STATE"] == "failure", !galleryQARetry {
            try? await Task.sleep(for: .seconds(2))
            guard galleryRequest == request, healthStorage.scopeID == scope, !Task.isCancelled else { return }
            galleryLoading = false; gallery = []; galleryError = "사진을 확인하지 못했어요. 다시 시도해 주세요."
            return
        }
        #endif
        defer { if galleryRequest == request { galleryLoading = false } }
        let load: (UnifiedWorkout) async throws -> [WorkoutPhotoReference]
        if ReviewDemoMode.isActive, ownerID == ReviewDemoMode.userID {
            load = { try await ReviewDemoPhotoStore.shared.load(workoutID: $0.id, ownerID: ReviewDemoMode.userID) }
        } else if isSignedIn, let ownerID,
                  let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() {
            let service = WorkoutPhotoService(client: client)
            load = { try await service.load(workoutID: $0.id, ownerID: ownerID) }
        } else {
            gallery = []; galleryError = "사진을 확인하려면 해당 기록의 계정으로 로그인해 주세요."
            return
        }
        var entries: [ProfileGalleryEntry] = []; var failed = 0
        for workout in workouts.prefix(galleryLimit) {
            guard !Task.isCancelled, galleryRequest == request, healthStorage.scopeID == scope,
                  authViewModel.session.currentUser?.id == ownerID else { return }
            do {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["SOOM_UX_GALLERY_LOADING_COUNTER"] == "1" { galleryReadCount += 1 }
                #endif
                let photos = try await load(workout)
                if !photos.isEmpty { entries.append(ProfileGalleryEntry(workout: workout, photos: photos)) }
            } catch is CancellationError { return }
            catch { failed += 1 }
        }
        guard !Task.isCancelled, galleryRequest == request, healthStorage.scopeID == scope,
              authViewModel.session.currentUser?.id == ownerID else { return }
        gallery = entries
        galleryError = failed > 0 ? "\(failed)개 운동의 사진을 확인하지 못했어요. 사진이 없는 상태와는 달라요." : nil
    }

    @MainActor
    private func refreshPendingRequests() async {
        pendingRequestCount = nil
        guard isSignedIn, !ReviewDemoMode.isActive, socialSafety.canUseSocial,
              let viewer = socialSafety.viewerID,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return }
        let generation = socialSafety.accountGeneration, revision = socialSafety.revision
        let service = SupabaseAccountPrivacyService(client: client)
        var cursor: IncomingFollowRequest?; var seen = Set<UUID>(); var count = 0
        do {
            while true {
                let rows = try await service.incoming(after: cursor)
                guard !Task.isCancelled, service.viewerID == viewer, socialSafety.viewerID == viewer,
                      generation == socialSafety.accountGeneration, revision == socialSafety.revision, socialSafety.canUseSocial else { return }
                for row in rows where seen.insert(row.id).inserted { if row.state == .pending { count += 1 } }
                if rows.count < 50 { break }
                guard let next = rows.last, next.id != cursor?.id else { return }
                cursor = next
            }
            pendingRequestCount = count
        } catch { /* Unknown remains unknown; never display a fabricated zero. */ }
    }

    private var workoutSummary: some View {
        ProfileWorkoutSummaryCard(metrics: profileIdentity.compactHeroStats.map {
            ProfileSummaryMetric(title: $0.title, value: $0.value)
        })
    }

    private var detailEntries: some View {
        VStack(spacing: 0) {
            if isSignedIn && !ReviewDemoMode.isActive {
                NavigationLink { FollowRequestsView() } label: {
                    SettingsNavigationRow(icon: "person.badge.clock", title: "팔로우 요청 · 승인 관리", subtitle: pendingRequestCount.map { "대기 요청 \($0)개 · 팔로워 관리" } ?? "요청 확인과 팔로워 관리")
                }.frame(minHeight: 44).accessibilityIdentifier("profile.followRequests")
                Divider()
            }
            NavigationLink {
                SOOMScreen { movementPatternSection }.navigationTitle("운동 성향").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsNavigationRow(icon: "figure.mixed.cardio", title: "운동 성향", subtitle: profileIdentity.hero.identityTitle)
            }
            Divider()
            NavigationLink {
                SOOMScreen { personalBestSection }.navigationTitle("대표 기록").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsNavigationRow(icon: SOOMIcon.medal, title: "대표 기록", subtitle: "종목별 최고 기록")
            }
            Divider()
            NavigationLink {
                SOOMScreen { badgeShowcaseSection }.navigationTitle("배지").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsNavigationRow(icon: "seal", title: "배지", subtitle: "기록으로 쌓은 성취")
            }
            Divider()
            NavigationLink {
                SOOMScreen { signatureRoutesSection }.navigationTitle("대표 코스").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            } label: {
                SettingsNavigationRow(icon: SOOMIcon.map, title: "대표 코스", subtitle: profileIdentity.signatureRoutes.isEmpty ? "아직 표시할 코스가 없어요" : "나를 대표하는 운동 경로")
            }
        }
        .buttonStyle(.plain)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var movementPatternSection: some View {
        SOOMCard {
            Text(profileIdentity.hero.identityTitle).font(.title3.weight(.semibold))
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(profileIdentity.patterns) { ProfilePatternCard(pattern: $0) }
            }
        }
    }

    private var personalBestSection: some View {
        SOOMCard {
            ForEach(profileIdentity.personalBests) { ProfileBestRow(best: $0) }
        }
    }

    private var signatureRoutesSection: some View {
        SOOMCard {
            if profileIdentity.signatureRoutes.isEmpty {
                Text("대표 코스를 표시할 자료가 아직 부족해요.")
                    .font(.body).foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(profileIdentity.signatureRoutes) { ProfileRouteIdentityCard(route: $0) }
                }
            }
        }
    }

    private var badgeShowcaseSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(profileIdentity.badges) { ProfileBadgeTile(badge: $0) }
        }
    }

    @MainActor
    private func refreshProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        localDataPresence = await LocalDataDetector.live(modelContext: modelContext).detect()
        do {
            let workouts = try await SwiftDataUnifiedWorkoutStore(modelContext: modelContext).fetchCanonicalRecentWorkouts(days: 3_650)
            self.workouts = workouts.sorted { $0.startDate > $1.startDate }
            profileIdentity = ProfileWorkoutAggregator().profileIdentity(from: workouts)
            loadError = nil
            hasLoadedProfile = true
            await refreshGallery()
        } catch {
            loadError = "운동 요약을 불러오지 못했어요."
        }
    }
}

private struct ProfileBestRow: View {
    let best: ProfileIdentitySystem.PersonalBest

    var body: some View {
        HStack(spacing: 12) {
            SOOMSportIconView(name: best.icon, size: SOOMFont.Size.body)
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: 36, height: 36)
                .background(SOOMColor.surfaceMuted)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(best.title)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                Text(best.value)
                    .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text(best.context)
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileRouteIdentityCard: View {
    let route: ProfileIdentitySystem.SignatureRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(soom: SOOMIcon.map)
                .font(.system(size: SOOMFont.Size.body, weight: .bold))
                .foregroundStyle(SOOMColor.secondaryInk)
                .frame(width: 32, height: 32)
                .background(SOOMColor.surfaceMuted)
                .clipShape(Circle())

            Text(route.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(route.marker)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.accentInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(route.mood)
                .font(SOOMFont.body(10, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfileBadgeTile: View {
    let badge: ProfileIdentitySystem.Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(soom: SOOMIcon.medal)
                    .font(.system(size: SOOMFont.Size.body, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(Circle())

                Spacer(minLength: 0)

                Text(badge.state)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(badge.isRare ? SOOMColor.accentInk : SOOMColor.secondaryInk)
                    .padding(.horizontal, SOOMLayout.Spacing.sm)
                    .padding(.vertical, SOOMLayout.Spacing.xs)
                    .background(badge.isRare ? SOOMColor.accentSurface : SOOMColor.surface)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(badge.subtitle)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(value: badge.progress)
                .tint(SOOMColor.accent)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)
                .accessibilityLabel("\(badge.title) 진행률")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

private struct ProfilePatternCard: View {
    let pattern: ProfileIdentitySystem.MovementPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SOOMSportIconView(name: pattern.icon, size: SOOMFont.Size.subheadline)
                    .foregroundStyle(pattern.isPrimary ? SOOMColor.accent : SOOMColor.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(pattern.isPrimary ? SOOMColor.accentSurface : SOOMColor.surface)
                    .clipShape(Circle())

                Text(pattern.isPrimary ? "대표" : "성향")
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(pattern.isPrimary ? SOOMColor.accentInk : SOOMColor.tertiaryInk)
            }

            Text(pattern.title)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)

            Text(pattern.subtitle)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

#Preview("ProfileIdentityView") {
    NavigationStack {
        ProfileIdentityView()
    }
    .environmentObject(AuthViewModel())
    .preferredColorScheme(.light)
}

/// Shared public identity and navigation used by both the owner and visitor.
/// Private controls stay in ProfileIdentityView and never enter this component.
struct ProfilePublicIdentityHeader: View {
    let userID: UUID?
    let avatarPath: String?
    let displayName: String
    let handle: String?
    let subtitle: String?
    let workoutCountLabel: String
    var subtitleIcon: String? = nil
    var onEdit: (() -> Void)? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                SOOMAvatarView(userID: userID, avatarPath: avatarPath, size: compact ? 56 : 64)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                    Text(displayName)
                        .font(compact ? .title2.weight(.semibold) : SOOMFont.displayMedium(26, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.displayName")
                        if let onEdit {
                            Button(action: onEdit) {
                                Image(systemName: "pencil").frame(width: compact ? 48 : 44, height: compact ? 48 : 44)
                                    .background(SOOMColor.accentSurface, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("프로필 수정")
                                .accessibilityIdentifier("profile.edit")
                        }
                    }
                    if let subtitle {
                        if let subtitleIcon {
                            Label(subtitle, soomIcon: subtitleIcon)
                                .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        } else {
                            Text(subtitle).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        }
                    }
                    if let handle, !handle.isEmpty {
                        Text(handle.hasPrefix("@") ? handle : "@\(handle)")
                            .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ProfileSectionTabs: View {
    @Binding var selection: ProfileSection
    var pendingRequests: Int? = nil
    var activityTitle = "내 운동"
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 7) {
            ForEach(ProfileSection.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        if !compact { Image(systemName: tab.icon).font(.system(size: 18)) }
                        Text(tab == .activities ? activityTitle : tab.title).font(.subheadline.weight(selection == tab ? .bold : .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if tab == .more, let count = pendingRequests, count > 0 {
                            Text("대기 요청 \(count)개").font(.caption.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: compact ? 44 : 62)
                    .foregroundStyle(selection == tab ? SOOMColor.accentInk : SOOMColor.secondaryInk)
                    .background(compact ? SOOMColor.surface : (selection == tab ? SOOMColor.accentSurface : SOOMColor.surfaceMuted),
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottom) {
                        if compact {
                            Capsule().fill(selection == tab ? SOOMColor.accent : .clear).frame(height: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selection == tab ? SOOMColor.accentLine : SOOMColor.line, lineWidth: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .more && (pendingRequests ?? 0) > 0 ? "더보기, 대기 요청 \(pendingRequests ?? 0)개" : (tab == .activities ? activityTitle : tab.title))
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                .accessibilityIdentifier("profile.tab.\(tab.rawValue)")
            }
        }
        .padding(.top, 7)
    }
}

struct ProfileSummaryMetric: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

struct ProfileWorkoutSummaryCard: View {
    let metrics: [ProfileSummaryMetric]
    var footnote: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SOOMCard {
            Text("운동 요약").font(.headline).foregroundStyle(SOOMColor.ink)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(metrics) { metric in summaryStat(metric) }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(metrics) { metric in summaryStat(metric) }
                }
            }
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            }
        }
    }

    private func summaryStat(_ metric: ProfileSummaryMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1).minimumScaleFactor(0.65).allowsTightening(true)
            Text(metric.title).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                .lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
