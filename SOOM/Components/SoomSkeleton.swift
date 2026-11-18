import SwiftUI

/// Presentation only: no timer, task, animation or data fetch. A refresh with
/// cached content must keep that content outside this view (including its IDs).
struct SOOMSkeleton: View {
    enum Layout: String, CaseIterable {
        case value, row, list, workout, feed, summary, chart, profile, detail, photo
    }

    var layout: Layout = .list
    var label: String = "데이터를 불러오는 중"
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 12
    private var fill: Color { Color(uiColor: .tertiarySystemFill) }

    var body: some View {
        shapes
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("skeleton.\(layout.rawValue)")
            .allowsHitTesting(false)
            // Static placeholders also respect Reduce Motion; parent expansion
            // animations must not animate placeholder removal or leave a trail.
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }

    @ViewBuilder private var shapes: some View {
        switch layout {
        case .value: line(fraction: 0.65, height: lineHeight + 4)
        case .row: row
        case .list:
            VStack(spacing: 16) { ForEach(0..<3, id: \.self) { _ in row } }
        case .workout:
            VStack(spacing: SOOMLayout.stackSpacing) {
                ForEach(0..<3, id: \.self) { _ in card { row; metrics } }
            }
        case .feed:
            card {
                row
                line(fraction: 0.7, height: 20)
                metrics
                block(height: 210)
                line(fraction: 0.45)
            }
        case .summary:
            card { line(fraction: 0.55, height: 20); metrics; line(fraction: 0.85); line(fraction: 0.65) }
        case .chart:
            card {
                line(fraction: 0.5, height: 20)
                VStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { index in
                        HStack(spacing: 12) {
                            block(height: lineHeight).frame(width: 36)
                            line(fraction: [0.65, 0.85, 0.5, 0.75, 0.35][index], height: 16)
                        }
                    }
                }
            }
        case .profile:
            card { row; metrics; line(fraction: 0.8) }
        case .detail:
            VStack(spacing: SOOMLayout.stackSpacing) {
                block(height: 220)
                SOOMSkeleton(layout: .summary)
                SOOMSkeleton(layout: .chart)
            }
        case .photo:
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill)
                .overlay { Image(systemName: "photo").font(.title).foregroundStyle(.tertiary) }
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(fill).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 9) {
                line(fraction: 0.55, height: lineHeight + 3)
                line(fraction: 0.85)
            }
        }.frame(minHeight: 56)
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    line(fraction: 0.65)
                    line(fraction: 0.9, height: lineHeight + 8)
                }
            }
        }
    }

    private func line(fraction: CGFloat, height: CGFloat? = nil) -> some View {
        GeometryReader { geometry in
            Capsule().fill(fill).frame(width: max(0, geometry.size.width * fraction))
        }.frame(height: height ?? lineHeight)
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill).frame(height: height)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: SOOMLayout.cardRadius))
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Controlled synthetic provider, reachable only through the existing review
/// sandbox. Completion is explicit, so screenshots never depend on a network.
@MainActor
private final class SkeletonQAWorkoutFetcher: ObservableObject, HealthKitWorkoutFetching {
    @Published var requests = 0
    private var pending: CheckedContinuation<[HealthKitWorkout], Error>?
    func fetchRecentWorkouts(limit: Int) async throws -> [HealthKitWorkout] {
        requests += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ outcome: Int) {
        guard let pending else { return }; self.pending = nil
        if outcome < 0 { pending.resume(throwing: NSError(domain: "Synthetic", code: 1)); return }
        let sample = HealthKitWorkout(id: UUID(uuidString: "D3000000-0000-4000-8000-000000000099")!, workoutType: .running,
            startDate: Date(timeIntervalSince1970: 1_800_000_000), endDate: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3600, distance: 10000, averageHeartRate: 148, calories: 520)
        pending.resume(returning: outcome == 0 ? [] : [sample])
    }
}

struct SOOMSkeletonQAView: View {
    @StateObject private var fetcher: SkeletonQAWorkoutFetcher
    @StateObject private var model: HealthKitWorkoutPreviewViewModel
    @State private var request: Task<Void, Never>?
    private let style = ProcessInfo.processInfo.environment["SOOM_SKELETON_STYLE"].flatMap(SOOMSkeleton.Layout.init(rawValue:))
    private let dark = ProcessInfo.processInfo.environment["SOOM_SKELETON_DARK"] == "1"
    private let large = ProcessInfo.processInfo.environment["SOOM_SKELETON_LARGE"] == "1"
    init() {
        let fetcher = SkeletonQAWorkoutFetcher()
        _fetcher = StateObject(wrappedValue: fetcher)
        _model = StateObject(wrappedValue: HealthKitWorkoutPreviewViewModel(fetcher: fetcher))
    }
    var body: some View {
        NavigationStack {
            if let style {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("스켈레톤 · \(style.rawValue)").font(.title2.bold())
                        SOOMSkeleton(layout: style, label: "검수 데이터 불러오는 중")
                            .frame(minHeight: style == .photo ? 220 : 0)
                        Text("합성 UI 검수 · 실제 사용자 데이터 없음").font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }.background(Color(uiColor: .systemGroupedBackground))
            } else {
                HealthKitWorkoutPreviewView(viewModel: model)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 4) {
                            Text("요청 \(fetcher.requests) · 합성 데이터").font(.caption).accessibilityIdentifier("skeleton.qa.requests")
                            HStack {
                                Button("완료") { fetcher.finish(1) }.accessibilityIdentifier("skeleton.qa.complete")
                                Button("실패") { fetcher.finish(-1) }.accessibilityIdentifier("skeleton.qa.fail")
                                Button("빈 결과") { fetcher.finish(0) }.accessibilityIdentifier("skeleton.qa.empty")
                                Button("갱신") { request = Task { await model.loadRecentWorkouts() } }.accessibilityIdentifier("skeleton.qa.refresh")
                            }.buttonStyle(.bordered).frame(minHeight: 44)
                            HStack {
                                Button("취소") { request?.cancel(); fetcher.finish(1) }.accessibilityIdentifier("skeleton.qa.cancel")
                                Button("다시 그리기") { redraw += 1 }.accessibilityIdentifier("skeleton.qa.redraw")
                            }.buttonStyle(.bordered)
                        }.padding(8).background(.regularMaterial)
                    }
                    .overlay(alignment: .topTrailing) { Text("\(redraw)").hidden() }
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(large ? .accessibility3 : .large)
    }
    @State private var redraw = 0
}
#endif
