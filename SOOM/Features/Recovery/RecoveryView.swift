import SwiftUI

struct RecoveryView: View {
    @StateObject private var viewModel: RecoveryViewModel
    private let explanationBuilder = RecoveryExplanationBuilder()
    private let readinessBuilder = DailyReadinessBuilder()

    init(viewModel: RecoveryViewModel = RecoveryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header

            if let recovery = viewModel.summary {
                recoveryContent(recovery)
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
            } else {
                loadingCard
            }
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task {
                await viewModel.refreshCheckInPersonalization()
            }
        }
        .navigationTitle("회복")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func recoveryContent(_ recovery: RecoverySummary) -> some View {
        coreRecoverySection(recovery)

        supportingInterpretationSection(recovery)
        managementActionSection
        dataQualityFootnote(recovery)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("회복")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("오늘의 몸 상태와 훈련 준비도를 확인하세요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func todayFocusSection(_ recovery: RecoverySummary) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.RecoveryScreen.focusCardSpacing) {
            DailyReadinessCard(state: readinessBuilder.build(from: recovery))

            RecoveryScoreCard(
                score: recovery.score,
                status: recovery.status,
                description: recovery.description,
                recommendation: recovery.recommendation,
                trendText: recovery.trendText,
                tint: SOOMColor.recovery
            )

            VStack(alignment: .leading, spacing: SOOMLayout.RecoveryScreen.supportingCardSpacing) {
                CoachMessageCard(
                    coachName: recovery.coachMessage.coachName,
                    message: recovery.coachMessage.message,
                    subtitle: recovery.coachMessage.subtitle,
                    icon: SOOMIcon.sparkles,
                    tint: SOOMColor.orange
                )

                explanationCard(recovery)

                RecommendationCard(
                    title: recovery.recommendationCard.title,
                    description: recovery.recommendationCard.description,
                    actionLabel: recovery.recommendationCard.actionLabel,
                    icon: recovery.recommendationCard.icon,
                    tint: SOOMColor.bike
                )
            }
        }
    }

    private func coreRecoverySection(_ recovery: RecoverySummary) -> some View {
        RecoverySection(
            title: "오늘 핵심",
            caption: "상태, 이유, 다음 행동"
        ) {
            todayFocusSection(recovery)
        }
    }

    private func explanationCard(_ recovery: RecoverySummary) -> some View {
        let explanation = explanationBuilder.build(
            summary: recovery,
            latestCheckIn: viewModel.latestCheckIn
        )

        return RecoveryExplanationCard(
            title: explanation.title,
            explanation: explanation.explanation,
            supportingBullets: explanation.supportingBullets,
            icon: explanation.icon,
            tone: explanation.tone
        )
    }

    @ViewBuilder
    private var latestCheckInSection: some View {
        if let latestCheckIn = viewModel.latestCheckIn {
            RecoverySection(
                title: "최근 컨디션 기록",
                caption: "점수는 그대로, 코칭만 보완"
            ) {
                CheckInSummaryCard(checkIn: latestCheckIn)
            }
        }
    }

