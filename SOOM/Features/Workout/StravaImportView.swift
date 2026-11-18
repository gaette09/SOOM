import SwiftUI
import UniformTypeIdentifiers

struct StravaImportView: View {
    @StateObject private var viewModel: StravaImportViewModel
    @State private var isFileImporterPresented = false

    init(viewModel: StravaImportViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            importGuideCard
            importActionCard

            if let errorMessage = viewModel.errorMessage {
                importErrorCard(errorMessage)
            }

            if let result = viewModel.lastResult {
                importResultCard(result)
                if let publication = viewModel.publicationResult { publicationCard(publication) }
                if !result.reviews.isEmpty { reviewCard(result.reviews) }
                if !result.issues.isEmpty { issuesCard(result.issues) }
            }
        }
        .navigationTitle("Strava 가져오기")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.cancelImport() }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.zip]
        ) { result in
            handleFileImport(result)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("Strava 활동 이관")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("Strava 계정 데이터 내보내기 zip을 SOOM 운동 기록으로 가져와요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var importGuideCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "ZIP 일괄 가져오기",
                caption: "직접 선택한 내보내기 파일에서 각 활동을 차례로 가져와요."
            )

            Text(ProfileOnlyPrivacyReleaseGate.productionReady ? "가져온 운동 요약은 프로필 공개범위에 따라 자동으로 반영돼요. 측정·경로 공유 동의는 별도예요." : "가져온 운동은 활동과 본인 피드에 표시돼요. 기존 자료를 다른 사람에게 자동 공개하지 않아요.")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("1. Strava 웹의 설정 > 내 계정 > 계정 다운로드에서 요청하세요.", soomIcon: SOOMIcon.package)
                Label("2. Strava 이메일의 링크에서 ZIP을 내려받아 파일 앱에 저장하세요.", soomIcon: SOOMIcon.package)
                Label("3. 아래에서 ZIP을 선택해 운동을 가져오세요.", soomIcon: SOOMIcon.checkCircle)
                Label("같은 활동은 보존하고, 비슷한 활동은 확인 후 가져와요.", soomIcon: SOOMIcon.checkCircle)
                Label("사용자가 제공한 Strava 파일을 읽으며, Strava 계정 자동 연동은 사용하지 않아요.", soomIcon: SOOMIcon.home)
            }
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)
            Link("Strava 공식 다운로드 안내 열기",
                 destination: URL(string: "https://support.strava.com/en-us/articles/15401919-how-do-i-export-my-strava-data")!)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .accessibilityElement(children: .contain)
    }

    private var importActionCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "zip 파일 선택",
                caption: "선택하면 바로 가져오기가 시작돼요."
            )

            Button {
                isFileImporterPresented = true
            } label: {
                HStack(spacing: SOOMLayout.SectionHeader.spacing) {
                    if viewModel.isImporting {
                        ProgressView()
                            .tint(SOOMColor.white)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.isImporting ? "가져오는 중" : "Strava zip 파일 선택")
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
            .accessibilityLabel("Strava zip 파일 선택")
            .accessibilityHint("Strava 계정 데이터 내보내기 zip 파일을 선택해 가져옵니다.")

            if viewModel.isImporting {
                if viewModel.progress.totalCount > 0 {
                    ProgressView(value: Double(viewModel.progress.completedCount), total: Double(viewModel.progress.totalCount))
                    Text("\(viewModel.progress.completedCount) / \(viewModel.progress.totalCount)개 처리")
                        .font(SOOMFont.body(13, relativeTo: .caption))
                } else {
                    Text("활동 목록을 확인하고 있어요.")
                        .font(SOOMFont.body(13, relativeTo: .caption))
                }
                Button(viewModel.isCancelling ? "현재 작업을 마치는 중" : "가져오기 중지") {
                    viewModel.cancelImport()
                }
                .disabled(viewModel.isCancelling)
            }
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

    private func importErrorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.package,
                title: "가져오지 못했어요",
                subtitle: message,
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func importResultCard(_ result: StravaImportResult) -> some View {
        SOOMCard {
            SOOMSectionHeader(
                resultTitle(for: result),
                caption: "전체 \(result.totalRowCount)건 중 \(result.processedCount)건을 처리했어요."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SOOMLayout.Metrics.compactListSpacing),
                    GridItem(.flexible(), spacing: SOOMLayout.Metrics.compactListSpacing)
                ],
                spacing: SOOMLayout.Metrics.compactListSpacing
            ) {
                StravaImportMetricTile(title: "전체", value: "\(result.totalRowCount)")
                StravaImportMetricTile(title: "가져옴", value: "\(result.importedCount)")
                StravaImportMetricTile(title: "중복 스킵", value: "\(result.skippedDuplicateCount)")
                StravaImportMetricTile(title: "유효하지 않음", value: "\(result.skippedInvalidCount)")
                StravaImportMetricTile(title: "요약만 저장", value: "\(result.summaryOnlyCount)")
                StravaImportMetricTile(title: "경로 복구", value: "\(result.repairedRouteCount)")
                StravaImportMetricTile(title: "검토 필요", value: "\(result.reviews.count)")
                StravaImportMetricTile(title: "완료하지 못함", value: "\(result.failedCount)")
            }
            if result.isCancelled || result.stoppedForLimit || result.failedCount > 0 {
                Text("완료한 기록은 유지돼요. 운동 요약만 저장되고 경로 저장이 끝나지 않은 항목도 재시도로 복구할 수 있어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                Button("완료하지 못한 항목 다시 시도") { viewModel.retryImport() }
            }
            if result.skippedByUserCount > 0 {
                Text("직접 건너뛴 활동 \(result.skippedByUserCount)개")
                    .font(SOOMFont.body(12, relativeTo: .caption))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strava 가져오기 결과")
        .accessibilityValue(
            "전체 \(result.totalRowCount), 가져옴 \(result.importedCount), 중복 스킵 \(result.skippedDuplicateCount), 유효하지 않음 \(result.skippedInvalidCount)"
        )
    }

    private func resultTitle(for result: StravaImportResult) -> String {
        if result.isCancelled { return "가져오기를 중지했어요" }
        if result.stoppedForLimit || result.failedCount > 0 { return "일부 활동을 마치지 못했어요" }
        if !result.reviews.isEmpty { return "비슷한 활동을 확인해 주세요" }
        if result.repairedRouteCount > 0 { return "운동 경로를 복구했어요" }
        return result.importedCount > 0 ? "활동을 가져왔어요" : "새로 가져올 활동이 없어요"
    }

    private func reviewCard(_ reviews: [StravaImportReview]) -> some View {
        SOOMCard {
            SOOMSectionHeader("비슷한 기존 운동이 있어요", caption: "기존 기록은 유지됩니다. 새 활동을 별도로 저장할지 선택해 주세요.")
            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 8) {
                    Text(review.activityName).font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    Text(review.activityDate.formatted(date: .abbreviated, time: .shortened))
                        .font(SOOMFont.body(12, relativeTo: .caption))
                    Button("별도 운동으로 가져오기") { viewModel.resolveReview(review.id, decision: .importSeparately) }
                    Button("이번 활동 건너뛰기") { viewModel.resolveReview(review.id, decision: .skip) }
                }
            }
        }
    }

    private func issuesCard(_ issues: [StravaImportIssue]) -> some View {
        SOOMCard {
            SOOMSectionHeader("항목별 확인 내용", caption: "저장되지 않았거나 요약만 저장된 이유를 확인해 주세요.")
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.activityName).font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    Text(issue.message).font(SOOMFont.body(12, relativeTo: .caption))
                }
            }
        }
    }

    @MainActor
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            viewModel.startImport(from: url)
        case .failure(let error):
            viewModel.fileSelectionFailed(error)
        }
    }
}

private struct StravaImportMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Text(title)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
            Text(value)
                .font(SOOMFont.displayMedium(20, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }
}
