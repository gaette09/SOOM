import SwiftUI

/// Minimal comment composer presented from a feed card's "댓글" action.
/// `feed_comments.body` is capped at 500 characters by the DB check
/// constraint, mirrored here so the button disables before a submit would
/// fail server-side.
struct FeedCommentComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var commentText = ""
    let onSubmit: (String) -> Void

    private static let maxLength = 500

    private var trimmedText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedText.isEmpty && trimmedText.count <= Self.maxLength
    }

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
                    Image(systemName: SOOMIcon.close)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
            }

            TextField("응원하는 마음을 남겨보세요", text: $commentText, axis: .vertical)
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .lineLimit(4, reservesSpace: true)
                .padding(SOOMLayout.Spacing.lg)
                .background(SOOMColor.surfaceAmbient)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))

            Text("\(trimmedText.count)/\(Self.maxLength)")
                .font(SOOMFont.body(11, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.tertiaryInk)

            Button {
                onSubmit(trimmedText)
                dismiss()
            } label: {
                Text("댓글 남기기")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(canSubmit ? SOOMColor.accent : SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            Spacer(minLength: 0)
        }
        .padding(SOOMLayout.screenPadding)
        .background(SOOMColor.background)
    }
}

#Preview("FeedCommentComposeSheet") {
    FeedCommentComposeSheet(onSubmit: { _ in })
}
