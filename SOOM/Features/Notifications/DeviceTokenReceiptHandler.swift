import Foundation
import Combine

@MainActor
final class PushRegistrationStatus: ObservableObject {
    static let shared = PushRegistrationStatus()
    enum State: Equatable { case signedOut, awaitingToken, registering, registered, legacyRegistered, failed, apnsFailed }
    enum Permission: Equatable { case unknown, notDetermined, denied, allowed }
    @Published var state: State = .signedOut
    @Published var permission: Permission = .unknown
    var retryAction: (() -> Void)?
    var message: String {
        switch state {
        case .signedOut: return "로그인하면 이 기기의 알림 수신을 등록해요."
        case .awaitingToken: return "iPhone의 기기 등록 응답을 기다리고 있어요."
        case .registering: return "이 기기의 알림 수신을 서버에 등록하고 있어요."
        case .registered: return "기기 등록 완료 · 실제 수신 여부는 별도 확인이 필요해요."
        case .legacyRegistered: return "기본 알림 등록 완료 · 확장 알림 서버 업데이트를 기다리고 있어요."
        case .failed: return "기기 등록을 저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요."
        case .apnsFailed: return "iPhone 기기 등록에 실패했어요. 연결과 알림 설정을 확인하고 다시 시도해 주세요."
        }
    }
    var permissionMessage: String {
        switch permission {
        case .unknown: return "iPhone 알림 권한 확인 필요"
        case .notDetermined: return "알림 표시 권한을 아직 선택하지 않았어요."
        case .denied: return "알림 표시가 꺼져 있어요. iPhone 설정에서 허용할 수 있어요."
        case .allowed: return "알림 표시 허용 · 집중 모드 등 iPhone 설정에 따라 표시가 달라질 수 있어요."
        }
    }
}

enum DeviceRegistrationError: Error { case accountChanged, extendedServiceUnavailable }

/// Token values stay private. Stale completions cannot change another account's
/// status; token-before-login and login-before-token both converge here.
@MainActor
final class DeviceTokenReceiptHandler {
    private let store: DeviceTokenStore
    private let registrar: any DeviceTokenRegistering
    private let status: PushRegistrationStatus
    private var currentUser: AppUser?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var inFlightToken: String?
    private var registeredToken: String?
    private var apnsFailedBeforeLogin=false

    init(store: DeviceTokenStore, registrar: any DeviceTokenRegistering, status: PushRegistrationStatus? = nil) {
        self.store = store; self.registrar = registrar; self.status = status ?? .shared
        self.status.retryAction = { [weak self] in self?.retry() }
    }
    func received(tokenHex: String, currentUser: AppUser?) {
        apnsFailedBeforeLogin=false
        store.cache(tokenHex: tokenHex)
        setUser(currentUser)
        register(tokenHex)
    }
    func loginStateChanged(currentUser: AppUser?) {
        setUser(currentUser)
        guard currentUser?.authProvider == .supabase else { return }
        guard let token = store.cachedTokenHex else { registeredToken=nil;status.state = apnsFailedBeforeLogin ? .apnsFailed:.awaitingToken; return }
        register(token)
    }
    func registrationFailed() {
        apnsFailedBeforeLogin=true
        guard currentUser?.authProvider == .supabase else { return }
        status.state = .apnsFailed
    }
    func retry() {
        registeredToken = nil
        guard currentUser?.authProvider == .supabase else { status.state = .signedOut; return }
        guard let token = store.cachedTokenHex else { status.state = .awaitingToken; return }
        register(token)
    }
    private func setUser(_ user: AppUser?) {
        if currentUser?.id != user?.id || currentUser?.authProvider != user?.authProvider {
            generation = UUID(); task?.cancel(); task = nil; inFlightToken = nil; registeredToken = nil
            status.state = user?.authProvider == .supabase ? .awaitingToken : .signedOut
        }
        currentUser = user
    }
    private func register(_ token: String) {
        guard currentUser?.authProvider == .supabase, let owner = currentUser?.id else { status.state = .signedOut; return }
        guard registeredToken != token, inFlightToken != token else { return }
        task?.cancel(); inFlightToken = token; status.state = .registering
        let revision = generation
        task = Task { [weak self, registrar] in
            var result: PushRegistrationStatus.State = .registered
            do { try await registrar.upsert(tokenHex: token, userId: owner) }
            catch DeviceRegistrationError.extendedServiceUnavailable { result = .legacyRegistered }
            catch { result = .failed }
            guard let self, !Task.isCancelled, self.generation == revision,
                  self.currentUser?.id == owner, self.currentUser?.authProvider == .supabase else { return }
            self.inFlightToken = nil
            self.registeredToken = result == .registered || result == .legacyRegistered ? token : nil
            self.status.state = result
        }
    }
}
