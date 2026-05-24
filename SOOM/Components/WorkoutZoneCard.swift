import SwiftUI

struct WorkoutZoneCard: View {
    let summary: WorkoutZoneSummary
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                if summary.isAvailable {
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 6) {
                        ForEach(summary.zones) { zone in
                            zoneRow(zone)
                        }
                    }
                } else {
                    unavailableView
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.type.displayTitle)
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: summary.type.iconName)
                .font(.system(size: SOOMLayout.IconButton.iconSize, weight: .semibold))
                .foregroundStyle(summary.type.accentColor(tint: tint))
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(summary.type.accentColor(tint: tint).opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.type.displayTitle)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    dataSourceBadge

                    if summary.isPersonalized {
                        personalizedBadge
                    }

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                    Text(dominantText)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(summary.isAvailable ? summary.type.accentColor(tint: tint) : SOOMColor.tertiaryInk)
                }

                if let insight = summary.insightText {
                    Text(insight)
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dataSourceBadge: some View {
        Text(summary.dataSource.label)
            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(dataSourceTint)
            .padding(.horizontal, SOOMLayout.Metrics.actionTextSpacing + 2)
            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing - 1)
            .background(dataSourceTint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            .accessibilityLabel(summary.dataSource.label)
            .accessibilityValue(summary.dataSource.description)
    }

    private var personalizedBadge: some View {
        Text(summary.baselineDescription ?? "개인 기준")
            .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(summary.type.accentColor(tint: tint))
            .padding(.horizontal, SOOMLayout.Metrics.actionTextSpacing + 2)
            .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing - 1)
            .background(summary.type.accentColor(tint: tint).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            .accessibilityLabel(summary.baselineDescription ?? "개인 기준")
    }

    private var unavailableView: some View {
        Text(summary.type.unavailableCopy)
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SOOMLayout.Metrics.actionTextSpacing)
            .background(SOOMColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

    private func zoneRow(_ zone: WorkoutZone) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Zone \(zone.zoneIndex)")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                if let range = zone.rangeDescription {
                    Text(range)
                        .font(SOOMFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                Text("\(durationText(zone.durationSeconds)) · \(percentageText(zone.percentage))")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(zone.id == summary.dominantZone?.id ? summary.type.accentColor(tint: tint) : SOOMColor.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SOOMColor.line.opacity(0.55))
                    Capsule()
                        .fill(summary.type.accentColor(tint: tint).opacity(zone.id == summary.dominantZone?.id ? 0.9 : 0.42))
                        .frame(width: max(4, proxy.size.width * zone.percentage / 100))
                }
            }
            .frame(height: 7)
            .accessibilityHidden(true)
        }
    }

    private var dominantText: String {
        guard let zone = summary.dominantZone else { return "데이터 없음" }
        return "주요 Zone \(zone.zoneIndex)"
    }

    private var dataSourceTint: Color {
        switch summary.dataSource.sourceType {
        case .healthKitStream:
            return summary.type.accentColor(tint: tint)
        case .fallbackEstimate, .manualFuture:
            return SOOMColor.secondaryInk
        case .unavailable:
            return SOOMColor.tertiaryInk
        }
    }

    private var accessibilityValue: String {
        guard summary.isAvailable else {
            return [summary.dataSource.description, summary.baselineDescription, summary.insightText ?? summary.type.unavailableCopy]
                .compactMap { $0 }
                .joined(separator: ". ")
        }

        let zones = summary.zones.map { zone in
            "Zone \(zone.zoneIndex) \(durationText(zone.durationSeconds)), \(percentageText(zone.percentage))"
        }.joined(separator: ". ")
        return [summary.dataSource.description, summary.baselineDescription, summary.insightText, zones].compactMap { $0 }.joined(separator: ". ")
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }
        return "\(max(1, minutes))분"
    }

    private func percentageText(_ percentage: Double) -> String {
        "\(Int(percentage.rounded()))%"
    }
}

extension WorkoutZoneType {
    var displayTitle: String {
        switch self {
        case .heartRate:
            return "심박존"
        case .cadence:
            return "케이던스존"
        case .power:
            return "파워존"
        }
    }

    var iconName: String {
        switch self {
        case .heartRate:
            return SOOMIcon.heart
        case .cadence:
            return SOOMIcon.waveform
        case .power:
            return SOOMIcon.bolt
        }
    }

    var unavailableCopy: String {
        switch self {
        case .heartRate:
            return "심박 데이터를 아직 찾지 못했어요. 기록이 있으면 강도 흐름을 보여드릴게요."
        case .cadence:
            return "케이던스 데이터가 없는 운동이에요. 센서 기록이 있으면 리듬 변화를 보여드릴게요."
        case .power:
            return "파워 데이터를 아직 찾지 못했어요. 파워 기록과 FTP가 준비되면 존 흐름을 보여드릴게요."
        }
    }

    func accentColor(tint: Color) -> Color {
        switch self {
        case .heartRate:
            return SOOMColor.run
        case .cadence:
            return tint
        case .power:
            return SOOMColor.bike
        }
    }
}

#Preview("WorkoutZoneCard") {
    let summary = WorkoutZoneBuilder().buildSummary(
        type: .heartRate,
        durations: [
            WorkoutZoneDurationInput(zoneIndex: 1, durationSeconds: 420, rangeDescription: "회복"),
            WorkoutZoneDurationInput(zoneIndex: 2, durationSeconds: 1_560, rangeDescription: "유산소"),
            WorkoutZoneDurationInput(zoneIndex: 3, durationSeconds: 720, rangeDescription: "템포")
        ]
    )

    SOOMScreen {
        WorkoutZoneCard(summary: summary, tint: SOOMColor.run)
    }
}
