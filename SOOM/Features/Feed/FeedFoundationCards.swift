import SwiftUI

struct FeedWeeklySnapshotCarousel: View {
    let snapshot: FeedWeeklySnapshot

    var body: some View {
        TabView {
            summaryCard
            sportCard
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 174)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("이번 주 운동 요약 카드")
    }

    private var summaryCard: some View {
        SOOMCard(depth: .primary) {
            Text("이번 주 운동")
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
            Text(snapshot.progress.trendType.title)
                .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                .foregroundStyle(SOOMColor.ink)
            HStack(spacing: 10) {
                metric("거리", String(format: "%.1f km", snapshot.progress.totalDistanceKm))
                metric("시간", durationText)
                metric("운동", "\(snapshot.progress.workoutCount)회")
            }
        }
    }

    private var sportCard: some View {
        SOOMCard(depth: .ambient) {
            Label("운동 종목", systemImage: SOOMIcon.activity)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.accent)
            Text(snapshot.sportSummary)
                .font(SOOMFont.displayMedium(20, relativeTo: .title3))
                .foregroundStyle(SOOMColor.ink)
            Text(snapshot.progress.averagePaceOrSpeedText)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(snapshot.progress.motivationText)
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        SOOMMetricPill(title, value, tint: SOOMColor.accent)
    }

    private var durationText: String {
        let minutes = snapshot.progress.totalDurationMinutes
        return minutes >= 60 ? "\(minutes / 60)시간 \(minutes % 60)분" : "\(minutes)분"
    }
}

struct FeedRecoveryInsightCard: View {
    let insight: FeedRecoveryInsight

    var body: some View {
        SOOMCard(depth: .ambient) {
            HStack(alignment: .top, spacing: 12) {
                SOOMMetricRing(score: insight.score, title: "Recovery", tint: SOOMColor.recovery)
                    .frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recovery Insight")
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.recovery)
                    Text(insight.status)
                        .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                    Text(insight.recommendation)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(2)
                }
            }
            if let coachMessage = insight.coachMessage {
                Label(coachMessage, systemImage: SOOMIcon.sparkles)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.accentInk)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recovery Insight")
        .accessibilityValue("\(insight.score)점, \(insight.status). \(insight.recommendation)")
    }
}
