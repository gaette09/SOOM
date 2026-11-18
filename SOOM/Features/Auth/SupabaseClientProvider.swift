import Foundation
import Supabase

struct SupabaseClientProvider {
    enum ClientState: Equatable {
        case ready
        case unconfigured
    }

    private let configuration: SupabaseAuthConfiguration
    private let clientRegistry: SupabaseAppClientRegistry

    init(
        configuration: SupabaseAuthConfiguration = .empty,
        clientRegistry: SupabaseAppClientRegistry = .shared
    ) {
        self.configuration = configuration
        self.clientRegistry = clientRegistry
    }

    init(environment: AuthEnvironment) {
        self.configuration = SupabaseAuthConfiguration.from(environment: environment)
        self.clientRegistry = .shared
    }

    /// Install SOOMApp's auth-owned client before constructing feature clients.
    /// Matching features then observe the same in-memory login/logout session.
    static func installAppClient(_ client: SupabaseClient?, configuration: SupabaseAuthConfiguration) {
        SupabaseAppClientRegistry.shared.install(client, configuration: configuration)
    }

    var state: ClientState {
        configuration.isConfigured ? .ready : .unconfigured
    }

    /// Response-version opt-in only. It never replaces authentication or RLS.
    /// The server also requires its separately controlled activation state.
    static func clientOptions(session: URLSession = LoadNetworkMetrics.session) -> SupabaseClientOptions {
        SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true),
            global: .init(headers: ["x-soom-feed-contract": "mutual-v1", "x-soom-social-contract": "approved-v1", "x-soom-workout-contract": "detail-v1"], session: session))
    }

    func makeClient() -> SupabaseClient? {
        guard !ReviewDemoMode.isActive else { return nil }
        guard configuration.isConfigured, let projectURL = configuration.projectURL, let anonKey = configuration.anonKey else {
            return nil
        }
        PhotoNoCacheURLProtocol.register(projectURL: projectURL)
        if let client = clientRegistry.client(for: configuration) { return client }
        return SupabaseClient(
            supabaseURL: projectURL, supabaseKey: anonKey,
            options: Self.clientOptions()
        )
    }
}

/// One active app environment. A lock protects configuration/client as a pair;
/// clients for unrelated configurations never inherit the app's auth session.
final class SupabaseAppClientRegistry: @unchecked Sendable {
    static let shared = SupabaseAppClientRegistry()
    private let lock = NSLock()
    private var registration: (configuration: SupabaseAuthConfiguration, client: SupabaseClient)?

    func install(_ client: SupabaseClient?, configuration: SupabaseAuthConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        guard let client, configuration.isConfigured else {
            registration = nil
            return
        }
        registration = (configuration, client)
    }

    func client(for configuration: SupabaseAuthConfiguration) -> SupabaseClient? {
        lock.lock()
        defer { lock.unlock() }
        guard registration?.configuration == configuration else { return nil }
        return registration?.client
    }
}
