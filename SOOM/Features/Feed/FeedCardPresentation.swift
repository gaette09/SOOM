import Foundation
import SwiftUI
import UIKit

#if DEBUG && targetEnvironment(simulator)
/// Actual playback starts after the existing delayed eligibility and visit gates.
/// Nonpublished and synthetic-only; no additional visibility observation.
@MainActor enum Feed61RoutePlaybackProbe {
    static var mapReplays = 0
}
#endif

enum FeedOverviewPageSelection {
    /// Keep the current overview on return; only missing pages need a fallback.
    static func resolve(_ current: Int, availablePages: [Int]) -> Int {
        availablePages.contains(current) ? current : (availablePages.first ?? 0)
    }
}

struct FeedCompactOverview: View {
    let snapshot: FeedWeeklySnapshot?
    let streak: FeedStreakSnapshot
    let recovery: FeedRecoveryInsight?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0
    private var availablePages: [Int] {
        (snapshot == nil ? [] : [0]) + (streak.weekCount > 0 ? [1] : []) + (recovery == nil ? [] : [2])
    }
    var body: some View {
        if snapshot != nil || streak.weekCount > 0 || recovery != nil {
            if dynamicTypeSize.isAccessibilitySize {
                pages
            } else {
                TabView(selection: $page) { pages }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 164)
                    .onAppear { page = FeedOverviewPageSelection.resolve(page, availablePages: availablePages) }
                    .onChange(of: availablePages) { _, values in
                        page = FeedOverviewPageSelection.resolve(page, availablePages: values)
                    }
            }
        }
    }
    @ViewBuilder private var pages: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 20) {
                Text("이번 주 운동").font(.subheadline.weight(.bold))
                HStack(alignment: .top, spacing: 20) {
                    metric("거리", String(format: "%.1f km", snapshot.progress.totalDistanceKm))
                    metric("시간", "\(snapshot.progress.totalDurationMinutes)분")
                    metric("운동", "\(snapshot.progress.workoutCount)회")
                }
                Spacer(minLength: 0)
            }.padding(.top, 8).padding(.horizontal, 6).tag(0)
        }
        if streak.weekCount > 0 {
            VStack(alignment: .leading, spacing: 18) {
                Text("꾸준히 쌓은 움직임").font(.subheadline.weight(.bold))
                HStack(spacing: 18) {
                    Image(soom: "flame.fill").font(.system(size: 36)).foregroundStyle(SOOMColor.accent)
                    Text("\(streak.weekCount)주 연속\n\(streak.activityCount)번의 운동").font(.headline)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).padding(.horizontal, 6).tag(1)
        }
        if let recovery {
            NavigationLink { RecoveryViewContainer() } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("오늘의 회복").font(.subheadline.weight(.bold))
                    Text(recovery.score.map { "\($0)점 · \(recovery.status)" } ?? recovery.status).font(.title2.weight(.semibold))
                    Text(recovery.recommendation).font(.caption).foregroundStyle(SOOMColor.secondaryInk).lineLimit(2)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).tag(2)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            Text(value).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum FeedCardFormatting {
    static func movement(sport: UnifiedWorkoutType, distance: Double?, seconds: Double?, pace: Int? = nil) -> String? {
        guard let distance, distance.isFinite, distance > 0, let seconds, seconds.isFinite, seconds > 0 else {
            guard let pace, pace > 0 else { return nil }
            if sport == .cycling || sport == .other { return String(format: "%.1f km/h", 3600.0 / Double(pace)) }
            let total = sport == .swimming ? Int((Double(pace) / 10).rounded()) : pace
            return "\(total / 60):\(String(format: "%02d", total % 60))/\(sport == .swimming ? "100m" : "km")"
        }
        if sport == .cycling || sport == .other {
            return String(format: "%.1f km/h", distance / seconds * 3.6)
        }
        let denominator = sport == .swimming ? 100.0 : 1000.0
        let value = seconds / (distance / denominator)
        guard value.isFinite, value < Double(Int.max) else { return nil }
        let total = Int(value.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))/\(sport == .swimming ? "100m" : "km")"
    }
    static func metrics(_ workout: UnifiedWorkout) -> [WorkoutCardMetric] {
        let movement = movement(sport: workout.workoutType, distance: workout.distanceMeters, seconds: workout.durationSeconds)
        return [WorkoutCardMetric(label: "거리", value: distance(workout.distanceMeters, sport: workout.workoutType)),
                WorkoutCardMetric(label: movementLabel(workout.workoutType), value: movement ?? "—"),
                WorkoutCardMetric(label: "총 시간", value: duration(workout.durationSeconds))]
    }
    static func distance(_ meters: Double?, sport: UnifiedWorkoutType? = nil) -> String {
        guard let meters, meters.isFinite, meters >= 0 else { return "—" }
        if sport == .swimming && meters < 1000 { return String(format: "%.0f m", meters) }
        return String(format: "%.2f km", meters / 1000)
    }
    static func metrics(_ item: FeedItem) -> [WorkoutCardMetric] {
        switch item.cardData {
        case .workoutSession(let card):
            return [WorkoutCardMetric(label: "거리", value: card.distanceText),
                    WorkoutCardMetric(label: movementLabel(card.workoutType), value: card.averagePaceText ?? "—"),
                    WorkoutCardMetric(label: "총 시간", value: card.durationText)]
        case .weeklyProgress(let card):
            return [WorkoutCardMetric(label: "운동", value: card.workoutCountText),
                    WorkoutCardMetric(label: "거리", value: card.totalDistanceText),
                    WorkoutCardMetric(label: "총 시간", value: card.totalDurationText)]
        }
    }
    static func region(_ name: String?, hasRoute: Bool) -> String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let known: [String: String] = [
                "seoul": "서울", "seoul special city": "서울", "gyeonggi": "경기도", "gyeonggi-do": "경기도",
                "gimpo-si": "김포시", "gimpo": "김포시", "suji-gu": "수지구", "yongin-si": "용인시",
                "incheon": "인천", "busan": "부산", "daegu": "대구", "daejeon": "대전", "gwangju": "광주",
                "ulsan": "울산", "sejong": "세종", "gangwon": "강원특별자치도", "chungbuk": "충청북도",
                "chungnam": "충청남도", "jeonbuk": "전북특별자치도", "jeonnam": "전라남도",
                "gyeongbuk": "경상북도", "gyeongnam": "경상남도", "jeju": "제주특별자치도"
            ]
            return name.split(separator: ",", omittingEmptySubsequences: false).map { part in
                let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return known[value.lowercased()] ?? value
            }.joined(separator: ", ")
        }
        return hasRoute ? "경로의 지역명 확인 전" : "지역 미입력"
    }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let total = Int(seconds)
        if total >= 3600 { return "\(total / 3600)시간 \((total % 3600) / 60)분" }
        return total >= 60 ? "\(total / 60)분 \(total % 60)초" : "\(total)초"
    }
    static func movementLabel(_ sport: UnifiedWorkoutType) -> String {
        [.cycling, .other].contains(sport) ? "평속" : "페이스"
    }
    static func icon(_ sport: UnifiedWorkoutType) -> String {
        switch sport {
        case .cycling: SOOMIcon.bike
        case .running: SOOMIcon.run
        case .swimming: SOOMIcon.swim
        case .walking, .hiking: "figure.walk"
        case .strength: "dumbbell"
        case .yoga: "figure.mind.and.body"
        case .other: SOOMIcon.activity
        }
    }
}

