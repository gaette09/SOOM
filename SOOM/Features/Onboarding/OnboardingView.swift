import SwiftUI

struct OnboardingStep: Identifiable, Equatable {
    let id: Int
    let iconName: String
    let title: String
    let message: String
}

extension OnboardingStep {
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            iconName: SOOMIcon.sparkles,
            title: "SOOM에 오신 걸 환영해요",
            message: "기록보다 리듬을 먼저 봅니다. 오늘 얼마나 움직였는지보다, 어떤 흐름으로 움직이고 있는지를 함께 봐요."
        ),
        OnboardingStep(
            id: 1,
            iconName: SOOMIcon.activity,
            title: "운동은 기록하고, 회복은 흐름으로 읽어요",
            message: "Health 앱에서 가져오거나 직접 기록하면, 피드에서 흐름을 보고 회복 인사이트로 오늘 컨디션을 확인할 수 있어요."
        ),
        OnboardingStep(
            id: 2,
            iconName: SOOMIcon.checkCircle,
            title: "지금은 로그인 없이 시작해요",
            message: "이 기기에서 바로 기록을 시작할 수 있어요. 계정 연결은 준비됐을 때 언제든 할 수 있어요."
        )
    ]
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    private let steps = OnboardingStep.all

    private var isLastStep: Bool {
        currentStep >= steps.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentStep) {
                ForEach(steps) { step in
                    OnboardingStepView(step: step)
                        .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastStep {
                    onComplete()
                } else {
                    withAnimation(SOOMMotion.normalEaseOut) {
                        currentStep += 1
                    }
                }
            } label: {
                Text(isLastStep ? "시작하기" : "다음")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(SOOMColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(SOOMLayout.screenPadding)
            .accessibilityIdentifier(isLastStep ? "onboarding.start" : "onboarding.next")
        }
        .background(SOOMColor.background)
    }
}

private struct OnboardingStepView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: SOOMLayout.Spacing.xl) {
            Spacer()

            Image(systemName: step.iconName)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 96, height: 96)
                .background(SOOMColor.accentMuted)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(spacing: SOOMLayout.Spacing.md) {
                Text(step.title)
                    .font(SOOMFont.displayMedium(24, relativeTo: .title2))
                    .foregroundStyle(SOOMColor.ink)
                    .multilineTextAlignment(.center)

                Text(step.message)
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SOOMLayout.Spacing.xl)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(step.title)
        .accessibilityValue(step.message)
    }
}

#Preview("OnboardingView") {
    OnboardingView(onComplete: {})
}
