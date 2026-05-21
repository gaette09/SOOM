import SwiftUI

struct RecoveryRealDataPreviewView: View {
    @StateObject private var viewModel: RecoveryRealDataPreviewViewModel

    init(viewModel: RecoveryRealDataPreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            previewContent
        }
        .navigationTitle("검증용 Recovery 미리보기")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("실제 운동 기반 미리보기")
                .font(SOOMFont.display(31, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("가져온 운동 기록으로 회복 흐름을 미리 확인하는 검증용 화면입니다. 아직 공식 Recovery에는 반영되지 않아요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var previewContent: some View {
        if viewModel.isLoading {
            loadingCard
        } else if let errorMessage = viewModel.errorMessage {
            messageCard(
                icon: SOOMIcon.recovery,
                title: "미리보기를 불러오지 못했어요",
                message: errorMessage,
                tint: SOOMColor.warning
            )
        } else if viewModel.hasInsufficientWorkoutData {
            messageCard(
                icon: SOOMIcon.record,
                title: "가져온 운동 기록이 부족해요",
                message: "HealthKit 운동 가져오기를 실행하면 저장된 기록으로 검증용 회복 흐름을 확인할 수 있어요.",
                tint: SOOMColor.secondaryInk
            )
        } else if let summary = viewModel.summary {
            summaryCard(summary)
            boundaryCard
        } else {
            messageCard(
                icon: SOOMIcon.recovery,
                title: "미리보기를 준비하고 있어요",
                message: "저장된 운동 기록을 확인한 뒤 검증용 회복 흐름을 표시합니다.",
                tint: SOOMColor.recovery
            )
        }
    }

    private var loadingCard: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
                ProgressView()
                    .tint(SOOMColor.recovery)
                    .accessibilityHidden(true)

                Text("가져온 운동 기록으로 검증용 회복 흐름을 계산하고 있어요.")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("실제 운동 기록 기반 검증용 Recovery 흐름 계산 중")
    }

    private func summaryCard(_ summary: RecoverySummary) -> some View {
        SOOMCard {
            SOOMSectionHeader(
                "검증용 Recovery 흐름",
                caption: "가져온 운동 기록만 기준으로 계산한 미리보기입니다."
            )

            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.scoreHeaderSpacing) {
                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text("미리보기 점수")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.tertiaryInk)

                    Text("\(summary.score)")
                        .font(SOOMFont.display(38, relativeTo: .title))
                        .foregroundStyle(SOOMColor.ink)
                }

                Spacer(minLength: SOOMLayout.Metrics.tagSpacing)

                VStack(alignment: .trailing, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(summary.status)
                        .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.recovery)

                    Text("사용된 운동 \(viewModel.usedWorkoutCount)개")
                        .font(SOOMFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                        .padding(.vertical, SOOMLayout.SectionHeader.spacing + 2)
                        .background(SOOMColor.recovery.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            Divider()
                .overlay(SOOMColor.line)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                previewBlock(
                    title: "미리보기 추천",
                    message: summary.recommendation,
                    icon: SOOMIcon.checkCircle,
                    tint: SOOMColor.recovery
                )

                previewBlock(
                    title: "데이터 상태",
                    message: summary.dataQuality.label,
                    icon: SOOMIcon.chartLine,
                    tint: SOOMColor.bike
                )

                previewBlock(
                    title: "계산 범위",
                    message: "분석 제외한 운동은 포함하지 않았고, 중복 운동은 아직 자동으로 정리하지 않아요.",
                    icon: SOOMIcon.sync,
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("실제 운동 기록 기반 검증용 Recovery 미리보기")
        .accessibilityValue("미리보기 점수 \(summary.score), 상태 \(summary.status), 사용된 운동 \(viewModel.usedWorkoutCount)개, 공식 Recovery에는 아직 반영되지 않음, \(summary.recommendation)")
    }

    private var boundaryCard: some View {
        SOOMCard {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                SOOMActionRow(
                    icon: SOOMIcon.health,
                    title: "아직 공식 Recovery에는 반영되지 않아요",
                    subtitle: "가져온 운동 기록을 기준으로 회복 흐름을 미리 계산해보는 검증용 영역입니다.",
                    tint: SOOMColor.secondaryInk
                )

                Divider()
                    .overlay(SOOMColor.line)

                previewBlock(
                    title: "반영 기준",
                    message: "분석 제외한 운동은 빼고 계산하며, 중복 운동은 아직 자동으로 정리되지 않을 수 있어요.",
                    icon: SOOMIcon.sync,
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("검증용 Recovery 미리보기 안내")
        .accessibilityValue("가져온 운동 기록 기준이며, 공식 Recovery에는 아직 반영되지 않습니다. 분석 제외 운동은 포함하지 않고, 중복 운동은 자동 정리하지 않습니다.")
    }

    private func previewBlock(title: String, message: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
            Image(systemName: icon)
                .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)

                Text(message)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func messageCard(icon: String, title: String, message: String, tint: Color) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: icon,
                title: title,
                subtitle: message,
                tint: tint
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

#Preview("RecoveryRealDataPreviewView") {
    NavigationStack {
        RecoveryRealDataPreviewView(
            viewModel: RecoveryRealDataPreviewViewModel(
                provider: UnifiedWorkoutRecoveryPreviewProvider(
                    store: PreviewUnifiedWorkoutStore()
                )
            )
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewUnifiedWorkoutStore: UnifiedWorkoutStore {
    func saveWorkout(_ workout: UnifiedWorkout) async throws {}
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {}

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        let now = Date()
        return [
            UnifiedWorkout(
                id: UUID(),
                externalId: "preview-run",
                source: .appleHealthKit,
                workoutType: .running,
                startDate: now.addingTimeInterval(-3_600),
                endDate: now,
                durationSeconds: 3_000,
                distanceMeters: 10_400,
                activeEnergyKcal: 620,
                averageHeartRate: 151,
                maxHeartRate: 174,
                averageSpeedMetersPerSecond: nil,
                elevationGainMeters: 78,
                dataQuality: .partial,
                createdAt: now,
                updatedAt: now
            )
        ]
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}
