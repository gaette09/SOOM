import Foundation
import Supabase
import SwiftUI

struct WorkoutSharedMetricsAccountScope: Equatable {
    let userID: UUID?
    let accountGeneration: Int
    let storageScopeID: String
    let safetyRevision: Int
}
struct WorkoutSharedMetricsRPCRequest {
    let function: String
    let headers: [String: String]
    let parameters: Data
}
enum WorkoutSharedMetricsRPCError: Error { case missingFunction, scopeChanged, invalidResponse, disabled }
/// Injectable call boundary; ordinary builds cannot enable the SDK executor.
@MainActor
protocol WorkoutSharedMetricsRPCPerforming {
    func perform(_ request: WorkoutSharedMetricsRPCRequest) async throws -> Data
}
struct WorkoutSharedMetricsWireReceipt: Codable, Equatable {
    let post_id: UUID
    let owner_id: UUID
    let source_workout_id: UUID?
    let state_id: UUID
    let sport: UnifiedWorkoutType
    let detail_revision: Int64
    let privacy_revision: Int64
    let selection_revision: Int64
    let data_revision: Int64
    let disclosure_version: Int
    let selected: Bool
    let can_read: Bool
    let can_write: Bool
    let can_manage: Bool
    let viewer_id: UUID
    enum CodingKeys: String, CodingKey {
        case post_id, owner_id, source_workout_id, state_id, sport, detail_revision, privacy_revision
        case selection_revision, data_revision, disclosure_version, selected, can_read, can_write, can_manage, viewer_id
    }
    // The SQL receipt has a deliberate null for peers. Preserve it for JSONB CAS.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(post_id.uuidString.lowercased(), forKey: .post_id); try c.encode(owner_id.uuidString.lowercased(), forKey: .owner_id)
        if let source_workout_id { try c.encode(source_workout_id.uuidString.lowercased(), forKey: .source_workout_id) }
        else { try c.encodeNil(forKey: .source_workout_id) }
        try c.encode(state_id.uuidString.lowercased(), forKey: .state_id); try c.encode(sport, forKey: .sport)
        try c.encode(detail_revision, forKey: .detail_revision); try c.encode(privacy_revision, forKey: .privacy_revision)
        try c.encode(selection_revision, forKey: .selection_revision); try c.encode(data_revision, forKey: .data_revision)
        try c.encode(disclosure_version, forKey: .disclosure_version); try c.encode(selected, forKey: .selected)
        try c.encode(can_read, forKey: .can_read); try c.encode(can_write, forKey: .can_write)
        try c.encode(can_manage, forKey: .can_manage); try c.encode(viewer_id.uuidString.lowercased(), forKey: .viewer_id)
    }
}

