import Foundation

protocol NotificationInboxFetching {
    func fetchNotifications() async throws -> [NotificationDTO]
    func markAllNotificationsAsRead() async throws
}

enum NotificationKind: String, Codable, Equatable {
    case reaction
    case comment
}

struct NotificationDTO: Codable, Equatable, Identifiable {
    let id: UUID
    let recipientId: UUID
    let actorId: UUID?
    let type: NotificationKind
    let postId: UUID?
    let body: String?
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipientId = "recipient_id"
        case actorId = "actor_id"
        case type
        case postId = "post_id"
        case body
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}
