import SwiftUI
import Testing
import UIKit
@testable import SOOM

@MainActor
struct ShareableWorkoutCardRendererTests {
    @Test func testRendererCreatesUIImageFromShareableCard() {
        let card = makeCard()
        let image = ShareableWorkoutCardRenderer().render(card: card, tint: SOOMColor.run)

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    @Test func testRendererUsesFourByFiveExportRatio() {
        let card = makeCard()
        let image = ShareableWorkoutCardRenderer().render(
            card: card,
            tint: SOOMColor.run
        )

        let width = image?.size.width ?? 0
        let height = image?.size.height ?? 0

        #expect(width > 0)
        #expect(abs((width / height) - ShareableWorkoutCardLayout.aspectRatio) < 0.02)
    }

    @Test func testRendererUsesStableRetinaScaleForShareCard() {
        let card = makeCard()
        let image = ShareableWorkoutCardRenderer().render(card: card, tint: SOOMColor.run)

        #expect(image?.scale == ShareableWorkoutCardLayout.exportScale)
    }

    @Test func testRendererHandlesSmallCustomView() {
        let image = ShareableWorkoutCardRenderer().render(
            Text("SOOM")
                .font(.headline)
                .padding(),
            width: 160,
            scale: 1
        )

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
    }

    private func makeCard() -> ShareableWorkoutCardModel {
        ShareableWorkoutCardModel(
            id: UUID(),
            workoutType: .running,
            title: "오늘의 러닝",
            distanceText: "10.40 km",
            durationText: "52분",
            primaryMessage: "오늘은 리듬을 잘 이어간 운동이에요.",
            growthMessage: "조금씩 거리가 길어지고 있어요.",
            recoveryMessage: "회복 흐름을 생각한 좋은 강도였어요.",
            footerText: "SOOM · 공유 전 미리보기",
            visibility: .privateOnly
        )
    }
}
