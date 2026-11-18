import SwiftUI

struct CheckInEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @FocusState private var noteFocused: Bool
    @AccessibilityFocusState private var resultFocused: Bool
    @StateObject private var viewModel: CheckInEditViewModel

    private let onSaved: (RecoveryCheckIn) -> Void

    init(
        viewModel: CheckInEditViewModel,
        onSaved: @escaping (RecoveryCheckIn) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        GeometryReader { viewport in
        SOOMScreen {
            header

            CheckInScaleSelector(
                title: "피로감",
                caption: "지금 몸이 얼마나 피곤하게 느껴지나요?",
                lowText: "가벼움",
                highText: "매우 피곤",
                selection: $viewModel.fatigueLevel
            )

            CheckInScaleSelector(
                title: "수면감",
                caption: "지난밤 잠이 얼마나 개운했나요?",
                lowText: "부족",
                highText: "아주 좋음",
                selection: $viewModel.sleepQuality
            )

            CheckInScaleSelector(
                title: "근육통",
                caption: "운동에 영향을 줄 뻐근함이 있나요?",
                lowText: "없음",
                highText: "많음",
                selection: $viewModel.muscleSoreness
            )

            CheckInScaleSelector(
                title: "기분",
                caption: "오늘 훈련을 시작할 마음 상태는 어떤가요?",
                lowText: "무거움",
                highText: "좋음",
                selection: $viewModel.moodLevel
            )

            noteCard
                .disabled(viewModel.isSaving)
        }
        .disabled(viewModel.isSaving)
        .onDisappear { viewModel.stopPresenting() }
        .navigationTitle("기록 수정")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { noteFocused = false }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: SOOMLayout.Spacing.sm) {
                if viewModel.confirmationMessage != nil || viewModel.errorMessage != nil {
                    SOOMBoundedFeedback(maxHeight: max(80, viewport.size.height * 0.30)) {
                        feedback.accessibilityFocused($resultFocused)
                    }
                }
                #if DEBUG && targetEnvironment(simulator)
                if ReviewDemoMode.isActive, ProcessInfo.processInfo.environment["SOOM_CHECKIN_FORM_QA"] == "1" {
                    Text("QA 저장 시도 \(viewModel.syntheticSaveAttempts)")
                        .font(.system(size: 12)).accessibilityIdentifier("checkin.qa.attempts")
                }
                #endif
                saveButton.fixedSize(horizontal: false, vertical: true)
            }
            .padding(SOOMLayout.screenPadding)
            .padding(.bottom, bottomOverlayInset)
            .background(SOOMColor.background)
        }
        .onChange(of: viewModel.errorMessage) { _, value in
            if value != nil { noteFocused = false; resultFocused = true }
        }
        .onChange(of: viewModel.confirmationMessage) { _, value in
            if value != nil { noteFocused = false; resultFocused = true }
        }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("컨디션 수정")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("잘못 남긴 부분만 가볍게 바꿔도 괜찮아요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var noteCard: some View {
        SOOMCard {
            SOOMSectionHeader("메모", caption: "수정할 내용이 있으면 짧게 정리해 주세요.")

            TextEditor(text: $viewModel.note)
                .focused($noteFocused)
                .font(SOOMFont.body(14, relativeTo: .body))
                .foregroundStyle(SOOMColor.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: SOOMLayout.CheckIn.noteHeight)
                .padding(SOOMLayout.Metrics.tagVerticalPadding)
                .background(SOOMColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if viewModel.note.isEmpty {
                        Text("선택 입력")
                            .font(SOOMFont.body(14, relativeTo: .body))
                            .foregroundStyle(SOOMColor.tertiaryInk)
                            .padding(SOOMLayout.Metrics.tagHorizontalPadding)
                            .padding(.top, SOOMLayout.Metrics.tagVerticalPadding + 1)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("메모")
                .accessibilityHint("컨디션에 영향을 준 일을 선택으로 수정합니다.")
        }
    }

    private var saveButton: some View {
        Button {
            noteFocused = false
            Task {
                if let updatedCheckIn = await viewModel.save() {
                    onSaved(updatedCheckIn)
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(SOOMColor.white)
                        .accessibilityHidden(true)
                } else {
                    Image(soom: SOOMIcon.checkCircle)
                        .font(.body.weight(.bold))
                }

                Text(viewModel.isSaving ? "저장하는 중" : "수정 내용 저장")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .headline))
            }
            .foregroundStyle(SOOMColor.white)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, SOOMLayout.CheckIn.saveButtonVerticalPadding)
            .frame(minHeight: 44)
            .background(SOOMColor.green)
            .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.RecoveryAI.ctaCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .accessibilityLabel("수정 내용 저장")
        .accessibilityHint("수정한 컨디션 기록을 저장합니다.")
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = viewModel.confirmationMessage {
            SOOMActionFeedback(title: "기록 완료", message: message)
                .accessibilityIdentifier("checkin.save.success")
        } else if let message = viewModel.errorMessage {
            SOOMActionFeedback(title: "저장하지 못했어요", message: message + " 선택한 값과 메모는 그대로 있어요.", isError: true)
                .accessibilityIdentifier("checkin.save.failure")
        }
    }

}

#Preview("CheckInEditView") {
    NavigationStack {
        CheckInEditView(
            viewModel: CheckInEditViewModel(
                checkIn: RecoveryCheckIn(
                    date: Date(timeIntervalSince1970: 1_800_000_000),
                    fatigueLevel: 3,
                    sleepQuality: 4,
                    muscleSoreness: 2,
                    moodLevel: 4,
                    note: "수면감 좋음"
                )
            )
        )
    }
    .preferredColorScheme(.light)
}

