import SwiftData
import SwiftUI

struct CheckInViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Production save flow uses SwiftData. CheckInView() defaults stay mock-backed for Preview/test rollback.
        CheckInView(
            viewModel: CheckInViewModelFactory.makeSwiftDataViewModel(
                modelContext: modelContext
            )
        )
    }
}

#Preview("CheckInViewContainer") {
    NavigationStack {
        CheckInViewContainer()
    }
    .modelContainer(for: CheckInRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}
