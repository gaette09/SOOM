import Foundation

@MainActor
final class HealthKitWorkoutImportViewModel: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var lastResult: HealthKitWorkoutImportResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var publicationResult: ImportedWorkoutPublication.Result?

    private let pipeline: any HealthKitWorkoutImporting
    private let limit: Int
    private let publication: ImportedWorkoutPublication?
    var willAutoPublish: Bool { ImportedWorkoutPublication.usesLegacyPublication && publication?.storage.autoPublishImportedWorkouts == true }
    var importSharingDescription: String {
        if !ImportedWorkoutPublication.usesLegacyPublication {return ImportedWorkoutPublication.profileImportDescription}
        return willAutoPublish ? "로그인 상태에서 새로 가져온 운동은 공개 피드에 바로 게시돼요. 활동에서 비공개로 변경할 수 있어요." : "새 운동은 활동에 비공개로 저장돼요."
    }

    init(
        pipeline: any HealthKitWorkoutImporting,
        limit: Int = 50,
        publication: ImportedWorkoutPublication? = nil
    ) {
        self.pipeline = pipeline
        self.limit = limit
        self.publication = publication
    }

    func retryPublication() async {
        guard ImportedWorkoutPublication.usesLegacyPublication, let publication, !isImporting else { return }
        isImporting = true
        publicationResult = await publication.publish()
        isImporting = false
    }

    func importRecentWorkouts() async {
        guard !isImporting else { return }

        isImporting = true
        errorMessage = nil
        publicationResult = nil

        let result = await pipeline.importRecentWorkouts(limit: limit)
        lastResult = result
        if !result.importedWorkouts.isEmpty, let storage = publication?.storage {
            HealthKitAutomaticImport.setEnabled(true, for: storage)
        }
        if ImportedWorkoutPublication.usesLegacyPublication, let publication, !result.importedWorkouts.isEmpty {
            let summary = await publication.publish(ids: result.importedWorkouts.map(\.id))
            if summary != .init() { publicationResult = summary }
        }
        errorMessage = result.failedCount > 0 ? result.message : nil
        isImporting = false
    }
}