/// Proposed real-schema RPC adapter, enabled only by explicit local injection.
/// Uses the existing approved-v1/detail-v1 gates alongside a separate metrics gate.
@MainActor
final class WorkoutSharedMetricsRPCAdapter: WorkoutSharedMetricsLocalTransport {
    let anchor: WorkoutSharedMetricsCandidate.Binding
    let sport: UnifiedWorkoutType
    private let executor: any WorkoutSharedMetricsRPCPerforming
    private let scope: () -> WorkoutSharedMetricsAccountScope
    private let enabled: Bool
    private var cached: (WorkoutSharedMetricsWireReceipt, WorkoutSharedMetricsReceipt, WorkoutSharedMetricsAccountScope)?
    init(anchor: WorkoutSharedMetricsCandidate.Binding, sport: UnifiedWorkoutType,
         executor: any WorkoutSharedMetricsRPCPerforming, scope: @escaping () -> WorkoutSharedMetricsAccountScope,
         enabledForLocalEvaluation: Bool = false) {
        self.anchor = anchor; self.sport = sport; self.executor = executor; self.scope = scope
        enabled = enabledForLocalEvaluation
    }
    func invalidate() { cached = nil }
    private func call<P: Encodable>(_ name: String, _ parameters: P) async throws -> Data {
        guard enabled else { throw WorkoutSharedMetricsRPCError.disabled }
        let expected = scope()
        guard expected.userID != nil, expected.storageScopeID == expected.userID?.uuidString.lowercased() else {
            invalidate(); throw WorkoutSharedMetricsRPCError.scopeChanged
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let request = WorkoutSharedMetricsRPCRequest(function: name,
            headers: ["x-soom-feed-contract":"mutual-v1", "x-soom-social-contract":"approved-v1", "x-soom-workout-contract":"detail-v1",
                      "x-soom-metrics-contract":"metrics-v2"], parameters: try encoder.encode(parameters))
        do {
            let data = try await executor.perform(request)
            guard !Task.isCancelled, scope() == expected else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            return data
        } catch { invalidate(); throw error }
    }
    func supportsCandidate() async throws -> Bool {
        struct Empty: Encodable {}
        guard enabled else { return false }
        do { return try JSONDecoder().decode(Bool.self, from: await call("soom_shared_metrics_ready_v2", Empty())) }
        catch WorkoutSharedMetricsRPCError.missingFunction { return false }
    }
    private func validateIdentity(_ raw: WorkoutSharedMetricsWireReceipt) throws {
        guard raw.post_id == anchor.postID, raw.owner_id == anchor.ownerID, raw.viewer_id == scope().userID,
              raw.selection_revision >= 0, raw.data_revision >= 0, raw.detail_revision >= 0, raw.privacy_revision > 0,
              [0, 2].contains(raw.disclosure_version), !raw.can_read || (raw.selected && raw.disclosure_version == 2),
              (!raw.can_write && !raw.can_manage) || raw.viewer_id == raw.owner_id,
              raw.viewer_id == raw.owner_id || raw.source_workout_id == nil else {
            throw WorkoutSharedMetricsRPCError.invalidResponse
        }
    }
    func displayReceipt(_ raw: WorkoutSharedMetricsWireReceipt) throws -> WorkoutSharedMetricsReceipt {
        try validateIdentity(raw)
        guard raw.sport == sport, raw.detail_revision == anchor.detailRevision,
              raw.privacy_revision == anchor.consentRevision,
              raw.viewer_id != raw.owner_id || raw.source_workout_id == anchor.sourceWorkoutID else {
            throw WorkoutSharedMetricsRPCError.invalidResponse
        }
        return .init(binding: anchor, viewerID: raw.viewer_id, workoutType: sport, postIncarnation: raw.state_id,
            disclosureVersion: raw.disclosure_version, selected: raw.selected, canRead: raw.can_read,
            canWrite: raw.can_write, accessEpoch: max(1, raw.selection_revision), snapshotRevision: raw.data_revision)
    }
    static let receiptKeys: Set<String> = ["post_id","owner_id","source_workout_id","state_id","sport","detail_revision","privacy_revision","selection_revision","data_revision","disclosure_version","selected","can_read","can_write","can_manage","viewer_id"]
    private func decodeReceipt(_ data: Data) throws -> WorkoutSharedMetricsWireReceipt? {
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              objects.allSatisfy({ Set($0.keys) == Self.receiptKeys }) else { throw WorkoutSharedMetricsRPCError.invalidResponse }
        let rows = try JSONDecoder().decode([WorkoutSharedMetricsWireReceipt].self, from: data)
        guard rows.count <= 1 else { throw WorkoutSharedMetricsRPCError.invalidResponse }
        guard let raw = rows.first else { invalidate(); return nil }
        try validateIdentity(raw)
        if let receipt = try? displayReceipt(raw) { cached = (raw, receipt, scope()) } else { invalidate() }
        return raw
    }
    func readCurrentReceipt() async throws -> WorkoutSharedMetricsWireReceipt? {
        struct Input: Encodable { let p_post_id: UUID }
        return try decodeReceipt(await call("soom_shared_metrics_receipt_v2", Input(p_post_id: anchor.postID)))
    }
    func receipt(postID: UUID, viewerID: UUID) async throws -> WorkoutSharedMetricsReceipt? {
        guard postID == anchor.postID, viewerID == scope().userID else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        guard let raw = try await readCurrentReceipt() else { return nil }
        return try displayReceipt(raw)
    }
    /// Explicit owner review action only. Creates no selection or measurement.
    func prepareSingleWorkoutReview() async throws -> WorkoutSharedMetricsWireReceipt {
        guard scope().userID == anchor.ownerID else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        struct Input: Encodable {
            let p_post_id: UUID; let p_source_workout_id: UUID; let p_detail_revision: Int64; let p_privacy_revision: Int64
        }
        let data = try await call("soom_prepare_shared_metrics_v2", Input(p_post_id: anchor.postID,
            p_source_workout_id: anchor.sourceWorkoutID, p_detail_revision: anchor.detailRevision, p_privacy_revision: anchor.consentRevision))
        guard let result = try decodeReceipt(data) else { throw WorkoutSharedMetricsRPCError.invalidResponse }
        return result
    }
    func select(_ selected: Bool, expected: WorkoutSharedMetricsWireReceipt, disclosureConfirmed: Bool = false) async throws {
        guard expected.can_manage, expected.viewer_id == scope().userID,
              !selected || disclosureConfirmed else { throw WorkoutSharedMetricsIntegrationError.consentRequired }
        if selected { _ = try displayReceipt(expected) } else { try validateIdentity(expected) }
        struct Input: Encodable { let p_expected: WorkoutSharedMetricsWireReceipt; let p_selected: Bool; let p_disclosure_version: Int }
        let returned = try await call("soom_select_shared_metrics_v2", Input(p_expected: expected,
            p_selected: selected, p_disclosure_version: WorkoutSharedMetricsDisclosure.version))
        guard let receipt = try decodeReceipt(returned), receipt.state_id == expected.state_id,
              receipt.selection_revision == expected.selection_revision + 1,
              receipt.selected == selected else { throw WorkoutSharedMetricsRPCError.invalidResponse }
        let fresh = try await readCurrentReceipt()
        guard fresh == receipt else { invalidate(); throw WorkoutSharedMetricsRPCError.scopeChanged }
    }
    private func raw(_ expected: WorkoutSharedMetricsReceipt) throws -> WorkoutSharedMetricsWireReceipt {
        guard let cached, cached.1 == expected, cached.2 == scope() else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        return cached.0
    }
    func fetch(expected: WorkoutSharedMetricsReceipt) async throws -> WorkoutSharedMetricsResponse? {
        struct Input: Encodable { let p_expected: WorkoutSharedMetricsWireReceipt }
        let data = try await call("soom_shared_metrics_v2", Input(p_expected: raw(expected)))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count <= 1 else {
            throw WorkoutSharedMetricsRPCError.invalidResponse
        }
        guard let row = rows.first else { return nil }
        guard Set(row.keys) == ["receipt", "payload"], let receiptObject = row["receipt"], let payload = row["payload"] else {
            throw WorkoutSharedMetricsRPCError.invalidResponse
        }
        guard let receiptDictionary = receiptObject as? [String: Any], Set(receiptDictionary.keys) == Self.receiptKeys else {
            throw WorkoutSharedMetricsRPCError.invalidResponse
        }
        let raw = try JSONDecoder().decode(WorkoutSharedMetricsWireReceipt.self,
            from: JSONSerialization.data(withJSONObject: receiptDictionary))
        let translated = try displayReceipt(raw)
        guard translated == expected else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        // Keep raw payload keys for strict candidate validation; Codable must not erase unknown health fields.
        return .init(receipt: translated, payload: try JSONSerialization.data(withJSONObject: payload))
    }
    func put(payload: Data, expected: WorkoutSharedMetricsReceipt) async throws {
        let decoded = try WorkoutSharedMetricsCandidate.decode(payload, binding: anchor, consent: expected.consent, expectedBinding: anchor)
        struct Input: Encodable { let p_expected: WorkoutSharedMetricsWireReceipt; let p_input: WorkoutSharedMetricsCandidate.Payload }
        let returned = try await call("put_shared_workout_metrics_v2", Input(p_expected: raw(expected), p_input: decoded.payload))
        guard let receipt = try decodeReceipt(returned), receipt.state_id == expected.postIncarnation,
              receipt.data_revision == expected.snapshotRevision + 1 else { throw WorkoutSharedMetricsRPCError.invalidResponse }
    }
    func withdraw(expected: WorkoutSharedMetricsReceipt) async throws { try await select(false, expected: raw(expected)) }
}

/// No persisted choice, private store read, startup publication, or automatic retry.
@MainActor
final class WorkoutSharedMetricsReviewFlow: ObservableObject {
    @Published var confirmed = false
    @Published private(set) var current: WorkoutSharedMetricsWireReceipt?
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    enum Outcome: Equatable { case checking, unselected, publicationPending, published, uncertain }
    @Published private(set) var outcome = Outcome.checking
    let session: WorkoutSharedMetricsLocalSession
    private let adapter: WorkoutSharedMetricsRPCAdapter
    private let enabled: Bool
    private var epoch = 0
    init(adapter: WorkoutSharedMetricsRPCAdapter, viewerID: UUID, enabledForLocalEvaluation: Bool = false) {
        self.adapter = adapter; enabled = enabledForLocalEvaluation
        session = .init(postID: adapter.anchor.postID, viewerID: viewerID, transport: adapter, enabledForLocalEvaluation: enabledForLocalEvaluation)
    }
    func invalidate(viewerID: UUID? = nil) {
        epoch += 1; confirmed = false; current = nil; busy = false; errorMessage = nil; outcome = .checking
        adapter.invalidate(); session.invalidate(viewerID: viewerID)
    }
    func revalidate() async {
        invalidate(); let token = epoch
        guard enabled else { return }
        do {
            let receipt = try await adapter.readCurrentReceipt()
            guard token == epoch else { return }
            current = receipt; await session.refresh()
            guard token == epoch else { return }
            outcome = session.projection != nil ? .published : (receipt?.selected == true ? .publicationPending : .unselected)
        } catch WorkoutSharedMetricsRPCError.missingFunction { }
        catch { if token == epoch { outcome = .uncertain; errorMessage = "공유 범위를 다시 확인해 주세요." } }
    }
    func beginReview() async throws {
        invalidate(); let token = epoch
        guard enabled else { throw WorkoutSharedMetricsRPCError.disabled }
        let receipt = try await adapter.prepareSingleWorkoutReview()
        guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        current = receipt // Loading/preparing never checks the disclosure toggle.
        await session.refresh()
        guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
        outcome = session.projection != nil ? .published : (receipt.selected ? .publicationPending : .unselected)
    }
    func confirmAndPublish(workout: UnifiedWorkout, telemetry: WorkoutTelemetry?) async throws {
        guard enabled, confirmed, let current, !busy else { throw WorkoutSharedMetricsIntegrationError.consentRequired }
        // Validate original measurements before any consent mutation, preserving a
        // prior valid snapshot if new source evidence is malformed.
        var preview = try adapter.displayReceipt(current)
        guard preview.canWrite else { throw WorkoutSharedMetricsIntegrationError.consentRequired }
        preview.selected = true; preview.disclosureVersion = 2; preview.canRead = true
        _ = try WorkoutSharedMetricsCandidate.makeFromRecordedTelemetry(workout: workout, telemetry: telemetry,
            ownerID: adapter.anchor.ownerID, receipt: preview)
        let token = epoch; busy = true; defer { if token == epoch { busy = false; confirmed = false } }
        session.invalidate()
        do {
            try await adapter.select(true, expected: current, disclosureConfirmed: true)
            guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            outcome = .publicationPending
            try await session.publish(workout: workout, telemetry: telemetry, confirmedSingleWorkoutDisclosure: true)
            guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            let fresh = try await adapter.readCurrentReceipt()
            guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            self.current = fresh
            outcome = session.projection == nil ? .publicationPending : .published
        } catch {
            if token == epoch {
                outcome = .uncertain; errorMessage = "변경 결과를 다시 확인해 주세요. 이미 완료된 서버 변경은 취소되지 않을 수 있어요."
                let fresh = try? await adapter.readCurrentReceipt()
                guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
                self.current = fresh
            }
            throw error
        }
    }
    func withdraw() async throws {
        guard enabled, let current, !busy else { throw WorkoutSharedMetricsRPCError.disabled }
        invalidate(); let token = epoch
        busy = true; defer { if token == epoch { busy = false } }
        do {
            try await adapter.select(false, expected: current)
            guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            let fresh = try await adapter.readCurrentReceipt()
            guard token == epoch else { throw WorkoutSharedMetricsRPCError.scopeChanged }
            self.current = fresh
            outcome = .unselected
        } catch {
            if token == epoch { outcome = .uncertain; errorMessage = "철회 결과를 다시 확인해 주세요." }
            throw error
        }
    }
}

/// Injectable review surface only; no production navigation/factory call site.
/// Reads the same auth, account-storage and safety epochs as the existing app.
struct WorkoutSharedMetricsReviewSurface: View {
    @ObservedObject var flow: WorkoutSharedMetricsReviewFlow
    let workout: UnifiedWorkout
    let telemetry: WorkoutTelemetry?
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var storage: HealthAccountStorageController
    @ObservedObject private var safety = CommunitySafetyStore.shared
    @Environment(\.scenePhase) private var phase
    @State private var actionError: String?
    private var accountScope: WorkoutSharedMetricsAccountScope {
        .init(userID: auth.session.currentUser?.id, accountGeneration: safety.accountGeneration,
            storageScopeID: storage.scopeID, safetyRevision: safety.revision)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(WorkoutSharedMetricsDisclosure.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(WorkoutSharedMetricsDisclosure.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if flow.current == nil, accountScope.userID != nil {
                    Button { run { try await flow.beginReview() } } label: {
                        Text("이 운동의 공유 항목 확인").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }
                } else if let receipt = flow.current, receipt.can_manage {
                    if receipt.can_write {
                        Toggle(isOn: $flow.confirmed) {
                            Text("위 설명에 동의해요").fixedSize(horizontal: false, vertical: true)
                        }
                            .frame(minHeight: 44)
                            .accessibilityLabel("설명을 확인했고 이 운동의 추가 측정값 공유에 동의해요")
                            .accessibilityIdentifier("shared.metrics.confirm")
                        Button { run { try await flow.confirmAndPublish(workout: workout, telemetry: telemetry) } } label: {
                            Text("이 운동 공유").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                        }
                            .frame(minHeight: 44).disabled(!flow.confirmed || flow.busy)
                            .accessibilityIdentifier("shared.metrics.publish")
                    }
                    Button(role: .destructive) { run { try await flow.withdraw() } } label: {
                        Text("추가 측정값 공유 철회").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }
                        .frame(minHeight: 44).disabled(flow.busy).accessibilityIdentifier("shared.metrics.withdraw")
                }
                Group {
                switch flow.outcome {
                case .checking: Text("공유 상태를 확인하고 있어요.")
                case .unselected: Text("추가 측정값 공유가 선택되지 않았어요.")
                case .publicationPending: Text("공유 선택은 확인했어요. 측정값 게시 상태를 확인해 주세요.")
                case .published: Text("이 운동의 추가 측정값 공유를 확인했어요.")
                case .uncertain: Text("변경 결과를 확인하지 못했어요. 다시 열어 서버 상태를 확인해 주세요.")
                }
                }.fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("shared.metrics.status")
                    .id("shared.metrics.status")
                if let message = actionError ?? flow.errorMessage { Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
        }
        .task(id: accountScope) {
            actionError = nil; flow.invalidate(viewerID: accountScope.userID)
            await flow.revalidate()
        }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await flow.revalidate() } }
            else { flow.invalidate() }
        }
        .onDisappear { flow.invalidate() }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        let expected = accountScope
        Task {
            do { actionError = nil; try await action() }
            catch { if expected == accountScope { actionError = "변경을 확인하지 못했어요. 공유 상태를 다시 확인해 주세요." } }
        }
    }
}

