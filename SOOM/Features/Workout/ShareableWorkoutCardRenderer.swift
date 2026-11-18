import Foundation
import SwiftUI
import UIKit

@MainActor
struct ShareableWorkoutCardRenderer {
    func render<V: View>(
        _ view: V,
        width: CGFloat = ShareableWorkoutCardLayout.exportWidth,
        scale: CGFloat? = nil,
        background: Color = SOOMColor.background,
        isOpaque: Bool = true
    ) -> UIImage? {
        let height = width / ShareableWorkoutCardLayout.aspectRatio
        let content = view
            .frame(width: width, height: height)
            .clipped()
            .background(background)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale ?? ShareableWorkoutCardLayout.exportScale
        renderer.isOpaque = isOpaque

        return renderer.uiImage
    }

    func render(card: ShareableWorkoutCardModel, tint: Color, resolvedRouteImage: UIImage? = nil) -> UIImage? {
        guard card.canExportShareImage else { return nil }
        return render(
            ShareableWorkoutCardView(card: card, tint: tint, resolvedRouteImage: resolvedRouteImage)
                .environment(\.colorScheme, .light),
            background: card.backgroundOption == .transparent ? .clear : SOOMColor.background,
            isOpaque: card.backgroundOption != .transparent
        )
    }

    func renderPrepared(card: ShareableWorkoutCardModel, tint: Color) async -> UIImage? {
        // Draw only the selected workout's masked coordinates locally.
        // No network image request or asynchronous image cache can change it.
        render(card: card, tint: tint)
    }
}
