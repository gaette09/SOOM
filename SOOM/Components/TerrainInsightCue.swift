import SwiftUI

struct TerrainInsightCue: View {
    let insight: TerrainInsight
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Image(systemName: iconName)
                        .font(.system(size: SOOMLayout.IconButton.iconSize - 2, weight: .semibold))
                        .foregroundStyle(toneTint)
                        .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                        .background(toneTint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.Metrics.rowTextSpacing) {
                        Text("지형 맥락")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(toneTint)

                        Text(titleText)
                            .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)
                    }

                    Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)
                }

                Text(insight.interpretation)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("지형 맥락")
        .accessibilityValue("\(titleText). \(insight.interpretation)")
    }

    private var titleText: String {
        if let difficulty = insight.terrainType.difficulty {
            return "\(insight.terrainDescription) · \(difficultyText(difficulty))"
        }
        return insight.terrainDescription
    }

    private var toneTint: Color {
        switch insight.terrainType.difficulty {
        case .light:
            return SOOMColor.secondaryInk
        case .moderate:
            return tint
        case .challenging:
            return SOOMColor.orange
        case nil:
            return SOOMColor.tertiaryInk
        }
    }

    private var iconName: String {
        switch insight.terrainType.terrainType {
        case .flat:
            return SOOMIcon.trendFlat
        case .rolling, .mixed:
            return SOOMIcon.waveform
        case .steadyClimb, .longClimb, .trail:
            return SOOMIcon.trendUp
        case .urbanStopGo:
            return SOOMIcon.map
        case .insufficientData:
            return SOOMIcon.checkCircle
        }
    }

    private func difficultyText(_ difficulty: TerrainType.Difficulty) -> String {
        switch difficulty {
        case .light:
            return "가벼운 난이도"
        case .moderate:
            return "중간 난이도"
        case .challenging:
            return "도전적인 흐름"
        }
    }
}

#Preview("TerrainInsightCue") {
    let input = WorkoutGrowthInput(
        id: UUID(),
        source: .soomLocal,
        workoutType: .cycling,
        startDate: Date(),
        durationMinutes: 90,
        distanceKm: 38,
        averagePaceText: nil,
        averageSpeedKmh: 24,
        averageHeartRate: 142,
        elevationGainMeters: 320,
        activeEnergyKcal: 740
    )

    SOOMScreen {
        TerrainInsightCue(
            insight: TerrainInsightBuilder().build(current: input),
            tint: SOOMColor.bike
        )
    }
}
