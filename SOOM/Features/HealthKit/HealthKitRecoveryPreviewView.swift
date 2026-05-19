import SwiftUI

struct HealthKitRecoveryPreviewView: View {
    @StateObject private var viewModel: HealthKitRecoveryPreviewViewModel

    init(viewModel: HealthKitRecoveryPreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            previewContent
        }
        .navigationTitle("Recovery 미리보기")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSummary()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("HealthKit Recovery")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("HealthKit source로 계산한 회복 요약을 개발/검증용으로 확인합니다. 실제 Recovery 기본 화면에는 아직 반영하지 않아요.")
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
                icon: SOOMIcon.health,
                title: "Recovery 미리보기를 불러오지 못했어요",
                message: errorMessage,
                tint: SOOMColor.warning
            )
        } else if viewModel.hasInsufficientHealthKitData {
            messageCard(
                icon: SOOMIcon.recovery,
                title: "HealthKit 운동 기록이 부족해요",
                message: "운동 기록이 쌓이면 Recovery 계산을 미리 확인할 수 있어요.",
                tint: SOOMColor.secondaryInk
            )
        } else if let summary = viewModel.summary {
            summaryCard(summary)
        } else {
            messageCard(
                icon: SOOMIcon.recovery,
                title: "Recovery 미리보기를 준비하고 있어요",
                message: "HealthKit 운동 기록을 확인한 뒤 개발용 요약을 표시합니다.",
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

                Text("HealthKit source로 Recovery 요약을 계산하고 있어요.")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HealthKit Recovery 미리보기 계산 중")
    }

    private func summaryCard(_ summary: RecoverySummary) -> some View {
        SOOMCard {
            SOOMSectionHeader(
                "개발용 미리보기",
                caption: "이 결과는 HealthKit source 검증용이며 production Recovery에는 아직 반영하지 않습니다."
            )

            HStack(alignment: .center, spacing: SOOMLayout.RecoveryAI.scoreHeaderSpacing) {
                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text("Recovery Score")
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.tertiaryInk)

                    Text("\(summary.score)")
                        .font(SOOMFont.display(44, relativeTo: .largeTitle))
                        .foregroundStyle(SOOMColor.ink)
                }

                Spacer(minLength: SOOMLayout.Metrics.tagSpacing)

                VStack(alignment: .trailing, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(summary.status)
                        .font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.recovery)

                    Text(summary.dataQuality.label)
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
                    title: "추천",
                    message: summary.recommendation,
                    icon: SOOMIcon.checkCircle,
                    tint: SOOMColor.recovery
                )

                previewBlock(
                    title: summary.coachMessage.coachName,
                    message: summary.coachMessage.message,
                    icon: SOOMIcon.sparkles,
                    tint: SOOMColor.warning
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HealthKit Recovery 개발용 미리보기")
        .accessibilityValue("점수 \(summary.score), 상태 \(summary.status), \(summary.recommendation)")
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

#Preview("HealthKitRecoveryPreviewView") {
    NavigationStack {
        HealthKitRecoveryPreviewView(
            viewModel: HealthKitRecoveryPreviewViewModel(
                provider: PreviewHealthKitRecoveryProvider()
            )
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewHealthKitRecoveryProvider: RecoveryDataProvider {
    func fetchRecoverySummary() async throws -> RecoverySummary {
        RecoverySummary.mockToday
    }
}
