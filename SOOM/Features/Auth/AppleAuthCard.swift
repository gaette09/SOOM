import SwiftUI
import AuthenticationServices

struct AppleAuthCard: View {
    @ObservedObject var authViewModel: AuthViewModel
    private let provider = AppleSignInProvider()
    @State private var currentNonce: String?
    @ObservedObject private var grantState = AppleGrantRegistrationState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            SOOMActionRow(
                icon: "apple.logo",
                title: authViewModel.isCurrentAccountLinkedToApple ? "Apple 계정 연결됨" : "Apple로 로그인",
                subtitle: "로그인 후 내 기록 동기화에 동의하면 이 계정의 운동과 건강 기록을 서버에 보관해요.",
                tint: SOOMColor.secondaryInk
            )

            SignInWithAppleButton(.signIn) { request in
                let nonce = provider.makeNonce()
                currentNonce = nonce
                provider.configure(request, rawNonce: nonce)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    do {
                        let credential = try provider.credential(
                            from: authorization,
                            rawNonce: currentNonce ?? ""
                        )
                        Task {
                            await authViewModel.signInWithAppleCredential(credential)
                        }
                    } catch {
                        Task { @MainActor in
                            authViewModel.handleAppleSignInFailure(error)
                        }
                    }
                case .failure(let error):
                    Task { @MainActor in
                        authViewModel.handleAppleSignInFailure(error)
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            .disabled(authViewModel.isAppleSignInInProgress)
            .opacity(authViewModel.isAppleSignInInProgress ? 0.68 : 1)

            if authViewModel.isCurrentAccountLinkedToApple, let owner = authViewModel.session.currentUser?.id,
               grantState.status(for: owner) != .registered {
                Text("계정 삭제 시 Apple 연결을 자동으로 해제하기 위한 확인이 필요해요. 위 Apple 로그인으로 다시 확인할 수 있어요. 확인에 실패해도 현재 로그인은 유지됩니다.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusText)
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if authViewModel.isAppleSignInInProgress {
            return "Apple 계정 연결을 확인하는 중이에요."
        }

        if authViewModel.session.currentUser?.authProvider == .supabase {
            return "로그인 전 기록은 자동으로 옮기지 않아요. 내 기록 동기화에서 직접 가져올 수 있어요."
        }

        return "Apple로 계정을 연결해요. 로그인 전 기록은 별도로 보관하고, 동기화 여부를 직접 선택합니다."
    }
}

#Preview("AppleAuthCard") {
    SOOMScreen {
        SOOMCard {
            AppleAuthCard(authViewModel: AuthViewModel())
        }
    }
}
