import Foundation

@MainActor
final class UnifiedWorkoutDuplicateReviewViewModel: ObservableObject {
    @Published private(set) var candidates: [UnifiedWorkoutDuplicateCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorTitle = "중복 후보를 불러오지 못했어요"

    @Published private(set) var isResolving = false
    @Published private(set) var resolutionMessage: String?
    @Published private(set) var resolutionSelection: String?
    @Published private(set) var resolutionTitle = "처리 완료"
    var applyResolution: (@MainActor ([UnifiedWorkout], UUID?, Bool) async throws -> Void)?
    private let store: any UnifiedWorkoutStore
    private let engine: UnifiedWorkoutDeduplicationEngine
    private let recentDays: Int

    init(
        store: any UnifiedWorkoutStore,
        engine: UnifiedWorkoutDeduplicationEngine = UnifiedWorkoutDeduplicationEngine(),
        recentDays: Int = 90
    ) {
        self.store = store
        self.engine = engine
        self.recentDays = recentDays
    }

    func loadDuplicateCandidates() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let workouts = try await store.fetchRecentWorkouts(days: recentDays)
            candidates = engine.findDuplicateCandidates(in: workouts)
            // Explicitly grouped originals remain selectable: the owner can
            // change the representative or split them later without deleting.
            for group in engine.canonicalGroups(workouts) where group.sourceWorkouts.count > 1
                && group.workout.preferredWorkoutID != nil
                && group.sourceWorkouts.allSatisfy({ $0.resolutionRequestID == nil }) {
                let chosen = group.sourceWorkouts.first { $0.id == group.workout.preferredWorkoutID } ?? group.sourceWorkouts[0]
                for other in group.sourceWorkouts where other.id != chosen.id {
                    candidates.append(UnifiedWorkoutDuplicateCandidate(primaryWorkout: chosen, duplicateWorkout: other,
                        confidence: 1, reasons: ["현재 대표 기록을 변경하거나 각각의 운동으로 되돌릴 수 있어요"],
                        preferredSource: chosen.source, resolutionPolicy: .needsReview))
                }
            }
            let pending = Dictionary(grouping: workouts.filter { $0.resolutionRequestID != nil }, by: { $0.resolutionRequestID! })
            for members in pending.values where members.count > 1 {
                let preferred = members.first(where: { $0.preferredWorkoutID == $0.id }) ?? members[0]
                guard let other = members.first(where: { $0.id != preferred.id }) else { continue }
                candidates.append(UnifiedWorkoutDuplicateCandidate(primaryWorkout: preferred, duplicateWorkout: other,
                    confidence: 1, reasons: ["피드 반영을 다시 시도해 주세요"], preferredSource: preferred.source, resolutionPolicy: .needsReview))
            }
        } catch {
            candidates = []
            errorTitle = "중복 후보를 불러오지 못했어요"
            errorMessage = "중복 후보를 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
        }

        isLoading = false
    }
    func resolve(_ candidate: UnifiedWorkoutDuplicateCandidate, primaryID: UUID?) async {
        guard !isResolving else { return }
        isResolving = true
        errorMessage = nil
        resolutionMessage = nil; resolutionSelection = nil
        defer { isResolving = false }
        do {
            let raw = try await store.fetchRecentWorkouts(days: 3_650)
            let selected = Set([candidate.primaryWorkout.id, candidate.duplicateWorkout.id])
            let groups = engine.canonicalGroups(raw).filter { !$0.sourceWorkouts.allSatisfy { !selected.contains($0.id) } }
            var members = groups.flatMap(\.sourceWorkouts)
            if let request = candidate.primaryWorkout.resolutionRequestID {
                let memberIDs = Set(members.map(\.id))
                members += raw.filter { $0.resolutionRequestID == request && !memberIDs.contains($0.id) }
            }
            guard members.count >= 2, primaryID.map({ id in members.contains { $0.id == id } }) ?? true else {
                throw WorkoutRecordManagementError.missingRecord
            }
            if let applyResolution { try await applyResolution(members, primaryID, primaryID == nil) }
            else {
                try await store.saveWorkouts(members.map { original in
                    var copy = original
                    copy.preferredWorkoutID = primaryID
                    copy.keepSeparate = primaryID == nil
                    return copy
                })
            }
            resolutionTitle = primaryID == nil ? "기록 구분 완료" : "대표 선택 완료"
            if let primaryID, let selected = members.first(where: { $0.id == primaryID }) {
                resolutionSelection = "\(selected.recordingSourceLabel) · \(FeedCardFormatting.distance(selected.distanceMeters)) · \(FeedCardFormatting.duration(selected.durationSeconds))"
            } else { resolutionSelection = "원본 \(members.count)개를 각각 유지" }
            resolutionMessage = primaryID == nil ? "각각의 운동으로 유지했어요." : "대표 기록의 거리·시간을 사용하고 빠진 측정값을 다른 기기에서 보완해요. 원본은 모두 보관됩니다."
            await loadDuplicateCandidates()
            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
        } catch {
            errorTitle = "대표 기록을 변경하지 못했어요"
            errorMessage = "대표 기록 변경을 완료하지 못했어요. 저장된 원본은 유지됩니다. 다시 시도해 주세요."
        }
    }

}