extension UnifiedWorkout {
    var feedSourceLabel: String {
        switch source {
        case .appleHealthKit: "Apple 건강"
        case .garmin: "Garmin"
        case .googleHealth: "Google Health"
        case .strava: "Strava 파일"
        case .samsungHealth: "Samsung Health"
        case .healthConnect: "Health Connect"
        case .soomLocal: "SOOM 기록"
        case .manual: "직접 입력"
        case .unknown: "가져온 기록"
        }
    }
}

/// Maps a shared post to the same card used for account workout records.
struct FeedWorkoutArticle<Management: View>: View {
    let item: FeedItem
    var workout: UnifiedWorkout? = nil
    var route: WorkoutRoute? = nil
    var achievements: [WorkoutAchievement] = []
    let onOpen: () -> Void
    @ViewBuilder let management: () -> Management
    @EnvironmentObject private var auth: AuthViewModel

    private var sport: UnifiedWorkoutType {
        if let workout { return workout.workoutType }
        if case .workoutSession(let card) = item.cardData { return card.workoutType }
        return .other
    }
    private var title: String { workout?.displayTitle ?? item.recordTitle }
    private var caption: String? { workout?.recordDescription ?? item.caption }
    private var date: Date { FeedDisplayOrder.date(item, localStart: workout?.startDate) }
    private var device: String? { workout.map { $0.deviceName ?? $0.feedSourceLabel } ?? item.deviceName }
    private var displayRoute: WorkoutRoute? { workout == nil ? item.permittedSharedDetail?.route(start: date) : route }
    private var region: String {
        FeedCardFormatting.region(workout?.locationName ?? item.locationHint,
            hasRoute: displayRoute.map { RoutePrivacyMasker().mask(route: $0).coordinates.count > 1 } ?? false)
    }
    private var metrics: [WorkoutCardMetric] {
        if let workout { return FeedCardFormatting.metrics(workout) }
        return FeedCardFormatting.metrics(item)
    }
    var body: some View {
        WorkoutRecordCard(title: title, description: caption, date: date, sport: sport,
            author: item.isLocalDraft ? (auth.session.currentUser?.displayName ?? "나") : (item.authorHandle ?? item.authorName),
            authorID: item.isLocalDraft ? auth.session.currentUser?.id : item.authorId,
            showsAuthorFollow: false,
            showsManagement: workout != nil,
            avatarPath: item.isLocalDraft ? auth.session.currentUser?.avatarPath : item.avatarPath,
            device: device, location: region, metrics: metrics, workoutID: workout?.id, route: displayRoute,
            routePrivacyAlreadyApplied: workout == nil && item.permittedSharedDetail != nil,
            photosAreKnown: !item.isLocalDraft,
            // Legacy route JPEGs cannot prove the current 200m reentry masking.
            // Show only the derived native route, while preserving normal photos.
            imageURL: nil, routePhoto: nil, photos: item.photos,
            achievements: achievements, onOpen: onOpen, management: management)
        .accessibilityIdentifier("feed.workout.article")
    }
}

