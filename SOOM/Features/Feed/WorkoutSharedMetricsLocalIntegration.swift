import Foundation
import SwiftUI

/// Proposed single disclosure group. Existing shareMeasurements consent is never
/// converted to this version; there is no onboarding/settings persistence caller.
enum WorkoutSharedMetricsDisclosure {
    static let version = 2
    static let title = "이 운동의 활동 칼로리와 원본 수영 랩 공유"
    static let text = "이 운동에 기록된 활동 칼로리와 원본 수영 랩의 시간·거리를 현재 공개 범위에 공유합니다. 없는 값은 만들지 않으며 다른 운동이나 과거 기록은 자동으로 공개하지 않습니다. 언제든 이 추가 공유를 철회할 수 있습니다."
}

struct WorkoutSharedMetricsReceipt: Equatable {
    let binding: WorkoutSharedMetricsCandidate.Binding
    let viewerID: UUID
    let workoutType: UnifiedWorkoutType
    var postIncarnation: UUID = UUID()
    var disclosureVersion: Int = 0
    var selected = false
    var canRead = false
    var canWrite = false
    var accessEpoch: Int64 = 0
    var snapshotRevision: Int64 = 0
    var isEligible: Bool {
        selected && disclosureVersion == WorkoutSharedMetricsDisclosure.version && canRead
            && accessEpoch > 0 && binding.detailRevision > 0 && binding.consentRevision > 0
    }
    var consent: WorkoutSharedMetricsCandidate.Consent {
        .init(binding: binding, energySelected: selected, originalLapsSelected: selected)
    }
}

struct WorkoutSharedMetricsResponse {
    let receipt: WorkoutSharedMetricsReceipt
    let payload: Data
}

/// An implementation must authenticate its current actor and perform atomic
/// receipt/revision checks. This repository supplies no network implementation.
@MainActor
protocol WorkoutSharedMetricsLocalTransport {
    func supportsCandidate() async throws -> Bool
    func receipt(postID: UUID, viewerID: UUID) async throws -> WorkoutSharedMetricsReceipt?
    func fetch(expected: WorkoutSharedMetricsReceipt) async throws -> WorkoutSharedMetricsResponse?
    func put(payload: Data, expected: WorkoutSharedMetricsReceipt) async throws
    func withdraw(expected: WorkoutSharedMetricsReceipt) async throws
}

enum WorkoutSharedMetricsIntegrationError: Error {
    case disabled, unsupported, scopeChanged, consentRequired, sourceMismatch
}

extension WorkoutSharedMetricsCandidate {
    /// Only parser-tagged rows qualify. Historical/unknown/segment rows are not
    /// promoted from their labels. Conflicting original providers fail closed.
    static func makeFromRecordedTelemetry(workout: UnifiedWorkout, telemetry: WorkoutTelemetry?,
                                          ownerID: UUID, receipt: WorkoutSharedMetricsReceipt) throws -> Envelope {
        guard receipt.isEligible, receipt.canWrite, receipt.viewerID == ownerID,
              receipt.binding.ownerID == ownerID, receipt.workoutType == workout.workoutType else {
            throw WorkoutSharedMetricsIntegrationError.consentRequired
        }
        var evidence: OriginalLaps?
        if let telemetry {
            guard telemetry.workoutID == workout.id else { throw WorkoutSharedMetricsIntegrationError.sourceMismatch }
            let rows = workout.workoutType == .swimming
                ? telemetry.splits.filter { $0.provenance == .healthKitLapEvent || $0.provenance == .tcxLapElement } : []
            let origins = Set(rows.compactMap { $0.provenance?.rawValue })
            guard origins.count <= 1 else { throw WorkoutSharedMetricsIntegrationError.sourceMismatch }
            if let first = rows.first {
                evidence = OriginalLaps(ownerID: ownerID, workoutID: workout.id,
                    origin: first.provenance == .healthKitLapEvent ? .healthKitLapEvent : .tcxLapElement, rows: rows)
            }
        }
        return try makeLocalPreview(workout: workout, sourceOwnerID: ownerID, currentOwnerID: ownerID,
            originalLaps: evidence, consent: receipt.consent, expectedBinding: receipt.binding, localPreviewEnabled: true)
    }
}

