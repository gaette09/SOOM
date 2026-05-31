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
        let content = view
            .frame(width: width)
            .frame(width: width, height: width / ShareableWorkoutCardLayout.aspectRatio)
            .background(background)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale ?? ShareableWorkoutCardLayout.exportScale
        renderer.isOpaque = isOpaque

        return renderer.uiImage
    }

    func render(card: ShareableWorkoutCardModel, tint: Color) -> UIImage? {
        render(
            ShareableWorkoutCardView(card: card, tint: tint)
                .environment(\.colorScheme, .light),
            background: card.backgroundOption == .transparent ? .clear : SOOMColor.background,
            isOpaque: card.backgroundOption != .transparent
        )
    }
}
