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

    @Test func testWorkoutDetailContentRendersSharePreviewSurface() {
        let workout = MockWorkoutHarness().loadWorkouts()[0]
        let content = makeWorkoutDetailContent(workout: workout)
            .frame(width: 390)

        let image = ShareableWorkoutCardRenderer().render(content, width: 390, scale: 1)

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect(WorkoutDetailContent.sharePrivacyCopy.contains("위치"))
        #expect(WorkoutDetailContent.sharePrivacyCopy.contains("심박"))
        #expect(WorkoutDetailContent.sharePrivacyCopy.contains("회복 점수"))
    }

    @Test func testWorkoutDetailContentUsesInjectedRendererForShareFlow() {
        let workout = MockWorkoutHarness().loadWorkouts()[0]
        let card = makeCard()
        var renderCallCount = 0
        let content = WorkoutDetailContent(
            workout: workout,
            showsHeader: false,
            shareableCard: card,
            renderShareImage: { _, _ in
                renderCallCount += 1
                return UIImage()
            }
        )

        let image = content.renderedShareImage(for: card)

        #expect(image != nil)
        #expect(renderCallCount == 1)
    }

    @Test func testAnalysisViewRendersWeeklySharePreviewSurface() {
        let viewModel = AnalysisViewModel(provider: StaticWeeklyProgressProvider(progress: makeWeeklyProgress()))
        let dashboardViewModel = DashboardViewModel(harness: MockWorkoutHarness())
        let content = AnalysisView(viewModel: viewModel)
            .environmentObject(dashboardViewModel)
            .frame(width: 390)

        let image = ShareableWorkoutCardRenderer().render(content, width: 390, scale: 1)

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect(AnalysisView.weeklySharePrivacyCopy.contains("위치"))
        #expect(AnalysisView.weeklySharePrivacyCopy.contains("심박"))
        #expect(AnalysisView.weeklySharePrivacyCopy.contains("회복 점수"))
    }

    @Test func testAnalysisViewUsesInjectedRendererForWeeklyShareFlow() {
        let card = ShareableWeeklyProgressCardBuilder().build(progress: makeWeeklyProgress())
        var renderCallCount = 0
        let view = AnalysisView(
            viewModel: AnalysisViewModel(provider: StaticWeeklyProgressProvider(progress: makeWeeklyProgress())),
            renderWeeklyShareImage: { _ in
                renderCallCount += 1
                return UIImage()
            }
        )

        let image = view.renderedWeeklyShareImage(for: card)

        #expect(image != nil)
        #expect(renderCallCount == 1)
    }

    @Test func testWorkoutShareSheetBuildsActivityController() {
        let sheet = WorkoutShareSheet(activityItems: ["SOOM"])
        let controller = sheet.makeActivityViewController()

        #expect(controller is UIActivityViewController)
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

    private func makeWorkoutDetailContent(workout: Workout) -> WorkoutDetailContent {
        let growth = WorkoutGrowthSummaryBuilder().build(current: workout, recentWorkouts: [workout])
        let weakness = WorkoutWeaknessInsightBuilder().build(current: workout, recentWorkouts: [workout])
        let impact = WorkoutRecoveryImpactBuilder().build(workout: workout)
        let session = WorkoutSessionSummaryBuilder().build(
            workout: workout,
            growthSummary: growth,
            weaknessInsight: weakness,
            recoveryImpact: impact
        )
        let card = ShareableWorkoutCardBuilder().build(
            workout: workout,
            sessionSummary: session,
            growthSummary: growth,
            recoveryImpact: impact
        )

        return WorkoutDetailContent(
            workout: workout,
            showsHeader: false,
            sessionSummary: session,
            growthSummary: growth,
            weaknessInsight: weakness,
            recoveryImpact: impact,
            shareableCard: card
        )
    }

    private func makeWeeklyProgress() -> WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutCount: 3,
            totalDistanceKm: 31.2,
            totalDurationMinutes: 180,
            averagePaceOrSpeedText: "평균 5:46/km",
            progressSummary: "이번 주도 리듬을 잘 이어갔어요.",
            motivationText: "꾸준히 움직인 흐름 자체가 좋은 성장 신호예요.",
            trendType: .steady
        )
    }
}

private struct StaticWeeklyProgressProvider: WeeklyWorkoutProgressProviding {
    let progress: WeeklyWorkoutProgress

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        progress
    }
}
