import SwiftUI

/// Batch 1 of soom-notification-inbox. Marks everything unread as read the
/// moment this loads (product decision: whole-screen-on-open, not
/// per-row-tap) — `onMarkedAllRead` lets the caller (the Feed bell icon's
/// badge) reset to 0 immediately rather than waiting for a re-fetch.
struct NotificationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    let fetcher: (any NotificationInboxFetching)?
    let profileFetcher: (any FeedRemoteProfileFetching)?
    let onSelectPost: (UUID) -> Void
    let onMarkedAllRead: () -> Void

    @State private var items: [NotificationDTO] = []
    @State private var actorNames: [UUID: String] = [:]
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    emptyState
                } else {
                    List(items) { item in
                        Button {
                            guard let postId = item.postId else { return }
                            onSelectPost(postId)
                        } label: {
                            NotificationInboxRow(
                                item: item,
                                actorName: item.actorId.flatMap { actorNames[$0] } ?? "누군가"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(item.postId == nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task {
            await load()
        }
    }

    private var emptyState: some View {
        VStack(spacing: SOOMLayout.Spacing.sm) {
            Text("아직 알림이 없어요")
                .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.ink)
            Text("응원이나 댓글을 받으면 여기서 볼 수 있어요.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard let fetcher else {
            isLoading = false
            return
        }

        let fetched = (try? await fetcher.fetchNotifications()) ?? []
        items = fetched
        isLoading = false

        let actorIds = Array(Set(fetched.compactMap(\.actorId)))
        if let profileFetcher, !actorIds.isEmpty {
            let profiles = (try? await profileFetcher.fetchProfiles(ids: actorIds)) ?? []
            actorNames = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.displayName) })
        }

        if fetched.contains(where: { $0.readAt == nil }) {
            try? await fetcher.markAllNotificationsAsRead()
            onMarkedAllRead()
        }
    }
}

private struct NotificationInboxRow: View {
    let item: NotificationDTO
    let actorName: String

    private var message: String {
        switch item.type {
        case .reaction:
            return "\(actorName)님이 회원님의 운동에 응원을 보냈어요."
        case .comment:
            return "\(actorName)님이 회원님의 운동에 댓글을 남겼어요."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
            Image(systemName: item.type == .reaction ? "hand.thumbsup.fill" : "bubble.left.fill")
                .font(.system(size: SOOMFont.Size.body, weight: .semibold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 32, height: 32)
                .background(SOOMColor.accentMuted)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(item.readAt == nil ? SOOMColor.ink : SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, SOOMLayout.Spacing.xs)
    }
}
