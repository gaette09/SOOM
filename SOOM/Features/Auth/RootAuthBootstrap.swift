import Foundation

@MainActor
final class RootAuthBootstrap: ObservableObject {
    enum State: Equatable {
        case idle
        case bootstrapping
        case completed
    }

    @Published private(set) var state: State = .idle

    private let initializeSession: @MainActor () async -> Void
    private var bootstrapTask: Task<Void, Never>?

    init(authViewModel: AuthViewModel) {
        self.initializeSession = {
            await authViewModel.initializeSession()
        }
    }

    init(initializeSession: @escaping @MainActor () async -> Void) {
        self.initializeSession = initializeSession
    }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        guard state != .completed else {
            return
        }

        state = .bootstrapping
        let task = Task { @MainActor [initializeSession] in
            await initializeSession()
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
        state = .completed
    }
}
