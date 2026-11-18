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
                title: "이메일로 로그인",
                subtitle: "이메일로 받은 링크를 열면 로그인됩니다.",
                tint: SOOMColor.accent
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
                        .background(viewModel.isSending ? SOOMColor.secondaryInk : SOOMColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
            }

            Text(statusText)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("로그인 후 내 기록 동기화에서 건강 기록 전송에 동의하고 로그인 전 기록을 직접 가져올 수 있어요.")
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if let successMessage = viewModel.successMessage { return successMessage }
        if let errorMessage = viewModel.errorMessage { return errorMessage }
        return "비밀번호 없이 이메일로 로그인 링크를 받아요."
    }

    private var statusColor: Color {
        viewModel.errorMessage == nil ? SOOMColor.secondaryInk : SOOMColor.red
    }
}

#Preview("EmailAuthCard") {
    SOOMScreen {
        SOOMCard {
            EmailAuthCard()
        }
    }
}
