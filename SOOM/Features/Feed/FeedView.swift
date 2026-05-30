import SwiftUI
import UIKit

struct FeedView: View {
    let items: [FeedItem]
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var isCoachBannerHidden = false

    init(items: [FeedItem] = FeedMockData.items) {
        self.items = items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        SOOMScreen {
            if !isCoachBannerHidden {
                FeedCoachAccessBanner {
                    withAnimation(reduceMotion ? nil : SOOMMotion.quickEaseOut) {
                        isCoachBannerHidden = true
                    }
                }
            }

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: SOOMLayout.Feed.cardSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                }
                .padding(.horizontal, SOOMLayout.Feed.contentBleed)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            hasAppeared = true
        }
    }

    private var feedSupportSection: some View {
        // Feed v1 keeps recommendation/support surfaces out of the main feed.
        // These surfaces can move to Record, Activity, or Club in a later pass.
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
            SOOMSectionHeader("가볍게 이어가기", caption: "피드를 읽은 뒤 조용히 이어갈 수 있는 route와 클럽입니다.")

            recommendationGrid
                .padding(.horizontal, SOOMLayout.Feed.quietSurfaceBleed)

            feedPromptRow
                .padding(.horizontal, SOOMLayout.Feed.quietSurfaceBleed)
        }
        .padding(.top, 14)
        .opacity(0.76)
    }

    private var feedPromptRow: some View {
        HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
            Image(systemName: SOOMIcon.sparkles)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SOOMColor.recovery.opacity(0.64))
                .frame(width: 32, height: 32)
                .background(SOOMColor.recovery.opacity(0.06))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("가볍게 확인")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text("회복 코치는 아래에서 필요할 때만 열 수 있어요.")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk.opacity(0.78))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.surfaceAmbient.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var recommendationGrid: some View {
        VStack(spacing: SOOMLayout.Metrics.gridSpacing) {
            HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                FeedSurfaceButton(
                    kind: "루트",
                    icon: SOOMIcon.map,
                    title: "오늘은 짧고 편하게",
                    subtitle: "회복 흐름에 맞는 강변 코스",
                    footer: "한강 45분",
                    tint: SOOMColor.bike
                )

                FeedSurfaceButton(
                    kind: "챌린지",
                    icon: SOOMIcon.medal,
                    title: "한 번 더 움직일 자리",
                    subtitle: "이번 주 루틴을 조용히 이어가기",
                    footer: "2 / 3 완료",
                    tint: SOOMColor.warning
                )
            }

            HStack(spacing: SOOMLayout.Metrics.gridSpacing) {
                FeedSurfaceButton(
                    kind: "클럽",
                    icon: SOOMIcon.clubs,
                    title: "오늘도 천천히 같이",
                    subtitle: "처음 오는 사람도 편한 토요 그룹런",
                    footer: "12명 준비 중",
                    tint: SOOMColor.run
                )

                FeedSurfaceButton(
                    kind: "리듬",
                    icon: SOOMIcon.trendFlat,
                    title: "페이스보다 호흡",
                    subtitle: "비슷한 회복 흐름의 사람들이 많아요",
                    footer: "오늘의 조용한 무드",
                    tint: SOOMColor.green
                )
            }
        }
    }

    @ViewBuilder
    private func feedDestination(for item: FeedItem) -> some View {
        switch item.cardData {
        case .workoutSession:
            if let workout = linkedWorkout(for: item) {
                WorkoutDetailView(workout: workout, comparisonWorkouts: dashboardViewModel.workouts)
            } else {
                AnalysisViewContainer()
            }
        case .weeklyProgress:
            AnalysisViewContainer()
        }
    }

    private func linkedWorkout(for item: FeedItem) -> Workout? {
        guard case .workoutSession(let card) = item.cardData else {
            return nil
        }

        return dashboardViewModel.workouts.first { workout in
            workout.sport.feedWorkoutType == card.workoutType
        }
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
}

private struct FeedCoachAccessBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SOOMColor.recovery.opacity(0.16))

                Image(systemName: SOOMIcon.sparkles)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SOOMColor.recovery)
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(width: 32, height: 32)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("회복 코치 안내 닫기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(SOOMColor.surface.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(12)
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
                .padding(14)
            }

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Label("강변 35분", systemImage: SOOMIcon.map)
                Label("무리 없는 시작", systemImage: SOOMIcon.recovery)
            }
            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.secondaryInk)
            .padding(.horizontal, SOOMLayout.Card.padding)
            .padding(.vertical, 12)
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.035))
                    .clipShape(Capsule())

                Spacer(minLength: 6)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
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

private extension WorkoutSport {
    var feedWorkoutType: UnifiedWorkoutType {
        switch self {
        case .swim:
            return .swimming
        case .bike:
            return .cycling
        case .run:
            return .running
        case .brick:
            return .other
        }
    }
}

#Preview("FeedView") {
    NavigationStack {
        FeedView()
            .environmentObject(DashboardViewModel(harness: MockWorkoutHarness()))
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
