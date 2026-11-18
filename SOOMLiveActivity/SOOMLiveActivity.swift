import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SOOMWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SOOMWorkoutAttributes.self) { context in
            WorkoutActivityCard(state: context.state, isStale: context.isStale)
                .padding(18)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "soom-workout://resume"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("SOOM", systemImage: context.state.sport.symbol)
                        .font(.headline).foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.isStale && context.state.isWatch ? "워치 연결 확인" : context.state.phase == .paused ? "일시정지" : context.state.sport.title)
                        .font(.caption).foregroundStyle(context.state.phase == .paused ? .orange : .white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityMetrics(state: context.state).padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .paused ? "pause.fill" : context.state.sport.symbol)
                    .foregroundStyle(context.state.phase == .paused ? .orange : .purple)
                    .accessibilityLabel(context.state.phase == .paused ? "운동 일시정지" : context.state.sport.title)
            } compactTrailing: {
                Text(context.state.displayDistance + context.state.distanceUnit).font(.caption).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.phase == .paused ? "pause.fill" : context.state.sport.symbol)
                    .foregroundStyle(.purple)
            }
            .widgetURL(URL(string: "soom-workout://resume"))
            .keylineTint(.purple)
        }
    }
}

private struct WorkoutActivityCard: View {
    let state: WorkoutLiveState
    let isStale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(state.sport.title, systemImage: state.sport.symbol).font(.headline)
                if state.isWatch { Image(systemName: "applewatch").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text(state.phase == .paused ? "일시정지" : state.phase == .saving ? "저장 중" : "SOOM")
                    .font(.caption.weight(.semibold)).foregroundStyle(state.phase == .paused ? .orange : .purple)
            }
            WorkoutActivityMetrics(state: state)
            if isStale && state.isWatch {
                Text("워치 연결을 확인해 주세요. 마지막으로 받은 운동 정보예요.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkoutActivityMetrics: View {
    let state: WorkoutLiveState
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if state.phase == .running {
                    Text(timerInterval: state.timerStart...state.timerStart.addingTimeInterval(172_800), countsDown: false)
                        .font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                } else {
                    Text(WorkoutLiveState.time(state.elapsed)).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Text("시간").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            metric(state.displayDistance, unit: state.distanceUnit, title: "거리")
            if state.sport == .cycling {
                metric(state.elevationGain.map { String(Int($0)) } ?? "–", unit: "m", title: "획득 고도")
            } else {
                metric(state.pace(at: state.updatedAt), unit: state.effortUnit, title: "평균 페이스")
            }
        }
    }
    private func metric(_ value: String, unit: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(value).font(.system(size: 25, weight: .bold, design: .rounded)) + Text(unit).font(.caption.weight(.semibold)))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