/// Presentation metadata only: no route coordinates, images or authorization.
struct FeedRoutePlaybackScope: Equatable {
    let visitID: UUID
    let viewerID: UUID
    let accountGeneration: Int
    let safetyRevision: Int
    let returnEpoch: Int
}

@MainActor final class FeedRoutePlaybackHistory {
    struct Key: Hashable {
        let workoutID: UUID
        let geometryFingerprint: Int
        init(route: WorkoutRoute) {
            workoutID = route.workoutId
            // Ignore regenerated sample/route UUIDs. Only the rendered masked
            // geometry and privacy policy affect whether this is a new route.
            var hash = Hasher()
            hash.combine(route.privacyMaskApplied)
            hash.combine(route.privacyMaskRadiusMeters)
            hash.combine(route.coordinates.count)
            for point in route.coordinates {
                hash.combine(point.latitude); hash.combine(point.longitude)
                hash.combine(point.segmentIndex)
            }
            geometryFingerprint = hash.finalize()
        }
    }
    private let maximumCount: Int
    private var scope: FeedRoutePlaybackScope?
    private var entries: [Key: UInt64] = [:]
    private var clock: UInt64 = 0
    var count: Int { entries.count }
    init(maximumCount: Int = 256) { self.maximumCount = max(0, maximumCount) }
    func hasPlayed(_ key: Key, scope: FeedRoutePlaybackScope) -> Bool {
        self.scope == scope && entries[key] != nil
    }
    /// Claim only when the delayed first animation actually starts. Re-entry
    /// after interruption keeps the complete route, including rebuilt lazy rows.
    func claim(_ key: Key, scope: FeedRoutePlaybackScope) -> Bool {
        guard maximumCount > 0 else { return false }
        if self.scope != scope { entries.removeAll(); self.scope = scope }
        guard entries[key] == nil else { return false }
        if entries.count >= maximumCount,
           let oldest = entries.min(by: { $0.value < $1.value })?.key { entries.removeValue(forKey: oldest) }
        clock &+= 1; entries[key] = clock
        return true
    }
    func reset() { entries.removeAll(); scope = nil }
}
private struct FeedRoutePlaybackHistoryKey: EnvironmentKey {
    static let defaultValue: FeedRoutePlaybackHistory? = nil
}
private struct FeedRoutePlaybackScopeKey: EnvironmentKey {
    static let defaultValue: FeedRoutePlaybackScope? = nil
}
extension EnvironmentValues {
    var soomFeedRoutePlaybackHistory: FeedRoutePlaybackHistory? {
        get { self[FeedRoutePlaybackHistoryKey.self] }
        set { self[FeedRoutePlaybackHistoryKey.self] = newValue }
    }
    var soomFeedRoutePlaybackScope: FeedRoutePlaybackScope? {
        get { self[FeedRoutePlaybackScopeKey.self] }
        set { self[FeedRoutePlaybackScopeKey.self] = newValue }
    }
}

