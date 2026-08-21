import SwiftData
import SwiftUI

struct RecoveryViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let snapshotStore = SwiftDataDailyRecoverySnapshotStore(modelContext: modelContext)
        let unifiedWorkoutStore = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)

        // Production Recovery reads latest check-in from SwiftData.
        // Recovery Timeline reads persisted daily snapshots from the same app container.
        // Activity source matches Feed's recovery insight card (UnifiedWorkoutRecoveryPreviewProvider)
        // so the summary card and this detail screen never disagree on the same day's numbers.
        RecoveryView(
            viewModel: RecoveryViewModel(
                provider: UnifiedWorkoutRecoveryDataProvider(
                    previewProvider: UnifiedWorkoutRecoveryPreviewProvider(store: unifiedWorkoutStore)
                ),
                checkInStore: SwiftDataCheckInStore(modelContext: modelContext),
                timelineBuilder: RecoveryTimelineBuilder(
                    snapshotStore: snapshotStore
                ),
                weeklySummaryBuilder: WeeklyRecoverySummaryBuilder(
                    snapshotStore: snapshotStore
                ),
                snapshotWriter: DailyRecoverySnapshotWriter(snapshotStore: snapshotStore)
            )
        )
    }
}

#Preview("RecoveryViewContainer") {
    NavigationStack {
        RecoveryViewContainer()
    }
    .modelContainer(
        for: [
            CheckInRecord.self,
            DailyRecoverySnapshotRecord.self,
            UnifiedWorkoutRecord.self,
            PersistedWorkoutRoute.self
        ],
        inMemory: true
    )
    .preferredColorScheme(.light)
}