/// Reference lease ensures a retained projection is invalid after refresh,
/// cancellation, withdrawal, account change, access change, or session dismissal.
@MainActor
private final class WorkoutSharedMetricsLease {
    var active = true
}

@MainActor
struct WorkoutSharedMetricsProjection {
    let receipt: WorkoutSharedMetricsReceipt
    let payload: WorkoutSharedMetricsCandidate.Payload
    private let lease: WorkoutSharedMetricsLease
    fileprivate init(receipt: WorkoutSharedMetricsReceipt, payload: WorkoutSharedMetricsCandidate.Payload,
                     lease: WorkoutSharedMetricsLease) {
        self.receipt = receipt; self.payload = payload; self.lease = lease
    }
    func applies(to item: FeedItem) -> Bool {
        lease.active && receipt.isEligible && item.permittedSharedDetail != nil
            && item.id == receipt.binding.postID && item.authorId == receipt.binding.ownerID
            && item.sourceWorkoutId == receipt.binding.sourceWorkoutID
            && item.serverPostSnapshot?.sharedDetailRevision == receipt.binding.detailRevision
            && item.recordWorkoutType == receipt.workoutType
    }
}

/// LOCAL EVALUATION ONLY. The default is OFF and no runtime settings can enable it.
/// Explicit injection is needed; no automatic publication, persistence or retries.
@MainActor
final class WorkoutSharedMetricsLocalSession: ObservableObject {
    @Published private(set) var projection: WorkoutSharedMetricsProjection?
    @Published private(set) var lastError: String?
    private let transport: any WorkoutSharedMetricsLocalTransport
    private let enabled: Bool
    private let postID: UUID
    private var viewerID: UUID
    private var generation = 0
    private var lease: WorkoutSharedMetricsLease?
    init(postID: UUID, viewerID: UUID, transport: any WorkoutSharedMetricsLocalTransport,
         enabledForLocalEvaluation: Bool = false) {
        self.postID = postID; self.viewerID = viewerID; self.transport = transport; self.enabled = enabledForLocalEvaluation
    }
    func invalidate(viewerID: UUID? = nil) {
        generation += 1; lease?.active = false; lease = nil; projection = nil
        if let viewerID { self.viewerID = viewerID }
    }
    func refresh() async {
        invalidate(); lastError = nil
        let token = generation
        do {
            guard enabled else { return }
            guard try await transport.supportsCandidate() else { return }
            guard let current = try await transport.receipt(postID: postID, viewerID: viewerID),
                  current.isEligible else { return }
            try check(current, token: token)
            guard let response = try await transport.fetch(expected: current) else { return }
            guard let latest = try await transport.receipt(postID: postID, viewerID: viewerID),
                  latest == current, response.receipt == current, current.snapshotRevision > 0 else {
                throw WorkoutSharedMetricsIntegrationError.scopeChanged
            }
            try check(current, token: token)
            let decoded = try WorkoutSharedMetricsCandidate.decode(response.payload, binding: current.binding,
                consent: current.consent, expectedBinding: current.binding)
            guard current.workoutType == .swimming || decoded.payload.originalSwimmingLaps.isEmpty else {
                throw WorkoutSharedMetricsIntegrationError.sourceMismatch
            }
            let currentLease = WorkoutSharedMetricsLease(); lease = currentLease
            projection = .init(receipt: current, payload: decoded.payload, lease: currentLease)
        } catch {
            if generation == token { invalidate(); lastError = "공유 범위를 다시 확인해 주세요." }
        }
    }
    func publish(workout: UnifiedWorkout, telemetry: WorkoutTelemetry?, confirmedSingleWorkoutDisclosure: Bool = false) async throws {
        invalidate(); let token = generation
        guard enabled else { throw WorkoutSharedMetricsIntegrationError.disabled }
        guard confirmedSingleWorkoutDisclosure else { throw WorkoutSharedMetricsIntegrationError.consentRequired }
        guard try await transport.supportsCandidate() else { throw WorkoutSharedMetricsIntegrationError.unsupported }
        guard let current = try await transport.receipt(postID: postID, viewerID: viewerID),
              current.isEligible, current.canWrite, current.binding.ownerID == viewerID else {
            throw WorkoutSharedMetricsIntegrationError.consentRequired
        }
        try check(current, token: token)
        let value = try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout,
            telemetry: telemetry, ownerID: viewerID, receipt: current)
        let data = try WorkoutSharedMetricsCandidate.encode(value, consent: current.consent, expectedBinding: current.binding)
        try await transport.put(payload: data, expected: current)
        try check(current, token: token)
        await refresh()
    }
    func withdraw() async throws {
        invalidate(); let token = generation
        guard enabled else { throw WorkoutSharedMetricsIntegrationError.disabled }
        guard let current = try await transport.receipt(postID: postID, viewerID: viewerID),
              current.canWrite, current.binding.ownerID == viewerID else {
            throw WorkoutSharedMetricsIntegrationError.scopeChanged
        }
        try check(current, token: token)
        try await transport.withdraw(expected: current)
        try check(current, token: token)
    }
    private func check(_ current: WorkoutSharedMetricsReceipt, token: Int) throws {
        guard !Task.isCancelled, generation == token, current.viewerID == viewerID,
              current.binding.postID == postID else { throw WorkoutSharedMetricsIntegrationError.scopeChanged }
    }
}

