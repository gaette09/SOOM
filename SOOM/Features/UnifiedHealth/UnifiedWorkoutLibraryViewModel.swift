import Foundation

@MainActor
final class UnifiedWorkoutLibraryViewModel: ObservableObject {
    @Published private(set) var workouts: [UnifiedWorkout] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updatingWorkoutIDs: Set<UUID> = []

    private var reloadPending = false
    private var requestedRevision: Int?
    private var loadedRevision: Int?
    private let store: any UnifiedWorkoutStore
    private let recentDays: Int
    private let includesLocalDemoSamples: Bool

    init(
        store: any UnifiedWorkoutStore,
        recentDays: Int = 30,
        includesLocalDemoSamples: Bool = false
    ) {
        self.store = store
        self.recentDays = recentDays
        self.includesLocalDemoSamples = includesLocalDemoSamples
    }

    /// Same retained model + successful local data revision can reuse its list.
    /// Explicit refresh/mutations still use loadRecentWorkouts directly.
    func loadIfNeeded(revision: Int) async {
        guard loadedRevision != revision else { return }
        let changed = requestedRevision != revision
        requestedRevision = revision
        await loadRecentWorkouts(requiresFollowUp: changed)
    }

    func loadRecentWorkouts(requiresFollowUp: Bool = false) async {
        guard !isLoading else {
            reloadPending = reloadPending || requiresFollowUp
            return
        }

        isLoading = true
        errorMessage = nil

        repeat {
        reloadPending = false
        errorMessage = nil
        let revision = requestedRevision
        do {
            let raw = try await store.fetchRecentWorkouts(days: recentDays)
            workouts = UnifiedWorkoutDeduplicationEngine().canonicalGroups(raw)
                .filter { includesLocalDemoSamples || $0.sourceWorkouts.contains(where: { $0.source.isImported }) }
                .map(\.workout)
            loadedRevision = revision
        } catch {
            errorMessage = "가져온 운동 기록을 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
        }

        } while reloadPending && !Task.isCancelled
        isLoading = false
    }

    func toggleExcluded(id: UUID) async {
        guard let workout = workouts.first(where: { $0.id == id }),
              !updatingWorkoutIDs.contains(id) else {
            return
        }

        let nextExcludedState = !workout.isExcludedFromAnalysis
        updatingWorkoutIDs.insert(id)
        errorMessage = nil

        do {
            try await store.markExcludedFromAnalysis(id: id, isExcluded: nextExcludedState)
            updateWorkout(id: id, isExcludedFromAnalysis: nextExcludedState)
        } catch {
            errorMessage = "분석 제외 상태를 변경하지 못했어요. 잠시 후 다시 시도해 주세요."
        }

        updatingWorkoutIDs.remove(id)
    }

    private func updateWorkout(id: UUID, isExcludedFromAnalysis: Bool) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let workout = workouts[index]
        workouts[index] = UnifiedWorkout(
            id: workout.id,
            externalId: workout.externalId,
            source: workout.source,
            workoutType: workout.workoutType,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.durationSeconds,
            distanceMeters: workout.distanceMeters,
            activeEnergyKcal: workout.activeEnergyKcal,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate,
            averageSpeedMetersPerSecond: workout.averageSpeedMetersPerSecond,
            elevationGainMeters: workout.elevationGainMeters,
            averagePowerWatts: workout.averagePowerWatts,
            averageCadence: workout.averageCadence,
            routeMissingReason: workout.routeMissingReason,
            dataQuality: workout.dataQuality,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: workout.createdAt,
            updatedAt: Date(),
            companionNames: workout.companionNames,
            userTitle: workout.userTitle,
            userDescription: workout.userDescription,
            sharingVisibilityRaw: workout.sharingVisibilityRaw,
            isBookmarked: workout.isBookmarked,
            deviceName: workout.deviceName,
            locationName: workout.locationName, preferredWorkoutID: workout.preferredWorkoutID, keepSeparate: workout.keepSeparate, resolutionRequestID: workout.resolutionRequestID
        )
    }
}
