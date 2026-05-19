import SwiftUI

struct HealthKitWorkoutPreviewView: View {
    @StateObject private var viewModel: HealthKitWorkoutPreviewViewModel

    init(viewModel: HealthKitWorkoutPreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SOOMScreen {
            header
            workoutListCard
        }
        .navigationTitle("운동 기록 미리보기")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRecentWorkouts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text("최근 운동 기록")
                .font(SOOMFont.display(34, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            Text("HealthKit에서 불러올 수 있는 운동 기록을 먼저 확인합니다. 아직 회복 점수에는 반영하지 않아요.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var workoutListCard: some View {
        SOOMCard {
            SOOMSectionHeader(
                "HealthKit Workout",
                caption: "읽기 권한으로 확인한 최근 운동 목록입니다."
            )

            if viewModel.isLoading {
                loadingState
            } else if let errorMessage = viewModel.errorMessage {
                messageState(
                    icon: SOOMIcon.health,
                    title: "운동 기록을 불러오지 못했어요",
                    message: errorMessage,
                    tint: SOOMColor.warning
                )
            } else if viewModel.workouts.isEmpty {
                messageState(
                    icon: SOOMIcon.record,
                    title: "아직 불러올 운동 기록이 없어요",
                    message: "HealthKit 권한을 허용하면 최근 운동 기록을 확인할 수 있어요.",
                    tint: SOOMColor.secondaryInk
                )
            } else {
                VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                    ForEach(viewModel.workouts) { workout in
                        HealthKitWorkoutPreviewRow(workout: workout)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: SOOMLayout.Metrics.actionRowSpacing) {
            ProgressView()
                .tint(SOOMColor.recovery)
                .accessibilityHidden(true)

            Text("최근 운동 기록을 확인하고 있어요.")
                .font(SOOMFont.body(13, relativeTo: .caption))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("운동 기록 불러오는 중")
    }

    private func messageState(icon: String, title: String, message: String, tint: Color) -> some View {
        SOOMActionRow(
            icon: icon,
            title: title,
            subtitle: message,
            tint: tint
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct HealthKitWorkoutPreviewRow: View {
    let workout: HealthKitWorkout

    var body: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
            Image(systemName: icon)
                .font(.system(size: SOOMLayout.RecoveryAI.iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
                .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.workoutType.displayName)
                        .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.ink)

                    Spacer(minLength: SOOMLayout.Metrics.tagSpacing)

                    Text(formattedDate)
                        .font(SOOMFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                }

                Text(primarySummary)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)

                Text(secondarySummary)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .padding(.vertical, SOOMLayout.SectionHeader.spacing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.workoutType.displayName) 운동")
        .accessibilityValue("\(formattedDate), \(primarySummary), \(secondarySummary)")
    }

    private var icon: String {
        switch workout.workoutType {
        case .running:
            return SOOMIcon.run
        case .cycling:
            return SOOMIcon.bike
        case .swimming:
            return SOOMIcon.swim
        case .walking:
            return SOOMIcon.run
        case .other:
            return SOOMIcon.record
        }
    }

    private var tint: Color {
        switch workout.workoutType {
        case .running, .walking:
            return SOOMColor.run
        case .cycling:
            return SOOMColor.bike
        case .swimming:
            return SOOMColor.swim
        case .other:
            return SOOMColor.secondaryInk
        }
    }

    private var formattedDate: String {
        workout.startDate.formatted(
            .dateTime
                .locale(Locale(identifier: "ko_KR"))
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }

    private var primarySummary: String {
        "\(formattedDuration) · \(formattedDistance)"
    }

    private var secondarySummary: String {
        "\(formattedHeartRate) · \(formattedCalories)"
    }

    private var formattedDuration: String {
        let totalMinutes = max(Int((workout.duration / 60).rounded()), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }

        return "\(minutes)분"
    }

    private var formattedDistance: String {
        guard let distance = workout.distance else {
            return "거리 없음"
        }

        if distance >= 1_000 {
            return String(format: "%.1f km", distance / 1_000)
        }

        return "\(Int(distance.rounded())) m"
    }

    private var formattedHeartRate: String {
        guard let averageHeartRate = workout.averageHeartRate else {
            return "평균 심박 없음"
        }

        return "평균 \(Int(averageHeartRate.rounded()))bpm"
    }

    private var formattedCalories: String {
        guard let calories = workout.calories else {
            return "칼로리 없음"
        }

        return "\(Int(calories.rounded())) kcal"
    }
}

#Preview("HealthKitWorkoutPreviewView") {
    NavigationStack {
        HealthKitWorkoutPreviewView(
            viewModel: HealthKitWorkoutPreviewViewModel(
                fetcher: PreviewHealthKitWorkoutFetcher()
            )
        )
    }
    .preferredColorScheme(.light)
}

private struct PreviewHealthKitWorkoutFetcher: HealthKitWorkoutFetching {
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        [
            HealthKitWorkout(
                id: UUID(),
                workoutType: .running,
                startDate: Date().addingTimeInterval(-3_600),
                endDate: Date(),
                duration: 3_120,
                distance: 10_400,
                averageHeartRate: 151,
                calories: 676
            ),
            HealthKitWorkout(
                id: UUID(),
                workoutType: .cycling,
                startDate: Date().addingTimeInterval(-90_000),
                endDate: Date().addingTimeInterval(-84_600),
                duration: 5_400,
                distance: 41_700,
                averageHeartRate: 144,
                calories: 727
            )
        ]
    }
}
