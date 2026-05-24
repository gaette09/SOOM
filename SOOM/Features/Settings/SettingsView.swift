import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            ProfileSummaryCard()
            profileSection
            dataConnectionSection
            trainingBaselineSection
            privacySection
            notificationSection
            appInfoSection
        }
        .navigationTitle("마이")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
        .alert(
            "설정 값을 확인해주세요",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.load() }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "입력 값을 다시 확인해주세요.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("마이")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)
            Text("프로필, 데이터 연결, 운동 기준값을 한곳에서 관리합니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var profileSection: some View {
        SOOMCard {
            SOOMSectionHeader("프로필", caption: "로그인과 공개 프로필은 다음 단계에서 연결합니다.")
            SOOMActionRow(icon: "person.crop.circle", title: "프로필 편집 준비 중", subtitle: "이름, 핸들, 운동 소개를 관리할 예정입니다.", tint: SOOMColor.recovery)
        }
    }

    private var dataConnectionSection: some View {
        SOOMCard {
            SOOMSectionHeader("데이터 연결", caption: "HealthKit과 가져온 운동 기록을 관리합니다.")

            NavigationLink {
                HealthKitSettingsViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.health, title: "Apple 건강 앱 연결 관리", subtitle: "읽기 권한과 HealthKit 미리보기를 확인합니다.", tint: SOOMColor.bike)
            }
            .buttonStyle(.plain)

            NavigationLink {
                HealthKitWorkoutImportViewContainer()
            } label: {
                SOOMActionRow(icon: SOOMIcon.sync, title: "HealthKit 운동 가져오기", subtitle: "가져온 운동은 성장 분석과 Recovery 미리보기에 사용됩니다.", tint: SOOMColor.recovery)
            }
            .buttonStyle(.plain)
        }
    }

    private var trainingBaselineSection: some View {
        SOOMCard {
            SOOMSectionHeader("운동 기준값", caption: "존 분석 고도화를 위한 개인 기준값입니다. 아직 계산식에는 자동 적용하지 않아요.")

            settingInputRow(
                title: "최대 심박",
                suffix: "bpm",
                text: $viewModel.maxHeartRateText,
                actionTitle: "저장",
                action: { viewModel.saveMaxHeartRate() }
            )

            settingInputRow(
                title: "사이클 FTP",
                suffix: "W",
                text: $viewModel.cyclingFTPText,
                actionTitle: "저장",
                action: { viewModel.saveCyclingFTP() }
            )

            Picker("단위", selection: Binding(
                get: { viewModel.settings.preferredUnit },
                set: { viewModel.updatePreferredUnit($0) }
            )) {
                ForEach(TrainingPreferredUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var privacySection: some View {
        SOOMCard {
            SOOMSectionHeader("공개 범위", caption: "공유 기본값은 사용자가 선택할 때만 적용되는 후보 설정입니다.")

            Picker("공유 기본값", selection: Binding(
                get: { viewModel.settings.privacyDefault },
                set: { viewModel.updatePrivacyDefault($0) }
            )) {
                Text(ShareableWorkoutVisibility.privateOnly.title).tag(ShareableWorkoutVisibility.privateOnly)
                Text(ShareableWorkoutVisibility.followers.title).tag(ShareableWorkoutVisibility.followers)
                Text(ShareableWorkoutVisibility.publicFeed.title).tag(ShareableWorkoutVisibility.publicFeed)
            }
            .pickerStyle(.segmented)

            Text("위치, 심박, 체크인 메모는 기본 공유 항목에 포함하지 않습니다.")
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }

    private var notificationSection: some View {
        SOOMCard {
            SOOMSectionHeader("알림", caption: "아침 체크인과 주간 리듬 알림을 담을 자리입니다.")
            SOOMActionRow(icon: "bell", title: "알림 설정 준비 중", subtitle: "강요하지 않는 리마인더 정책으로 설계합니다.", tint: SOOMColor.warning)
        }
    }

    private var appInfoSection: some View {
        SOOMCard {
            SOOMSectionHeader("앱 정보")
            SOOMActionRow(icon: "info.circle", title: "SOOM Foundation", subtitle: "Recovery, Growth, HealthKit 데이터 신뢰 구조를 실험 중입니다.", tint: SOOMColor.secondaryInk)
        }
    }

    private func settingInputRow(
        title: String,
        suffix: String,
        text: Binding<String>,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                Text(title)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.ink)
                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    TextField("미설정", text: text)
                        .keyboardType(.numberPad)
                        .font(SOOMFont.body(15, relativeTo: .subheadline))
                    Text(suffix)
                        .font(SOOMFont.body(12, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            }

            Button(actionTitle, action: action)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.recovery)
        }
        .padding(SOOMLayout.Metrics.pillPadding)
        .background(SOOMColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
    }
}

#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.light)
}