struct FeedStaticRouteImage: View {
    let route: WorkoutRoute
    let sport: UnifiedWorkoutType
    var isAlreadyPrivacyMasked = false
    var onOpen: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workoutCardRouteViewport) private var viewport
    @Environment(\.soomFeedRoutePlaybackHistory) private var feedPlaybackHistory
    @Environment(\.soomFeedRoutePlaybackScope) private var feedPlaybackScope
    @State private var playbackKey: FeedRoutePlaybackHistory.Key?
    @State private var playbackVisitCount = 0
    @State private var cachedPreview: WorkoutRoute?
    @State private var sufficientlyVisible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var gate = WorkoutCardRoutePlaybackGate()
    @State private var playbackEpoch = UUID()
    @State private var playbackProgress: Double?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        let previewRoute = cachedPreview ?? (isAlreadyPrivacyMasked ? route : RoutePrivacyMasker().mask(route: route))
        ZStack(alignment: .bottomLeading) {
            if MapboxAccessTokenAvailability.hasUsableToken {
                WorkoutDetailMapView(
                    route: previewRoute,
                    fallbackStyle: StaticRouteFallbackStyle(workoutType: sport),
                    tint: SOOMColor.accent,
                    routeLineWidth: SOOMRouteRenderingStyle.feedLineWidth,
                    feedCardPresentation: true,
                    playbackProgress: playbackProgress
                )
                .allowsHitTesting(false)
            } else {
                WorkoutRecordRoutePreview(route: previewRoute)
                    .allowsHitTesting(false)
            }

            if let onOpen {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
                    .accessibilityLabel("운동 상세 보기")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("workout.card.open.map")
            }


        }
        .onAppear { updatePreview(route); schedulePlayback() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_FEED_ENRICHMENT_QA"] == "1" && feedPlaybackHistory != nil ? "feed.lifecycle.linkedRoute" : "workout.card.routePreview")
        .accessibilityValue(ReviewDemoMode.isActive ? "재생 \(playbackVisitCount)회" : (playbackTask == nil ? "경로 미리보기" : "경로 재생 중"))
        .onChange(of: viewport, initial: true) { _, value in
            gate.updatePresence(value.present, now: Date())
            sufficientlyVisible = value.sufficientlyVisible
            #if DEBUG && targetEnvironment(simulator)
            if Feed68ScrollProbe.enabled, value.isScrolling { Feed68ScrollProbe.routeScrollEvents += 1 }
            #endif
            if value.active && value.sufficientlyVisible && !value.isScrolling { schedulePlayback() } else { stopPlayback() }
        }
        .onChange(of: feedPlaybackScope) { _, _ in
            gate = WorkoutCardRoutePlaybackGate(); stopPlayback(); schedulePlayback()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { stopPlayback() } else { schedulePlayback() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if lowPower { stopPlayback() } else { schedulePlayback() }
        }
        .onDisappear { gate.updatePresence(false, now: Date()); stopPlayback() }
        .onChange(of: route) { _, value in
            updatePreview(value)
            gate = WorkoutCardRoutePlaybackGate(); stopPlayback(); schedulePlayback()
        }
        .onChange(of: isAlreadyPrivacyMasked) { _, masked in
            updatePreview(route)
            gate = WorkoutCardRoutePlaybackGate(); stopPlayback(); schedulePlayback()
        }
    }

    private func updatePreview(_ value: WorkoutRoute) {
        let preview = isAlreadyPrivacyMasked ? value : RoutePrivacyMasker().mask(route: value)
        cachedPreview = preview
        playbackKey = .init(route: preview)
    }
    private var canStartForVisit: Bool {
        guard let history = feedPlaybackHistory else { return true } // Activity preserves its policy.
        guard let scope = feedPlaybackScope, let playbackKey else { return false }
        return !history.hasPlayed(playbackKey, scope: scope)
    }
    private func claimVisit() -> Bool {
        guard let history = feedPlaybackHistory else { return true }
        guard let scope = feedPlaybackScope, let playbackKey else { return false }
        return history.claim(playbackKey, scope: scope)
    }
    private var canAnimate: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if Feed68ScrollProbe.enabled && ProcessInfo.processInfo.environment["SOOM_FEED68_MOTION_OFF"] == "1" { return false }
        #endif
        return WorkoutCardRoutePlaybackGate.isEligible(visible: sufficientlyVisible, active: viewport.active,
            reduceMotion: reduceMotion || viewport.reduceMotion || viewport.isScrolling, lowPower: lowPower, renderer: MapboxAccessTokenAvailability.hasUsableToken,
            route: (cachedPreview ?? (isAlreadyPrivacyMasked ? route : RoutePrivacyMasker().mask(route: route))).coordinates.count > 1)
    }
    private func schedulePlayback() {
        guard canAnimate, gate.canPlay, canStartForVisit, playbackTask == nil else { return }
        let epoch = UUID(); playbackEpoch = epoch
        playbackTask = Task { @MainActor in
            defer { if playbackEpoch == epoch { playbackTask = nil } }
            // Ignore cards passing through the viewport during a quick scroll.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled, playbackEpoch == epoch, canAnimate, gate.canPlay,
                  canStartForVisit, claimVisit() else { return }
            gate.didStart()
            #if DEBUG && targetEnvironment(simulator)
            if Feed61CardLifecycleProbe.isEnabled { Feed61RoutePlaybackProbe.mapReplays += 1 }
            #endif
            playbackVisitCount += 1; playbackProgress = 0
            for step in 1...120 {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard !Task.isCancelled, playbackEpoch == epoch, canAnimate else { return }
                #if DEBUG && targetEnvironment(simulator)
                if Feed68ScrollProbe.enabled {
                    Feed68ScrollProbe.ticks += 1
                    if Feed68ScrollProbe.scrolling { Feed68ScrollProbe.ticksWhileScrolling += 1 }
                }
                #endif
                playbackProgress = Double(step) / 120
            }
            if playbackEpoch == epoch { playbackTask = nil }
        }
    }
    private func stopPlayback() {
        playbackEpoch = UUID()
        playbackTask?.cancel(); playbackTask = nil; playbackProgress = nil
    }
}


