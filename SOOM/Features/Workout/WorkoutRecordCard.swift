import SwiftData
import SwiftUI

struct WorkoutCardMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

enum WorkoutCardDateFormatter {
    static func label(_ date: Date, calendar: Calendar = .current) -> String {
        let value = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = value.year, let month = value.month, let day = value.day,
              let hour = value.hour, let minute = value.minute else { return "날짜 확인 필요" }
        return String(format: "%04d-%02d-%02d %@%d:%02d", year, month, day,
                      hour < 12 ? "오전" : "오후", hour % 12 == 0 ? 12 : hour % 12, minute)
    }
}

private struct SOOMCurrentProfileIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
extension EnvironmentValues {
    var soomCurrentProfileID: UUID? {
        get { self[SOOMCurrentProfileIDKey.self] }
        set { self[SOOMCurrentProfileIDKey.self] = newValue }
    }
}

struct WorkoutIdentityLine: View {
    let author: String
    let authorID: UUID?
    let avatarPath: String?
    let date: Date
    let device: String?
    let sport: UnifiedWorkoutType
    let location: String
    var onOpen: (() -> Void)? = nil
    var showsAuthorFollow = false
    var onOpenAuthor: (() -> Void)? = nil
    @Environment(\.soomCurrentProfileID) private var currentProfileID

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let authorID, authorID == currentProfileID {
                SOOMAvatarView(userID: authorID, avatarPath: avatarPath, size: 46)
            } else if let authorID, let onOpenAuthor {
                Button(action: onOpenAuthor) {
                    SOOMAvatarView(userID: authorID, avatarPath: avatarPath, size: 46)
                }.buttonStyle(.plain).accessibilityLabel("\(author) 프로필 보기")
            } else if let authorID {
                SOOMProfileLink(userID: authorID) {
                    SOOMAvatarView(userID: authorID, avatarPath: avatarPath, size: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(author) 프로필 보기")
            } else {
                SOOMAvatarView(userID: nil, avatarPath: avatarPath, size: 46)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let authorID, authorID == currentProfileID {
                    Text(author).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                } else if authorID != nil, let onOpenAuthor {
                    Button(action: onOpenAuthor) {
                        Text(author).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                    }.buttonStyle(.plain).accessibilityIdentifier("workout.card.authorProfile")
                } else if let authorID {
                    SOOMProfileLink(userID: authorID) {
                        Text(author).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout.card.authorProfile")
                } else {
                    Text(author).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                }
                if let onOpen, currentProfileID == nil || currentProfileID != authorID {
                    Button(action: onOpen) { workoutMetadata }
                        .buttonStyle(.plain)
                        .accessibilityLabel("운동 상세 보기")
                } else {
                    workoutMetadata
                }
            }
            Spacer(minLength: 0)
            if showsAuthorFollow, let authorID { FeedAuthorFollowControl(userID: authorID, author: author) }
        }
    }

    private var workoutMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WorkoutCardDateFormatter.label(date) + (device.map { " · \($0)" } ?? ""))
                .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(location)
            } icon: {
                SOOMSportIconView(name: FeedCardFormatting.icon(sport), size: 13)
            }
            .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            .accessibilityLabel("\(sport.shareDisplayName), \(location)")
        }
    }
}

struct WorkoutCardLoadIdentity: Equatable {
    let account: AccountDeletionTarget
    let scopeID: String
    let workoutID: UUID
    let workoutUpdatedAt: Date
    let routeUpdatedAt: Date?
    var dataRevision: Int = 0
    var routeContent: WorkoutRouteReadSnapshot? = nil
    var sourceWorkout: UnifiedWorkout? = nil
}

/// Presentation inputs only. Avatar pixels still require the existing current batch grant.
enum Feed61OwnedAuthorPresentation: Equatable {
    case localOwner
    case authorized(FeedProfileDTO)
    case unavailable

