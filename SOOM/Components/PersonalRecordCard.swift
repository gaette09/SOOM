import SwiftUI

struct PersonalRecordCard: View {
    let records: [PersonalRecord]
    let tint: Color

    var body: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                HStack(alignment: .top, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
                    Image(systemName: SOOMIcon.medal)
                        .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                        Text("개인 기록")
                            .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(tint)

                        Text(titleText)
                            .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink)

                        Text(summaryText)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if records.isEmpty {
                    Text("운동 기록이 쌓이면 거리, 시간, 페이스 같은 개인 성장 신호를 보여드릴게요.")
                        .font(SOOMFont.body(13, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                        ForEach(records) { record in
                            recordRow(record)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("개인 기록")
        .accessibilityValue(accessibilityValue)
    }

    private var titleText: String {
        records.first?.metricType.title ?? "기록을 쌓는 중이에요"
    }

    private var summaryText: String {
        records.first?.comparisonText ?? "최근 운동에서 의미 있는 성과가 생기면 이곳에 정리됩니다."
    }

    private var accessibilityValue: String {
        guard !records.isEmpty else {
            return "아직 표시할 개인 기록이 없습니다."
        }

        return records
            .map { "\($0.metricType.title), \($0.value), \($0.comparisonText)" }
            .joined(separator: ". ")
    }

    private func recordRow(_ record: PersonalRecord) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.gridSpacing) {
            Image(systemName: record.metricType.icon)
                .font(.system(size: SOOMLayout.RecoveryAI.promptIconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.RecoveryAI.promptIconFrame, height: SOOMLayout.RecoveryAI.promptIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.metricType.title)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.ink)

                    Spacer(minLength: SOOMLayout.Metrics.tagSpacing)

                    Text(record.value)
                        .font(SOOMFont.displayMedium(15, relativeTo: .subheadline))
                        .foregroundStyle(tint)
                }

                Text("\(formattedDate(record.achievedAt)) · \(record.motivationText)")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }
}

#Preview("PersonalRecordCard") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let records = PersonalRecordBuilder().build(workouts: workouts)

    SOOMScreen {
        PersonalRecordCard(records: records, tint: SOOMColor.warning)
    }
    .preferredColorScheme(.light)
}
