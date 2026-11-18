import Foundation

/// LOCAL CONTRACT CANDIDATE ONLY. Used only by the explicitly injected local
/// evaluation session. No active network RPC, persistence, or readiness caller.
/// This supplement is intentionally independent of the active detail-v1 payload.
/// Shipping this type does not enable sharing; server review and new consent are required.
enum WorkoutSharedMetricsCandidate {
    static let transportEnabled = false
    static let contract = "detail-v2-candidate"
    static let maximumBytes = 262_144
    static let maximumLaps = 1_024

    enum Failure: Error, Equatable {
        case previewDisabled, scopeMismatch, consentUnavailable, invalidMeasurement, invalidContract
    }

    /// A caller-supplied local receipt, not proof of remote authorization.
    /// Production would need an authoritative, current server receipt at every read/write.
    struct Binding: Equatable {
        let postID: UUID
        let ownerID: UUID
        let sourceWorkoutID: UUID
        let detailRevision: Int64
        let consentRevision: Int64
    }
    struct Consent: Equatable {
        let binding: Binding
        var energySelected = false
        var originalLapsSelected = false
    }
    enum LapOrigin: String, Codable {
        case healthKitLapEvent, tcxLapElement
    }
    /// Explicit provider evidence only. Generic telemetry splits, segments, length
    /// totals, labels, and distance-derived chart splits cannot construct this implicitly.
    struct OriginalLaps {
        let ownerID: UUID
        let workoutID: UUID
        let origin: LapOrigin
        let rows: [WorkoutTelemetrySplit]
    }
    struct Lap: Codable, Equatable {
        let startSeconds: Double
        let endSeconds: Double
        let durationSeconds: Double
        let distanceMeters: Double?
        let origin: LapOrigin
    }
    struct Payload: Codable, Equatable {
        let version: Int
        /// Elapsed span bounds relative lap times; never substituted for active duration.
        let elapsedSeconds: Double
        let activeEnergyKcal: Double?
        let originalSwimmingLaps: [Lap]
    }
    /// Local fixture envelope only; Binding is never part of the proposed measurement wire.
    /// This codec is not a server authorization mechanism or an active transport adapter.
    struct Envelope: Equatable {
        let binding: Binding
        let payload: Payload
    }

    /// Explicit opt-in is for synthetic/local contract evaluation only. It is not
    /// a runtime feature flag. No automatic telemetry fetch or private-data fallback.
    static func makeLocalPreview(
        workout: UnifiedWorkout, sourceOwnerID: UUID, currentOwnerID: UUID,
        originalLaps: OriginalLaps? = nil, consent: Consent,
        expectedBinding: Binding, localPreviewEnabled: Bool = false
    ) throws -> Envelope {
        guard localPreviewEnabled else { throw Failure.previewDisabled }
        try validateBinding(consent.binding, expected: expectedBinding)
        guard sourceOwnerID == expectedBinding.ownerID, currentOwnerID == expectedBinding.ownerID,
              workout.id == expectedBinding.sourceWorkoutID else {
            throw Failure.scopeMismatch
        }
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard inRange(elapsed, 0...604_800) else { throw Failure.invalidMeasurement }
        var energy: Double?
        if consent.energySelected {
            energy = workout.activeEnergyKcal
            guard energy.map({ inRange($0, 0...100_000) }) ?? true else { throw Failure.invalidMeasurement }
        }
        var laps: [Lap] = []
        if consent.originalLapsSelected, let originalLaps {
            guard originalLaps.ownerID == sourceOwnerID, originalLaps.workoutID == workout.id else {
                throw Failure.scopeMismatch
            }
            guard workout.workoutType == .swimming else { throw Failure.invalidMeasurement }
            guard originalLaps.rows.count <= maximumLaps else { throw Failure.invalidMeasurement }
            // Keep each original interval and its measured active duration intact.
            // Do not sort, clamp, fill gaps, infer distances, or divide by pool length.
            laps = originalLaps.rows.map {
                Lap(startSeconds: $0.startDate.timeIntervalSince(workout.startDate),
                    endSeconds: $0.endDate.timeIntervalSince(workout.startDate),
                    durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters,
                    origin: originalLaps.origin)
            }
        }
        let value = Envelope(binding: expectedBinding, payload: Payload(version: 2, elapsedSeconds: elapsed,
            activeEnergyKcal: energy, originalSwimmingLaps: laps))
        try validate(value, consent: consent, expectedBinding: expectedBinding)
        return value
    }

