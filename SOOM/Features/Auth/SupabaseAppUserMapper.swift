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

        let email = normalizedEmail(snapshot.email)
        return AppUser(
            id: userIdentifier(from: userId),
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
            return "Supabase \(trimmedId.prefix(8))"
        }

        return "Supabase 사용자"
    }

    private func userIdentifier(from userId: String) -> UUID {
        if let uuid = UUID(uuidString: userId) {
            return uuid
        }

        return UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    }
}
