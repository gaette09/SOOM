import SwiftData
import SwiftUI

struct CheckInDetailViewContainer: View {
    @Environment(\.modelContext) private var modelContext

    let checkIn: RecoveryCheckIn
    let onUpdated: (RecoveryCheckIn) -> Void
    let onDeleted: (UUID) -> Void

    var body: some View {
        CheckInDetailView(
            checkIn: checkIn,
            viewModel: CheckInDetailViewModel(
                store: SwiftDataCheckInStore(modelContext: modelContext),
                onDeleted: onDeleted
            ),
            onUpdated: onUpdated
        )
    }
}

#Preview("CheckInDetailViewContainer") {
    NavigationStack {
        CheckInDetailViewContainer(
            checkIn: RecoveryCheckIn(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                fatigueLevel: 3,
                sleepQuality: 4,
                muscleSoreness: 2,
                moodLevel: 4,
                note: "수면감은 좋고 다리는 조금 가벼움"
            ),
            onUpdated: { _ in },
            onDeleted: { _ in }
        )
    }
    .modelContainer(for: CheckInRecord.self, inMemory: true)
    .preferredColorScheme(.light)
}
