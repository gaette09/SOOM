import Foundation
import SwiftUI

struct CheckInSummaryCard: View {
    let checkIn: RecoveryCheckIn

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
                Image(systemName: SOOMIcon.recovery)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(SOOMColor.recovery)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(SOOMColor.recovery.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text("오늘 컨디션 기록")
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(formattedDate)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    summaryPill(title: "피로감", value: checkIn.fatigueLevel, tint: SOOMColor.warning)
                    summaryPill(title: "수면감", value: checkIn.sleepQuality, tint: SOOMColor.recovery)
                }

                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    summaryPill(title: "근육통", value: checkIn.muscleSoreness, tint: SOOMColor.run)
                    summaryPill(title: "기분", value: checkIn.moodLevel, tint: SOOMColor.bike)
                }
            }

            if let note = checkIn.note, !note.isEmpty {
                Text(note)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SOOMLayout.SectionHeader.spacing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오늘 컨디션 기록")
        .accessibilityValue(accessibilitySummary)
    }

    private var formattedDate: String {
        checkIn.date.formatted(
            .dateTime
                .locale(Locale(identifier: "ko_KR"))
                .month(.wide)
                .day()
                .hour()
                .minute()
        )
    }

    private var accessibilitySummary: String {
        "피로감 \(checkIn.fatigueLevel)점, 수면감 \(checkIn.sleepQuality)점, 근육통 \(checkIn.muscleSoreness)점, 기분 \(checkIn.moodLevel)점"
    }

    private func summaryPill(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: SOOMLayout.SectionHeader.spacing) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            Spacer(minLength: SOOMLayout.SectionHeader.spacing)
            Text("\(value)/5")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
        .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
    }
}

#Preview("CheckInSummaryCard") {
    SOOMScreen {
        CheckInSummaryCard(
            checkIn: RecoveryCheckIn(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                fatigueLevel: 3,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "수면감은 좋고 다리는 조금 가벼움"
            )
        )
    }
    .preferredColorScheme(.light)
}
