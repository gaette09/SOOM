import SwiftUI

/// Minimal comment composer presented from a feed card's "댓글" action.
/// `feed_comments.body` is capped at 500 characters by the DB check
/// constraint, mirrored here so the button disables before a submit would
/// fail server-side.
struct FeedCommentComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var safetyStore = CommunitySafetyStore.shared
    @StateObject private var viewModel = FeedCommentComposeViewModel()
    let onSubmit: (String) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
            HStack {
                Text("댓글 남기기")
                    .font(SOOMFont.body(18, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(SOOMColor.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(soom: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
                .disabled(viewModel.isSubmitting)
            }

            TextField("응원하는 마음을 남겨보세요", text: $viewModel.text, axis: .vertical)
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .lineLimit(4, reservesSpace: true)
                .disabled(viewModel.isSubmitting)
                .padding(SOOMLayout.Spacing.lg)
                .background(SOOMColor.surfaceAmbient)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

            Text("\(viewModel.trimmedText.count)/500")
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(SOOMFont.body(13, relativeTo: .caption))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("feed.comment.error")
            }

            Button {
                Task {
                    if await viewModel.submit(using: onSubmit) { dismiss() }
                }
            } label: {
                Text(viewModel.isSubmitting ? "댓글 보내는 중…" : "댓글 남기기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(viewModel.canSubmit ? SOOMColor.accent : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .onChange(of: safetyStore.accountGeneration) { _, _ in dismiss() }
    }
}

#Preview("FeedCommentComposeSheet") {
    FeedCommentComposeSheet(onSubmit: { _ in })
}
