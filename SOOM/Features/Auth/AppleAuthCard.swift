import SwiftUI
import AuthenticationServices

struct AppleAuthCard: View {
    @ObservedObject var authViewModel: AuthViewModel
    private let provider = AppleSignInProvider()
    @State private var currentNonce: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            SOOMActionRow(
                icon: "apple.logo",
                title: authViewModel.session.currentUser?.authProvider == .supabase ? "Apple 계정 연결됨" : "Apple로 로그인",
                subtitle: "계정 연결 후에도 현재 기록은 로컬에 유지돼요. 데이터 동기화는 다음 단계입니다.",
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
            return "계정은 연결됐지만 로컬 운동 기록의 소유권 이전과 동기화는 아직 진행하지 않아요."
        }

        return "Apple 로그인은 계정 연결 상태만 확인하고, 로컬 운동 기록은 그대로 유지합니다."
    }
}

#Preview("AppleAuthCard") {
    SOOMScreen {
        SOOMCard {
            AppleAuthCard(authViewModel: AuthViewModel())
        }
    }
}
