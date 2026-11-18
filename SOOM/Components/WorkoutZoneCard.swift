import SwiftUI

struct WorkoutZoneCard: View {
    let summary: WorkoutZoneSummary
    let tint: Color
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var statisticsWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 48

    @ViewBuilder var body: some View {
        if summary.type == .heartRate {
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.bottom, 12)
                Text("심박수 훈련 구간").font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    .accessibilityHint([summary.baselineDescription, summary.insightText].compactMap { $0 }.joined(separator: ". "))
                    .padding(.bottom, 6)
                ForEach(1...5, id: \.self) { index in
                    let zone = summary.zones.first { $0.zoneIndex == index }
                    let fraction = (zone?.percentage ?? 0) / 100
                    WorkoutCompactMeasuredBar(fraction: fraction, tint: WorkoutDetailPalette.zone(index),
                        labelWidth: 24, statisticsWidth: 76, revealID: "providerZones.heartRate.\(index)", baseHeight: 28) {
                        Text("\(index)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(fraction >= 0.12 ? Color.white : SOOMColor.ink)
                    } values: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(zone.map { WorkoutSplitDisplay.duration($0.durationSeconds) } ?? "기록 없음").fontWeight(.semibold)
                            Text(zone.map { percentageText($0.percentage) } ?? "—").foregroundStyle(SOOMColor.secondaryInk)
                        }.font(.caption.monospacedDigit())
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Zone \(index), " + (zone.map { durationText($0.durationSeconds) + ", " + percentageText($0.percentage) } ?? "기록 없음"))
                }
                if !summary.isAvailable { unavailableView }
            }
        } else { legacyCard }
    }
    private var legacyCard: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                header

                if summary.type == .heartRate {
                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing + 6) {
                        ForEach(1...5, id: \.self) { index in
                            if let zone = summary.zones.first(where: { $0.zoneIndex == index }) { zoneRow(zone) }
                            else { HStack { Text("Zone \(index)"); Spacer(); Text("기록 없음 · —") }.font(.caption).foregroundStyle(SOOMColor.secondaryInk) }
                        }
                    }
                    if !summary.isAvailable { unavailableView }
                } else if summary.isAvailable {
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
            Image(soom: summary.type.iconName)
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
        VStack(alignment: .leading, spacing: 4) {
            WorkoutTrailingValueBar(label: "Z\(zone.zoneIndex)", fraction: zone.percentage / 100,
                tint: summary.type == .heartRate ? WorkoutDetailPalette.zone(zone.zoneIndex) : summary.type.accentColor(tint: tint),
                statisticsWidth: statisticsWidth, labelWidth: labelWidth, rowHeight: rowHeight,
                revealID: "providerZones.\(summary.type).\(zone.zoneIndex)") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(durationText(zone.durationSeconds)).fontWeight(.semibold)
                    Text(percentageText(zone.percentage)).foregroundStyle(SOOMColor.secondaryInk)
                }.font(.caption.monospacedDigit())
            }
            if let range = zone.rangeDescription {
                Text(range).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
            }
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
        guard seconds >= 60 else { return "\(Int(max(0, seconds).rounded()))초" }
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
