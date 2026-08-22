import Foundation

protocol FeedShareDraftStoreProtocol {
    func saveDraft(_ draft: FeedShareDraft) async throws
    func fetchDrafts() async throws -> [FeedShareDraft]
    func deleteDraft(id: UUID) async throws
    func deleteAllDrafts() async throws
}

actor FileFeedShareDraftStore: FeedShareDraftStoreProtocol {
    static let live = FileFeedShareDraftStore()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("SOOM", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("SOOM", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("feed_share_drafts.json")
        }
    }

    func saveDraft(_ draft: FeedShareDraft) async throws {
        try ensureDirectoryExists()
        var drafts = try loadDrafts()
        drafts.removeAll { $0.id == draft.id || $0.sourceWorkoutId == draft.sourceWorkoutId }
        drafts.append(draft)
        drafts.sort { $0.createdAt > $1.createdAt }
        try encoder.encode(drafts).write(to: fileURL, options: .atomic)
    }

    func fetchDrafts() async throws -> [FeedShareDraft] {
        try loadDrafts().sorted { $0.createdAt > $1.createdAt }
    }

    func deleteDraft(id: UUID) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        var drafts = try loadDrafts()
        drafts.removeAll { $0.id == id }
        try encoder.encode(drafts).write(to: fileURL, options: .atomic)
    }

    func deleteAllDrafts() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func loadDrafts() throws -> [FeedShareDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([FeedShareDraft].self, from: data)
    }
}
