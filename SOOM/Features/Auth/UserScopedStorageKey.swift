import Foundation

struct UserScopedStorageKey: Equatable {
    let namespace: String
    let userId: UUID?
    let rawKey: String

    var value: String {
        guard let userId else {
            return "\(namespace).local.\(rawKey)"
        }
        return "\(namespace).user.\(userId.uuidString).\(rawKey)"
    }

    static func auth(_ rawKey: String, userId: UUID? = nil) -> UserScopedStorageKey {
        UserScopedStorageKey(namespace: "auth", userId: userId, rawKey: rawKey)
    }

    static func training(_ rawKey: String, userId: UUID? = nil) -> UserScopedStorageKey {
        UserScopedStorageKey(namespace: "training", userId: userId, rawKey: rawKey)
    }
}
