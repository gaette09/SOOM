import Foundation

/// Local draft only. Handles are labels, never stable identities or authorization.
/// A future server contract must revalidate recipients against post visibility,
/// blocks and current handle ownership before persisting or notifying anyone.
struct FeedMentionDraft: Equatable {
    struct Selection: Equatable, Codable {
        let userID: UUID
        let handle: String
        enum CodingKeys: String, CodingKey { case userID = "user_id", handle }
    }
    private(set) var selections: [Selection] = []

    mutating func select(userID: UUID, handle: String) {
        let normalized = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else { return }
        selections.removeAll { $0.userID == userID || $0.handle.lowercased() == normalized.lowercased() }
        selections.append(Selection(userID: userID, handle: normalized))
    }

    /// Editing out a selected token invalidates the selection. Arbitrary typed
    /// @text does not become a recipient, and emails do not create mentions.
    func retainedSelections(in text: String) -> [Selection] {
        selections.filter { selection in
            let token = NSRegularExpression.escapedPattern(for: selection.handle)
            let pattern = "(?<![\\p{L}\\p{N}_.@])@" + token + "(?![\\p{L}\\p{N}_.])"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    mutating func reset() { selections.removeAll() }
}

/// Render only server-authorized identities; never resolve a typed handle locally.
struct FeedMentionReference: Decodable, Equatable {
    let userID: UUID
    let handle: String
    enum CodingKeys: String, CodingKey { case userID = "user_id", handle }
}

enum FeedMentionText {
    static func attributed(_ body: String, references: [FeedMentionReference]) -> AttributedString {
        var result = AttributedString(body)
        for reference in references {
            let escaped = NSRegularExpression.escapedPattern(for: reference.handle)
            guard let expression = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_.@])@" + escaped + "(?![\\p{L}\\p{N}_.])", options: [.caseInsensitive]) else { continue }
            for match in expression.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let sourceRange = Range(match.range, in: body),
                      let start = AttributedString.Index(sourceRange.lowerBound, within: result),
                      let end = AttributedString.Index(sourceRange.upperBound, within: result) else { continue }
                result[start..<end].link = URL(string: "soom-mention://profile/\(reference.userID.uuidString)")
            }
        }
        return result
    }
}

/// A request survives uncertain results. Editing cannot silently turn a retry
/// into a second submission; callers must resolve the original ID first.
struct FeedCommentPendingRequest: Equatable, Codable {
    let id: UUID
    let postID: UUID
    let viewerID: UUID
    let body: String
    let parentID: UUID?
    let mentions: [FeedMentionDraft.Selection]
    init(id: UUID = UUID(), postID: UUID, viewerID: UUID, body: String, parentID: UUID?, mentions: [FeedMentionDraft.Selection]) {
        self.id = id; self.postID = postID; self.viewerID = viewerID
        self.body = body; self.parentID = parentID; self.mentions = mentions
    }
    func matches(postID: UUID, viewerID: UUID, body: String, parentID: UUID?, mentions: [FeedMentionDraft.Selection]) -> Bool {
        self.postID == postID && self.viewerID == viewerID && self.body == body && self.parentID == parentID && self.mentions == mentions
    }
}

/// Account/post-scoped durable retry state, never sent to another account.
/// Clear only after an authoritative acknowledgement/read, not on view dismissal.
enum FeedCommentPendingStore {
    private static func key(viewer: UUID, post: UUID) -> String { "soom.comment.pending.v1.\(viewer.uuidString).\(post.uuidString)" }
    enum StoreError: Error { case invalidScope }
    static func read(viewer: UUID, post: UUID, defaults: UserDefaults = .standard) throws -> FeedCommentPendingRequest? {
        guard let data = defaults.data(forKey: key(viewer: viewer, post: post)) else { return nil }
        let request = try JSONDecoder().decode(FeedCommentPendingRequest.self, from: data)
        guard request.viewerID == viewer, request.postID == post else { throw StoreError.invalidScope }
        return request
    }
    static func save(_ request: FeedCommentPendingRequest, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(request), forKey: key(viewer: request.viewerID, post: request.postID))
    }
    static func clear(viewer: UUID, post: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(viewer: viewer, post: post))
    }
}

enum FeedCommentFailurePolicy {
    static func isDefinitiveFirstRejection(code: String?) -> Bool {
        code == "22023" || code == "42501"
    }
}

/// Unknown states fail decoding. No generic/null response authorizes resending.
enum FeedCommentRecoveryState: String, Decodable {
    case found, absent, unavailable
    func permitsRetry(_ pending: FeedCommentPendingRequest, postID: UUID, viewerID: UUID,
                      body: String, parentID: UUID?, mentions: [FeedMentionDraft.Selection]) -> Bool {
        self == .absent && pending.matches(postID: postID, viewerID: viewerID,
            body: body, parentID: parentID, mentions: mentions)
    }
}
