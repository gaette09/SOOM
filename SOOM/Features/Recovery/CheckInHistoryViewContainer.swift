import SwiftData
import SwiftUI

struct CheckInHistoryViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        CheckInHistoryView(
            viewModel: CheckInHistoryViewModel(
                store: SwiftDataCheckInStore(modelContext: modelContext)
            )
        )
    }
}

#Preview("CheckInHistoryViewContainer") {
    NavigationStack {
        CheckInHistoryViewContainer()
    }
    .modelContainer(for: CheckInRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}