/// Real SDK boundary, compiled/type-checked but inert in ordinary builds.
/// No production factory instantiates this. Build flag is intentionally absent.
@MainActor
final class SupabaseWorkoutSharedMetricsExecutor: WorkoutSharedMetricsRPCPerforming {
    static var buildEnabled: Bool {
        #if SOOM_SHARED_METRICS_V2_NETWORK
        true
        #else
        false
        #endif
    }
    private let client: SupabaseClient?
    private let scope: () -> WorkoutSharedMetricsAccountScope
    init(client: SupabaseClient?, scope: @escaping () -> WorkoutSharedMetricsAccountScope) {
        self.client = client; self.scope = scope
    }
    static func classify(_ error: Error) -> Error {
        if let error = error as? PostgrestError, error.code == "PGRST202" { return WorkoutSharedMetricsRPCError.missingFunction }
        return error
    }
    func perform(_ request: WorkoutSharedMetricsRPCRequest) async throws -> Data {
        guard Self.buildEnabled else { throw WorkoutSharedMetricsRPCError.disabled }
        let expected = scope()
        guard let client, let user = expected.userID, client.auth.currentSession?.user.id == user,
              expected.storageScopeID == user.uuidString.lowercased(),
              ["soom_shared_metrics_ready_v2","soom_shared_metrics_receipt_v2","soom_prepare_shared_metrics_v2",
               "soom_select_shared_metrics_v2","soom_shared_metrics_v2","put_shared_workout_metrics_v2"].contains(request.function),
              request.headers == ["x-soom-feed-contract":"mutual-v1", "x-soom-social-contract":"approved-v1","x-soom-workout-contract":"detail-v1","x-soom-metrics-contract":"metrics-v2"] else {
            throw WorkoutSharedMetricsRPCError.scopeChanged
        }
        do {
            let parameters = try JSONDecoder().decode(JSONObject.self, from: request.parameters)
            let builder = try client.rpc(request.function, params: parameters)
            for (name, value) in request.headers { builder.setHeader(name: name, value: value) }
            let response = try await builder.execute()
            guard !Task.isCancelled, scope() == expected, client.auth.currentSession?.user.id == user else {
                throw WorkoutSharedMetricsRPCError.scopeChanged
            }
            return response.data
        } catch { throw Self.classify(error) }
    }
}
