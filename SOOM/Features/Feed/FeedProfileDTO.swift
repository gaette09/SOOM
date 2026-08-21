import Foundation

protocol FeedRemoteProfileFetching {
    func fetchProfiles(ids: [UUID]) async throws -> [FeedProfileDTO]
}

struct FeedProfileDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let handle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handle
    }
}
