import SwiftData
import SwiftUI

struct AnalysisViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let provider = UnifiedWorkoutWeeklyProgressProvider(store: store)
        let trendProvider = UnifiedWorkoutGrowthTrendProvider(store: store)
        let personalRecordProvider = UnifiedWorkoutPersonalRecordProvider(store: store)

        AnalysisView(
            viewModel: AnalysisViewModel(
                provider: provider,
                fourWeekTrendProvider: trendProvider,
                personalRecordProvider: personalRecordProvider
            )
        )
    }
}

#Preview("AnalysisViewContainer") {
    NavigationStack {
        AnalysisViewContainer()
            .environmentObject(DashboardViewModel(harness: MockWorkoutHarness()))
    }
    .modelContainer(for: UnifiedWorkoutRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}
