import SwiftUI

struct ShareableWeeklyProgressCardView: View {
    let card: ShareableWeeklyProgressCardModel
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            header

            Spacer(minLength: SOOMLayout.Card.contentSpacing)

            VStack(alignment: .leading, spacing: ShareableWorkoutCardLayout.messageSpacing) {
                Text(card.weekLabel)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(tint)

                Text(card.progressMessage)
                    .font(SOOMFont.displayMedium(25, relativeTo: .title2))
                    .foregroundStyle(SOOMColor.ink)
                    .lineSpacing(ShareableWorkoutCardLayout.primaryLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: ShareableWorkoutCardLayout.metricSpacing), count: 3),
                spacing: ShareableWorkoutCardLayout.metricSpacing
            ) {
                ShareableWeeklyMetric(label: "운동", value: card.workoutCountText)
                ShareableWeeklyMetric(label: "거리", value: card.totalDistanceText)
                ShareableWeeklyMetric(label: "시간", value: card.totalDurationText)
            }

            Label {
                Text(card.motivationText)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: SOOMIcon.trendUp)
                    .foregroundStyle(tint)
            }
            .padding(SOOMLayout.Card.padding)
            .background(SOOMColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous))

            Spacer(minLength: SOOMLayout.Card.contentSpacing)

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ShareableWorkoutCardLayout.outerPadding)
        .aspectRatio(ShareableWorkoutCardLayout.aspectRatio, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                .fill(SOOMColor.surface)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.10))
                .frame(width: ShareableWorkoutCardLayout.accentCircleSize, height: ShareableWorkoutCardLayout.accentCircleSize)
                .offset(x: ShareableWorkoutCardLayout.accentCircleOffset, y: -ShareableWorkoutCardLayout.accentCircleOffset)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous)
                .stroke(SOOMColor.line, lineWidth: SOOMLayout.Card.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.outerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("주간 운동 공유 카드 미리보기")
        .accessibilityValue("\(card.weekLabel). 운동 \(card.workoutCountText), 거리 \(card.totalDistanceText), 시간 \(card.totalDurationText). \(card.progressMessage). \(card.motivationText). \(card.visibility.title)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.iconTextSpacing) {
            Image(systemName: SOOMIcon.chartBar)
                .font(.system(size: ShareableWorkoutCardLayout.headerIconSize, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: ShareableWorkoutCardLayout.headerIconFrame, height: ShareableWorkoutCardLayout.headerIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                Text("SOOM")
                    .font(SOOMFont.displayMedium(15, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text("이번 주 성장 기록")
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer()

            ShareablePrivacyBadge(title: "민감 정보 제외")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            Divider()
                .overlay(SOOMColor.line)

            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(card.footerText)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)

                Spacer()

                ShareablePrivacyBadge(title: card.visibility.title, tint: tint)
            }
        }
    }
}

private struct ShareableWeeklyMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text(label)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: ShareableWorkoutCardLayout.innerRadius, style: .continuous))
    }
}

#Preview("ShareableWeeklyProgressCardView") {
    let workouts = MockWorkoutHarness().loadWorkouts()
    let progress = WeeklyWorkoutProgressBuilder().build(workouts: workouts)
    let model = ShareableWeeklyProgressCardBuilder().build(progress: progress)

    SOOMScreen {
        ShareableWeeklyProgressCardView(card: model, tint: SOOMColor.bike)
    }
    .preferredColorScheme(.light)
}
