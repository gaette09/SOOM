import Foundation

struct UnifiedWorkoutCanonicalGroup {
    let workout: UnifiedWorkout
    let sourceWorkouts: [UnifiedWorkout]
}

struct UnifiedWorkoutDeduplicationEngine {
    private let candidateThreshold = 0.75
    private let startDateTolerance: TimeInterval = 10 * 60
    private let durationToleranceRatio = 0.25
    private let distanceToleranceRatio = 0.25

    /// Keep each provider's raw record and external ID for future updates, but
    /// present and analyse one enriched workout for the same physical session.
    func canonicalWorkouts(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkout] {
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("canonicalize")
        #endif
        return canonicalGroups(workouts).map(\.workout)
    }

    func canonicalGroups(_ workouts: [UnifiedWorkout]) -> [UnifiedWorkoutCanonicalGroup] {
        // Invalid/non-finite dates retain the original scan semantics.
        let hasFiniteStartDates = workouts.allSatisfy { $0.startDate.timeIntervalSinceReferenceDate.isFinite }
        var groups: [[UnifiedWorkout]] = []
        for workout in workouts.sorted(by: {
            $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
        }) {
            var match: Int?
            for index in groups.indices.reversed() {
                if workout.startDate.timeIntervalSince(groups[index][0].startDate) > 120,
                   workout.preferredWorkoutID == nil {
                    // Groups retain their first member and are inserted in chronological
                    // order. All remaining reverse-scan candidates are equally old.
                    if hasFiniteStartDates { break }
                    continue
                }
                if groups[index].contains(where: { isSameActivity($0, workout) }) {
                    match = index
                    break
                }
            }
            if let index = match {
                groups[index].append(workout)
            } else {
                groups.append([workout])
            }
        }
        let positions = Dictionary(workouts.enumerated().map { ($0.element.id, $0.offset) },
                                   uniquingKeysWith: min)
        return groups.map { members in
            let primary = members.reduce(members[0]) { preferredWorkout(between: $0, and: $1) }
            // A provisional single card prevents duplicate feed/analysis entries,
            // but cross-device measurements are combined only after owner confirmation.
            let ordered = members.sorted { $0.id.uuidString < $1.id.uuidString }
            let confirmed = primary.preferredWorkoutID != nil
            let enriched = confirmed ? ordered.reduce(primary) { merged($0, with: $1) } : primary
            return UnifiedWorkoutCanonicalGroup(workout: enriched, sourceWorkouts: members)
        }.sorted { left, right in
            let leftPosition = left.sourceWorkouts.compactMap { positions[$0.id] }.min() ?? 0
            let rightPosition = right.sourceWorkouts.compactMap { positions[$0.id] }.min() ?? 0
            return leftPosition < rightPosition
        }
    }