    struct Header: Equatable {
        let name: String
        let id: UUID?
        let avatarPath: String?
    }
    static func resolve(_ presentation: Self?, authName: String?, authID: UUID?, authAvatarPath: String?) -> Header {
        switch presentation {
        case .localOwner?:
            return .init(name: "내 기록", id: nil, avatarPath: nil)
        case .authorized(let author)?:
            return .init(name: author.displayName, id: author.id, avatarPath: author.avatarPath)
        case .unavailable?:
            return .init(name: "작성자 정보 확인 불가", id: nil, avatarPath: nil)
        case nil:
            return .init(name: authName ?? "나", id: authID, avatarPath: authAvatarPath)
        }
    }
}

/// Other metadata edits must not cancel a region lookup already in flight.
struct WorkoutCardRegionLoadIdentity: Equatable {
    let account: AccountDeletionTarget
    let scopeID: String
    let workoutID: UUID
    let routeUpdatedAt: Date?
    let locationName: String?
}

/// The single workout-card layout used by feed, activity, saved records and club posts.
/// Navigation regions are separate buttons so editing, expansion and horizontal media scrolling stay independent.
struct WorkoutRecordCard<Management: View>: View {
    let title: String
    let description: String?
    let date: Date
    let sport: UnifiedWorkoutType
    let author: String
    var authorID: UUID? = nil
    var showsAuthorFollow = false
    var showsManagement = false
    var avatarPath: String? = nil
    var device: String? = nil
    var location: String = "지역 미입력"
    let metrics: [WorkoutCardMetric]
    var workoutID: UUID? = nil
    var route: WorkoutRoute? = nil
    var routePrivacyAlreadyApplied = false
    var photosAreKnown = false
    var imageURL: URL? = nil
    var routePhoto: WorkoutPhotoReference? = nil
    var photos: [WorkoutPhotoReference] = []
    var achievements: [WorkoutAchievement] = []
    var onOpen: (() -> Void)? = nil
    var onOpenAuthor: (() -> Void)? = nil
    @ViewBuilder let management: () -> Management
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expanded = false
    @State private var routeProjection = WorkoutCardRouteProjection()
    private var maskedRoute: WorkoutRoute? { routeProjection.preview(route) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                WorkoutIdentityLine(author: author, authorID: authorID, avatarPath: avatarPath,
                    date: date, device: device, sport: sport, location: location, onOpen: onOpen, showsAuthorFollow: showsAuthorFollow, onOpenAuthor: onOpenAuthor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsManagement { management() }
            }
            .padding(.horizontal, 16).padding(.top, 24)

            VStack(alignment: .leading, spacing: 13) {
                openRegion("summary") {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(title).font(.title2.weight(.bold)).foregroundStyle(SOOMColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                                .lineLimit(expanded ? nil : 3).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let description, description.count > 70 || description.filter({ $0 == "\n" }).count > 2 {
                    Button(expanded ? "접기" : "더 보기") { expanded.toggle() }
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk).frame(minHeight: 44)
                        .accessibilityIdentifier("workout.card.expand")
                }
            }.padding(.horizontal, 16).padding(.top, 27)

            openRegion("metrics") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 16) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.label).font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
                            Text(metric.value).font(SOOMFont.body(17, weight: .bold, relativeTo: .headline)).foregroundStyle(SOOMColor.ink)
                                .minimumScaleFactor(0.8).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)

            if let achievement = achievements.first {
                openRegion("achievement") {
                    HStack(spacing: 12) {
                        Image(soom: SOOMIcon.medal).font(.system(size: 31))
                            .foregroundStyle(achievement.rank == 1 ? .yellow : .orange)
                        Text(achievement.bannerComparisonText).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        if achievements.count > 1 { Text("+\(achievements.count - 1)").font(.caption.weight(.bold)) }
                    }.padding(16).background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 9))
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }

            WorkoutPhotoMediaRow(workoutID: workoutID, photos: photos, photosAreKnown: photosAreKnown,
                allowsFeedPresentationReuse: true,
                hasRoute: (maskedRoute?.coordinates.count ?? 0) > 1,
                routeHandlesOpen: (maskedRoute?.coordinates.count ?? 0) > 1,
                onOpenPhoto: onOpen) {
                Group {
                    if let route = maskedRoute, route.coordinates.count > 1 {
                        FeedStaticRouteImage(route: route, sport: sport, isAlreadyPrivacyMasked: true, onOpen: onOpen)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface)
        .accessibilityIdentifier("workout.card")
    }

    @ViewBuilder private func openRegion<Content: View>(_ identifier: String, @ViewBuilder content: () -> Content) -> some View {
        if let onOpen {
            Button(action: onOpen) {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("운동 상세 보기")
            .accessibilityIdentifier("workout.card.open.\(identifier)")
        } else {
            content()
        }
    }
}

struct WorkoutRecordRoutePreview: View {
    let route: WorkoutRoute
    var body: some View {
        Canvas { context, size in
            let coordinates = route.coordinates
            guard let minLat = coordinates.map(\.latitude).min(), let maxLat = coordinates.map(\.latitude).max(),
                  let minLon = coordinates.map(\.longitude).min(), let maxLon = coordinates.map(\.longitude).max() else { return }
            let longitudeFactor = max(cos((minLat + maxLat) / 2 * .pi / 180), 0.01)
            let spanX = max((maxLon - minLon) * longitudeFactor, 0.000001)
            let spanY = max(maxLat - minLat, 0.000001)
            let scale = min((size.width - 36) / spanX, (size.height - 36) / spanY)
            let insetX = (size.width - spanX * scale) / 2
            let insetY = (size.height - spanY * scale) / 2
            for segment in route.coordinateSegments where segment.count > 1 {
                var path = Path()
                for (index, point) in segment.enumerated() {
                    let target = CGPoint(x: insetX + (point.longitude - minLon) * longitudeFactor * scale,
                                         y: size.height - insetY - (point.latitude - minLat) * scale)
                    if index == 0 { path.move(to: target) } else { path.addLine(to: target) }
                }
                context.stroke(path, with: .color(SOOMColor.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("실제 운동 경로")
    }
}

/// Activity and an exact self-owned feed projection share the same local card
/// data preparation, media loader, route masking and achievement presentation.
struct OwnedWorkoutRecordCard<Management: View>: View {
    let workout: UnifiedWorkout
    var showsManagement = false
    var enrichRegion = true
    var ownedPhotoPresentation: Feed61OwnedPhotoPresentation? = nil
    var ownedAuthorPresentation: Feed61OwnedAuthorPresentation? = nil
    var isAuthorized: () -> Bool = { true }
    var onOpen: (() -> Void)? = nil
    var onOpenAuthor: (() -> Void)? = nil
    @ViewBuilder let management: () -> Management
    @State private var achievements: [WorkoutAchievement] = []
    @State private var relatedRoute: WorkoutRoute?
    @State private var loadedIdentity: WorkoutCardLoadIdentity?
    @State private var approvedMapRepair = ApprovedWorkoutMapRepair()
    @State private var routeProjection = WorkoutCardRouteProjection()
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Query private var routes: [PersistedWorkoutRoute]
    init(workout: UnifiedWorkout, showsManagement: Bool = false, enrichRegion: Bool = true,
         ownedPhotoPresentation: Feed61OwnedPhotoPresentation? = nil,
         ownedAuthorPresentation: Feed61OwnedAuthorPresentation? = nil,
         isAuthorized: @escaping () -> Bool = { true }, onOpen: (() -> Void)? = nil,
         onOpenAuthor: (() -> Void)? = nil, @ViewBuilder management: @escaping () -> Management) {
        self.workout = workout; self.showsManagement = showsManagement; self.enrichRegion = enrichRegion; self.isAuthorized = isAuthorized
        self.ownedPhotoPresentation = ownedPhotoPresentation
        self.ownedAuthorPresentation = ownedAuthorPresentation
        self.onOpen = onOpen; self.onOpenAuthor = onOpenAuthor; self.management = management
        let id = workout.id
        _routes = Query(filter: #Predicate<PersistedWorkoutRoute> { $0.workoutId == id })
    }
    private var loadIdentity: WorkoutCardLoadIdentity {
        WorkoutCardLoadIdentity(account: auth.accountDeletionTarget, scopeID: storage.scopeID,
            workoutID: workout.id, workoutUpdatedAt: workout.updatedAt, routeUpdatedAt: routes.first?.updatedAt,
            dataRevision: storage.dataRevision, routeContent: routes.first.map(WorkoutRouteReadSnapshot.init),
            sourceWorkout: ownedPhotoPresentation != nil ? workout : nil)
    }
    private var resolvedHeader: Feed61OwnedAuthorPresentation.Header {
        Feed61OwnedAuthorPresentation.resolve(ownedAuthorPresentation,
            authName: auth.session.currentUser?.displayName, authID: auth.session.currentUser?.id,
            authAvatarPath: auth.session.currentUser?.avatarPath)
    }
    var body: some View {
        let header = resolvedHeader
        WorkoutRecordCard(title: workout.displayTitle, description: workout.recordDescription,
            date: workout.startDate, sport: workout.workoutType,
            author: header.name,
            authorID: header.id, showsManagement: showsManagement, avatarPath: header.avatarPath,
            device: workout.deviceName ?? workout.feedSourceLabel,
            location: FeedCardFormatting.region(workout.locationName, hasRoute: (route?.coordinates.count ?? 0) > 1),
            metrics: FeedCardFormatting.metrics(workout), workoutID: workout.id, route: route,
            photosAreKnown: ownedPhotoPresentation != nil, photos: ownedPhotoPresentation?.photos ?? [],
            achievements: loadedIdentity == loadIdentity ? achievements : [],
            onOpen: onOpen, onOpenAuthor: onOpenAuthor, management: management)
            .task(id: loadIdentity) {
                guard isAuthorized() else { return }
                let expectedIdentity = loadIdentity
                if loadedIdentity != expectedIdentity { relatedRoute = nil; achievements = []; loadedIdentity = nil }
                let expectedScope = storage.scopeID
                let expectedAccount = auth.accountDeletionTarget
                let loadedRoute = try? await WorkoutTelemetryStore(modelContext: context).resolvedRoute(for: workout)
                guard !Task.isCancelled, isAuthorized(), loadIdentity == expectedIdentity, storage.scopeID == expectedScope,
                      storage.container === context.container, auth.accountDeletionTarget == expectedAccount else { return }
                relatedRoute = loadedRoute; loadedIdentity = expectedIdentity
                // Publish geometry before optional historical markers.
                let loaded = await WorkoutCardAchievementLoader.load(workout: workout, route: loadedRoute ?? route, context: context)
                guard !Task.isCancelled, isAuthorized(), loadIdentity == expectedIdentity, storage.scopeID == expectedScope,
                      storage.container === context.container, auth.accountDeletionTarget == expectedAccount else { return }
                achievements = loaded
                relatedRoute = loadedRoute
            }
            .task(id: WorkoutCardRegionLoadIdentity(account: auth.accountDeletionTarget, scopeID: storage.scopeID,
                workoutID: workout.id, routeUpdatedAt: routes.first?.updatedAt, locationName: workout.locationName)) {
                guard isAuthorized() else { return }
                let expectedScope = storage.scopeID
                let expectedAccount = auth.accountDeletionTarget
                guard enrichRegion else { return }
                _ = await WorkoutRegionEnricher.resolveAndPersist(workoutID: workout.id, context: context,
                    scopeID: expectedScope, isCurrent: {
                        isAuthorized() && storage.scopeID == expectedScope && storage.container === context.container
                            && auth.accountDeletionTarget == expectedAccount
                    })
            }
    }
    private var route: WorkoutRoute? {
        let own = routeProjection.route(routes.first, context: context)
        let related = loadedIdentity == loadIdentity ? relatedRoute : nil
        let original = (related?.coordinates.count ?? 0) > (own?.coordinates.count ?? 0) ? related : own
        guard original?.workoutId == ApprovedWorkoutMapRepair.targetID, isAuthorized() else { return original }
        return approvedMapRepair.resolve(original, viewerID: auth.session.currentUser?.id,
            storage: storage, context: context)
    }
}

struct ActivityWorkoutRow: View {
    let workout: UnifiedWorkout
    var onOpen: ((UnifiedWorkout) -> Void)? = nil
    @State private var opening = false
    @State private var publicationFailureMessage: String?
    var body: some View {
        WorkoutManagementHost(workout: workout) { current, management in
            if onOpen == nil {
                card(workout: current, management: management)
                    .navigationDestination(isPresented: $opening) { OwnWorkoutDetailDestination(workout: current) }
            } else { card(workout: current, management: management) }
        }
    }
    private func card(workout current: UnifiedWorkout, management: WorkoutRecordManagement) -> some View {
        VStack(spacing: 0) {
            OwnedWorkoutRecordCard(workout: current, onOpen: {
                SOOMHaptics.selection()
                if let onOpen { onOpen(current) } else { opening = true }
            }) { EmptyView() }
            .alert("공개 범위를 변경하지 못했어요", isPresented: Binding(
                get: { management.errorMessage != nil || publicationFailureMessage != nil },
                set: { if !$0 { management.errorMessage = nil; publicationFailureMessage = nil } })) {
                Button("확인", role: .cancel) { management.errorMessage = nil; publicationFailureMessage = nil }
            } message: { Text(management.errorMessage ?? publicationFailureMessage ?? "") }
            Rectangle().fill(SOOMColor.surfaceMuted).frame(height: 6)
        }.padding(.horizontal, -SOOMLayout.screenPadding)
    }
    static func metrics(_ workout: UnifiedWorkout) -> [WorkoutCardMetric] {
        var result = FeedCardFormatting.metrics(workout)
        // The detail metrics panel also uses this helper and retains its additional elevation value.
        if let elevation = workout.elevationGainMeters, elevation.isFinite, elevation >= 0, elevation < Double(Int.max) {
            result.append(WorkoutCardMetric(label: "획득 고도", value: "\(Int(elevation)) m"))
        }
        return result
    }
}

enum WorkoutCardAchievementLoader {
    @MainActor static func load(workout: UnifiedWorkout, route: WorkoutRoute?, context: ModelContext) async -> [WorkoutAchievement] {
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("achievementLoad")
        WorkoutCardPerformanceProbe.hit("activeAchievements")
        defer { WorkoutCardPerformanceProbe.hit("activeAchievements", by: -1) }
        #endif
        guard !Task.isCancelled, let route else { return [] }
        let months = WorkoutAchievementConfig.lookbackMonths
        let window = Calendar.current.date(byAdding: .month, value: -months, to: workout.startDate) ?? workout.startDate
        let workouts = (try? await SwiftDataUnifiedWorkoutStore(modelContext: context)
            .fetchCanonicalRecentWorkouts(days: max(months * 31 + 31, 1))) ?? []
        guard !Task.isCancelled else { return [] }
        let ids = workouts.filter { $0.id != workout.id && $0.workoutType == workout.workoutType
            && !$0.isExcludedFromAnalysis && $0.startDate >= window && $0.startDate < workout.startDate }.map(\.id)
        // One local query replaces one query for every candidate, including missing routes.
        #if DEBUG
        if !ids.isEmpty { WorkoutCardPerformanceProbe.hit("routeBatchFetch") }
        #endif
        let records = ids.isEmpty ? [] : ((try? context.fetch(FetchDescriptor<PersistedWorkoutRoute>(
            predicate: #Predicate { ids.contains($0.workoutId) }))) ?? [])
        let byID = Dictionary(records.map { ($0.workoutId, WorkoutRouteReadSnapshot($0)) }, uniquingKeysWith: { first, _ in first })
        let snapshots = ids.compactMap { byID[$0] }
        let worker = Task.detached(priority: .userInitiated) { () throws -> [WorkoutAchievement] in
            var history: [Int: [Double]] = [:]
            for snapshot in snapshots {
                try Task.checkCancellation()
                for effort in WorkoutSegmentBestEffortFinder.bestEfforts(from: snapshot.route()) {
                    history[effort.durationMinutes, default: []].append(effort.averageMetersPerSecond)
                }
            }
            try Task.checkCancellation()
            return WorkoutAchievementBuilder.build(todayEfforts: WorkoutSegmentBestEffortFinder.bestEfforts(from: route),
                historicalEffortsByDuration: history, workoutType: workout.workoutType).markers
        }
        let result = try? await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        return Task.isCancelled ? [] : (result ?? [])
    }
}

struct OwnWorkoutDetailDestination: View {
    let workout: UnifiedWorkout
    @Environment(\.modelContext) private var context
    var body: some View {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        let routes = SwiftDataWorkoutRoutePersistenceStore(modelContext: context)
        UnifiedWorkoutDetailDestination(unifiedWorkout: workout,
            similarCandidateProvider: SimilarWorkoutCandidateProvider(store: store, persistedRouteProvider: PersistedRouteCandidateProvider(store: routes)),
            comparisonHistoryProvider: SwiftDataWorkoutComparisonHistoryProvider(store: store),
            detailRouteContextProvider: WorkoutDetailRouteContextProvider(store: routes),
            relativeEffortHistoryProvider: SwiftDataRelativeEffortHistoryProvider(store: store),
            achievementHistoryProvider: SwiftDataWorkoutAchievementHistoryProvider(workoutStore: store, routeStore: routes),
            fitnessTrendHistoryProvider: SwiftDataFitnessTrendHistoryProvider(store: store),
            gpxRouteAttachmentService: GPXRouteAttachmentService(workoutStore: store, routeStore: routes),
            fitRouteAttachmentService: FITRouteAttachmentService(workoutStore: store, routeStore: routes),
            tcxRouteAttachmentService: TCXRouteAttachmentService(workoutStore: store, routeStore: routes),
            companionUpdateService: WorkoutCompanionUpdateService(workoutStore: store))
    }
}

struct WorkoutBookmarksView: View {
    @Query(sort: \UnifiedWorkoutRecord.startDate, order: .reverse) private var records: [UnifiedWorkoutRecord]
    @State private var feedBookmarks = false
    @State private var selectedWorkout: UnifiedWorkout?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Button { feedBookmarks = true } label: {
                    Label("피드에서 저장한 글", soomIcon: "person.2").frame(minHeight: 44)
                }
                if saved.isEmpty {
                    ContentUnavailableView("저장한 기록이 없어요", soomIcon: "bookmark", description: Text("운동 상세의 북마크 버튼으로 모아둘 수 있어요."))
                }
                ForEach(saved) { workout in
                    ActivityWorkoutRow(workout: workout, onOpen: { selectedWorkout = $0 })
                }
            }.padding(20)
        }
        .background(SOOMColor.background)
        .navigationTitle("저장한 기록").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $feedBookmarks) { FeedSavedPostsViewContainer() }
        .workoutCardDestination(selection: $selectedWorkout)
    }
    private var saved: [UnifiedWorkout] {
        UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(
            records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        ).filter { $0.isBookmarked == true }
    }
}
