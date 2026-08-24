import SwiftUI

enum OnboardingStepKind: Equatable {
    case explanation
    case healthKitPermission
    case locationPermission
}

struct OnboardingStep: Identifiable, Equatable {
    let id: Int
    let kind: OnboardingStepKind
    let iconName: String
    let title: String
    let message: String
}

extension OnboardingStep {
    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            kind: .explanation,
            iconName: SOOMIcon.sparkles,
            title: "SOOM에 오신 걸 환영해요",
            message: "기록보다 리듬을 먼저 봅니다. 오늘 얼마나 움직였는지보다, 어떤 흐름으로 움직이고 있는지를 함께 봐요."
        ),
        OnboardingStep(
            id: 1,
            kind: .explanation,
            iconName: SOOMIcon.activity,
            title: "운동은 기록하고, 회복은 흐름으로 읽어요",
            message: "Health 앱에서 가져오거나 직접 기록하면, 피드에서 흐름을 보고 회복 인사이트로 오늘 컨디션을 확인할 수 있어요."
        ),
        OnboardingStep(
            id: 2,
            kind: .healthKitPermission,
            iconName: SOOMIcon.health,
            title: "Health 앱과 연결하면 기록이 쉬워져요",
            message: "운동 데이터를 자동으로 가져올 수 있어요. 지금 허용하지 않아도 설정에서 언제든 다시 할 수 있어요."
        ),
        OnboardingStep(
            id: 3,
            kind: .locationPermission,
            iconName: SOOMIcon.map,
            title: "위치를 허용하면 경로가 함께 남아요",
            message: "달리거나 라이딩할 때 route를 그려서 보여드려요. 지금 허용하지 않아도 기록을 시작할 때 언제든 다시 물어볼게요."
        ),
        OnboardingStep(
            id: 4,
            kind: .explanation,
            iconName: SOOMIcon.checkCircle,
            title: "지금은 로그인 없이 시작해요",
            message: "이 기기에서 바로 기록을 시작할 수 있어요. 계정 연결은 준비됐을 때 언제든 할 수 있어요."
        )
    ]
}

struct OnboardingView: View {
    let healthKitManager: any HealthKitManaging
    let locationPermissionRequester: any OnboardingLocationPermissionRequesting
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var isRequestingHealthKitPermission = false
    private let steps = OnboardingStep.all

    init(
        healthKitManager: any HealthKitManaging = HealthKitManager(),
        locationPermissionRequester: any OnboardingLocationPermissionRequesting = OnboardingLocationPermissionRequester(),
        onComplete: @escaping () -> Void
    ) {
        self.healthKitManager = healthKitManager
        self.locationPermissionRequester = locationPermissionRequester
        self.onComplete = onComplete
    }

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

            bottomControl
                .padding(SOOMLayout.screenPadding)
        }
        .background(SOOMColor.background)
    }

    @ViewBuilder
    private var bottomControl: some View {
        switch steps[currentStep].kind {
        case .explanation:
            OnboardingPrimaryButton(title: isLastStep ? "시작하기" : "다음") {
                advanceOrComplete()
            }
        case .healthKitPermission:
            OnboardingPermissionButtons(
                isBusy: isRequestingHealthKitPermission,
                onAllow: requestHealthKitPermissionThenAdvance,
                onSkip: advanceOrComplete
            )
        case .locationPermission:
            OnboardingPermissionButtons(
                isBusy: false,
                onAllow: {
                    locationPermissionRequester.requestWhenInUseAuthorization()
                    advanceOrComplete()
                },
                onSkip: advanceOrComplete
            )
        }
    }

    private func requestHealthKitPermissionThenAdvance() {
        isRequestingHealthKitPermission = true
        Task {
            try? await healthKitManager.requestAuthorization()
            isRequestingHealthKitPermission = false
            advanceOrComplete()
        }
    }

    private func advanceOrComplete() {
        if isLastStep {
            onComplete()
        } else {
            withAnimation(SOOMMotion.normalEaseOut) {
                currentStep += 1
            }
        }
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

private struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Spacing.lg)
                .background(SOOMColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// "허용"/"나중에" — neither blocks progress; both simply move onboarding
/// forward. `isBusy` only disables the buttons mid-request (HealthKit's
/// async call) so a stray double-tap can't fire it twice.
private struct OnboardingPermissionButtons: View {
    let isBusy: Bool
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
            Button(action: onAllow) {
                Text("허용")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.lg)
                    .background(SOOMColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button(action: onSkip) {
                Text("나중에")
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Spacing.sm)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }
}

#Preview("OnboardingView") {
    OnboardingView(onComplete: {})
}
