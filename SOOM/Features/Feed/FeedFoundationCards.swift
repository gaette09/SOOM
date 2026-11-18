import SwiftUI

struct FeedWeeklySnapshotCarousel: View {
    let snapshot: FeedWeeklySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("이번 주 운동")
                        .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                    Text(snapshot.progress.trendType.title)
                        .font(SOOMFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    metric("거리", value: String(format: "%.1f", snapshot.progress.totalDistanceKm), unit: "km")
                    metric("시간", value: durationText, unit: nil)
                    metric("운동", value: "\(snapshot.progress.workoutCount)", unit: "회")
                }

                Divider().overlay(SOOMColor.line)

                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.sportSummary)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                    Text(snapshot.progress.averagePaceOrSpeedText)
                        .font(SOOMFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                    Text(snapshot.progress.motivationText)
                        .font(SOOMFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("이번 주 운동 요약")
        .accessibilityIdentifier("today.weeklyWorkoutCard")
    }

    private func metric(_ title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(SOOMFont.displayMedium(28, relativeTo: .title))
                    .foregroundStyle(SOOMColor.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if let unit {
                    Text(unit)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value + (unit.map { " " + $0 } ?? ""))
    }

    private var durationText: String {
        let minutes = snapshot.progress.totalDurationMinutes
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(minutes)분"
    }
}

/// Strava's real "Weekly Streak" rule (WeeklyStreakCalculator.swift): at least 1 activity
/// per calendar week keeps it alive. Hidden entirely at weekCount == 0 (FeedView.swift) so a
/// broken/reset streak doesn't read as a discouraging "0" card.
struct FeedStreakCard: View {
    let streak: FeedStreakSnapshot

    var body: some View {
        SOOMCard(depth: .ambient) {
            HStack(spacing: 12) {
                Image(soom: "flame.fill")
                    .font(.system(size: SOOMFont.Size.headline, weight: .bold))
                    .foregroundStyle(SOOMColor.accent)
                    .frame(width: 40, height: 40)
                    .background(SOOMColor.accentSurface)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Streak")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("\(streak.weekCount)주 연속")
                        .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Streak Activities")
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text("\(streak.activityCount)회")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("주간 스트릭")
        .accessibilityValue("\(streak.weekCount)주 연속, 활동 \(streak.activityCount)회")
    }
}

struct FeedRecoveryInsightCard: View {
    let insight: FeedRecoveryInsight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SOOMCard(depth: .primary) {
            VStack(alignment: .leading, spacing: 20) {
                Text("회복 점수")
                    .font(SOOMFont.body(16, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
                layout {
                    if let score = insight.score {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(score)")
                                .font(SOOMFont.display(60, relativeTo: .largeTitle))
                                .foregroundStyle(SOOMColor.ink)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text("점")
                                .font(SOOMFont.body(14, relativeTo: .subheadline))
                                .foregroundStyle(SOOMColor.secondaryInk)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(insight.status)
                            .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                            .foregroundStyle(SOOMColor.ink)
                        Text(insight.score == nil ? "운동 기록이 쌓이면 점수를 확인할 수 있어요." : "최근 운동을 바탕으로 한 회복 추정")
                            .font(SOOMFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Text(insight.recommendation)
                    .font(SOOMFont.body(15, relativeTo: .body))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let coachMessage = insight.coachMessage {
                    Divider().overlay(SOOMColor.line)
                    Text(coachMessage)
                        .font(SOOMFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 점수")
        .accessibilityValue(insight.accessibilityValue)
        .accessibilityIdentifier("today.recoveryScoreCard")
    }
}

/// Shown only when signed out. Feed silently falls back to mock content and
/// local-only share drafts when there's no Supabase session — this makes
/// that state visible and actionable instead of leaving it unexplained.
struct FeedSignInBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SOOMCard(depth: .ambient) {
                SOOMActionRow(
                    icon: "person.crop.circle.badge.plus",
                    title: "로그인하고 다른 사람의 활동도 보기",
                    subtitle: "지금은 로그인 없이 내 기록만 이 기기에 저장돼요.",
                    tint: SOOMColor.accent
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("로그인 화면으로 이동합니다.")
    }
}
