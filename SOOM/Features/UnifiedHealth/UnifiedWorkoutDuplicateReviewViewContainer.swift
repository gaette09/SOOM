import SwiftData
import SwiftUI

struct UnifiedWorkoutDuplicateReviewViewContainer: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController

    var body: some View {
        UnifiedWorkoutDuplicateReviewView(viewModel: makeViewModel())
    }

    private func makeViewModel() -> UnifiedWorkoutDuplicateReviewViewModel {
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: SwiftDataUnifiedWorkoutStore(modelContext: modelContext))
        model.applyResolution = { members, primaryID, keepSeparate in
            let owner = storage.userID
            let scope = storage.scopeID
            @MainActor func validate() throws {
                guard storage.userID == owner, storage.scopeID == scope,
                      modelContext.container === storage.container else { throw CommunitySafetyError.accountChanged }
            }
            try validate()
            if !ImportedWorkoutPublication.usesLegacyPublication {
                try ProfileOnlyLocalDuplicateResolution.apply(memberIDs:Set(members.map(\.id)),primaryID:primaryID,
                    keepSeparate:keepSeparate,context:modelContext,validate:validate)
                NotificationCenter.default.post(name:WorkoutRecordManagement.didChange,object:owner)
                return
            }
            let request = UUID()
            let ids = Set(members.map(\.id))
            let records = try modelContext.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).filter { ids.contains($0.id) }
            for record in records {
                record.preferredWorkoutID = primaryID
                record.keepSeparate = keepSeparate
                record.resolutionRequestID = request
                record.updatedAt = Date()
                try HealthCloudJournal.workout(record, context: modelContext)
            }
            try HealthCloudJournal.commit(modelContext)
            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
            if keepSeparate {
                for member in members where member.sharingVisibilityRaw == "source_review_pending" || ImportedWorkoutPublication.isPending(member.sharingVisibilityRaw) {
                    let management = WorkoutRecordManagement(workout: member)
                    management.configure(context: modelContext, storage: storage)
                    guard await management.setVisibility(ImportedWorkoutPublication.resolutionAudience(member.sharingVisibilityRaw, autoPublish: storage.autoPublishImportedWorkouts))
                    else { throw WorkoutRecordManagementError.unavailable }
                    try validate()
                }
            }
            if !keepSeparate, let primaryID {
                // Make secondary posts private; never delete their comments,
                // photos or original measurements. These calls are retryable.
                for member in members where member.id != primaryID {
                    let management = WorkoutRecordManagement(workout: member)
                    management.configure(context: modelContext, storage: storage)
                    guard await management.setVisibility(.privatePost) else { throw WorkoutRecordManagementError.unavailable }
                    try validate()
                }
                guard let chosen = members.first(where: { $0.id == primaryID }) else { throw WorkoutRecordManagementError.missingRecord }
                let management = WorkoutRecordManagement(workout: chosen)
                management.configure(context: modelContext, storage: storage)
                await management.refreshSharing()
                try validate()
                let isNew = chosen.sharingVisibilityRaw == "source_review_pending" || ImportedWorkoutPublication.isPending(chosen.sharingVisibilityRaw)
                let target = isNew ? ImportedWorkoutPublication.resolutionAudience(chosen.sharingVisibilityRaw, autoPublish: storage.autoPublishImportedWorkouts) : (management.visibility ?? .privatePost)
                guard await management.setVisibility(target)
                else { throw WorkoutRecordManagementError.unavailable }
                try validate()
            }
            for record in records {
                record.resolutionRequestID = nil
                record.updatedAt = Date()
                try HealthCloudJournal.workout(record, context: modelContext)
            }
            try HealthCloudJournal.commit(modelContext)
        }
        return model
    }
}


/// Local representative metadata only. There is deliberately no remote dependency.
@MainActor enum ProfileOnlyLocalDuplicateResolution {
    static func apply(memberIDs:Set<UUID>,primaryID:UUID?,keepSeparate:Bool,context:ModelContext,
                      validate:() throws -> Void) throws {
        try validate()
        guard !memberIDs.isEmpty,keepSeparate || primaryID.map(memberIDs.contains)==true else {throw WorkoutRecordManagementError.missingRecord}
        let records=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).filter{memberIDs.contains($0.id)}
        guard records.count==memberIDs.count else {throw WorkoutRecordManagementError.missingRecord}
        for record in records {
            record.preferredWorkoutID=primaryID;record.keepSeparate=keepSeparate
            record.resolutionRequestID=nil;record.updatedAt=Date()
            try HealthCloudJournal.workout(record,context:context)
        }
        try HealthCloudJournal.commit(context)
    }
}
