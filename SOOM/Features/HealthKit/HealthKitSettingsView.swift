import SwiftUI

struct HealthKitSettingsView: View {
    @StateObject private var viewModel: HealthKitSettingsViewModel

    init(viewModel: HealthKitSettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            HealthKitStatusCard(status: viewModel.status)
            permissionCard
            workoutPreviewEntryCard
            workoutImportEntryCard
            workoutLibraryEntryCard
            recoveryPreviewEntryCard

            if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
            }
        }
        .navigationTitle("HealthKit 연결")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("HealthKit 연결")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("운동 기록을 불러와 회복 해석을 더 정확하게 만들 수 있어요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "읽기 권한만 요청합니다",
                caption: "SOOM은 현재 운동 기록, 심박, 활동 에너지, 거리 데이터를 읽는 권한만 사용합니다."
            )

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Label("운동 기록을 회복 해석의 입력 후보로 준비합니다.", systemImage: SOOMIcon.record)
                Label("언제든 iPhone 건강 앱 설정에서 권한을 변경할 수 있어요.", systemImage: SOOMIcon.health)
                Label("HealthKit 데이터는 아직 회복 점수에 반영하지 않습니다.", systemImage: SOOMIcon.checkCircle)
            }
            .font(SOOMFont.body(13, relativeTo: .caption))
            .foregroundStyle(SOOMColor.secondaryInk)

            Button {
                Task {
                    await viewModel.requestAuthorization()
                }
            } label: {
                HStack(spacing: SOOMLayout.SectionHeader.spacing) {
                    if viewModel.isRequesting {
                        ProgressView()
                            .tint(SOOMColor.white)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.isRequesting ? "권한 요청 중" : "HealthKit 권한 요청하기")
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SOOMLayout.Metrics.actionTextSpacing + 10)
                .foregroundStyle(SOOMColor.white)
                .background(viewModel.canRequestAuthorization ? SOOMColor.recovery : SOOMColor.tertiaryInk)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRequestAuthorization)
            .accessibilityLabel("HealthKit 권한 요청하기")
            .accessibilityHint("Apple 건강 앱의 운동 데이터 읽기 권한 요청을 시작합니다.")
        }
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMActionRow(
                icon: SOOMIcon.health,
                title: "권한 요청을 완료하지 못했어요",
                subtitle: message,
                tint: SOOMColor.warning
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var workoutPreviewEntryCard: some View {
        NavigationLink {
            HealthKitWorkoutPreviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.record,
                    title: "최근 운동 기록 미리보기",
                    subtitle: "HealthKit에서 불러올 수 있는 운동 목록을 확인합니다.",
                    tint: SOOMColor.recovery
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("최근 운동 기록 미리보기")
        .accessibilityHint("HealthKit 운동 기록 미리보기 화면으로 이동합니다.")
    }

    private var recoveryPreviewEntryCard: some View {
        NavigationLink {
            HealthKitRecoveryPreviewViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.recovery,
                    title: "HealthKit Recovery 미리보기",
                    subtitle: "HealthKit source로 계산한 회복 요약을 개발용으로 확인합니다.",
                    tint: SOOMColor.warning
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("HealthKit Recovery 미리보기")
        .accessibilityHint("HealthKit 기반 Recovery 개발용 미리보기 화면으로 이동합니다.")
    }

    private var workoutImportEntryCard: some View {
        NavigationLink {
            HealthKitWorkoutImportViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.sync,
                    title: "HealthKit 운동 가져오기",
                    subtitle: "운동 기록을 SOOM 공통 운동 데이터로 저장합니다.",
                    tint: SOOMColor.recovery
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("HealthKit 운동 가져오기")
        .accessibilityHint("HealthKit 운동 기록 import 화면으로 이동합니다.")
    }

    private var workoutLibraryEntryCard: some View {
        NavigationLink {
            UnifiedWorkoutLibraryViewContainer()
        } label: {
            SOOMCard {
                SOOMActionRow(
                    icon: SOOMIcon.package,
                    title: "가져온 운동 기록 보기",
                    subtitle: "SOOM 공통 운동 데이터로 저장된 기록을 확인합니다.",
                    tint: SOOMColor.secondaryInk
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("가져온 운동 기록 보기")
        .accessibilityHint("UnifiedWorkout 저장소에 저장된 운동 기록 목록으로 이동합니다.")
    }
}

#Preview("HealthKitSettingsView") {
    NavigationStack {
        HealthKitSettingsView(
            viewModel: HealthKitSettingsViewModel(manager: PreviewHealthKitManager())
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewHealthKitManager: HealthKitManaging {
    func isHealthDataAvailable() -> Bool { true }
    func requestAuthorization() async throws {}
}
