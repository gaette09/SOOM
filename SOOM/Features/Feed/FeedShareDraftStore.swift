import Foundation

protocol FeedShareDraftStoreProtocol {
    func saveDraft(_ draft: FeedShareDraft) async throws
    func fetchDrafts() async throws -> [FeedShareDraft]
    func deleteDraft(id: UUID) async throws
    func deleteAllDrafts() async throws
}

actor FileFeedShareDraftStore: FeedShareDraftStoreProtocol {
    static private(set) var live = FileFeedShareDraftStore()
    private static let guest = live
    private static var accountStores: [UUID: FileFeedShareDraftStore] = [:]

    static func selectAccount(_ userID: UUID?, directory: URL) {
        guard let userID else { live = guest; return }
        if let existing = accountStores[userID] { live = existing; return }
        let scoped = FileFeedShareDraftStore(fileURL: directory.appendingPathComponent("feed_share_drafts.json"))
        accountStores[userID] = scoped
        live = scoped
    }

    /// Used by the disposable demonstration without touching account caches.
    static func useDemoScope(_ store: FileFeedShareDraftStore) { live = store }

    // Per-instance fence permits a demo session to retire its draft store
    // synchronously before deleting temporary files. Queued actor saves cannot
    // recreate them after exit, and future demos get independent lifetimes.
    private let lifetimeFence = AccountDeletionWriteFence()
    private let lifetimeID = UUID()
    nonisolated func retireDemoScope() { lifetimeFence.retire(lifetimeID) }

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
        try lifetimeFence.withActiveScope(lifetimeID) {
            try AccountDeletionWriteFence.shared.withActiveScope(UUID(uuidString: fileURL.deletingLastPathComponent().lastPathComponent)) {
                try ensureDirectoryExists()
                var drafts = try loadDrafts()
                drafts.removeAll { $0.id == draft.id || $0.sourceWorkoutId == draft.sourceWorkoutId }
                drafts.append(draft)
                drafts.sort { $0.createdAt > $1.createdAt }
                try write(drafts)
            }
        }
    }

    func fetchDrafts() async throws -> [FeedShareDraft] {
        try loadDrafts().sorted { $0.createdAt > $1.createdAt }
    }

    func deleteDraft(id: UUID) async throws {
        try lifetimeFence.withActiveScope(lifetimeID) {
            try AccountDeletionWriteFence.shared.withActiveScope(UUID(uuidString: fileURL.deletingLastPathComponent().lastPathComponent)) {
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
                var drafts = try loadDrafts()
                drafts.removeAll { $0.id == id }
                try write(drafts)
            }
        }
    }

    func deleteAllDrafts() async throws {
        try lifetimeFence.withActiveScope(lifetimeID) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }

            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func write(_ drafts: [FeedShareDraft]) throws {
        try encoder.encode(drafts).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func loadDrafts() throws -> [FeedShareDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([FeedShareDraft].self, from: data)
    }
}
