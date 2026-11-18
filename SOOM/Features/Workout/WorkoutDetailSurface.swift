import SwiftUI

/// Routes and photos share one movable detail layer. Text-only records retain
/// a normal safe-area scroll view; missing routes never create a placeholder map.
struct WorkoutDetailSurface<Actions: View, Content: View>: View {
    @StateObject private var sharing = WorkoutDetailShareActions()
    let workout: Workout?
    let route: WorkoutRoute?
    var achievements: [WorkoutAchievement] = []
    var photos: [WorkoutPhotoReference] = []
    var sharedPostManagement: FeedPostManagement? = nil
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let content: () -> Content
    private var displayRoute: WorkoutRoute? { route.map { RoutePrivacyMasker().mask(route: $0) } }
    var body: some View {
        Group {
            if let workout, WorkoutDetailSurfacePolicy.usesMediaSheet(route: displayRoute, photos: photos) {
                WorkoutMapSheetScaffold(workout: workout, routeOverride: displayRoute,
                    navigationTitle: "운동 상세", achievements: achievements, photos: photos, sharedPostManagement: sharedPostManagement) { content() }
            } else {
                SOOMScreen { content() }
                    .navigationTitle("운동 상세").navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { actions() } }
            }
        }.environment(\.workoutDetailSharing, sharing).hidesSOOMTabBar()
    }
}

struct WorkoutRecordMetricsCard: View {
    let metrics: [WorkoutCardMetric]
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .center),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: compact ? 12 : 24) {
            ForEach(metrics) { metric in
                VStack(alignment: .center, spacing: 6) {
                    Text(metric.label).font(compact ? .caption : .subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Text(metric.value).font(SOOMFont.body(18, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workout.summary.metric." + metric.label)
            }
        }
        .padding(compact ? 12 : 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(SOOMColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(SOOMColor.line.opacity(0.25), lineWidth: 1) }
    }
}

enum WorkoutDetailSurfacePolicy {
    static func usesMediaSheet(route: WorkoutRoute?, photos: [WorkoutPhotoReference]) -> Bool {
        (route?.coordinates.count ?? 0) > 1 || !photos.isEmpty
    }
}
