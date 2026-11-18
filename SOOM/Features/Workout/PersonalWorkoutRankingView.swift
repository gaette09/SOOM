import SwiftData
import SwiftUI

struct PersonalWorkoutRankingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Query(sort: \UnifiedWorkoutRecord.startDate, order: .reverse) private var records: [UnifiedWorkoutRecord]
    @State private var sport: UnifiedWorkoutType = .running
    @State private var metric: PersonalWorkoutRankingMetric = .distance
    @State private var period: PersonalWorkoutRankingPeriod = .all
    @State private var distanceBand: PersonalWorkoutDistanceBand = .all
    @State private var visibleCount = 50
    @State private var selectedWorkout: UnifiedWorkout?

    private let sports: [UnifiedWorkoutType] = [.running, .cycling, .walking, .swimming, .hiking, .strength, .yoga, .other]

    private var entries: [PersonalWorkoutRankingEntry] {
        PersonalWorkoutRankingBuilder().build(
            workouts: UnifiedWorkoutDeduplicationEngine().canonicalWorkouts(
                records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
            ),
            sport: sport, metric: metric, period: period, distanceBand: distanceBand
        )
    }

    var body: some View {
        SOOMScreen {
            SOOMCard {
                SOOMSectionHeader("내 기록 순위", caption: "내가 저장한 운동을 종목과 기준별로 비교해요.")
                Text(authViewModel.session.currentUser?.authProvider == .supabase
                     ? "현재 계정의 기록을 사용해요. 서버에서 복원한 기록과 아직 동기화를 기다리는 이 기기 기록이 함께 표시됩니다."
                     : "현재 이 기기의 기록을 사용해요. 로그인 후 동기화에 동의하면 다른 기기에서도 이어 볼 수 있어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
                Picker("종목", selection: $sport) {
                    ForEach(sports, id: \.self) { Text(title(for: $0)).tag($0) }
                }
                Picker("순위 기준", selection: $metric) {
                    ForEach(PersonalWorkoutRankingMetric.available(for: sport)) { Text($0.title).tag($0) }
                }
                Picker("기간", selection: $period) {
                    ForEach(PersonalWorkoutRankingPeriod.allCases) { Text($0.title).tag($0) }
                }
                if metric == .pace || metric == .speed || metric == .distance {
                    Picker("거리 구간", selection: $distanceBand) {
                        ForEach(PersonalWorkoutDistanceBand.allCases) { Text($0.title).tag($0) }
                    }
                }
                Text("분석 제외 기록은 빠져요. 같은 표시 값은 공동 순위예요. 페이스와 속도는 운동 전체의 평균이며, 코스·고도·거리가 다르면 직접적인 성과 비교에는 차이가 있어요.")
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
            let ranked = entries
            if ranked.isEmpty {
                SOOMCard {
                    Text("조건에 맞는 기록이 아직 없어요")
                        .font(SOOMFont.body(17, weight: .bold))
                    Text("종목이나 기간을 바꾸거나 운동을 저장해 주세요. 측정값이 없는 기록은 해당 순위에 표시되지 않아요.")
                        .font(SOOMFont.body(13))
                        .foregroundStyle(SOOMColor.secondaryInk)
                }
            } else {
                SOOMSectionHeader("\(ranked.count)개 기록", caption: "\(title(for: sport)) · \(metric.title) · \(period.title)")
                ForEach(ranked.prefix(visibleCount)) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("\(entry.rank)위").font(.title3.weight(.bold)).foregroundStyle(SOOMColor.accent)
                            Text("\(metric.title) · \(entry.valueText)").font(.subheadline.weight(.semibold))
                        }.accessibilityElement(children: .combine)
                        ActivityWorkoutRow(workout: entry.workout, onOpen: { selectedWorkout = $0 })
                    }

                }
                if ranked.count > visibleCount {
                    Button("기록 더 보기") { visibleCount += 50 }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .tint(SOOMColor.accent)
        .workoutCardDestination(selection: $selectedWorkout)
        .navigationTitle("내 기록 순위")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sport) { _, newValue in
            if !PersonalWorkoutRankingMetric.available(for: newValue).contains(metric) {
                metric = PersonalWorkoutRankingMetric.available(for: newValue)[0]
            }
            visibleCount = 50
        }
        .onChange(of: metric) { _, _ in
            distanceBand = .all
            visibleCount = 50
        }
        .onChange(of: period) { _, _ in visibleCount = 50 }
        .onChange(of: distanceBand) { _, _ in visibleCount = 50 }
    }

    private func title(for sport: UnifiedWorkoutType) -> String {
        switch sport {
        case .running: return "러닝"
        case .cycling: return "사이클"
        case .walking: return "걷기"
        case .swimming: return "수영"
        case .hiking: return "하이킹"
        case .strength: return "근력 운동"
        case .yoga: return "요가"
        case .other: return "기타"
        }
    }
}
