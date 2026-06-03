import Foundation

struct SupabaseAppUserMapper {
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func map(snapshot: SupabaseAuthSessionSnapshot) -> AppUser? {
        guard snapshot.status == .signedIn,
              snapshot.hasSession,
              let userId = snapshot.userId,
              !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        guard let userUUID = userIdentifier(from: userId) else {
            return nil
        }

        let email = normalizedEmail(snapshot.email)
        return AppUser(
            id: userUUID,
            displayName: displayName(from: email, fallbackUserId: userId),
            handle: email.map { "@\($0)" },
            email: email,
            authProvider: .supabase,
            createdAt: now()
        )
    }

    private func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func displayName(from email: String?, fallbackUserId: String) -> String {
        if let prefix = email?.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }

        let trimmedId = fallbackUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId.count >= 8 {
            return "SOOM \(trimmedId.prefix(8))"
        }

        return "SOOM 사용자"
    }

    private func userIdentifier(from userId: String) -> UUID? {
        UUID(uuidString: userId.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
