import SwiftUI

struct ProfileSummaryCard: View {
    let name: String
    let handle: String
    let totalWorkoutCount: String
    let weeklySummary: String
    let authStatus: String

    init(
        name: String = "SOOM 사용자",
        handle: String = "@soom.local",
        totalWorkoutCount: String = "-",
        weeklySummary: String = "이번 주 기록 준비 중",
        authStatus: String = "로컬 사용자"
    ) {
        self.name = name
        self.handle = handle
        self.totalWorkoutCount = totalWorkoutCount
        self.weeklySummary = weeklySummary
        self.authStatus = authStatus
    }

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.Card.contentSpacing) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(SOOMColor.recovery)
                    .frame(width: 54, height: 54)
                    .background(SOOMColor.recovery.opacity(0.12))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(name)
                        .font(SOOMFont.display(22, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)

                    HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        Text(handle)
                            .font(SOOMFont.body(13, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)

                        Text(authStatus)
                            .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(SOOMColor.recovery)
                            .padding(.horizontal, SOOMLayout.Metrics.tagSpacing)
                            .padding(.vertical, 4)
                            .background(SOOMColor.recovery.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                        metricPill(title: "총 운동", value: totalWorkoutCount)
                        metricPill(title: "이번 주", value: weeklySummary)
                    }
                    .padding(.top, SOOMLayout.Metrics.actionTextSpacing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("프로필 요약")
        .accessibilityValue("\(name), \(handle), \(authStatus), 총 운동 \(totalWorkoutCount), \(weeklySummary)")
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}
