import SwiftUI

struct EmailAuthCard: View {
    @StateObject private var viewModel: EmailAuthViewModel

    
    init(viewModel: EmailAuthViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    
    init(environment: AuthEnvironment = AuthEnvironmentLoader().load()) {
        _viewModel = StateObject(wrappedValue: EmailAuthViewModel(environment: environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            SOOMActionRow(
                icon: "envelope",
                title: "이메일 계정 연결",
                subtitle: "로그인 링크 요청만 준비됐고, 현재 기록은 로컬에 유지돼요.",
                tint: SOOMColor.recovery
            )

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                TextField("email@example.com", text: $viewModel.emailText)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .padding(SOOMLayout.Metrics.pillPadding)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    Text(viewModel.isSending ? "링크 보내는 중" : "이메일로 로그인 링크 받기")
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SOOMLayout.Card.padding)
                        .background(viewModel.isSending ? SOOMColor.secondaryInk : SOOMColor.recovery)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
            }

            Text(statusText)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("계정 연결 후 데이터 동기화와 소유권 연결은 다음 단계에서 명시적으로 진행됩니다.")
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if let successMessage = viewModel.successMessage { return successMessage }
        if let errorMessage = viewModel.errorMessage { return errorMessage }
        return "Apple/Google 로그인은 준비 중이고, 비밀번호 로그인과 회원가입은 아직 연결하지 않았어요."
    }

    private var statusColor: Color {
        viewModel.errorMessage == nil ? SOOMColor.secondaryInk : SOOMColor.warning
    }
}

#Preview("EmailAuthCard") {
    SOOMScreen {
        SOOMCard {
            EmailAuthCard()
        }
    }
}
