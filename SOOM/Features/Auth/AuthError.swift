import Foundation

enum AuthError: Error, Equatable {
    case unsupportedProvider(AuthProvider)
    case invalidDisplayName
    case sessionNotFound
    case futureRemoteAuthNotConfigured
    case unknown(String)

    var userMessage: String {
        switch self {
        case .unsupportedProvider(let provider):
            return "\(provider.title)은 아직 준비 중이에요. 지금은 로컬 사용자로 계속 이용할 수 있어요."
        case .invalidDisplayName:
            return "표시 이름을 입력해주세요."
        case .sessionNotFound:
            return "사용자 정보를 찾지 못했어요. 로컬 사용자로 다시 시작할 수 있어요."
        case .futureRemoteAuthNotConfigured:
            return "계정 연결은 이후 단계에서 연결할 예정이에요. 지금은 로컬 사용자로 안전하게 기록을 이어갈 수 있어요."
        case .unknown(let message):
            return message.isEmpty ? "계정 상태를 확인하지 못했어요." : message
        }
    }
}
