import SwiftData
import SwiftUI

struct UnifiedWorkoutLibraryViewContainer: View {
    @EnvironmentObject private var healthStorage: HealthAccountStorageController
    @Environment(\.modelContext) private var modelContext
    var body: some View {
        UnifiedWorkoutLibraryView(viewModel: UnifiedWorkoutLibraryViewModel(
            store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext),
            includesLocalDemoSamples: ReviewDemoMode.isActive
                && HealthCloudJournal.accountID(for: modelContext) == ReviewDemoMode.userID),
            dataRevision: healthStorage.dataRevision)
    }
}
