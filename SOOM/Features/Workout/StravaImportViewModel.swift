import Foundation

@MainActor
final class StravaImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var lastResult: StravaImportResult?
    @Published private(set) var errorMessage: String?

    private let pipeline: StravaImportPipeline

    init(pipeline: StravaImportPipeline) {
        self.pipeline = pipeline
    }

    func importZip(from url: URL) async {
        guard !isImporting else { return }

        isImporting = true
        errorMessage = nil

        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let result = try await pipeline.importZip(data)
            lastResult = result
        } catch let error as StravaExportReaderError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Strava zip 파일을 가져오지 못했습니다."
        }

        isImporting = false
    }

    private static func message(for error: StravaExportReaderError) -> String {
        switch error {
        case .emptyData:
            return "선택한 파일이 비어 있습니다."
        case .notAZipArchive:
            return "zip 파일이 아닙니다. Strava 계정 데이터 내보내기 zip을 선택해 주세요."
        case .missingActivitiesCSV:
            return "이 zip 안에서 activities.csv를 찾을 수 없습니다."
        case .malformedCSV:
            return "activities.csv 형식을 읽을 수 없습니다."
        case .entryCountLimitExceeded:
            return "활동 기록이 너무 많습니다. 파일을 나눠서 가져와 주세요."
        case .fileTooLarge:
            return "파일 하나의 용량이 너무 큽니다."
        }
    }
}