/// Hysteresis: crossing the playback threshold is not a new visit. A card must
/// leave the viewport for half a second before returning to earn one replay.
struct WorkoutCardRoutePlaybackGate {
    static func isEligible(visible: Bool, active: Bool, reduceMotion: Bool, lowPower: Bool, renderer: Bool, route: Bool) -> Bool {
        visible && active && !reduceMotion && !lowPower && renderer && route
    }
    private(set) var hasPlayed = false
    private(set) var leftAt: Date?
    var canPlay: Bool { !hasPlayed }
    mutating func updatePresence(_ present: Bool, now: Date) {
        if present {
            if let leftAt, now.timeIntervalSince(leftAt) >= 0.5 { hasPlayed = false }
            leftAt = nil
        } else if leftAt == nil { leftAt = now }
    }
    mutating func didStart() { hasPlayed = true }
}

/// Passed explicitly across the UIKit media pager's independent hosting roots.
/// Visibility is measured on the outer SwiftUI row in the real feed scroll view.
struct WorkoutCardRouteViewport: Equatable {
    var isScrolling = false
    var sufficientlyVisible = false
    var present = false
    var active = false
    var reduceMotion = false
}
private struct WorkoutCardRouteViewportKey: EnvironmentKey {
    static let defaultValue = WorkoutCardRouteViewport()
}
extension EnvironmentValues {
    var workoutCardRouteViewport: WorkoutCardRouteViewport {
        get { self[WorkoutCardRouteViewportKey.self] }
        set { self[WorkoutCardRouteViewportKey.self] = newValue }
    }
}

private struct SOOMFeedIsScrollingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var soomFeedIsScrolling: Bool {
        get { self[SOOMFeedIsScrollingKey.self] }
        set { self[SOOMFeedIsScrollingKey.self] = newValue }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic simulator measurement only. Samples display-link delivery, not GPU FPS.
@MainActor final class Feed71FrameProbe: NSObject {
    static let shared = Feed71FrameProbe()
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var samples = 0, hitches = 0
    private var maximum: Double = 0
    private var elapsed: Double = 0
    var label: String { "frames=\(samples);hitches=\(hitches);worstMs=\(Int(maximum * 1000));sampleMs=\(Int(elapsed * 1000))" }
    func setScrolling(_ active: Bool) {
        guard Feed68ScrollProbe.enabled else { return }
        if active {
            guard link == nil else { return }
            last = nil
            let display = CADisplayLink(target: self, selector: #selector(tick(_:)))
            display.add(to: .main, forMode: .common); link = display
        } else {
            link?.invalidate(); link = nil; last = nil
        }
    }
    @objc private func tick(_ display: CADisplayLink) {
        defer { last = display.timestamp }
        guard let last else { return }
        let delta = display.timestamp - last
        guard delta > 0 else { return }
        samples += 1; elapsed += delta; maximum = max(maximum, delta)
        let budget = max(1.0 / 120, display.targetTimestamp - display.timestamp)
        if delta > budget * 1.5 { hitches += 1 }
    }
}

@MainActor enum Feed68ScrollProbe {
    static var enabled: Bool { ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_FEED68_SCROLL_QA"] == "1" }
    static var scrolling = false
    static var scrollEvents = 0
    static var routeScrollEvents = 0
    static var ticks = 0
    static var ticksWhileScrolling = 0
    static var label: String { "scroll=\(scrollEvents);route=\(routeScrollEvents);ticks=\(ticks);illegal=\(ticksWhileScrolling);" + Feed71FrameProbe.shared.label }
}
#endif