    static func encode(_ value: Envelope, consent: Consent, expectedBinding: Binding) throws -> Data {
        try validate(value, consent: consent, expectedBinding: expectedBinding)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value.payload)
        guard data.count <= maximumBytes else { throw Failure.invalidContract }
        return data
    }

    static func decode(_ data: Data, binding: Binding, consent: Consent, expectedBinding: Binding) throws -> Envelope {
        guard data.count <= maximumBytes else { throw Failure.invalidContract }
        // Codable alone ignores unknown fields. Fail closed on every object boundary
        // so a future health channel cannot slip through an older reader's consent.
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              keys(payload, allowed: ["version", "elapsedSeconds", "activeEnergyKcal", "originalSwimmingLaps"],
                   required: ["version", "elapsedSeconds", "originalSwimmingLaps"]),
              let laps = payload["originalSwimmingLaps"] as? [[String: Any]], laps.count <= maximumLaps,
              laps.allSatisfy({ keys($0,
                  allowed: ["startSeconds", "endSeconds", "durationSeconds", "distanceMeters", "origin"],
                  required: ["startSeconds", "endSeconds", "durationSeconds", "origin"]) }) else {
            throw Failure.invalidContract
        }
        let value = Envelope(binding: binding, payload: try JSONDecoder().decode(Payload.self, from: data))
        try validate(value, consent: consent, expectedBinding: expectedBinding)
        return value
    }

    private static func validate(_ value: Envelope, consent: Consent, expectedBinding: Binding) throws {
        try validateBinding(consent.binding, expected: expectedBinding)
        try validateBinding(value.binding, expected: expectedBinding)
        let payload = value.payload
        guard payload.version == 2, inRange(payload.elapsedSeconds, 0...604_800),
              payload.originalSwimmingLaps.count <= maximumLaps else { throw Failure.invalidContract }
        if let energy = payload.activeEnergyKcal {
            guard consent.energySelected else { throw Failure.consentUnavailable }
            guard inRange(energy, 0...100_000) else { throw Failure.invalidMeasurement }
        }
        guard consent.originalLapsSelected || payload.originalSwimmingLaps.isEmpty else {
            throw Failure.consentUnavailable
        }
        var previousEnd = 0.0
        for lap in payload.originalSwimmingLaps {
            guard inRange(lap.startSeconds, 0...payload.elapsedSeconds),
                  inRange(lap.endSeconds, 0...payload.elapsedSeconds),
                  lap.startSeconds >= previousEnd, lap.endSeconds > lap.startSeconds,
                  lap.durationSeconds.isFinite, lap.durationSeconds > 0,
                  lap.durationSeconds <= lap.endSeconds - lap.startSeconds,
                  (lap.origin != .healthKitLapEvent ||
                   abs(lap.durationSeconds - (lap.endSeconds - lap.startSeconds)) <= 0.000_001),
                  lap.distanceMeters.map({ inRange($0, 0...10_000_000) }) ?? true else {
                throw Failure.invalidMeasurement
            }
            previousEnd = lap.endSeconds
        }
    }
    private static func validateBinding(_ actual: Binding, expected: Binding) throws {
        guard expected.detailRevision > 0, expected.consentRevision > 0,
              actual == expected else { throw Failure.scopeMismatch }
    }
    private static func inRange(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
    }
    private static func keys(_ value: [String: Any], allowed: Set<String>, required: Set<String>) -> Bool {
        let present = Set(value.keys)
        return present.isSubset(of: allowed) && required.isSubset(of: present)
    }
}
