import SwiftUI
import UIKit

struct FeedView: View {
    let items: [FeedItem]
    let weeklySnapshot: FeedWeeklySnapshot?
    let recoveryInsight: FeedRecoveryInsight?
    let streak: FeedStreakSnapshot
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var visibleItems: [FeedItem]
    @State private var isSignInSheetPresented = false

    init(
        items: [FeedItem] = FeedMockData.items,
        weeklySnapshot: FeedWeeklySnapshot? = nil,
        recoveryInsight: FeedRecoveryInsight? = nil,
        streak: FeedStreakSnapshot = FeedStreakSnapshot(weekCount: 0, activityCount: 0)
    ) {
        let sortedItems = FeedView.prioritizedItems(items)
        self.items = sortedItems
        self.weeklySnapshot = weeklySnapshot
        self.recoveryInsight = recoveryInsight
        self.streak = streak
        _visibleItems = State(initialValue: sortedItems)
    }

    var body: some View {
        SOOMScreen {
            topHeader

            if !authViewModel.session.isSignedIn {
                FeedSignInBanner {
                    isSignInSheetPresented = true
                }
            }

            if let weeklySnapshot {
                FeedWeeklySnapshotCarousel(snapshot: weeklySnapshot)
            }

            if streak.weekCount > 0 {
                FeedStreakCard(streak: streak)
            }

            if let recoveryInsight {
                NavigationLink {
                    RecoveryViewContainer()
                } label: {
                    FeedRecoveryInsightCard(insight: recoveryInsight)
                }
                .buttonStyle(.plain)
                .accessibilityHint("회복 상세 화면으로 이동합니다.")
            }

            if visibleItems.isEmpty {
                emptyState
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(friendWorkoutItems.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            feedDestination(for: item)
                        } label: {
                            FeedItemCard(item: item)
                        }
                        .buttonStyle(FeedCardButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            SOOMHaptics.selection()
                        })
                        .feedCardReveal(
                            index: index,
                            isVisible: hasAppeared,
                            reduceMotion: reduceMotion
                        )
                        .accessibilityHint("자세한 운동 흐름으로 이동합니다.")
                    }

                    aiDiscoveryCard
                        .feedCardReveal(
                            index: friendWorkoutItems.count,
                            isVisible: hasAppeared,
                            reduceMotion: reduceMotion
                        )

                    ForEach(Array(supportingItems.enumerated()), id: \.element.id) { offset, item in
                        NavigationLink {
                            feedDestination(for: item)
                        } label: {
                            FeedItemCard(item: item)
                        }
                        .buttonStyle(FeedCardButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            SOOMHaptics.selection()
                        })
                        .feedCardReveal(
                            index: friendWorkoutItems.count + offset + 1,
                            isVisible: hasAppeared,
                            reduceMotion: reduceMotion
                        )
                        .accessibilityHint("자세한 운동 흐름으로 이동합니다.")
                    }
                }
                .padding(.horizontal, SOOMLayout.Feed.contentBleed)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            hasAppeared = true
        }
        .onChange(of: items) { _, newItems in
            visibleItems = Self.prioritizedItems(newItems)
        }
        .onChange(of: authViewModel.session.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                isSignInSheetPresented = false
            }
        }
        .sheet(isPresented: $isSignInSheetPresented) {
            signInSheet
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    private var signInSheet: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.lg) {
            AppleAuthCard(authViewModel: authViewModel)
            Spacer()
        }
        .padding(SOOMLayout.Spacing.xl)
    }

    private var topHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(SOOMColor.ink)

                Text("S")
                    .font(SOOMFont.displayMedium(16, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.white)
            }
            .frame(width: 38, height: 38)
            .accessibilityLabel("내 프로필")

            VStack(alignment: .leading, spacing: 1) {
                Text("SOOM")
                    .font(SOOMFont.displayMedium(24, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text("운동 피드")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer()

            headerIconButton(icon: "magnifyingglass", label: "검색")
            headerIconButton(icon: "bell", label: "알림")
        }
        .padding(.bottom, -4)
    }

    private func headerIconButton(icon: String, label: String) -> some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: SOOMFont.Size.headline, weight: .semibold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: 38, height: 38)
                .background(SOOMColor.surfaceMuted)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var friendWorkoutItems: [FeedItem] {
        let workouts = visibleItems.filter {
            if case .workoutSession = $0.cardData {
                return true
            }
            return false
        }
        return Array(workouts.prefix(2))
    }

    private var supportingItems: [FeedItem] {
        visibleItems.filter { item in
            friendWorkoutItems.contains(where: { $0.id == item.id }) == false
        }
    }

    private var aiDiscoveryCard: some View {
        HStack(spacing: 10) {
            Image(systemName: SOOMIcon.sparkles)
                .font(.system(size: SOOMFont.Size.subheadline, weight: .semibold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 28, height: 28)
                .background(SOOMColor.accentMuted)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("발견")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text("오늘은 가볍게 다시 탈 만한 코스가 많이 보입니다.")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()
        }
        .padding(.horizontal, SOOMLayout.Spacing.lg)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceAmbient.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func feedDestination(for item: FeedItem) -> some View {
        FeedItemDetailDestination(item: item)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            SOOMFirstJourneyCard(
                prompt: .feed,
                actions: [
                    SOOMFirstJourneyAction(
                        title: "첫 운동 가져오기",
                        subtitle: "Health 앱의 최근 움직임을 SOOM의 이야기로 이어봅니다.",
                        iconName: SOOMIcon.sync
                    ),
                    SOOMFirstJourneyAction(
                        title: "추천 코스 보기",
                        subtitle: "오늘은 짧고 편하게 시작할 수 있는 route를 먼저 둡니다.",
                        iconName: SOOMIcon.map
                    ),
                    SOOMFirstJourneyAction(
                        title: "천천히 맞는 클럽 찾기",
                        subtitle: "속도보다 분위기가 맞는 사람들을 만나는 입구입니다.",
                        iconName: SOOMIcon.clubs
                    )
                ],
                footer: "피드는 기록이 쌓일수록 점수판보다 하루의 흐름처럼 읽히게 됩니다."
            )

            FeedFirstJourneyStoryPreview()
        }
        .accessibilityElement(children: .contain)
    }

    private static func prioritizedItems(_ items: [FeedItem]) -> [FeedItem] {
        items.sorted { lhs, rhs in
            let lhsPriority = feedPriority(for: lhs)
            let rhsPriority = feedPriority(for: rhs)

            if lhsPriority == rhsPriority {
                return lhs.createdAt > rhs.createdAt
            }

            return lhsPriority < rhsPriority
        }
    }

    private static func feedPriority(for item: FeedItem) -> Int {
        if case .workoutSession = item.cardData {
            return 0
        }

        if item.clubContext != nil {
            return 1
        }

        return 3
    }
}

