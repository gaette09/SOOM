import Charts
import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    var body: some View {
        SOOMScreen {
            Text("분석")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            SOOMCard {
                SOOMSectionHeader("지난 한 달 변화", caption: "종목별 볼륨과 강도 흐름")
                Chart(viewModel.monthlySnapshot.summaries) { item in
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
                ForEach(viewModel.monthlySnapshot.insights) { insight in
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
                ForEach(viewModel.monthlySnapshot.recommendations) { item in
                    SOOMActionRow(icon: SOOMIcon.calendarClock, title: "\(item.targetDay) \(item.title)", subtitle: item.detail, tint: SOOMColor.bike)
                }
            }

            VStack(alignment: .leading, spacing: SOOMLayout.Metrics.compactListSpacing) {
                Text("분석할 운동")
                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                ForEach(viewModel.workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        SOOMCard {
                            SOOMActionRow(icon: workout.sport.iconName, title: workout.title, subtitle: "\(workout.formattedDistance) · \(workout.formattedPace)", tint: workout.sport.tint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("분석")
        .navigationBarTitleDisplayMode(.inline)
    }
}
