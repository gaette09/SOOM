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
            }
        }
        .navigationTitle("Strava 가져오기")
        .navigationBarTitleDisplayMode(.inline)
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
                "완전 자동 가져오기",
                caption: "선택 화면 없이 zip 안의 모든 활동을 한 번에 가져와요."
            )

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("Strava 설정 > 내 계정 내보내기에서 받은 zip 파일을 선택하세요.", systemImage: SOOMIcon.package)
                Label("이미 가져온 활동은 자동으로 건너뛰어요.", systemImage: SOOMIcon.checkCircle)
                Label("GPS 기록이 없는 실내 운동도 활동 정보만으로 저장돼요.", systemImage: SOOMIcon.home)
            }
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
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
                caption: "전체 \(result.totalRowCount)건 중 결과예요."
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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strava 가져오기 결과")
        .accessibilityValue(
            "전체 \(result.totalRowCount), 가져옴 \(result.importedCount), 중복 스킵 \(result.skippedDuplicateCount), 유효하지 않음 \(result.skippedInvalidCount)"
        )
    }

    private func resultTitle(for result: StravaImportResult) -> String {
        result.importedCount > 0 ? "활동을 가져왔어요" : "새로 가져올 활동이 없어요"
    }

    @MainActor
    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                await viewModel.importZip(from: url)
            }
        case .failure:
            break
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
