import SwiftUI

/// A small unread-count badge overlaid on the top-trailing corner of any
/// icon view. Generic on purpose — the notification-inbox batch is its
/// first caller (the Feed bell icon), but nothing here is Feed-specific,
/// so any other icon (tab bar items, other header buttons) can reuse it
/// as-is via `.soomBadge(count:)`.
private struct SOOMBadgeModifier: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count > 9 ? "9+" : "\(count)")
                    .font(SOOMFont.body(9, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(SOOMColor.warning)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(SOOMColor.white, lineWidth: 1.5)
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Overlays an unread-count badge (a small capsule, "9+" past 9, hidden
    /// at 0) on this view's top-trailing corner.
    func soomBadge(count: Int) -> some View {
        modifier(SOOMBadgeModifier(count: count))
    }
}
