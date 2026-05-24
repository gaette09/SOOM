import SwiftUI
import UIKit
import HealthKit

struct WorkoutDetailContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let workout: Workout
    let showsHeader: Bool
    var sessionSummary: WorkoutSessionSummary?
    var growthSummary: WorkoutGrowthSummary?
    var growthMetrics: [WorkoutGrowthMetric]?
    var comparisonInsight: WorkoutComparisonInsight?
    var splitInsight: WorkoutSplitInsight?
    var weaknessInsight: WorkoutWeaknessInsight?
    var recoveryImpact: WorkoutRecoveryImpact?
    var shareableCard: ShareableWorkoutCardModel?
    var mapRoute: WorkoutRoute?
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?
    var splitDataProvider: WorkoutSplitDataProviding?
    var renderShareImage: @MainActor (ShareableWorkoutCardModel, Color) -> UIImage? = { card, tint in
        ShareableWorkoutCardRenderer().render(card: card, tint: tint)
    }
    @State private var shareImage: UIImage?
    @State private var isShareSheetPresented = false
    @State private var shareErrorMessage: String?
    @State private var streamZoneSummaries: [WorkoutZoneSummary]?
    @State private var streamSplitInsight: WorkoutSplitInsight?
    @State private var isLoadingZoneSummaries = false
    @State private var didFailLoadingZoneSummaries = false

    static let sharePrivacyCopy = "4:5 이미지로 저장돼요. 위치, 심박, 회복 점수는 기본으로 제외됩니다."

    var body: some View {
        Group {
            if showsHeader {
                DetailHeader(
                    icon: workout.sport.iconName,
                    title: workout.title,
                    subtitle: "\(workout.sport.title) · \(workout.formattedDistance) · \(workout.formattedDuration)",
                    tint: workout.sport.tint
                )
            }

            WorkoutDetailMapOverlay(workout: workout, route: mapRoute)

            detailSection(.core) {
                WorkoutMetricsSection(workout: workout)

                if let sessionSummary {
                    WorkoutSessionSummaryCard(summary: sessionSummary, tint: workout.sport.tint)
                }
            }

            detailSection(.growth) {
                if let metrics = growthMetrics, !metrics.isEmpty {
                    WorkoutGrowthMetricsCard(metrics: metrics, tint: workout.sport.tint)
                }

                if let growthSummary {
                    WorkoutGrowthCard(summary: growthSummary, tint: workout.sport.tint)
                }

                if let comparisonInsight {
                    WorkoutComparisonInsightCard(insight: comparisonInsight, tint: workout.sport.tint)
                }

                if let displayedSplitInsight {
                    WorkoutSplitInsightCard(insight: displayedSplitInsight, tint: workout.sport.tint)
                }
            }

            detailSection(.sensorData) {
                WorkoutZoneSection(
                    workout: workout,
                    streamSummaries: streamZoneSummaries,
                    isLoadingStream: isLoadingZoneSummaries,
                    didFailLoadingStream: didFailLoadingZoneSummaries
                )
                WorkoutChartStack(workout: workout)
                WorkoutSplitsCard(workout: workout)
            }

            detailSection(.recovery) {
                if let recoveryImpact {
                    WorkoutRecoveryImpactCard(impact: recoveryImpact, tint: workout.sport.tint)
                }

                if let weaknessInsight {
                    WorkoutWeaknessCard(insight: weaknessInsight, tint: workout.sport.tint)
                }

                SOOMCard {
                    SOOMSectionHeader("AI 해석")
                    Text(workout.aiSummary)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI 해석")
                .accessibilityValue(workout.aiSummary)

                SOOMCard {
                    SOOMSectionHeader("다음 액션")
                    Label("회복 상태를 확인하고 다음 세션 강도를 조절하세요.", systemImage: SOOMIcon.checkCircle)
                    Label("같은 종목의 최근 4주 추세와 비교하세요.", systemImage: SOOMIcon.trend)
                    Label("피드에 공유할 때는 운동 목적을 함께 남기세요.", systemImage: SOOMIcon.feed)
                }
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("다음 액션")
            }

            if let shareableCard {
                VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                    SOOMSectionHeader("공유 카드 미리보기")
                    Text(Self.sharePrivacyCopy)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ShareableWorkoutCardView(card: shareableCard, tint: workout.sport.tint)
                shareButton(for: shareableCard)
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let shareImage {
                WorkoutShareSheet(activityItems: [shareImage])
            }
        }
        .task(id: healthKitWorkout?.uuid) {
            await loadStreamZoneSummaries()
            await loadStreamSplitInsight()
        }
        .alert(
            "공유 카드를 만들지 못했어요",
            isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        shareErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
    }


    @ViewBuilder
    private func detailSection<Content: View>(
        _ group: WorkoutDetailSectionGroup,
        @ViewBuilder content: () -> Content
    ) -> some View {
        WorkoutDetailSectionContainer(group: group, reduceMotion: reduceMotion) {
            content()
        }
    }

    @MainActor
    private func loadStreamZoneSummaries() async {
        guard let healthKitWorkout, let zoneDataProvider else {
            streamZoneSummaries = nil
            isLoadingZoneSummaries = false
            didFailLoadingZoneSummaries = false
            return
        }

        isLoadingZoneSummaries = true
        didFailLoadingZoneSummaries = false

        do {
            let summaries = try await zoneDataProvider.summaries(for: healthKitWorkout, sport: workout.sport)
            streamZoneSummaries = summaries.contains { $0.isAvailable } ? summaries : nil
        } catch {
            streamZoneSummaries = nil
            didFailLoadingZoneSummaries = true
        }

        isLoadingZoneSummaries = false
    }

    @MainActor
    private func loadStreamSplitInsight() async {
        guard let healthKitWorkout, let splitDataProvider else {
            streamSplitInsight = nil
            return
        }

        do {
            streamSplitInsight = try await splitDataProvider.insight(
                for: healthKitWorkout,
                current: workoutGrowthInput
            )
        } catch {
            streamSplitInsight = nil
        }
    }

    private var displayedSplitInsight: WorkoutSplitInsight? {
        streamSplitInsight ?? splitInsight
    }

    private var workoutGrowthInput: WorkoutGrowthInput {
        WorkoutGrowthInput(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(workoutSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: Double(workout.avgHeartRate),
            elevationGainMeters: Double(workout.elevationGain),
            activeEnergyKcal: Double(workout.activeCalories)
        )
    }

    private func shareButton(for card: ShareableWorkoutCardModel) -> some View {
        Button {
            share(card)
        } label: {
            Label("공유하기", systemImage: SOOMIcon.share)
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Card.padding)
                .background(workout.sport.tint)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("공유 카드 공유하기")
        .accessibilityHint("공유 카드 이미지를 만든 뒤 iOS 공유 시트를 엽니다.")
    }

    @MainActor
    private func share(_ card: ShareableWorkoutCardModel) {
        guard let image = renderedShareImage(for: card) else {
            shareErrorMessage = "공유 카드 이미지를 만들 수 없어요."
            return
        }

        shareImage = image
        isShareSheetPresented = true
    }

    @MainActor
    func renderedShareImage(for card: ShareableWorkoutCardModel) -> UIImage? {
        renderShareImage(card, workout.sport.tint)
    }
}

struct DetailHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.detailHeaderSpacing) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: SOOMLayout.Metrics.detailIconFrame, height: SOOMLayout.Metrics.detailIconFrame)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(title)
                        .font(SOOMFont.display(22, relativeTo: .title2))
                        .foregroundStyle(SOOMColor.ink)
                    Text(subtitle)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}

private struct WorkoutDetailSectionContainer<Content: View>: View {
    let group: WorkoutDetailSectionGroup
    let reduceMotion: Bool
    @ViewBuilder let content: Content
    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupContentSpacing) {
            header
            content
        }
        .padding(.top, SOOMLayout.WorkoutDetail.groupTopPadding)
        .opacity(shouldAnimate ? (didAppear ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.muted) : SOOMMotion.Opacity.visible)
        .offset(y: shouldAnimate ? (didAppear ? 0 : SOOMMotion.Offset.subtleRevealY) : 0)
        .animation(SOOMMotion.normalEaseOut.delay(Double(group.priority) * 0.03), value: didAppear)
        .onAppear {
            didAppear = true
        }
        .accessibilityElement(children: .contain)
    }

    private var shouldAnimate: Bool {
        !reduceMotion
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.WorkoutDetail.groupHeaderSpacing) {
            Text(group.title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .textCase(.none)

            Text(group.caption)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(group.title)
        .accessibilityValue(group.caption)
    }
}


private extension UnifiedWorkoutType {
    init(workoutSport sport: WorkoutSport) {
        switch sport {
        case .swim:
            self = .swimming
        case .bike, .brick:
            self = .cycling
        case .run:
            self = .running
        }
    }
}