    private func supportingInterpretationSection(_ recovery: RecoverySummary) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.RecoveryScreen.sectionGroupSpacing) {
            latestCheckInSection
            trendSection(recovery)
            timelineSection(recovery)
            weeklySummarySection
            insightSection(recovery)
        }
    }

    private func trendSection(_ recovery: RecoverySummary) -> some View {
        RecoverySection(
            title: "최근 변화",
            caption: "오늘 판단을 보조하는 흐름"
        ) {
            ForEach(recovery.trends) { trend in
                TrendCard(
                    title: trend.title,
                    currentValue: trend.currentValue,
                    unit: trend.unit,
                    changeText: trend.changeText,
                    trendDirection: trend.direction.cardDirection,
                    values: trend.values
                )
            }
        }
    }

    private func timelineSection(_ recovery: RecoverySummary) -> some View {
        RecoverySection(
            title: "회복 흐름",
            caption: "일별 스냅샷 기반 흐름"
        ) {
            if viewModel.timelineEntries.isEmpty {
                timelineEmptyCard
            } else {
                RecoveryTimelineCard(entries: viewModel.timelineEntries)
            }
        }
    }

    private var timelineEmptyCard: some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.calendarClock,
                title: "아직 회복 흐름 기록이 없어요.",
                subtitle: "일별 회복 스냅샷이 쌓이면 최근 흐름을 이곳에서 보여줄게요.",
                tint: SOOMColor.recovery
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("아직 회복 흐름 기록이 없습니다.")
    }

    @ViewBuilder
    private var weeklySummarySection: some View {
        RecoverySection(
            title: "이번 주 회복 흐름",
            caption: "7일 흐름을 가볍게 요약"
        ) {
            if let weeklySummary = viewModel.weeklySummary {
                WeeklyCoachSummaryCard(summary: weeklySummary)
            } else {
                weeklySummaryEmptyCard
            }
        }
    }

    private var weeklySummaryEmptyCard: some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.sparkles,
                title: "이번 주 요약을 준비하고 있어요.",
                subtitle: "회복 스냅샷이 쌓이면 평균 점수와 흐름을 이곳에서 보여줄게요.",
                tint: SOOMColor.orange
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("이번 주 회복 요약을 준비하고 있습니다.")
    }

    private func insightSection(_ recovery: RecoverySummary) -> some View {
        RecoverySection(
            title: "인사이트",
            caption: "행동으로 이어지는 짧은 해석"
        ) {
            ForEach(recovery.insights) { insight in
                InsightCard(
                    title: insight.title,
                    message: insight.message,
                    icon: insight.icon,
                    tone: insight.tone.cardTone
                )
            }
        }
    }

    private var managementActionSection: some View {
        RecoverySection(
            title: "관리",
            caption: "컨디션 기록과 데이터 연결 설정"
        ) {
            SOOMCard {
                managementNavigationRow(
                    destination: CheckInViewContainer(),
                    icon: SOOMIcon.edit,
                    title: "오늘 컨디션 기록하기",
                    subtitle: "10초 안에 몸 상태를 남겨요.",
                    tint: SOOMColor.recovery,
                    accessibilityLabel: "오늘 컨디션 기록하기",
                    accessibilityHint: "피로감, 수면감, 근육통, 기분을 기록하는 화면으로 이동합니다."
                )

                managementDivider

                managementNavigationRow(
                    destination: CheckInHistoryViewContainer(),
                    icon: SOOMIcon.calendarClock,
                    title: "컨디션 기록 보기",
                    subtitle: "최근 기록을 확인하고 수정합니다.",
                    tint: SOOMColor.recovery,
                    accessibilityLabel: "컨디션 기록 보기",
                    accessibilityHint: "저장된 컨디션 기록 목록으로 이동합니다."
                )

                managementDivider

                managementNavigationRow(
                    destination: HealthKitSettingsViewContainer(),
                    icon: SOOMIcon.health,
                    title: "HealthKit 연결",
                    subtitle: "읽기 권한과 연결 상태를 관리합니다.",
                    tint: SOOMColor.secondaryInk,
                    accessibilityLabel: "HealthKit 연결",
                    accessibilityHint: "HealthKit 권한 상태와 읽기 권한 요청 화면으로 이동합니다."
                )
            }
        }
    }

    private var loadingCard: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
                ProgressView()
                    .tint(SOOMColor.recovery)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    Text("회복 데이터를 불러오는 중")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)

                    Text("오늘의 컨디션 요약을 준비하고 있습니다.")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("회복 데이터를 불러오는 중")
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMSectionHeader("회복 데이터를 불러오지 못했습니다.", caption: message)
            Text("잠시 후 다시 시도해 주세요.")
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func dataQualityFootnote(_ recovery: RecoverySummary) -> some View {
        Text("데이터 상태 · \(recovery.dataQuality.label)")
            .font(SOOMFont.body(11, relativeTo: .caption2))
            .foregroundStyle(SOOMColor.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SOOMLayout.RecoveryScreen.footnoteTopPadding)
            .accessibilityLabel("데이터 상태")
            .accessibilityValue(recovery.dataQuality.label)
    }

    private var managementDivider: some View {
        Divider()
            .overlay(SOOMColor.line)
            .padding(.leading, SOOMLayout.Metrics.actionIconFrame + SOOMLayout.Metrics.actionRowSpacing)
    }

    private func managementNavigationRow<Destination: View>(
        destination: Destination,
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        accessibilityLabel: String,
        accessibilityHint: String
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            SOOMActionRow(
                icon: icon,
                title: title,
                subtitle: subtitle,
                tint: tint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct RecoverySection<Content: View>: View {
    let title: String
    let caption: String?
    let content: Content

    init(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.RecoveryScreen.compactSectionSpacing) {
            SOOMSectionHeader(title, caption: caption)
            content
        }
    }
}

#Preview("RecoveryView") {
    NavigationStack {
        RecoveryView(viewModel: RecoveryViewModel(provider: MockRecoveryDataProvider()))
    }
    .preferredColorScheme(.light)
}
