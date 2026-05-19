import SwiftUI

struct CheckInEditView: View {
    @Environment(\.dismiss) private var dismiss
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
            saveButton
            feedback
        }
        .navigationTitle("기록 수정")
        .navigationBarTitleDisplayMode(.inline)
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
                    Image(systemName: SOOMIcon.checkCircle)
                        .font(.body.weight(.bold))
                }

                Text(viewModel.isSaving ? "저장하는 중" : "수정 내용 저장")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .headline))
            }
            .foregroundStyle(SOOMColor.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SOOMLayout.CheckIn.saveButtonVerticalPadding)
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
        if let confirmationMessage = viewModel.confirmationMessage {
            SOOMCard {
                HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
                    Image(systemName: SOOMIcon.sparkles)
                        .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                        .foregroundStyle(SOOMColor.orange)
                        .frame(width: SOOMLayout.CheckIn.confirmationIconFrame, height: SOOMLayout.CheckIn.confirmationIconFrame)
                        .background(SOOMColor.orange.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))

                    Text(confirmationMessage)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(SOOMFont.body(12, relativeTo: .caption))
                .foregroundStyle(SOOMColor.red)
                .frame(maxWidth: .infinity, alignment: .leading)
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

