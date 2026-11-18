import Foundation

@MainActor
final class RootAuthBootstrap: ObservableObject {
    enum State: Equatable {
        case idle
        case bootstrapping
        case completed
        case timedOut
    }

    @Published private(set) var state: State = .idle
    private let initializeSession: @MainActor () async -> Void
    private let timeoutNanoseconds: UInt64
    private var initializationTask: Task<Void, Never>?
    private var initializationFinished = false
    private var deadlineTask: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    convenience init(authViewModel: AuthViewModel) {
        self.init { await authViewModel.initializeSession() }
    }

    init(timeoutNanoseconds: UInt64 = 10_000_000_000,
         initializeSession: @escaping @MainActor () async -> Void) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.initializeSession = initializeSession
    }

    func bootstrap() async {
        guard state == .idle || state == .bootstrapping else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard state == .idle else { return }
            state = .bootstrapping
            if initializationFinished {
                finishWaiting(.completed)
                return
            }
            // Retain one initialization even after timeout. Retrying must not
            // start competing authentication operations or open a fallback owner.
            if initializationTask == nil {
                initializationTask = Task { @MainActor [weak self, initializeSession] in
                    let trace = LoadTrace("root-auth-bootstrap")
                    await initializeSession()
                    trace.mark("session-initialized")
                    guard let self else { return }
                    initializationFinished = true
                    initializationTask = nil
                    if state == .bootstrapping { finishWaiting(.completed) }
                }
            }
            deadlineTask = Task { @MainActor [weak self, timeoutNanoseconds] in
                do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.finishWaiting(.timedOut)
            }
        }
    }

    func retry() async {
        guard state == .timedOut else { return }
        state = .idle
        await bootstrap()
    }

    private func finishWaiting(_ result: State) {
        guard state == .bootstrapping else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        state = result
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