@MainActor
extension WorkoutDetailSharedRecord {
    private var currentMetricsProjection: WorkoutSharedMetricsProjection? {
        localMetricsProjection.flatMap { $0.applies(to: item) ? $0 : nil }
    }
    var presentationMetrics: [WorkoutCardMetric] {
        guard let energy = currentMetricsProjection?.payload.activeEnergyKcal else { return metrics }
        return metrics + [.init(label: "활동 칼로리", value: String(format: "%.0f kcal", energy))]
    }
    var presentationTelemetry: WorkoutTelemetry? {
        guard let preview = currentMetricsProjection else { return telemetry }
        let start = item.activityDate ?? item.createdAt
        var result = telemetry ?? WorkoutTelemetry(workoutID: item.id, source: .unknown, fetchedAt: start)
        result.splits = preview.payload.originalSwimmingLaps.enumerated().map { index, lap in
            .init(label: "랩 \(index + 1)", startDate: start.addingTimeInterval(lap.startSeconds),
                endDate: start.addingTimeInterval(lap.endSeconds), durationSeconds: lap.durationSeconds,
                distanceMeters: lap.distanceMeters,
                provenance: lap.origin == .healthKitLapEvent ? .healthKitLapEvent : .tcxLapElement)
        }
        return result
    }
    var presentationWorkout: UnifiedWorkout {
        guard let preview = currentMetricsProjection else { return measurementWorkout }
        let original = measurementWorkout
        return UnifiedWorkout(id: original.id, externalId: nil, source: .unknown, workoutType: original.workoutType,
            startDate: original.startDate, endDate: original.startDate.addingTimeInterval(preview.payload.elapsedSeconds),
            durationSeconds: original.durationSeconds, distanceMeters: original.distanceMeters,
            activeEnergyKcal: preview.payload.activeEnergyKcal, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: original.createdAt, updatedAt: original.updatedAt)
    }
}

/// No app navigation entry point. A synthetic host may inject a session and reuse
/// the existing summary, telemetry, map and movable sheet without a new layout.
struct WorkoutSharedMetricsLocalPreview: View {
    let item: FeedItem
    @ObservedObject var session: WorkoutSharedMetricsLocalSession
    var body: some View {
        Group {
        if let projection = session.projection, projection.applies(to: item) {
            let shared = WorkoutDetailSharedRecord(item: item, localMetricsProjection: projection)
            WorkoutDeepDetailView(workout: shared.layoutIdentity, sharedRecord: shared)
        } else {
            ContentUnavailableView("추가 공유를 표시할 수 없어요", soomIcon: "lock")
        }
        }.onDisappear { session.invalidate() }
    }
}
