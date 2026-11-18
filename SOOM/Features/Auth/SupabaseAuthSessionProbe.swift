import Foundation
import Supabase

protocol SupabaseAuthSessionReading {
    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo?
}

struct SupabaseClientSessionReader: SupabaseAuthSessionReading {
    private let client: SupabaseClient

    private let includesProfile: Bool

    init(client: SupabaseClient) {
        self.init(client: client, includesProfile: true)
    }

    init(client: SupabaseClient, includesProfile: Bool) {
        self.client = client
        self.includesProfile = includesProfile
    }

    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo? {
        guard let session = client.auth.currentSession else {
            return nil
        }

        // The SDK's existing session supplies identity. Optional network profile
        // reads must not prevent opening that account's local records at startup.
        let profile = SupabaseProfileStore(client: client)
        let displayName = includesProfile
            ? await profile.readDisplayName(expectedUserID: session.user.id)
            : profile.cachedDisplayName(expectedUserID: session.user.id)
        let avatarPath = includesProfile
            ? await profile.readAvatarPath(expectedUserID: session.user.id) : nil
        // A profile fetch must never publish a session replaced during its await.
        guard client.auth.currentSession?.user.id == session.user.id else { return nil }
        let appleAccount = SupabaseAppleAccountMetadata(user: session.user)
        return SupabaseAuthSessionProbe.SessionInfo(
            userId: session.user.id.uuidString,
            email: session.user.email,
            displayName: displayName ?? session.user.userMetadata["full_name"]?.stringValue,
            appleUserIdentifier: appleAccount.userIdentifier,
            linkedAuthProviders: appleAccount.providers,
            avatarPath: avatarPath
        )
    }
}

struct SupabaseAuthSessionProbe {
    struct SessionInfo: Equatable {
        let userId: String
        let email: String?
        var displayName: String? = nil
        var appleUserIdentifier: String? = nil
        var linkedAuthProviders: [String]? = nil
        var avatarPath: String? = nil
    }

    private let isConfigured: Bool
    private let reader: (any SupabaseAuthSessionReading)?
    private let now: () -> Date

    init(clientProvider: SupabaseClientProvider, now: @escaping () -> Date = { Date() }) {
        self.isConfigured = clientProvider.state == .ready
        if let client = clientProvider.makeClient() {
            self.reader = SupabaseClientSessionReader(client: client)
        } else {
            self.reader = nil
        }
        self.now = now
    }

    init(
        isConfigured: Bool,
        reader: (any SupabaseAuthSessionReading)?,
        now: @escaping () -> Date = { Date() }
    ) {
        self.isConfigured = isConfigured
        self.reader = reader
        self.now = now
    }

    func checkSessionStatus() async -> SupabaseAuthSessionSnapshot {
        guard isConfigured else {
            return snapshot(status: .unconfigured, hasSession: false)
        }

        guard let reader else {
            return snapshot(status: .failed, hasSession: false)
        }

        do {
            guard let sessionInfo = try await reader.readCurrentSession() else {
                return snapshot(status: .signedOut, hasSession: false)
            }

            return SupabaseAuthSessionSnapshot(
                isConfigured: true,
                hasSession: true,
                userId: sessionInfo.userId,
                email: sessionInfo.email,
                checkedAt: now(),
                status: .signedIn,
                displayName: sessionInfo.displayName,
                appleUserIdentifier: sessionInfo.appleUserIdentifier,
                linkedAuthProviders: sessionInfo.linkedAuthProviders,
                avatarPath: sessionInfo.avatarPath
            )
        } catch {
            return snapshot(status: .failed, hasSession: false)
        }
    }

    private func snapshot(status: SupabaseAuthSessionSnapshot.Status, hasSession: Bool) -> SupabaseAuthSessionSnapshot {
        SupabaseAuthSessionSnapshot(
            isConfigured: isConfigured,
            hasSession: hasSession,
            userId: nil,
            email: nil,
            checkedAt: now(),
            status: status
        )
    }
}

/// Authenticated Supabase identity metadata, never email or a display-name guess.
struct SupabaseAppleAccountMetadata {
    let userIdentifier: String?
    let providers: [String]

    init(user: User) {
        let identity = user.identities?.first { $0.provider == "apple" }
        let subject = identity?.identityData?["sub"]?.stringValue ?? identity?.id
        let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        userIdentifier = trimmedSubject?.isEmpty == false ? trimmedSubject : nil
        var linked = user.identities?.map(\.provider) ?? []
        linked += user.appMetadata["providers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if let provider = user.appMetadata["provider"]?.stringValue { linked.append(provider) }
        providers = Array(Set(linked)).sorted()
    }
}
