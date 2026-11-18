import Foundation
import SwiftData

/// Public source snapshot: owner-specific repair configuration is deliberately omitted.
/// The exact deployed source remains private. Public builds always keep the original route.
@MainActor final class ApprovedWorkoutMapRepair {
    // Non-personal sentinel retained for existing view call sites.
    static let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    func resolve(_ original: WorkoutRoute?, viewerID: UUID?, storage: HealthAccountStorageController,
                 context: ModelContext) -> WorkoutRoute? {
        original
    }
}
