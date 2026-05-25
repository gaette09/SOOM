import Foundation
import Supabase

struct SupabaseClientProvider {
    enum ClientState: Equatable {
        case ready
        case unconfigured
    }

    private let configuration: SupabaseAuthConfiguration

    init(configuration: SupabaseAuthConfiguration = .empty) {
        self.configuration = configuration
    }

    init(environment: AuthEnvironment) {
        self.configuration = SupabaseAuthConfiguration.from(environment: environment)
    }

    var state: ClientState {
        configuration.isConfigured ? .ready : .unconfigured
    }

    func makeClient() -> SupabaseClient? {
        guard configuration.isConfigured, let projectURL = configuration.projectURL, let anonKey = configuration.anonKey else {
            return nil
        }
        return SupabaseClient(supabaseURL: projectURL, supabaseKey: anonKey)
    }
}
