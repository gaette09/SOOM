import SwiftData
import SwiftUI

struct CheckInEditViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    let checkIn: RecoveryCheckIn
    let onSaved: (RecoveryCheckIn) -> Void

    var body: some View {
        CheckInEditView(
            viewModel: CheckInEditViewModel(
                checkIn: checkIn,
                store: SwiftDataCheckInStore(modelContext: modelContext)
            ),
            onSaved: onSaved
        )
    }
}

#Preview("CheckInEditViewContainer") {
    NavigationStack {
        CheckInEditViewContainer(
            checkIn: RecoveryCheckIn(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                fatigueLevel: 3,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "수면감 좋음"
            ),
            onSaved: { _ in }
        )
    }
    .modelContainer(for: CheckInRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}

