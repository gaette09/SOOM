import XCTest
@testable import SOOM

final class OnboardingViewTests: XCTestCase {
    func testStepsAreFiveStepsWithNonEmptyCopy() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.count, 5)
        steps.forEach { step in
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.message.isEmpty)
            XCTAssertFalse(step.iconName.isEmpty)
        }
    }

    func testStepsHaveUniqueSequentialIds() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.map(\.id), [0, 1, 2, 3, 4])
    }

    func testPermissionStepsSitBetweenExplanationSteps() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.map(\.kind), [
            .explanation,
            .explanation,
            .healthKitPermission,
            .locationPermission,
            .explanation
        ])
    }

    func testLastStepIntroducesGuestModeWithoutForcingSignIn() {
        guard let lastStep = OnboardingStep.all.last else {
            return XCTFail("Expected at least one onboarding step")
        }

        XCTAssertEqual(lastStep.kind, .explanation)
        XCTAssertTrue(lastStep.message.contains("로그인") || lastStep.title.contains("로그인"))
    }

    func testPermissionStepsMentionThatSkippingIsSafe() {
        let permissionSteps = OnboardingStep.all.filter { $0.kind != .explanation }

        XCTAssertEqual(permissionSteps.count, 2)
        permissionSteps.forEach { step in
            XCTAssertTrue(
                step.message.contains("나중") || step.message.contains("언제든"),
                "Permission step '\(step.title)' should make clear skipping now is safe"
            )
        }
    }
}
