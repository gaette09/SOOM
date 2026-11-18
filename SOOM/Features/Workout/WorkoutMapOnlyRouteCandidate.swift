import Foundation

/// Validated map geometry only. No persistence, sharing or analytics replacement. Supplied geometry still goes through the normal masker.
struct WorkoutMapOnlyRouteCandidate {
    struct Gap: Hashable {
        let before: UUID
        let after: UUID
    }
    private let original: WorkoutRoute
    private let display: WorkoutRoute

    init?(original: WorkoutRoute, display: WorkoutRoute, sourceInsertions: [WorkoutRouteCoordinate],
          joinedGaps: Set<Gap>) {
        guard !original.privacyMaskApplied, !display.privacyMaskApplied,
              original.workoutId == display.workoutId, original.source == display.source,
              !joinedGaps.isEmpty, !sourceInsertions.isEmpty,
              original.coordinates.count >= 2,
              Set(original.coordinates.map(\.id)).count == original.coordinates.count,
              Set(display.coordinates.map(\.id)).count == display.coordinates.count,
              Set(sourceInsertions.map(\.id)).count == sourceInsertions.count else { return nil }
        let raw = original.coordinates, merged = display.coordinates
        let rawIDs = Set(raw.map(\.id)), insertedIDs = Set(sourceInsertions.map(\.id))
        guard rawIDs.isDisjoint(with: insertedIDs), Set(merged.map(\.id)) == rawIDs.union(insertedIDs),
              merged.first?.id == raw.first?.id, merged.last?.id == raw.last?.id else { return nil }
        func sameFix(_ a: WorkoutRouteCoordinate, _ b: WorkoutRouteCoordinate) -> Bool {
            a.id == b.id && a.latitude == b.latitude && a.longitude == b.longitude &&
            a.altitude == b.altitude && a.timestamp == b.timestamp
        }
        let retained = merged.filter { rawIDs.contains($0.id) }
        guard retained.count == raw.count, zip(raw, retained).allSatisfy({ sameFix($0, $1) }) else { return nil }
        let dictionary = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        guard sourceInsertions.allSatisfy({ fix in dictionary[fix.id].map { sameFix(fix, $0) } == true }) else { return nil }
        var ranges: [ClosedRange<Date>] = []
        var observedGaps: Set<Gap> = []
        for i in 1..<raw.count {
            let a = raw[i - 1], b = raw[i], gap = Gap(before: a.id, after: b.id)
            let originalBreak = a.segmentIndex != b.segmentIndex
            let displayBreak = dictionary[a.id]!.segmentIndex != dictionary[b.id]!.segmentIndex
            if joinedGaps.contains(gap) {
                guard originalBreak, !displayBreak, let start = a.timestamp, let end = b.timestamp, start < end else { return nil }
                ranges.append(start...end); observedGaps.insert(gap)
            } else if originalBreak != displayBreak { return nil }
        }
        guard observedGaps == joinedGaps,
              sourceInsertions.allSatisfy({ p in p.timestamp.map { t in ranges.contains { $0.lowerBound < t && t < $0.upperBound } } == true }) else { return nil }
        for i in merged.indices {
            let p = merged[i]
            guard p.latitude.isFinite, p.longitude.isFinite, abs(p.latitude) <= 90, abs(p.longitude) <= 180,
                  let time = p.timestamp, time.timeIntervalSinceReferenceDate.isFinite else { return nil }
            if i > 0, let previous = merged[i - 1].timestamp, previous >= time { return nil }
        }
        self.original = original; self.display = display
    }

    /// Equality rejects changed source versions, a different workout and stale candidates.
    func mapGeometry(for currentOriginal: WorkoutRoute?) -> WorkoutRoute? {
        guard currentOriginal == original else { return currentOriginal }
        return display
    }
    func analysisGeometry(for currentOriginal: WorkoutRoute?) -> WorkoutRoute? { currentOriginal }
}
