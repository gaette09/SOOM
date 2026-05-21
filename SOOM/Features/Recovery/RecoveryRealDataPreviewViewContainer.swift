import SwiftData
import SwiftUI

struct RecoveryRealDataPreviewViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RecoveryRealDataPreviewView(
            viewModel: RecoveryRealDataPreviewViewModel(
                provider: UnifiedWorkoutRecoveryPreviewProvider(
                    store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
                ),
                officialProvider: RecoveryDataProviderFactory.makeProvider()
            )
        )
    }
}
