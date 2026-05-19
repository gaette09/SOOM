import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        SOOMScreen {
            VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
                Text("SOOM")
                    .font(SOOMFont.display(44, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)
                Text("오늘")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text("훈련 흐름은 좋아지고 있습니다. 다음 성장은 회복을 얼마나 잘 조절하느냐에 달려 있어요.")
                    .font(SOOMFont.display(24, relativeTo: .title2))
                    .foregroundStyle(SOOMColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            conditionCard
            recoveryEntryCard
            monthlyCard
            aiCoachCard
            recentWorkouts
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var conditionCard: some View {
        SOOMCard {
            SOOMSectionHeader("SOOM 컨디션")
            HStack {
                SOOMMetricRing(score: viewModel.monthlySnapshot.conditionScore, title: "흐름", tint: SOOMColor.bike)
                Spacer()
                SOOMMetricRing(score: viewModel.monthlySnapshot.fatigueScore, title: "피로", tint: SOOMColor.warning)
                Spacer()
                SOOMMetricRing(score: viewModel.monthlySnapshot.riskScore, title: "위험", tint: SOOMColor.run)
            }
        }
    }

    private var recoveryEntryCard: some View {
        NavigationLink {
            RecoveryViewContainer()
        } label: {
            RecoveryScoreCard(
                score: recoveryPreview.score,
                status: recoveryPreview.status,
                description: "오늘의 몸 상태와 훈련 준비도를 확인하세요.",
                recommendation: recoveryPreview.recommendation,
                trendText: recoveryPreview.trendText,
                tint: SOOMColor.recovery
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("회복 화면으로 이동합니다.")
    }

    private var recoveryPreview: RecoverySummary {
        .mockToday
    }

    private var monthlyCard: some View {
        SOOMCard {
            HStack(alignment: .top) {
                SOOMSectionHeader("최근 30일", caption: "\(viewModel.monthlySnapshot.workoutCount)회 운동 · \(String(format: "%.1f", viewModel.monthlySnapshot.trainingHours)) h · 휴식 \(viewModel.monthlySnapshot.restDays)일")
                Spacer()
                Text("고강도 \(viewModel.monthlySnapshot.highIntensityRatio)%")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
            }

            ForEach(viewModel.monthlySnapshot.summaries) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(summary.sport.title, systemImage: summary.sport.iconName)
                            .foregroundStyle(summary.sport.tint)
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        Spacer()
                        Text("+\(summary.change)%")
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(summary.sport.tint)
                    }
                    ProgressView(value: summary.progress)
                        .tint(summary.sport.tint)
                    Text("\(summary.volume) · \(summary.sessions)회")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }
        }
    }

    private var aiCoachCard: some View {
        SOOMCard {
            SOOMSectionHeader("AI 코치")
            Text("유산소 기반은 좋아지고 있습니다. 특히 사이클과 러닝 흐름이 좋지만, 러닝 훈련량 증가 폭이 커서 다음 주에는 회복을 섞어 부상 위험을 낮추는 편이 좋습니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.monthlySnapshot.recommendations) { item in
                Label("\(item.targetDay) · \(item.title): \(item.detail)", systemImage: SOOMIcon.sparkles)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
            }
        }
    }

    private var recentWorkouts: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
            Text("최근 운동")
                .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)

            ForEach(viewModel.recentWorkouts) { workout in
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    SOOMCard {
                        SOOMActionRow(
                            icon: workout.sport.iconName,
                            title: workout.title,
                            subtitle: "\(workout.formattedDistance) · \(workout.formattedDuration) · 평균 \(workout.avgHeartRate)bpm",
                            tint: workout.sport.tint
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