private struct FeedCoachAccessBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SOOMColor.accentMuted)

                Image(systemName: SOOMIcon.sparkles)
                    .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                    .foregroundStyle(SOOMColor.accent)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("가볍게 확인")
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                    .lineLimit(1)

                Text("회복 코치는 오른쪽 아래에서 필요할 때 열 수 있어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: SOOMIcon.close)
                    .font(.system(size: SOOMFont.Size.caption, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("회복 코치 안내 닫기")
        }
        .padding(.horizontal, SOOMLayout.Spacing.lg)
        .padding(.vertical, SOOMLayout.Spacing.md)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: SOOMColor.black.opacity(0.03), radius: 10, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("가볍게 확인")
        .accessibilityValue("회복 코치는 오른쪽 아래에서 필요할 때 열 수 있어요.")
    }
}

private struct FeedFirstJourneyStoryPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.bike.opacity(0.13),
                                SOOMColor.recovery.opacity(0.08),
                                SOOMColor.surfaceMuted
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 168)
                    .overlay {
                        FirstJourneyRouteLine()
                            .stroke(SOOMColor.bike.opacity(0.64), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 38)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text("예시 route")
                            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.tertiaryInk)
                            .padding(.horizontal, SOOMLayout.Spacing.sm)
                            .padding(.vertical, SOOMLayout.Spacing.sm)
                            .background(SOOMColor.surface.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(SOOMLayout.Spacing.md)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("첫 움직임이 기록되면")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("오늘의 길과 호흡이 한 장의 이야기로 남아요.")
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SOOMLayout.Spacing.lg)
            }

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Label("강변 35분", systemImage: SOOMIcon.map)
                Label("무리 없는 시작", systemImage: SOOMIcon.recovery)
            }
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Card.padding)
            .padding(.vertical, SOOMLayout.Spacing.md)
        }
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.56), lineWidth: SOOMLayout.Card.borderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("첫 피드 예시")
        .accessibilityValue("첫 움직임이 기록되면 오늘의 길과 호흡이 한 장의 이야기로 남아요.")
    }
}

private struct FirstJourneyRouteLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.26))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.midY - rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.midY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY - rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY + rect.height * 0.06),
            control1: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.midY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.midY + rect.height * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY - rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.midY - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.midY - rect.height * 0.22)
        )
        return path
    }
}

private struct FeedSurfaceButton: View {
    let kind: String
    let icon: String
    let title: String
    let subtitle: String
    let footer: String
    let tint: Color

    var body: some View {
        Button {
            SOOMHaptics.selection()
        } label: {
            FeedSurfaceCard(
                kind: kind,
                icon: icon,
                title: title,
                subtitle: subtitle,
                footer: footer,
                tint: tint
            )
        }
        .buttonStyle(FeedCardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct FeedSurfaceCard: View {
    let kind: String
    let icon: String
    let title: String
    let subtitle: String
    let footer: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind)
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(tint.opacity(0.52))
                    .padding(.horizontal, SOOMLayout.Spacing.sm)
                    .padding(.vertical, SOOMLayout.Spacing.xs)
                    .background(tint.opacity(0.035))
                    .clipShape(Capsule())

                Spacer(minLength: 6)

                Image(systemName: icon)
                    .font(.system(size: SOOMFont.Size.subheadline, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.42))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk.opacity(0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(footer)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk.opacity(0.70))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: SOOMLayout.Feed.surfaceCardMinHeight, alignment: .topLeading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.surfaceAmbient.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous)
                .stroke(SOOMColor.line.opacity(0.07), lineWidth: SOOMLayout.Card.borderWidth)
        }
    }
}

private struct FeedCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : SOOMMotion.cardPress, value: configuration.isPressed)
    }
}

#Preview("FeedView") {
    NavigationStack {
        FeedView()
    }
    .preferredColorScheme(.light)
}

private extension View {
    func feedCardReveal(index: Int, isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.hidden)
            .offset(y: reduceMotion || isVisible ? 0 : SOOMMotion.Offset.cardRevealY)
            .animation(
                reduceMotion
                    ? nil
                    : SOOMMotion.normalEaseOut.delay(Double(index) * 0.025),
                value: isVisible
            )
    }
}
