import SwiftUI

struct HealthKitWorkoutImportView: View {
    @StateObject private var viewModel: HealthKitWorkoutImportViewModel

    init(viewModel: HealthKitWorkoutImportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            importGuideCard
            importActionCard

            if let result = viewModel.lastResult {
                importResultCard(result)
            }
        }
        .navigationTitle("운동 가져오기")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("HealthKit 운동 가져오기")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("운동 기록을 SOOM 분석용 데이터로 가져와요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var importGuideCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "읽기 전용 import",
                caption: "가져온 기록은 아직 회복 점수나 성장 분석에 자동 반영되지 않아요."
            )

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("HealthKit 운동을 SOOM 공통 운동 데이터로 저장합니다.", systemImage: SOOMIcon.health)
                Label("중복 기록은 저장소 기준으로 한 번만 유지돼요.", systemImage: SOOMIcon.checkCircle)
                Label("Deduplication과 Recovery/Growth 연결은 다음 단계에서 진행합니다.", systemImage: SOOMIcon.sync)
            }
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var importActionCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "수동 가져오기",
                caption: "권한이 허용되어 있으면 최근 운동 기록을 가져옵니다."
            )

            Button {
                Task {
                    await viewModel.importRecentWorkouts()
                }
            } label: {
                HStack(spacing: SOOMLayout.SectionHeader.spacing) {
                    if viewModel.isImporting {
                        ProgressView()
                            .tint(SOOMColor.white)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.isImporting ? "가져오는 중" : "HealthKit 운동 가져오기")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing + 10)
                .foregroundStyle(SOOMColor.white)
                .background(viewModel.isImporting ? SOOMColor.tertiaryInk : SOOMColor.recovery)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isImporting)
            .accessibilityLabel("HealthKit 운동 가져오기")
            .accessibilityHint("최근 HealthKit 운동 기록을 SOOM 분석용 데이터로 가져옵니다.")
        }
    }

    private func importResultCard(_ result: HealthKitWorkoutImportResult) -> some View {
        SOOMCard {
            SOOMSectionHeader(
                result.failedCount > 0 ? "가져오기를 완료하지 못했어요" : resultTitle(for: result),
                caption: result.message
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SOOMLayout.Metrics.compactListSpacing),
                    GridItem(.flexible(), spacing: SOOMLayout.Metrics.compactListSpacing)
                ],
                spacing: SOOMLayout.Metrics.compactListSpacing
            ) {
                ImportMetricTile(title: "확인", value: "\(result.fetchedCount)")
                ImportMetricTile(title: "저장", value: "\(result.savedCount)")
                ImportMetricTile(title: "건너뜀", value: "\(result.skippedCount)")
                ImportMetricTile(title: "실패", value: "\(result.failedCount)")
            }

            if result.failedCount > 0 {
                SOOMActionRow(
                    icon: SOOMIcon.health,
                    title: "다시 시도해 주세요",
                    subtitle: "HealthKit 권한 또는 일시적인 저장 상태를 확인해 주세요.",
                    tint: SOOMColor.warning
                )
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("HealthKit 운동 가져오기 결과")
        .accessibilityValue("확인 \(result.fetchedCount), 저장 \(result.savedCount), 건너뜀 \(result.skippedCount), 실패 \(result.failedCount)")
    }

    private func resultTitle(for result: HealthKitWorkoutImportResult) -> String {
        result.savedCount > 0 ? "운동 기록을 가져왔어요" : "가져올 운동 기록이 없어요"
    }
}

private struct ImportMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)

            Text(value)
                .font(SOOMFont.display(26, relativeTo: .title2))
                .foregroundStyle(SOOMColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

#Preview("HealthKitWorkoutImportView") {
    NavigationStack {
        HealthKitWorkoutImportView(
            viewModel: HealthKitWorkoutImportViewModel(
                pipeline: PreviewHealthKitWorkoutImportPipeline()
            )
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewHealthKitWorkoutImportPipeline: HealthKitWorkoutImporting {
    func importRecentWorkouts(limit: Int) async -> HealthKitWorkoutImportResult {
        .success(
            importedWorkouts: [],
            fetchedCount: 0
        )
    }
}