    /// Automatic grouping is stricter than the review screen's candidate score.
    /// Similar workouts on the same day must not be silently collapsed.
    func isSameActivity(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> Bool {
        if isSameExternalWorkout(a, b) { return true }
        let leftGroup = a.preferredWorkoutID ?? a.id
        let rightGroup = b.preferredWorkoutID ?? b.id
        if leftGroup == rightGroup { return true }
        if a.keepSeparate == true || b.keepSeparate == true { return false }
        if a.preferredWorkoutID != nil || b.preferredWorkoutID != nil { return false }
        guard a.source != .manual, b.source != .manual,
              a.workoutType == b.workoutType, a.workoutType != .other else { return false }
        let startDelta = abs(a.startDate.timeIntervalSince(b.startDate))
        let endDelta = abs(a.endDate.timeIntervalSince(b.endDate))
        guard startDelta <= 120, endDelta <= 120 else { return false }
        let sameBoundaries = startDelta <= 10 && endDelta <= 10
        let durationDifference = differenceRatio(a.durationSeconds, b.durationSeconds)
        guard durationDifference <= 0.05 || (sameBoundaries && durationDifference <= 0.20) else { return false }
        if let firstDistance = positive(a.distanceMeters), let secondDistance = positive(b.distanceMeters) {
            return differenceRatio(firstDistance, secondDistance) <= 0.08
        }
        // When distance is unavailable, require close boundaries plus a
        // matching independent metric, or nearly exact start/end timestamps.
        guard startDelta <= 30, endDelta <= 30 else { return false }
        if let firstHR = positive(a.averageHeartRate), let secondHR = positive(b.averageHeartRate) {
            return differenceRatio(firstHR, secondHR) <= 0.05
        }
        if let firstEnergy = positive(a.activeEnergyKcal), let secondEnergy = positive(b.activeEnergyKcal) {
            return differenceRatio(firstEnergy, secondEnergy) <= 0.08
        }
        return sameBoundaries
    }

    /// Publication identity is pinned once. Before that, choose coverage rather
    /// than a provider brand; UUID resolves ties independently of fetch order.
    func automaticPublicationPrimary(in members: [UnifiedWorkout], measuredCoverage: [UUID: Int] = [:]) -> UnifiedWorkout? {
        members.sorted { a, b in
            let aPinned = a.preferredWorkoutID == a.id
            let bPinned = b.preferredWorkoutID == b.id
            if aPinned != bPinned { return aPinned }
            let aShared = a.recordVisibility.map { $0 != .privatePost } ?? false
            let bShared = b.recordVisibility.map { $0 != .privatePost } ?? false
            if aShared != bShared { return aShared }
            let aScore = coverageScore(a) + (measuredCoverage[a.id] ?? 0)
            let bScore = coverageScore(b) + (measuredCoverage[b.id] ?? 0)
            if aScore != bScore { return aScore > bScore }
            let aDuration = a.durationSeconds.isFinite ? max(0, a.durationSeconds) : 0
            let bDuration = b.durationSeconds.isFinite ? max(0, b.durationSeconds) : 0
            if aDuration != bDuration { return aDuration > bDuration }
            return a.id.uuidString < b.id.uuidString
        }.first
    }

    private func coverageScore(_ workout: UnifiedWorkout) -> Int {
        [workout.distanceMeters, workout.activeEnergyKcal, workout.averageHeartRate,
         workout.maxHeartRate, workout.averageSpeedMetersPerSecond, workout.elevationGainMeters,
         workout.averagePowerWatts, workout.averageCadence].reduce(0) { $0 + (positive($1) == nil ? 0 : 1) }
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func merged(_ primary: UnifiedWorkout, with other: UnifiedWorkout) -> UnifiedWorkout {
        UnifiedWorkout(
            id: primary.id, externalId: primary.externalId, source: primary.source,
            workoutType: primary.workoutType, startDate: primary.startDate, endDate: primary.endDate,
            durationSeconds: primary.durationSeconds,
            distanceMeters: positive(primary.distanceMeters) ?? positive(other.distanceMeters),
            activeEnergyKcal: positive(primary.activeEnergyKcal) ?? positive(other.activeEnergyKcal),
            averageHeartRate: positive(primary.averageHeartRate) ?? positive(other.averageHeartRate),
            maxHeartRate: positive(primary.maxHeartRate) ?? positive(other.maxHeartRate),
            averageSpeedMetersPerSecond: primary.durationSeconds > 0
                ? (positive(primary.distanceMeters) ?? positive(other.distanceMeters)).map { $0 / primary.durationSeconds }
                : positive(primary.averageSpeedMetersPerSecond),
            elevationGainMeters: primary.elevationGainMeters ?? other.elevationGainMeters,
            averagePowerWatts: positive(primary.averagePowerWatts) ?? positive(other.averagePowerWatts),
            averageCadence: positive(primary.averageCadence) ?? positive(other.averageCadence),
            routeMissingReason: primary.routeMissingReason,
            dataQuality: primary.dataQuality, isExcludedFromAnalysis: primary.isExcludedFromAnalysis,
            createdAt: primary.createdAt, updatedAt: max(primary.updatedAt, other.updatedAt),
            companionNames: primary.companionNames.isEmpty ? other.companionNames : primary.companionNames,
            userTitle: primary.userTitle ?? other.userTitle,
            userDescription: primary.userDescription ?? other.userDescription,
            sharingVisibilityRaw: primary.sharingVisibilityRaw,
            isBookmarked: (primary.isBookmarked == true || other.isBookmarked == true)
                ? true : (primary.isBookmarked ?? other.isBookmarked),
            deviceName: primary.deviceName ?? other.deviceName,
            locationName: primary.locationName ?? other.locationName,
            preferredWorkoutID: primary.preferredWorkoutID, keepSeparate: primary.keepSeparate, resolutionRequestID: primary.resolutionRequestID
        )
    }

    /// Check both arrival orders before publishing a newly recorded activity.
    /// A secondary source or unfinished publication request must never bypass
    /// the user's representative choice.
    func needsSourceSelectionBeforePublication(_ workout: UnifiedWorkout, in originals: [UnifiedWorkout]) -> Bool {
        if workout.resolutionRequestID != nil { return true }
        if let selected = workout.preferredWorkoutID, selected != workout.id { return true }
        return originals.contains { compare(workout, $0) != nil }
    }

    func findDuplicateCandidates(in workouts: [UnifiedWorkout]) -> [UnifiedWorkoutDuplicateCandidate] {
        guard workouts.count > 1 else { return [] }

        var candidates: [UnifiedWorkoutDuplicateCandidate] = []

        for leftIndex in workouts.indices {
            for rightIndex in workouts.index(after: leftIndex)..<workouts.endIndex {
                if let candidate = compare(workouts[leftIndex], workouts[rightIndex]) {
                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted {
            if $0.confidence == $1.confidence {
                return $0.primaryWorkout.startDate > $1.primaryWorkout.startDate
            }
            return $0.confidence > $1.confidence
        }
    }

    func compare(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> UnifiedWorkoutDuplicateCandidate? {
        guard a.id != b.id, a.keepSeparate != true, b.keepSeparate != true else { return nil }
        if (a.preferredWorkoutID ?? a.id) == (b.preferredWorkoutID ?? b.id) { return nil }
        if isSameExternalWorkout(a, b) {
            return makeCandidate(
                a,
                b,
                confidence: 0.98,
                reasons: ["same externalId and source"],
                resolutionPolicy: .keepPrimary
            )
        }

        guard a.workoutType == b.workoutType else { return nil }

        let startDateDelta = abs(a.startDate.timeIntervalSince(b.startDate))
        guard startDateDelta <= startDateTolerance,
              abs(a.endDate.timeIntervalSince(b.endDate)) <= startDateTolerance else { return nil }
        let shorter = min(a.endDate.timeIntervalSince(a.startDate), b.endDate.timeIntervalSince(b.startDate))
        let overlap = min(a.endDate, b.endDate).timeIntervalSince(max(a.startDate, b.startDate))
        guard shorter > 0, overlap / shorter >= 0.85 else { return nil }

        let durationDeltaRatio = differenceRatio(a.durationSeconds, b.durationSeconds)
        guard durationDeltaRatio <= durationToleranceRatio else { return nil }

        var confidence = 0.0
        var reasons: [String] = []

        confidence += 0.25
        reasons.append("same workout type")

        confidence += 0.25
        reasons.append("start and end within 10 minutes")

        confidence += 0.20
        reasons.append("duration difference within 25%")

        if let distanceRatio = optionalDifferenceRatio(a.distanceMeters, b.distanceMeters) {
            guard distanceRatio <= distanceToleranceRatio else { return nil }
            confidence += 0.20
            reasons.append("distance difference within 25%")
        }

        if a.source != b.source {
            confidence += 0.10
            reasons.append("cross-source duplicate candidate")
        }

        if let heartRateRatio = optionalDifferenceRatio(a.averageHeartRate, b.averageHeartRate),
           heartRateRatio <= 0.10 {
            confidence += 0.05
            reasons.append("average heart rate is similar")
        }

        let clampedConfidence = min(confidence, 0.95)
        guard clampedConfidence >= candidateThreshold else { return nil }

        let resolutionPolicy: UnifiedWorkoutDuplicateResolutionPolicy = clampedConfidence >= 0.90
            ? .keepPrimary
            : .needsReview

        return makeCandidate(
            a,
            b,
            confidence: clampedConfidence,
            reasons: reasons,
            resolutionPolicy: resolutionPolicy
        )
    }

    private func isSameExternalWorkout(_ a: UnifiedWorkout, _ b: UnifiedWorkout) -> Bool {
        guard let leftExternalId = a.externalId, let rightExternalId = b.externalId else {
            return false
        }
        return leftExternalId == rightExternalId && a.source == b.source
    }

    private func makeCandidate(
        _ a: UnifiedWorkout,
        _ b: UnifiedWorkout,
        confidence: Double,
        reasons: [String],
        resolutionPolicy: UnifiedWorkoutDuplicateResolutionPolicy
    ) -> UnifiedWorkoutDuplicateCandidate {
        let preferred = preferredWorkout(between: a, and: b)
        let duplicate = preferred.id == a.id ? b : a

        return UnifiedWorkoutDuplicateCandidate(
            primaryWorkout: preferred,
            duplicateWorkout: duplicate,
            confidence: confidence,
            reasons: reasons,
            preferredSource: preferred.source,
            resolutionPolicy: resolutionPolicy
        )
    }

    private func preferredWorkout(between a: UnifiedWorkout, and b: UnifiedWorkout) -> UnifiedWorkout {
        if a.preferredWorkoutID == a.id { return a }
        if b.preferredWorkoutID == b.id { return b }
        // Keep the identity of an already shared or user-edited card stable.
        let leftUserState = userStateRank(a)
        let rightUserState = userStateRank(b)
        if leftUserState != rightUserState { return leftUserState > rightUserState ? a : b }
        let leftRank = sourcePriority(a.source)
        let rightRank = sourcePriority(b.source)

        if leftRank == rightRank {
            let leftDetail = detailRank(a)
            let rightDetail = detailRank(b)
            if leftDetail != rightDetail { return leftDetail > rightDetail ? a : b }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
            return a.id.uuidString < b.id.uuidString ? a : b
        }

        return leftRank > rightRank ? a : b
    }

    private func detailRank(_ workout: UnifiedWorkout) -> Int {
        (workout.routeMissingReason == .none ? 4 : 0)
            + (positive(workout.distanceMeters) != nil ? 2 : 0)
            + (positive(workout.averageHeartRate) != nil ? 1 : 0)
            + (positive(workout.averagePowerWatts) != nil ? 1 : 0)
            + (positive(workout.averageCadence) != nil ? 1 : 0)
    }

    private func userStateRank(_ workout: UnifiedWorkout) -> Int {
        if workout.sharingVisibilityRaw == "public" || workout.sharingVisibilityRaw == "publicPost" { return 2 }
        if workout.userTitle != nil || workout.userDescription != nil || workout.isBookmarked == true { return 1 }
        return 0
    }

    private func sourcePriority(_ source: UnifiedDataSource) -> Int {
        switch source {
        case .manual:
            return 60
        case .soomLocal:
            return 50
        case .garmin:
            return 40
        case .strava:
            return 35
        case .appleHealthKit:
            return 32
        case .googleHealth:
            return 30
        case .samsungHealth:
            return 20
        case .healthConnect:
            return 15
        case .unknown:
            return 0
        }
    }

    private func differenceRatio(_ a: Double, _ b: Double) -> Double {
        let baseline = max(abs(a), abs(b))
        guard baseline > 0 else { return 0 }
        return abs(a - b) / baseline
    }

    private func optionalDifferenceRatio(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return differenceRatio(a, b)
    }
}

/// Derived from account-local raw records; never saved over originals or sent to a public feed.
struct UnifiedWorkoutProvenance {
    let group: UnifiedWorkoutCanonicalGroup
    var isConfirmed: Bool { group.sourceWorkouts.count > 1 && group.workout.preferredWorkoutID != nil }
    var status: String {
        if group.sourceWorkouts.contains(where: { $0.resolutionRequestID != nil }) { return "병합 선택 저장 · 피드 반영 대기" }
        if isConfirmed { return "확인한 병합 · 원본 \(group.sourceWorkouts.count)건" }
        if group.sourceWorkouts.count > 1 { return "중복 표시 정리 · 병합 확인 전 · 원본 \(group.sourceWorkouts.count)건" }
        if group.workout.preferredWorkoutID != nil { return "병합 선택 있음 · 이 기기 원본 1건 · 연결 원본 확인 필요" }
        if group.workout.keepSeparate == true { return "각각 유지 · 이 카드 원본 1건" }
        return "수집 원본 1건 · 다른 기기 수집 여부 확인 전"
    }
    var orderedSources: [UnifiedWorkout] {
        group.sourceWorkouts.sorted {
            if $0.id == group.workout.id && $1.id != group.workout.id { return true }
            if $1.id == group.workout.id { return false }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    /// Matches the canonical metric policy: chosen record wins valid conflicts;
    /// only absent/invalid positive measurements use deterministic fallback.
    func source(for value: KeyPath<UnifiedWorkout, Double?>) -> UnifiedWorkout? {
        (isConfirmed ? orderedSources : [group.workout]).first {
            guard let number = $0[keyPath: value] else { return false }
            return number.isFinite && number > 0
        }
    }
}

extension UnifiedWorkout {
    var recordingSourceLabel: String {
        if let name = deviceName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if name.localizedCaseInsensitiveContains("apple watch")
                || name.localizedCaseInsensitiveContains("soom watch")
                || name.localizedCaseInsensitiveContains("soomwatch") { return "Apple Watch · \(name)" }
            if name.localizedCaseInsensitiveContains("iphone") { return "iPhone · \(name)" }
            return "\(name) · \(source.rawValue)"
        }
        if source == .soomLocal { return "SOOM iPhone" }
        if source == .appleHealthKit { return "Apple 건강 · 기기 미확인" }
        return source.rawValue
    }
}
