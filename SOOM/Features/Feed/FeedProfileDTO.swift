import Foundation

protocol FeedRemoteProfileFetching {
    func fetchProfiles(ids: [UUID]) async throws -> [FeedProfileDTO]
}

struct FeedProfileDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let handle: String?
    var avatarPath: String? = nil

    init(id: UUID, displayName: String, handle: String?, avatarPath: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarPath = avatarPath
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
        case avatarPath = "avatar_path"
    }
}
