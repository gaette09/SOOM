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
        render(
            ShareableWorkoutCardView(card: card, tint: tint, resolvedRouteImage: resolvedRouteImage)
                .environment(\.colorScheme, .light),
            background: card.backgroundOption == .transparent ? .clear : SOOMColor.background,
            isOpaque: card.backgroundOption != .transparent
        )
    }

    func renderPrepared(card: ShareableWorkoutCardModel, tint: Color) async -> UIImage? {
        let routeImage = await loadStaticRouteImage(for: card)
        return render(card: card, tint: tint, resolvedRouteImage: routeImage)
    }

    private func loadStaticRouteImage(for card: ShareableWorkoutCardModel) async -> UIImage? {
        guard card.backgroundOption == .mapPhoto,
              let imageURL = card.staticRoutePreview?.imageURL
        else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: imageURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
