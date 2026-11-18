import SwiftUI

struct HealthKitWorkoutImportView: View {
    @StateObject private var viewModel: HealthKitWorkoutImportViewModel
    @State private var showingPublicImportConfirmation = false

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
            if ImportedWorkoutPublication.usesLegacyPublication, let publication = viewModel.publicationResult { publicationCard(publication) }
        }
        .navigationTitle("운동 가져오기")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("새 운동을 공개 피드에 올릴까요?", isPresented: $showingPublicImportConfirmation,
                            titleVisibility: .visible) {
            Button("공개로 가져오기") { Task { await viewModel.importRecentWorkouts() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("새로 가져온 운동의 종목·날짜·거리·시간·지역 및 보호 처리된 경로 지도가 공개 피드에 표시됩니다. 활동에서 개별 비공개 또는 전체 비공개로 바꿀 수 있어요. 기존 운동은 공개되지 않습니다.")
        }
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
                "운동 기록 가져오기",
                caption: "가져온 기록을 기기에 저장하고, 분석에 포함한 운동으로 활동과 회복 흐름을 보여줘요."
            )

            Text(viewModel.importSharingDescription)
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("Apple 건강 앱의 원본을 바꾸지 않고 SOOM에 기록을 저장해요.", soomIcon: SOOMIcon.health)
                Label("중복 기록은 저장소 기준으로 한 번만 유지돼요.", soomIcon: SOOMIcon.checkCircle)
                Label("운동 도서관에서 기록을 확인하고 분석 포함 여부를 관리할 수 있어요.", soomIcon: SOOMIcon.sync)
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
                if viewModel.willAutoPublish { showingPublicImportConfirmation = true }
                else { Task { await viewModel.importRecentWorkouts() } }
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
                .background(viewModel.isImporting ? SOOMColor.tertiaryInk : SOOMColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isImporting)
            .accessibilityLabel("HealthKit 운동 가져오기")
            .accessibilityHint("최근 HealthKit 운동 기록을 SOOM 분석용 데이터로 가져옵니다.")
        }
    }

    private func publicationCard(_ result: ImportedWorkoutPublication.Result) -> some View {
        SOOMCard {
            Text("공개 피드 반영")
                .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
            Text("공개 \(result.published)개 · 비공개 \(result.leftPrivate)개 · 반영 실패 \(result.failed)개")
                .font(SOOMFont.body(13, relativeTo: .caption))
            if result.failed > 0 {
                Text("공개되지 않은 새 운동은 활동에 남아 있어요. 연결을 확인한 뒤 다시 시도해 주세요.")
                    .font(SOOMFont.body(13, relativeTo: .caption))
                Button("피드 공개 다시 시도") { Task { await viewModel.retryPublication() } }
                    .disabled(viewModel.isImporting)
            }
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
