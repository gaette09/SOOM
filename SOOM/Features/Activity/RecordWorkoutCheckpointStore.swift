import Foundation

/// A local in-progress workout, retained until the user saves/completes or discards it.
/// The last checkpoint time ends active time after process termination; the missing interval is never inferred.
struct RecordWorkoutCheckpointStore {
    let fileURL: URL
    private let isAccountRetired: (UUID) -> Bool

    init(fileURL: URL, isAccountRetired: @escaping (UUID) -> Bool = {
        AccountDeletionWriteFence.shared.isRetired($0)
    }) {
        self.fileURL = fileURL
        self.isAccountRetired = isAccountRetired
    }

    func save(_ session: RecordWorkoutSession, at date: Date) throws {
        // An old RecordView can disappear after deletion cleanup finishes.
        // Keep ordinary account switches resumable, but never recreate a
        // confirmed-deleted account's directory from its retained checkpoint.
        let owner = UUID(uuidString: fileURL.deletingLastPathComponent().lastPathComponent)
        if let owner, isAccountRetired(owner) {
            throw RecordWorkoutCheckpointError.accountDeleted
        }
        // Serialize the full disk write against retirement and cleanup. A
        // future background writer must not pass a check before deletion,
        // then recreate the file after cleanup has completed.
        try AccountDeletionWriteFence.shared.withActiveScope(owner) {
            let checkpoint = Checkpoint(savedAt: date, session: session)
            let data = try JSONEncoder().encode(checkpoint)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
    }

    func load() throws -> RecordWorkoutSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: fileURL))
        if checkpoint.session.state == .active {
            return checkpoint.session.paused(at: checkpoint.savedAt)
        }
        return checkpoint.session.state == .cancelled ? nil : checkpoint.session
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private struct Checkpoint: Codable {
        let savedAt: Date
        let session: RecordWorkoutSession
    }
}


enum RecordWorkoutCheckpointError: Error, Equatable {
    case accountDeleted
}
