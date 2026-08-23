import XCTest
@testable import SOOM

final class OnboardingViewTests: XCTestCase {
    func testStepsAreThreeStepsWithNonEmptyCopy() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.count, 3)
        steps.forEach { step in
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.message.isEmpty)
            XCTAssertFalse(step.iconName.isEmpty)
        }
    }

    func testStepsHaveUniqueSequentialIds() {
        let steps = OnboardingStep.all

        XCTAssertEqual(steps.map(\.id), [0, 1, 2])
    }

    func testLastStepIntroducesGuestModeWithoutForcingSignIn() {
        guard let lastStep = OnboardingStep.all.last else {
            return XCTFail("Expected at least one onboarding step")
        }

        XCTAssertTrue(lastStep.message.contains("로그인") || lastStep.title.contains("로그인"))
    }
}
