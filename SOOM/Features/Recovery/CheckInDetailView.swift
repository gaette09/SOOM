import SwiftUI

struct CheckInDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checkIn: RecoveryCheckIn
    @StateObject private var viewModel: CheckInDetailViewModel
    @State private var isShowingDeleteConfirmation = false

    private let onUpdated: (RecoveryCheckIn) -> Void

    @MainActor
    init(
        checkIn: RecoveryCheckIn,
        viewModel: CheckInDetailViewModel,
        onUpdated: @escaping (RecoveryCheckIn) -> Void = { _ in }
    ) {
        _checkIn = State(initialValue: checkIn)
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onUpdated = onUpdated
    }

    var body: some View {
        SOOMScreen {
            header
            metricCard
            noteCard
            usageCard
            deleteFeedback
        }
        .navigationTitle("기록 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        CheckInEditViewContainer(checkIn: checkIn) { updatedCheckIn in
                            checkIn = updatedCheckIn
                            onUpdated(updatedCheckIn)
                        }
                    } label: {
                        Label("수정하기", systemImage: SOOMIcon.edit)
                    }

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("삭제하기", systemImage: SOOMIcon.trash)
                    }
                    .disabled(viewModel.isDeleting)
                } label: {
                    Image(systemName: SOOMIcon.more)
                }
                .accessibilityLabel("기록 관리")
                .accessibilityHint("이 컨디션 기록을 수정하거나 삭제합니다.")
            }
        }
        .confirmationDialog(
            "이 기록을 삭제할까요?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제하기", role: .destructive) {
                Task {
                    await deleteCheckIn()
                }
            }

            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제해도 회복 점수는 다시 계산되지 않아요.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("컨디션 기록")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text(formattedDate)
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricCard: some View {
        SOOMCard {
            SOOMSectionHeader("기록한 몸 상태", caption: "1점에서 5점 사이로 남긴 주관 컨디션입니다.")

            VStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    metricPill(title: "피로감", value: checkIn.fatigueLevel, tint: SOOMColor.warning)
                    metricPill(title: "수면감", value: checkIn.sleepQuality, tint: SOOMColor.recovery)
                }

                HStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                    metricPill(title: "근육통", value: checkIn.muscleSoreness, tint: SOOMColor.run)
                    metricPill(title: "기분", value: checkIn.moodLevel, tint: SOOMColor.bike)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("기록한 몸 상태")
        .accessibilityValue(accessibilitySummary)
    }

    private var noteCard: some View {
        SOOMCard {
            SOOMSectionHeader("메모")

            Text(noteText)
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(hasNote ? SOOMColor.secondaryInk : SOOMColor.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var usageCard: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
                Image(systemName: SOOMIcon.sparkles)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(SOOMColor.orange)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(SOOMColor.orange.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                Text("이 기록은 회복 코칭 문장을 더 개인화하는 데 사용됩니다.")
                    .font(SOOMFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var deleteFeedback: some View {
        if viewModel.isDeleting {
            SOOMCard {
                HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
                    ProgressView()
                        .tint(SOOMColor.recovery)
                        .accessibilityHidden(true)

                    Text("기록을 정리하는 중")
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)
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

    @MainActor
    private func deleteCheckIn() async {
        if await viewModel.deleteCheckIn(id: checkIn.id) {
            dismiss()
        }
    }

    private var formattedDate: String {
        checkIn.date.formatted(
            .dateTime
                .locale(Locale(identifier: "ko_KR"))
                .year()
                .month(.wide)
                .day()
                .hour()
                .minute()
        )
    }

    private var hasNote: Bool {
        guard let note = checkIn.note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var noteText: String {
        guard let note = checkIn.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return "메모가 없어요."
        }

        return note
    }

    private var accessibilitySummary: String {
        "피로감 \(checkIn.fatigueLevel)점, 수면감 \(checkIn.sleepQuality)점, 근육통 \(checkIn.muscleSoreness)점, 기분 \(checkIn.moodLevel)점"
    }

    private func metricPill(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))

            Text("\(value)/5")
                .font(SOOMFont.displayMedium(20, relativeTo: .title3))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
        .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
    }
}

#Preview("CheckInDetailView") {
    NavigationStack {
        CheckInDetailView(
            checkIn: RecoveryCheckIn(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                fatigueLevel: 3,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "수면감은 좋고 다리는 조금 가벼움"
            ),
            viewModel: CheckInDetailViewModel()
        )
    }
    .modelContainer(for: CheckInRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}
