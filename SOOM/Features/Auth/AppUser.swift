import Foundation

enum AuthProvider: String, Codable, Equatable, CaseIterable {
    case local
    case apple
    case google
    case supabase
    case supabaseFuture

    var title: String {
        switch self {
        case .local:
            return "로컬 사용자"
        case .apple:
            return "Apple 로그인"
        case .google:
            return "Google 로그인"
        case .supabase:
            return "원격 계정"
        case .supabaseFuture:
            return "계정 연결 준비 중"
        }
    }
}

struct AppUser: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var handle: String?
    var email: String?
    let authProvider: AuthProvider
    let createdAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String? = nil,
        email: String? = nil,
        authProvider: AuthProvider = .local,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.email = email
        self.authProvider = authProvider
        self.createdAt = createdAt
    }
}
