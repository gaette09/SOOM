import SwiftUI

struct FeedCommentListView: View {
    @Environment(\.dismiss) private var dismiss
    let comments: [FeedComment]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SOOMLayout.screenPadding)
                .padding(.top, SOOMLayout.screenPadding)
                .padding(.bottom, SOOMLayout.Spacing.lg)

            if comments.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: SOOMLayout.Spacing.md) {
                        ForEach(comments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(.horizontal, SOOMLayout.screenPadding)
                    .padding(.bottom, SOOMLayout.Screen.bottomPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SOOMColor.background)
    }

    private var header: some View {
        HStack {
            Text("댓글 \(comments.count)개")
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
    }

    private var emptyState: some View {
        VStack(spacing: SOOMLayout.Spacing.sm) {
            Text("아직 댓글이 없어요")
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)

            Text("첫 댓글을 남겨보세요.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commentRow(_ comment: FeedComment) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Spacing.sm) {
            HStack(spacing: SOOMLayout.Spacing.sm) {
                Text(comment.isViewerAuthor ? "나" : "멤버")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)

                Text(relativeTimeText(for: comment.createdAt))
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Text(comment.body)
                .font(SOOMFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.lg)
        .background(SOOMColor.surfaceAmbient)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func relativeTimeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("FeedCommentListView") {
    FeedCommentListView(
        comments: [
            FeedComment(
                id: UUID(),
                authorId: UUID(),
                body: "오늘 페이스가 정말 안정적이었어요.",
                createdAt: Date().addingTimeInterval(-3_600),
                isViewerAuthor: false
            ),
            FeedComment(
                id: UUID(),
                authorId: UUID(),
                body: "응원 고마워요! 다음 운동도 꾸준히 이어갈게요.",
                createdAt: Date().addingTimeInterval(-1_800),
                isViewerAuthor: true
            ),
            FeedComment(
                id: UUID(),
                authorId: UUID(),
                body: "좋은 흐름이에요.",
                createdAt: Date().addingTimeInterval(-300),
                isViewerAuthor: false
            )
        ]
    )
}
