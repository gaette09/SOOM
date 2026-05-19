import SwiftUI

struct CheckInHistoryView: View {
    @StateObject private var viewModel: CheckInHistoryViewModel

    init(viewModel: CheckInHistoryViewModel = CheckInHistoryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header

            if viewModel.isLoading {
                loadingCard
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
            } else if viewModel.checkIns.isEmpty {
                emptyCard
            } else {
                historyList
            }
        }
        .task {
            await viewModel.load()
        }
        .navigationTitle("컨디션 기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("컨디션 기록")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("최근에 남긴 피로감, 수면감, 근육통, 기분을 확인하세요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
            ForEach(viewModel.checkIns) { checkIn in
                NavigationLink {
                    CheckInDetailViewContainer(
                        checkIn: checkIn,
                        onUpdated: { updatedCheckIn in
                            viewModel.updateCheckIn(updatedCheckIn)
                        },
                        onDeleted: { deletedID in
                            viewModel.removeCheckIn(id: deletedID)
                        }
                    )
                } label: {
                    CheckInHistoryRow(checkIn: checkIn)
                }
                .buttonStyle(.plain)
                .accessibilityHint("컨디션 기록 상세 화면으로 이동합니다.")
            }
        }
    }

    private var loadingCard: some View {
        SOOMCard {
            HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
                ProgressView()
                    .tint(SOOMColor.recovery)
                    .accessibilityHidden(true)

                Text("컨디션 기록을 불러오는 중")
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("컨디션 기록을 불러오는 중")
    }

    private var emptyCard: some View {
        SOOMCard {
            Image(systemName: SOOMIcon.recovery)
                .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                .foregroundStyle(SOOMColor.recovery)
                .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                .background(SOOMColor.recovery.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))

            SOOMSectionHeader(
                "아직 기록된 컨디션이 없어요.",
                caption: "오늘 컨디션을 가볍게 남겨보세요."
            )
        }
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        SOOMCard {
            SOOMSectionHeader("기록을 불러오지 못했습니다.", caption: message)
            Text("잠시 후 다시 확인해 주세요.")
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CheckInHistoryRow: View {
    let checkIn: RecoveryCheckIn

    var body: some View {
        SOOMCard {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
                Image(systemName: SOOMIcon.calendarClock)
                    .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                    .foregroundStyle(SOOMColor.recovery)
                    .frame(width: SOOMLayout.RecoveryAI.iconFrame, height: SOOMLayout.RecoveryAI.iconFrame)
                    .background(SOOMColor.recovery.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.RecoveryAI.textSpacing) {
                    Text(formattedDate)
                        .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    metricGrid

                    if let note = checkIn.note, !note.isEmpty {
                        Text(note)
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: SOOMLayout.Metrics.actionTextSpacing)

                Image(systemName: SOOMIcon.chevronRight)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("컨디션 기록")
        .accessibilityValue(accessibilitySummary)
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Metrics.tagSpacing) {
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

    private var formattedDate: String {
        checkIn.date.formatted(
            .dateTime
                .locale(Locale(identifier: "ko_KR"))
                .month(.wide)
                .day()
                .hour()
                .minute()
        )
    }

    private var accessibilitySummary: String {
        "피로감 \(checkIn.fatigueLevel)점, 수면감 \(checkIn.sleepQuality)점, 근육통 \(checkIn.muscleSoreness)점, 기분 \(checkIn.moodLevel)점"
    }

    private func metricPill(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: SOOMLayout.SectionHeader.spacing) {
            Text(title)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
            Spacer(minLength: SOOMLayout.SectionHeader.spacing)
            Text("\(value)/5")
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
        .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
    }
}

#Preview("CheckInHistoryView") {
    NavigationStack {
        CheckInHistoryView()
    }
    .preferredColorScheme(.light)
}
