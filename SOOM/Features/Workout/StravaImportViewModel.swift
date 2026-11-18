import Foundation

@MainActor
final class StravaImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var isCancelling = false
    @Published private(set) var lastResult: StravaImportResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var publicationResult: ImportedWorkoutPublication.Result?
    @Published private(set) var progress = StravaImportProgress(completedCount: 0, totalCount: 0, activityName: nil)

    private let pipeline: StravaImportPipeline
    private let publication: ImportedWorkoutPublication?
    var willAutoPublish: Bool { ImportedWorkoutPublication.usesLegacyPublication && AccountActivityFeedReleaseGate.productionReady && publication?.storage.autoPublishImportedWorkouts == true }
    private var task: Task<Void, Never>?
    private var selectedURL: URL?
    private var completedEntryIDs: Set<String> = []
    private var decisions: [String: StravaImportReviewDecision] = [:]

    init(pipeline: StravaImportPipeline, publication: ImportedWorkoutPublication? = nil) {
        self.pipeline = pipeline
        self.publication = publication
    }

    func retryPublication() async {
        guard ImportedWorkoutPublication.usesLegacyPublication, AccountActivityFeedReleaseGate.productionReady, let publication, !isImporting else { return }
        isImporting = true
        publicationResult = await publication.publish()
        isImporting = false
    }

    func startImport(from url: URL) {
        guard !isImporting else { return }
        selectedURL = url
        completedEntryIDs = []
        decisions = [:]
        launch()
    }

    func retryImport() {
        guard !isImporting, selectedURL != nil else { return }
        launch()
    }

    func resolveReview(_ id: String, decision: StravaImportReviewDecision) {
        guard !isImporting else { return }
        decisions[id] = decision
        launch()
    }

    func cancelImport() {
        guard isImporting else { return }
        isCancelling = true
        task?.cancel()
    }

    func fileSelectionFailed(_ error: Error) {
        guard (error as NSError).code != NSUserCancelledError else { return }
        errorMessage = "파일 선택을 마치지 못했어요. 다시 선택해 주세요."
    }

    private func launch() {
        guard let url = selectedURL else { return }
        isImporting = true
        isCancelling = false
        errorMessage = nil
        publicationResult = nil
        lastResult = nil
        progress = StravaImportProgress(completedCount: 0, totalCount: 0, activityName: nil)
        task = Task { await performImport(from: url) }
    }

    private func performImport(from url: URL) async {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess { url.stopAccessingSecurityScopedResource() }
            isImporting = false
            isCancelling = false
            task = nil
        }
        do {
            let result = try await pipeline.importZip(from: url, decisions: decisions,
                alreadyCompleted: completedEntryIDs) { [weak self] value in
                    self?.updateProgress(value)
                }
            completedEntryIDs.formUnion(result.completedEntryIDs)
            lastResult = result
            if ImportedWorkoutPublication.usesLegacyPublication, AccountActivityFeedReleaseGate.productionReady, let publication, !result.importedWorkoutIDs.isEmpty {
                let summary = await publication.publish(ids: result.importedWorkoutIDs)
                if summary != .init() { publicationResult = summary }
            }
        } catch is CancellationError {
            lastResult = StravaImportResult(isCancelled: true)
        } catch let error as StravaExportReaderError {
            errorMessage = Self.message(for: error)
        } catch StravaImportError.alreadyImporting {
            errorMessage = "다른 파일의 가져오기가 끝난 뒤 다시 시도해 주세요."
        } catch {
            errorMessage = "파일을 가져오지 못했어요. 파일 접근 권한과 저장 공간을 확인하고 다시 선택해 주세요."
        }
    }

    private func updateProgress(_ value: StravaImportProgress) { progress = value }

    static func message(for error: StravaExportReaderError) -> String {
        switch error {
        case .emptyData: return "선택한 파일이 비어 있어요."
        case .notAZipArchive: return "Strava 계정 데이터 내보내기 ZIP 파일을 선택해 주세요."
        case .missingActivitiesCSV: return "ZIP에서 activities.csv를 찾을 수 없어요."
        case .malformedCSV: return "활동 목록의 형식을 읽을 수 없어요. 원본 내보내기 파일을 확인해 주세요."
        case .entryCountLimitExceeded: return "한 번에 처리할 수 있는 활동 수를 넘었어요. 파일을 나눠서 가져와 주세요."
        case .fileTooLarge: return "활동 파일 하나의 압축 해제 용량이 한도를 넘었어요."
        case .archiveTooLarge: return "ZIP 파일이 너무 커요. 512MB 이하로 나눠서 가져와 주세요."
        case .csvTooLarge: return "활동 목록 파일이 너무 커요. 활동 수를 나눠서 가져와 주세요."
        case .expansionLimitExceeded: return "한 번에 압축을 해제할 수 있는 용량을 넘었어요. 파일을 나눠서 가져와 주세요."
        case .unsafePath: return "안전하게 읽을 수 없는 파일 경로가 있어요. 원본 내보내기 파일을 확인해 주세요."
        case .ambiguousManifest: return "활동 목록이나 파일 경로가 중복되어 있어요. 원본 ZIP을 선택해 주세요."
        case .corruptEntry: return "압축된 파일이 손상되어 있어요. 원본 ZIP을 다시 확인해 주세요."
        }
    }
}
