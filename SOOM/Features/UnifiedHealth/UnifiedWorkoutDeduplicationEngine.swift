import Foundation

struct UnifiedWorkoutDeduplicationEngine {
    private let candidateThreshold = 0.75
    private let startDateTolerance: TimeInterval = 5 * 60
    private let durationToleranceRatio = 0.05
    private let distanceToleranceRatio = 0.10

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
        guard startDateDelta <= startDateTolerance else { return nil }

        let durationDeltaRatio = differenceRatio(a.durationSeconds, b.durationSeconds)
        guard durationDeltaRatio <= durationToleranceRatio else { return nil }

        var confidence = 0.0
        var reasons: [String] = []

        confidence += 0.25
        reasons.append("same workout type")

        confidence += 0.25
        reasons.append("start time within 5 minutes")

        confidence += 0.20
        reasons.append("duration difference within 5%")

        if let distanceRatio = optionalDifferenceRatio(a.distanceMeters, b.distanceMeters) {
            guard distanceRatio <= distanceToleranceRatio else { return nil }
            confidence += 0.20
            reasons.append("distance difference within 10%")
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
        let leftRank = sourcePriority(a.source)
        let rightRank = sourcePriority(b.source)

        if leftRank == rightRank {
            return a.updatedAt >= b.updatedAt ? a : b
        }

        return leftRank > rightRank ? a : b
    }

    private func sourcePriority(_ source: UnifiedDataSource) -> Int {
        switch source {
        case .manual:
            return 60
        case .soomLocal:
            return 50
        case .garmin:
            return 40
        case .appleHealthKit:
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
