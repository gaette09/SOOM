import Foundation
import Supabase

protocol SupabaseAuthSessionReading {
    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo?
}

struct SupabaseClientSessionReader: SupabaseAuthSessionReading {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func readCurrentSession() async throws -> SupabaseAuthSessionProbe.SessionInfo? {
        guard let session = client.auth.currentSession else {
            return nil
        }

        return SupabaseAuthSessionProbe.SessionInfo(
            userId: session.user.id.uuidString,
            email: session.user.email
        )
    }
}

struct SupabaseAuthSessionProbe {
    struct SessionInfo: Equatable {
        let userId: String
        let email: String?
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
                status: .signedIn
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
