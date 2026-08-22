import SwiftUI
import HealthKit

/// Feed-detail-migration batch 1: pure container swap-in point for `WorkoutDetailView`.
/// Delegates entirely to `WorkoutDetailView` today, so output is byte-identical to the
/// existing Activity detail — this batch only proves the navigation swap works before
/// any new PDF-derived sections land in later batches. See feed-detail-migration-plan.md.
struct WorkoutDeepDetailView: View {
    let workout: Workout
    var comparisonWorkouts: [Workout] = []
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?
    var splitDataProvider: WorkoutSplitDataProviding?
    var comparisonInsightOverride: WorkoutComparisonInsight?
    var courseRecordOverride: CourseRecord?
    var courseProgressionOverride: CourseProgressionTimeline?
    var climbInsightOverride: ClimbInsight?
    var terrainInsightOverride: TerrainInsight?
    var detailRouteOverride: WorkoutRoute?
    var samplesOverride: [WorkoutSample]?
    var splitsOverride: [WorkoutSplit]?
    var heartRateChartSamplesOverride: [WorkoutDistanceChartSample]?
    var relativeEffortComparisonOverride: RelativeEffortComparison?
    var achievementsOverride: [WorkoutAchievement]?
    var fitnessTrendOverride: FitnessTrend?
    var sourceUnifiedWorkout: UnifiedWorkout? = nil
    var routeAttachmentAction: ActivityDetailGPXRouteImportAction?
    var companionUpdateAction: WorkoutCompanionUpdateAction?

    var body: some View {
        WorkoutDetailView(
            workout: workout,
            comparisonWorkouts: comparisonWorkouts,
            healthKitWorkout: healthKitWorkout,
            zoneDataProvider: zoneDataProvider,
            splitDataProvider: splitDataProvider,
            comparisonInsightOverride: comparisonInsightOverride,
            courseRecordOverride: courseRecordOverride,
            courseProgressionOverride: courseProgressionOverride,
            climbInsightOverride: climbInsightOverride,
            terrainInsightOverride: terrainInsightOverride,
            detailRouteOverride: detailRouteOverride,
            samplesOverride: samplesOverride,
            splitsOverride: splitsOverride,
            heartRateChartSamplesOverride: heartRateChartSamplesOverride,
            relativeEffortComparisonOverride: relativeEffortComparisonOverride,
            achievementsOverride: achievementsOverride,
            fitnessTrendOverride: fitnessTrendOverride,
            sourceUnifiedWorkout: sourceUnifiedWorkout,
            routeAttachmentAction: routeAttachmentAction,
            companionUpdateAction: companionUpdateAction
        )
    }
}
