import SwiftUI

/// Typed-confirmation gate for the account-deletion danger-zone action.
/// Copy branches on `isGuestUser` per SOOM's existing tone: logged-in users
/// see "계정 삭제" (Supabase account + local data), guest users see "기기
/// 데이터 초기화" (local data only) — reusing the "초기화" wording already
/// used for the lighter, non-destructive "로컬 세션 초기화" action elsewhere
/// in `SettingsView`, so the two read as clearly different in severity.
struct AccountDeletionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    let isGuestUser: Bool
    let onConfirm: () -> Void

    init(isGuestUser: Bool, onConfirm: @escaping () -> Void) {
        self.isGuestUser = isGuestUser; self.onConfirm = onConfirm
    }
    #if DEBUG
    /// Local native-render test input; never available in a Release build.
    init(isGuestUser: Bool, reviewConfirmationText: String, onConfirm: @escaping () -> Void) {
        self.isGuestUser = isGuestUser; self.onConfirm = onConfirm
        _confirmationText = State(initialValue: reviewConfirmationText)
    }
    #endif
    private static let requiredConfirmationText = "삭제"

    private var title: String {
        isGuestUser ? "기기 데이터 초기화" : "계정 삭제"
    }

    private var explanation: String {
        isGuestUser
            ? "이 기기의 운동·경로·체크인·회복 기록, 공유 초안과 설정을 삭제해요. 온라인 계정과 Apple 건강 앱의 원본은 그대로 유지됩니다."
            : "온라인 계정과 게시물·소유한 클럽, 이 기기의 운동·경로·체크인·회복 기록과 설정을 삭제해요. 소유한 클럽의 다른 멤버도 해당 클럽에 접근할 수 없게 됩니다. Apple 건강 앱의 원본은 유지됩니다."
    }

    private var confirmButtonTitle: String {
        isGuestUser ? "기기 데이터 초기화하기" : "계정 삭제하기"
    }

    private var canConfirm: Bool {
        Self.acceptsConfirmation(confirmationText)
    }

    static func acceptsConfirmation(_ text: String) -> Bool {
        text == requiredConfirmationText
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(soom: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SOOMColor.warning)
                    .frame(width: 44, height: 44)
                    .background(SOOMColor.warning.opacity(0.14))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(soom: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(SOOMFont.body(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Text(explanation)
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Text("계속하려면 \"\(Self.requiredConfirmationText)\"를 입력하세요")
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)

                TextField(Self.requiredConfirmationText, text: $confirmationText,
                          prompt: Text(Self.requiredConfirmationText).foregroundColor(SOOMColor.secondaryInk))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
                    .accessibilityIdentifier("deletion.confirmation.input")
                    .padding(SOOMLayout.Spacing.lg)
                    .background(SOOMColor.surfaceAmbient)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }

            Button {
                onConfirm()
                dismiss()
            } label: {
                Text(confirmButtonTitle)
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(canConfirm ? SOOMColor.ink : SOOMColor.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(canConfirm ? SOOMColor.warning : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(ReadableDeletionConfirmationStyle())
            .disabled(!canConfirm)
            .accessibilityIdentifier("deletion.confirmation.confirm")
        }
        .padding(SOOMLayout.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SOOMColor.background)
    }
}

#Preview("AccountDeletionConfirmationSheet - Guest") {
    AccountDeletionConfirmationSheet(isGuestUser: true, onConfirm: {})
}

#Preview("AccountDeletionConfirmationSheet - Supabase") {
    AccountDeletionConfirmationSheet(isGuestUser: false, onConfirm: {})
}

/// Preserve the declared disabled contrast while retaining the system disabled
/// action and accessibility semantics. PlainButtonStyle otherwise dims it again.
private struct ReadableDeletionConfirmationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
