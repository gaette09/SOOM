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

    private static let requiredConfirmationText = "삭제"

    private var title: String {
        isGuestUser ? "기기 데이터 초기화" : "계정 삭제"
    }

    private var explanation: String {
        isGuestUser
            ? "이 기기에 저장된 운동 기록, route, 만든 클럽, 설정이 모두 삭제되며 되돌릴 수 없어요. 서버에는 저장된 데이터가 없어요."
            : "Supabase 계정과 이 기기에 저장된 운동 기록, route, 만든 클럽, 설정이 모두 삭제되며 되돌릴 수 없어요."
    }

    private var confirmButtonTitle: String {
        isGuestUser ? "기기 데이터 초기화하기" : "계정 삭제하기"
    }

    private var canConfirm: Bool {
        confirmationText == Self.requiredConfirmationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
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
                    Image(systemName: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 32, height: 32)
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

                TextField(Self.requiredConfirmationText, text: $confirmationText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
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
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(canConfirm ? SOOMColor.warning : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}

#Preview("AccountDeletionConfirmationSheet - Guest") {
    AccountDeletionConfirmationSheet(isGuestUser: true, onConfirm: {})
}

#Preview("AccountDeletionConfirmationSheet - Supabase") {
    AccountDeletionConfirmationSheet(isGuestUser: false, onConfirm: {})
}
