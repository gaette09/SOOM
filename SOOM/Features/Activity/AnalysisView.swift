import Charts
import SwiftUI
import UIKit

struct AnalysisView: View {
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var analysisViewModel: AnalysisViewModel
    private let renderWeeklyShareImage: @MainActor (ShareableWeeklyProgressCardModel) -> UIImage?
    @State private var weeklyShareImage: UIImage?
    @State private var isWeeklyShareSheetPresented = false
    @State private var weeklyShareErrorMessage: String?

    static let weeklySharePrivacyCopy = "이번 주 성장 흐름을 4:5 이미지로 저장해요. 위치, 심박, 회복 점수는 기본으로 제외됩니다."

    init(
        viewModel: AnalysisViewModel,
        renderWeeklyShareImage: @escaping @MainActor (ShareableWeeklyProgressCardModel) -> UIImage? = { card in
            ShareableWorkoutCardRenderer().render(
                ShareableWeeklyProgressCardView(card: card, tint: SOOMColor.bike)
                    .environment(\.colorScheme, .light)
            )
        }
    ) {
        _analysisViewModel = StateObject(wrappedValue: viewModel)
        self.renderWeeklyShareImage = renderWeeklyShareImage
    }

    var body: some View {
        SOOMScreen {
            Text("분석")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            WeeklyWorkoutProgressCard(
                progress: analysisViewModel.progress,
                tint: SOOMColor.bike
            )

            weeklySharePreview

            FourWeekWorkoutTrendCard(
                trend: analysisViewModel.fourWeekTrend,
                tint: SOOMColor.bike
            )

            PersonalRecordCard(
                records: analysisViewModel.personalRecords,
                tint: SOOMColor.warning
            )

            SOOMCard {
                SOOMSectionHeader("지난 한 달 변화", caption: "종목별 볼륨과 강도 흐름")
                Chart(dashboardViewModel.monthlySnapshot.summaries) { item in
                    BarMark(
                        x: .value("종목", item.sport.title),
                        y: .value("증가율", item.change)
                    )
                    .foregroundStyle(item.sport.tint)
                }
                .frame(height: 180)
            }

            SOOMCard {
                SOOMSectionHeader("AI 판단")
                ForEach(dashboardViewModel.monthlySnapshot.insights) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(insight.priority.rawValue) · \(insight.title)")
                            .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.ink)
                        Text(insight.message)
                            .font(SOOMFont.body(12, relativeTo: .caption))
                            .foregroundStyle(SOOMColor.secondaryInk)
                    }
                    Divider()
                }
            }

            SOOMCard {
                SOOMSectionHeader("추천 주간 구성")
                ForEach(dashboardViewModel.monthlySnapshot.recommendations) { item in
                    SOOMActionRow(icon: SOOMIcon.calendarClock, title: "\(item.targetDay) \(item.title)", subtitle: item.detail, tint: SOOMColor.bike)
                }
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Text("분석할 운동")
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                ForEach(dashboardViewModel.workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout, comparisonWorkouts: dashboardViewModel.workouts)
                    } label: {
                        SOOMCard {
                            SOOMActionRow(icon: workout.sport.iconName, title: workout.title, subtitle: "\(workout.formattedDistance) · \(workout.formattedPace)", tint: workout.sport.tint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            await analysisViewModel.load(fallbackWorkouts: dashboardViewModel.workouts)
        }
        .sheet(isPresented: $isWeeklyShareSheetPresented) {
            if let weeklyShareImage {
                WorkoutShareSheet(activityItems: [weeklyShareImage])
            }
        }
        .alert(
            "공유 카드를 만들지 못했어요",
            isPresented: Binding(
                get: { weeklyShareErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        weeklyShareErrorMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(weeklyShareErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .navigationTitle("분석")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weeklySharePreview: some View {
        let card = ShareableWeeklyProgressCardBuilder().build(
            progress: analysisViewModel.progress,
            trend: analysisViewModel.fourWeekTrend
        )

        return VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                SOOMSectionHeader("공유 카드 미리보기")
                Text(Self.weeklySharePrivacyCopy)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShareableWeeklyProgressCardView(card: card, tint: SOOMColor.bike)

            Button {
                shareWeeklyProgress(card)
            } label: {
                Label("주간 카드 공유하기", systemImage: SOOMIcon.share)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Card.padding)
                    .background(SOOMColor.bike)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("주간 공유 카드 공유하기")
            .accessibilityHint("주간 운동 공유 카드 이미지를 만든 뒤 iOS 공유 시트를 엽니다.")
        }
    }

    @MainActor
    private func shareWeeklyProgress(_ card: ShareableWeeklyProgressCardModel) {
        guard let image = renderedWeeklyShareImage(for: card) else {
            weeklyShareErrorMessage = "주간 공유 카드 이미지를 만들 수 없어요."
            return
        }

        weeklyShareImage = image
        isWeeklyShareSheetPresented = true
    }

    @MainActor
    func renderedWeeklyShareImage(for card: ShareableWeeklyProgressCardModel) -> UIImage? {
        renderWeeklyShareImage(card)
    }
}
