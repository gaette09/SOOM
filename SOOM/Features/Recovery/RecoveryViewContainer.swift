import SwiftData
import SwiftUI

struct RecoveryViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    private let activitySource: RecoveryActivitySource

    init(activitySource: RecoveryActivitySource = .defaultSource) {
        self.activitySource = activitySource
    }

    var body: some View {
        let snapshotStore = SwiftDataDailyRecoverySnapshotStore(modelContext: modelContext)

        // Production Recovery reads latest check-in from SwiftData.
        // Recovery Timeline reads persisted daily snapshots from the same app container.
        // RecoveryView() defaults stay mock-backed for Preview/test rollback.
        // The activity source is an internal development switch; default keeps the existing mock-backed flow.
        RecoveryView(
            viewModel: RecoveryViewModel(
                provider: RecoveryDataProviderFactory.makeProvider(source: activitySource),
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
    .modelContainer(for: [CheckInRecord.self, DailyRecoverySnapshotRecord.self], inMemory: true)
    .preferredColorScheme(.light)
}
