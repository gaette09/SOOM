import Charts
import SwiftUI
import UIKit

struct AnalysisView: View {
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var analysisViewModel: AnalysisViewModel
    private let renderWeeklyShareImage: @MainActor (ShareableWeeklyProgressCardModel) -> UIImage?
    @State private var weeklyShareImage: UIImage?
    @State private var isWeeklyShareSheetPresented = false
    @State private var weeklyShareErrorMessage: String?
    @State private var isManualWorkoutPresented = false
    @State private var selectedWorkout: Workout?

    static let weeklySharePrivacyCopy = "이번 주 성장 흐름을 9:16 이미지로 저장해요. 위치, 심박, 회복 점수는 기본으로 제외됩니다."

    init(
        viewModel: AnalysisViewModel,
        renderWeeklyShareImage: @escaping @MainActor (ShareableWeeklyProgressCardModel) -> UIImage? = { card in
            ShareableWorkoutCardRenderer().render(
                ShareableWeeklyProgressCardView(card: card, tint: SOOMColor.accent)
                    .environment(\.colorScheme, .light)
            )
        }
    ) {
        _analysisViewModel = StateObject(wrappedValue: viewModel)
        self.renderWeeklyShareImage = renderWeeklyShareImage
    }

    var body: some View {
        SOOMScreen {
            HStack {
                Text("분석")
                    .font(SOOMFont.display(38, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)
                Spacer()
                Button { isManualWorkoutPresented = true } label: {
                    Label("직접 입력", soomIcon: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("analysis.manualWorkout")
            }

            if analysisViewModel.isLoading && !analysisViewModel.hasLoaded {
                SOOMSkeleton(layout: .summary, label: "주간 운동 분석 중")
                SOOMSkeleton(layout: .chart, label: "운동 흐름 불러오는 중")
            } else {
            WeeklyWorkoutProgressCard(
                progress: analysisViewModel.progress,
                tint: SOOMColor.accent
            )

            weeklySharePreview

            FourWeekWorkoutTrendCard(
                trend: analysisViewModel.fourWeekTrend,
                tint: SOOMColor.accent
            )

            ProgressionIntelligenceCard(
                intelligence: analysisViewModel.progressionIntelligence,
                tint: SOOMColor.accent
            )

            PersonalRecordCard(
                records: analysisViewModel.personalRecords,
                tint: SOOMColor.warning
            )

            }

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
                    SOOMActionRow(icon: SOOMIcon.calendarClock, title: "\(item.targetDay) \(item.title)", subtitle: item.detail, tint: SOOMColor.accent)
                }
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Text("분석할 운동")
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                ForEach(dashboardViewModel.workouts) { workout in
                    VStack(spacing: 0) {
                        WorkoutRecordCard(title: workout.title, description: nil, date: workout.date,
                            sport: workout.comparisonWorkoutType, author: auth.session.currentUser?.displayName ?? "나",
                            authorID: auth.session.currentUser?.id, avatarPath: auth.session.currentUser?.avatarPath,
                            device: workout.source,
                            location: FeedCardFormatting.region(nil, hasRoute: workout.route.count > 1),
                            metrics: Self.legacyCardMetrics(workout),
                            route: WorkoutMapSheetRouteContext.route(for: workout, override: nil),
                            onOpen: {
                                SOOMHaptics.selection()
                                selectedWorkout = workout
                            }) {
                                EmptyView()
                        }
                        Rectangle().fill(SOOMColor.surfaceMuted).frame(height: 6)
                    }
                    .padding(.horizontal, -SOOMLayout.screenPadding)
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
        .sheet(isPresented: $isManualWorkoutPresented) {
            ManualWorkoutEntryView { _ in
                Task { await analysisViewModel.load(fallbackWorkouts: dashboardViewModel.workouts) }
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
        .navigationDestination(isPresented: Binding(
            get: { selectedWorkout != nil },
            set: { if !$0 { selectedWorkout = nil } }
        )) {
            if let selectedWorkout {
                WorkoutDeepDetailView(workout: selectedWorkout, comparisonWorkouts: dashboardViewModel.workouts)
            }
        }
    }

    /// Legacy records keep their own identity and detail route; only display values are adapted.
    static func legacyCardMetrics(_ workout: Workout) -> [WorkoutCardMetric] {
        let sport = workout.comparisonWorkoutType
        return [WorkoutCardMetric(label: "거리", value: FeedCardFormatting.distance(workout.distanceMeters)),
                WorkoutCardMetric(label: FeedCardFormatting.movementLabel(sport),
                    value: FeedCardFormatting.movement(sport: sport, distance: workout.distanceMeters, seconds: workout.duration) ?? "—"),
                WorkoutCardMetric(label: "총 시간", value: FeedCardFormatting.duration(workout.duration))]
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

            ShareableWeeklyProgressCardView(card: card, tint: SOOMColor.accent)

            Button {
                shareWeeklyProgress(card)
            } label: {
                Label("주간 카드 공유하기", soomIcon: SOOMIcon.share)
                    .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Card.padding)
                    .background(SOOMColor.accent)
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
