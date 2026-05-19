import SwiftUI

struct RecoveryTimelineCard: View {
    let entries: [RecoveryTimelineEntry]

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    RecoveryTimelineRow(
                        entry: entry,
                        previousScore: previousScore(for: index),
                        isLast: index == min(entries.count, 5) - 1
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("최근 회복 흐름")
    }

    private func previousScore(for index: Int) -> Int? {
        let nextIndex = index + 1
        guard entries.indices.contains(nextIndex) else {
            return nil
        }

        return entries[nextIndex].recoveryScore
    }
}

private struct RecoveryTimelineRow: View {
    let entry: RecoveryTimelineEntry
    let previousScore: Int?
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
            timelineMarker

            VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                    Label(trendText, systemImage: trendIcon)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(trendTint)
                        .labelStyle(.titleAndIcon)
                }

                HStack(alignment: .firstTextBaseline, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text("\(entry.clampedScore)")
                        .font(SOOMFont.displayMedium(22, relativeTo: .title3))
                        .foregroundStyle(SOOMColor.ink)

                    Text(entry.status)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }

                if let shortExplanation = entry.shortExplanation, !shortExplanation.isEmpty {
                    Text(shortExplanation)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let summary = supportingSummary {
                    Text(summary)
                        .font(SOOMFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.bottom, isLast ? 0 : SOOMLayout.SectionHeader.spacing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.dateFormatter.string(from: entry.date))
        .accessibilityValue(accessibilityValue)
    }

    private var timelineMarker: some View {
        VStack(spacing: SOOMLayout.SectionHeader.spacing) {
            Circle()
                .fill(trendTint)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(trendTint.opacity(0.18), lineWidth: 6)
                )

            if !isLast {
                Rectangle()
                    .fill(SOOMColor.line)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: SOOMLayout.RecoveryAI.iconFrame)
    }

    private var supportingSummary: String? {
        let values = [entry.checkInSummary, entry.recommendationSummary]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else {
            return nil
        }

        return values.joined(separator: " · ")
    }

    private var trendDelta: Int {
        guard let previousScore else {
            return 0
        }

        return entry.clampedScore - previousScore
    }

    private var trendText: String {
        if trendDelta > 0 {
            return "+\(trendDelta)"
        }

        if trendDelta < 0 {
            return "\(trendDelta)"
        }

        return "유지"
    }

    private var trendIcon: String {
        if trendDelta > 0 {
            return SOOMIcon.trendUp
        }

        if trendDelta < 0 {
            return SOOMIcon.trendDown
        }

        return SOOMIcon.trendFlat
    }

    private var trendTint: Color {
        if trendDelta > 0 {
            return SOOMColor.recovery
        }

        if trendDelta < 0 {
            return SOOMColor.warning
        }

        return SOOMColor.secondaryInk
    }

    private var accessibilityValue: String {
        var parts = ["회복 점수 \(entry.clampedScore)", entry.status, trendText]

        if let shortExplanation = entry.shortExplanation {
            parts.append(shortExplanation)
        }

        if let supportingSummary {
            parts.append(supportingSummary)
        }

        return parts.joined(separator: ", ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()
}

#Preview("RecoveryTimelineCard") {
    SOOMScreen {
        RecoveryTimelineCard(entries: RecoveryTimelineBuilder().buildMockTimeline(endingAt: .mockToday))
    }
    .preferredColorScheme(.light)
}
