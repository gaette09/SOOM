import Foundation
import SwiftUI
import UIKit
import Supabase
import XCTest
@testable import SOOM

@MainActor
final class WorkoutSharedMetricsRPCTests: XCTestCase {
    private let owner = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
    private let peer = UUID(uuidString: "bbbbbbbb-4444-4444-4444-444444444444")!
    private let post = UUID(uuidString: "cccccccc-2222-2222-2222-222222222222")!
    private let source = UUID(uuidString: "dddddddd-3333-3333-3333-333333333333")!
    private var anchor: WorkoutSharedMetricsCandidate.Binding {
        .init(postID: post, ownerID: owner, sourceWorkoutID: source, detailRevision: 3, consentRevision: 7)
    }
    private func workout(id: UUID? = nil) -> UnifiedWorkout {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return .init(id: id ?? source, externalId: nil, source: .appleHealthKit, workoutType: .swimming,
            startDate: start, endDate: start.addingTimeInterval(300), durationSeconds: 250,
            distanceMeters: 50, activeEnergyKcal: 88, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: start, updatedAt: start)
    }
    private func setup(enabled: Bool = true, asPeer: Bool = false) -> (MetricsRPCMock, WorkoutSharedMetricsRPCAdapter, WorkoutSharedMetricsReviewFlow) {
        let mock = MetricsRPCMock(owner: owner, viewer: asPeer ? peer : owner, post: post, source: source)
        let adapter = WorkoutSharedMetricsRPCAdapter(anchor: anchor, sport: .swimming, executor: mock,
            scope: { mock.scope }, enabledForLocalEvaluation: enabled)
        let flow = WorkoutSharedMetricsReviewFlow(adapter: adapter, viewerID: asPeer ? peer : owner, enabledForLocalEvaluation: enabled)
        return (mock, adapter, flow)
    }
    func testDefaultOffAndRealSDKBuildGateMakeZeroCalls() async throws {
        let (mock, adapter, flow) = setup(enabled: false)
        let supported = try await adapter.supportsCandidate(); XCTAssertFalse(supported)
        await flow.revalidate(); XCTAssertEqual(mock.calls.count, 0)
        XCTAssertFalse(SupabaseWorkoutSharedMetricsExecutor.buildEnabled)
        let executor = SupabaseWorkoutSharedMetricsExecutor(client: nil, scope: { mock.scope })
        do { _ = try await executor.perform(.init(function: "soom_shared_metrics_ready_v2", headers: [:], parameters: Data())); XCTFail() }
        catch WorkoutSharedMetricsRPCError.disabled {} catch { XCTFail("\(error)") }
    }
    func testOnlyMissingFunctionMeansOldServerNotPermissionOrNetworkFailure() async throws {
        let (mock, adapter, _) = setup()
        mock.error = WorkoutSharedMetricsRPCError.missingFunction
        let supported = try await adapter.supportsCandidate(); XCTAssertFalse(supported)
        for error in [URLError(.notConnectedToInternet) as Error, PostgrestError(code: "42501", message: "denied")] {
            mock.error = error
            do { _ = try await adapter.supportsCandidate(); XCTFail() } catch { }
            XCTAssertFalse(SupabaseWorkoutSharedMetricsExecutor.classify(error) is WorkoutSharedMetricsRPCError)
        }
        XCTAssertTrue(SupabaseWorkoutSharedMetricsExecutor.classify(PostgrestError(code: "PGRST202", message: "missing")) is WorkoutSharedMetricsRPCError)
    }
    func testPrepareIsExplicitMetadataOnlyAndNeverPersistsConfirmation() async throws {
        let (mock, _, flow) = setup()
        await flow.revalidate(); XCTAssertFalse(mock.prepared); XCTAssertNil(flow.current)
        try await flow.beginReview()
        XCTAssertTrue(mock.prepared); XCTAssertFalse(flow.confirmed); XCTAssertFalse(try XCTUnwrap(flow.current).selected)
        XCTAssertNil(mock.payload); XCTAssertEqual(mock.mutations, 1)
        flow.confirmed = true; flow.invalidate()
        XCTAssertFalse(flow.confirmed); XCTAssertNil(flow.current); XCTAssertEqual(flow.outcome, .checking)
        XCTAssertFalse(mock.selected)
    }
    func testExplicitSingleWorkoutPublishRoundtripAndWithdraw() async throws {
        let (mock, _, flow) = setup(); try await flow.beginReview()
        do { try await flow.confirmAndPublish(workout: workout(), telemetry: nil); XCTFail() } catch { }
        XCTAssertNil(mock.payload)
        flow.confirmed = true; try await flow.confirmAndPublish(workout: workout(), telemetry: nil)
        XCTAssertEqual(flow.outcome, .published); XCTAssertNotNil(flow.session.projection)
        XCTAssertEqual(mock.payload?["activeEnergyKcal"] as? Double, 88)
        XCTAssertEqual((mock.payload?["originalSwimmingLaps"] as? [Any])?.count, 0)
        XCTAssertEqual(mock.calls.last?.headers["x-soom-feed-contract"], "mutual-v1")
        XCTAssertEqual(mock.calls.last?.headers["x-soom-workout-contract"], "detail-v1")
        try await flow.withdraw(); XCTAssertNil(mock.payload); XCTAssertFalse(mock.selected)
        XCTAssertNil(flow.session.projection); XCTAssertEqual(flow.outcome, .unselected)
    }
    func testPeerNullSourceAndLowercaseUUIDSurviveActualJSONParameters() async throws {
        let (mock, adapter, flow) = setup(asPeer: true)
        mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2; mock.payload = MetricsRPCMock.energy
        await flow.revalidate(); XCTAssertNotNil(flow.session.projection)
        let request = try XCTUnwrap(mock.calls.first { $0.function == "soom_shared_metrics_v2" })
        let params = try XCTUnwrap(JSONSerialization.jsonObject(with: request.parameters) as? [String: Any])
        let expected = try XCTUnwrap(params["p_expected"] as? [String: Any])
        XCTAssertTrue(expected["source_workout_id"] is NSNull)
        XCTAssertEqual(expected["post_id"] as? String, post.uuidString.lowercased())
        XCTAssertEqual(Set(expected.keys), WorkoutSharedMetricsRPCAdapter.receiptKeys)
        let raw = try await adapter.readCurrentReceipt()
        XCTAssertFalse(try XCTUnwrap(raw).can_manage)
        // Same wire fixture is persisted as an XCTest attachment for SQL roundtrip evidence.
        let attachment = XCTAttachment(data: request.parameters, uniformTypeIdentifier: "public.json")
        attachment.name = "peer-null-source-request"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testStrictReceiptRejectsUnknownFieldsAndWrongActor() async throws {
        for alteration in ["unknown", "actor", "source"] {
            let (mock, adapter, _) = setup(asPeer: true); mock.prepared = true
            mock.receiptAlteration = alteration
            do { _ = try await adapter.readCurrentReceipt(); XCTFail(alteration) } catch { }
        }
    }
    func testStrictPayloadPreservesUnknownKeyForCandidateRejection() async throws {
        let (mock, _, flow) = setup(); mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2
        mock.payload = MetricsRPCMock.energy; mock.payload?["privateHeartRate"] = 170
        await flow.revalidate(); XCTAssertNil(flow.session.projection)
    }
    func testSourcePreflightPreservesPreviouslySharedSnapshot() async throws {
        let (mock, _, flow) = setup(); mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2; mock.payload = MetricsRPCMock.energy
        await flow.revalidate(); flow.confirmed = true
        let writes = mock.mutations
        do { try await flow.confirmAndPublish(workout: workout(id: UUID()), telemetry: nil); XCTFail() } catch { }
        XCTAssertEqual(mock.mutations, writes); XCTAssertNotNil(mock.payload)
    }
    func testStaleBaseAndNullSourceStillAllowOwnerWithdrawalWhenPublicationDisabled() async throws {
        let (mock, _, flow) = setup(); mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2; mock.payload = MetricsRPCMock.energy
        mock.detailRevision = 4; mock.privacyRevision = 8; mock.source = nil; mock.canWrite = false; mock.ready = false
        await flow.revalidate(); XCTAssertNotNil(flow.current); XCTAssertNil(flow.session.projection)
        XCTAssertFalse(try XCTUnwrap(flow.current).can_write)
        try await flow.withdraw(); XCTAssertFalse(mock.selected); XCTAssertNil(mock.payload)
        let request = try XCTUnwrap(mock.calls.first { $0.function == "soom_select_shared_metrics_v2" })
        let params = try XCTUnwrap(JSONSerialization.jsonObject(with: request.parameters) as? [String: Any])
        XCTAssertTrue((params["p_expected"] as? [String: Any])?["source_workout_id"] is NSNull)
    }
    func testSessionScopeChangesAfterResponsePreventCacheAndDisplay() async throws {
        for axis in 0..<4 {
            let (mock, adapter, _) = setup(); mock.prepared = true
            mock.afterResponse = { name in
                guard name == "soom_shared_metrics_receipt_v2" else { return }
                let old = mock.scope
                mock.scope = .init(userID: axis == 0 ? self.peer : old.userID,
                    accountGeneration: old.accountGeneration + (axis == 1 ? 1 : 0),
                    storageScopeID: axis == 2 ? "other" : old.storageScopeID,
                    safetyRevision: old.safetyRevision + (axis == 3 ? 1 : 0))
            }
            do { _ = try await adapter.readCurrentReceipt(); XCTFail("axis \(axis)") }
            catch WorkoutSharedMetricsRPCError.scopeChanged {} catch { XCTFail("\(error)") }
        }
    }
    func testReadOnlyScopeChangeDoesNotRegisterOrPublish() async throws {
        let (mock, _, flow) = setup(); mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2; mock.payload = MetricsRPCMock.energy
        await flow.revalidate(); XCTAssertNotNil(flow.session.projection)
        let writes = mock.mutations
        flow.invalidate(viewerID: peer); mock.scope = .init(userID: peer, accountGeneration: 2, storageScopeID: peer.uuidString.lowercased(), safetyRevision: 1)
        mock.canRead = false; await flow.revalidate()
        XCTAssertNil(flow.session.projection); XCTAssertEqual(mock.mutations, writes)
        XCTAssertNil(flow.errorMessage); XCTAssertEqual(flow.outcome, .unselected)
    }
    func testLateReviewAndWithdrawalReceiptsCannotRepopulateDismissedFlow() async throws {
        for withdrawing in [false, true] {
            let (mock, _, flow) = setup(); try await flow.beginReview()
            mock.afterResponse = { name in
                if name == "soom_shared_metrics_receipt_v2" { flow.invalidate() }
            }
            if withdrawing { do { try await flow.withdraw() } catch {} }
            else { await flow.revalidate() }
            XCTAssertNil(flow.current); XCTAssertNil(flow.errorMessage); XCTAssertEqual(flow.outcome, .checking)
        }
    }
    func testLostPublishReplyIsUncertainThenReentryReadsCommittedReceiptWithoutRetry() async throws {
        let (mock, _, flow) = setup(); try await flow.beginReview(); flow.confirmed = true
        mock.losePutReply = true
        do { try await flow.confirmAndPublish(workout: workout(), telemetry: nil); XCTFail() } catch {}
        XCTAssertEqual(flow.outcome, .uncertain); XCTAssertNotNil(mock.payload)
        let writes = mock.mutations; await flow.revalidate()
        XCTAssertEqual(flow.outcome, .published); XCTAssertEqual(mock.mutations, writes)
    }
    func testPartialSelectionCommitWithRejectedPublicationIsVisibleAndRecoverable() async throws {
        let (mock, _, flow) = setup(); try await flow.beginReview(); flow.confirmed = true; mock.rejectPut = true
        do { try await flow.confirmAndPublish(workout: workout(), telemetry: nil); XCTFail() } catch {}
        XCTAssertTrue(mock.selected); XCTAssertNil(mock.payload); XCTAssertEqual(flow.outcome, .uncertain)
        await flow.revalidate(); XCTAssertEqual(flow.outcome, .publicationPending)
        try await flow.withdraw(); XCTAssertFalse(mock.selected)
    }
    func testLateRecoveryReceiptAfterAccountChangeDoesNotRestoreOldErrorOrState() async throws {
        let (mock, _, flow) = setup(); try await flow.beginReview(); flow.confirmed = true
        mock.rejectPut = true
        mock.afterResponse = { name in
            if name == "soom_shared_metrics_receipt_v2", mock.didRejectPut { flow.invalidate(viewerID: self.peer) }
        }
        do { try await flow.confirmAndPublish(workout: workout(), telemetry: nil); XCTFail() } catch {}
        XCTAssertNil(flow.current); XCTAssertNil(flow.errorMessage); XCTAssertEqual(flow.outcome, .checking)
    }
    func testTwoReviewSessionsCASRejectsStaleConfirmation() async throws {
        let (mock, adapter, first) = setup()
        let second = WorkoutSharedMetricsReviewFlow(adapter: adapter, viewerID: owner, enabledForLocalEvaluation: true)
        try await first.beginReview(); try await second.beginReview()
        first.confirmed = true; try await first.confirmAndPublish(workout: workout(), telemetry: nil)
        let revision = mock.dataRevision
        second.confirmed = true
        do { try await second.confirmAndPublish(workout: workout(), telemetry: nil); XCTFail() } catch {}
        XCTAssertEqual(mock.dataRevision, revision); XCTAssertNotNil(mock.payload)
    }
    func testWithdrawalInFlightDisablesRepeatAndPreservesSuccessfulOutcome() async throws {
        let (mock, _, flow) = setup(); try await flow.beginReview()
        var resume: CheckedContinuation<Void, Never>?
        mock.suspendedResponse = { name in
            if name == "soom_select_shared_metrics_v2" {
                await withCheckedContinuation { continuation in resume = continuation }
            }
        }
        let first = Task { try await flow.withdraw() }
        for _ in 0..<1000 { if resume != nil { break }; await Task.yield() }
        XCTAssertNotNil(resume); XCTAssertTrue(flow.busy)
        let calls = mock.calls.filter { $0.function == "soom_select_shared_metrics_v2" }.count
        do { try await flow.withdraw(); XCTFail("in-flight withdrawal must reject repeat") } catch {}
        XCTAssertEqual(mock.calls.filter { $0.function == "soom_select_shared_metrics_v2" }.count, calls)
        resume?.resume(); try await first.value
        XCTAssertFalse(flow.busy); XCTAssertEqual(flow.outcome, .unselected); XCTAssertNil(flow.errorMessage)
    }
    // Exercises the installed SDK's real request builder through URLProtocol.
    // It does not enable the production executor or authenticate to any server.
    private func syntheticSDK() -> (SupabaseClient, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetricsSDKHTTPFixture.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(supabaseURL: URL(string: "https://metrics-sdk.invalid")!, supabaseKey: "synthetic-only-key",
            options: .init(auth: .init(storage: MetricsSDKNoAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                global: .init(headers: ["x-soom-feed-contract":"mutual-v1"], session: session)))
        return (client, session)
    }
    private func executeSDK(_ request: WorkoutSharedMetricsRPCRequest, client: SupabaseClient) async throws -> Data {
        let builder = try client.rpc(request.function, params: JSONDecoder().decode(JSONObject.self, from: request.parameters))
        for (name, value) in request.headers { builder.setHeader(name: name, value: value) }
        return try await builder.execute().data
    }
    func testActualSDKPreservesRPCHeadersAndPeerNullCASJSON() async throws {
        let (mock, _, flow) = setup(asPeer: true)
        mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2; mock.payload = MetricsRPCMock.energy
        await flow.revalidate(); XCTAssertNotNil(flow.session.projection)
        let request = try XCTUnwrap(mock.calls.last { $0.function == "soom_shared_metrics_v2" })
        MetricsSDKHTTPFixture.state.reset(status: 200, body: "[]")
        let (client, session) = syntheticSDK(); defer { session.invalidateAndCancel() }
        let data = try await executeSDK(request, client: client)
        XCTAssertEqual(data, Data("[]".utf8))
        let captured = try XCTUnwrap(MetricsSDKHTTPFixture.state.requests().last)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.url?.path, "/rest/v1/rpc/soom_shared_metrics_v2")
        for (name, value) in request.headers { XCTAssertEqual(captured.value(forHTTPHeaderField: name), value) }
        let bytes = try XCTUnwrap(captured.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: bytes) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: request.parameters) as? NSDictionary)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertTrue((json["p_expected"] as? [String: Any])?["source_workout_id"] is NSNull)
        XCTAssertFalse(SupabaseWorkoutSharedMetricsExecutor.buildEnabled)
        let evidence = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        evidence.name = "SDK-PEER-NULL-CAS-REQUEST"; evidence.lifetime = .keepAlways; add(evidence)
    }
    func testActualSDKMissingRPCIsDistinctFromPermissionFailure() async throws {
        let (client, session) = syntheticSDK(); defer { session.invalidateAndCancel() }
        let request = WorkoutSharedMetricsRPCRequest(function: "soom_shared_metrics_ready_v2", headers: [:], parameters: Data("{}".utf8))
        for code in ["PGRST202", "42501"] {
            MetricsSDKHTTPFixture.state.reset(status: code == "PGRST202" ? 404 : 403,
                body: "{\"code\":\"\(code)\",\"message\":\"synthetic failure\",\"details\":null,\"hint\":null}")
            do { _ = try await executeSDK(request, client: client); XCTFail("HTTP failure must propagate") }
            catch {
                let raw = try XCTUnwrap(error as? PostgrestError); XCTAssertEqual(raw.code, code)
                let classified = SupabaseWorkoutSharedMetricsExecutor.classify(error)
                if code == "PGRST202" {
                    guard case WorkoutSharedMetricsRPCError.missingFunction = classified else { return XCTFail("missing RPC classification") }
                } else { XCTAssertEqual((classified as? PostgrestError)?.code, "42501") }
            }
        }
    }
    func testActualSDKNetworkFailureAndEmptyRowsRemainDistinct() async throws {
        let (client, session) = syntheticSDK(); defer { session.invalidateAndCancel() }
        let request = WorkoutSharedMetricsRPCRequest(function: "soom_shared_metrics_receipt_v2", headers: [:], parameters: Data("{}".utf8))
        MetricsSDKHTTPFixture.state.reset(status: 200, body: "[]")
        let empty = try await executeSDK(request, client: client)
        XCTAssertEqual(empty, Data("[]".utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutSharedMetricsWireReceipt.self, from: empty))
        MetricsSDKHTTPFixture.state.reset(status: 200, body: "", networkFailure: true)
        do { _ = try await executeSDK(request, client: client); XCTFail("network error must propagate") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(MetricsSDKHTTPFixture.state.requests().count, 1)
    }
    func testInjectedActualReviewSurfaceRendersAndScrollsAtMaximumTypeSize() async throws {
        let demo = ReviewDemoController.shared; demo.start(); defer { demo.exit() }
        let runtime = try XCTUnwrap(demo.runtime)
        let actor = try XCTUnwrap(runtime.auth.session.currentUser?.id)
        for size in [DynamicTypeSize.large, .accessibility5] {
            let mock = MetricsRPCMock(owner: actor, viewer: actor, post: post, source: source)
            mock.prepared = true; mock.selected = true; mock.selectionRevision = 1; mock.dataRevision = 2
            mock.payload = size == .large ? MetricsRPCMock.energy : nil
            let anchor = WorkoutSharedMetricsCandidate.Binding(postID: post, ownerID: actor,
                sourceWorkoutID: source, detailRevision: 3, consentRevision: 7)
            let adapter = WorkoutSharedMetricsRPCAdapter(anchor: anchor, sport: .swimming, executor: mock,
                scope: { .init(userID: runtime.auth.session.currentUser?.id,
                    accountGeneration: CommunitySafetyStore.shared.accountGeneration,
                    storageScopeID: runtime.storage.scopeID, safetyRevision: CommunitySafetyStore.shared.revision) },
                enabledForLocalEvaluation: true)
            let flow = WorkoutSharedMetricsReviewFlow(adapter: adapter, viewerID: actor, enabledForLocalEvaluation: true)
            let view = ScrollViewReader { proxy in
                WorkoutSharedMetricsReviewSurface(flow: flow, workout: self.workout(), telemetry: nil)
                    .task {
                        if size == .accessibility5 {
                            try? await Task.sleep(for: .milliseconds(300))
                            proxy.scrollTo("shared.metrics.status", anchor: .bottom)
                        }
                    }
            }.environmentObject(runtime.auth).environmentObject(runtime.storage).environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: view); host.safeAreaRegions = []
            host.traitOverrides.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            defer {
                window.isHidden = true; window.rootViewController = nil
                previousKeyWindow?.makeKey(); flow.invalidate()
            }
            for _ in 0..<20 { host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30)) }
            XCTAssertEqual(flow.outcome, size == .large ? .published : .publicationPending)
            func scrolls(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
            }
            let scroll = try XCTUnwrap(scrolls(host.view).max { $0.contentSize.height < $1.contentSize.height })
            if size == .accessibility5 {
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                // SwiftUI resolves large multiline labels over several layout passes.
                // Recompute the endpoint after each pass instead of capturing the
                // first, stale contentSize as if it proved the footer is reachable.
                for _ in 0..<20 {
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height-scroll.bounds.height)), animated: false)
                    host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(30))
                }
                XCTAssertGreaterThan(scroll.contentOffset.y, 0)
                XCTAssertEqual(scroll.contentOffset.y + scroll.bounds.height, scroll.contentSize.height, accuracy: 2)
                let geometry = XCTAttachment(string: "content=\(scroll.contentSize) bounds=\(scroll.bounds) offset=\(scroll.contentOffset)")
                geometry.name = "R3-MAXIMUM-SCROLL-GEOMETRY"; geometry.lifetime = .keepAlways; add(geometry)
            }
            var visited = Set<ObjectIdentifier>()
            func accessibilityObject(_ object: NSObject, identifier: String) -> NSObject? {
                guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
                if (object as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return object }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 500 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject,
                           let found = accessibilityObject(child, identifier: identifier) { return found }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews { if let found = accessibilityObject(child, identifier: identifier) { return found } }
                }
                return nil
            }
            // A unit-hosted SwiftUI view may not expose virtual AX objects.
            // Record this separately; it is not a passing VoiceOver/AX assertion.
            let withdraw = accessibilityObject(host.view, identifier: "shared.metrics.withdraw")
            visited.removeAll()
            let status = accessibilityObject(host.view, identifier: "shared.metrics.status")
            let accessibilityEvidence = XCTAttachment(string: "virtualAXAvailable=\(withdraw != nil && status != nil); withdrawal=\(String(describing: withdraw?.accessibilityFrame)); status=\(String(describing: status?.accessibilityFrame)); VoiceOver not verified")
            accessibilityEvidence.name = "R3-UNIT-HOST-AX-LIMITATION"; accessibilityEvidence.lifetime = .keepAlways; add(accessibilityEvidence)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = size == .large ? "R3-REVIEW-PUBLISHED-NORMAL" : "R3-REVIEW-PENDING-MAXIMUM-SCROLLED"
            attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(mock.mutations, 0, "Rendering must not prepare/select/publish")
            if size == .accessibility5, ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_HOLD"] == "1" {
                // Test-only live window for native Simulator scroll/tap inspection.
                // The flow and all mutations remain in MetricsRPCMock memory.
                for _ in 0..<120 { try await Task.sleep(for: .seconds(1)) }
                let interaction = XCTAttachment(string: "mutations=\(mock.mutations); selected=\(mock.selected); outcome=\(flow.outcome)")
                interaction.name = "NATIVE-SYNTHETIC-INTERACTION"; interaction.lifetime = .keepAlways; add(interaction)
            }
        }
    }

}

/// A serialized RPC fixture, not a production server implementation.
@MainActor
private final class MetricsRPCMock: WorkoutSharedMetricsRPCPerforming {
    let owner: UUID, post: UUID
    var source: UUID?
    let stateID = UUID(uuidString: "eeeeeeee-5555-5555-5555-555555555555")!
    var scope: WorkoutSharedMetricsAccountScope
    var prepared = false, selected = false, canRead = true, canWrite = true, ready = true
    var selectionRevision = 0, dataRevision = 0, detailRevision = 3, privacyRevision = 7, mutations = 0
    var payload: [String: Any]?, error: Error?, receiptAlteration: String?
    var losePutReply = false, rejectPut = false, didRejectPut = false
    var calls: [WorkoutSharedMetricsRPCRequest] = []
    var afterResponse: ((String) -> Void)?
    var suspendedResponse: ((String) async -> Void)?
    static let energy: [String: Any] = ["version":2, "elapsedSeconds":300, "activeEnergyKcal":88, "originalSwimmingLaps":[]]
    init(owner: UUID, viewer: UUID, post: UUID, source: UUID) {
        self.owner = owner; self.post = post; self.source = source
        scope = .init(userID: viewer, accountGeneration: 1, storageScopeID: viewer.uuidString.lowercased(), safetyRevision: 0)
    }
    func receipt() -> [String: Any] {
        let managing = scope.userID == owner
        var r: [String: Any] = ["post_id":post.uuidString.lowercased(),"owner_id":owner.uuidString.lowercased(),
            "source_workout_id":managing ? (source?.uuidString.lowercased() as Any? ?? NSNull()) : NSNull(),
            "state_id":stateID.uuidString.lowercased(),"sport":"swimming","detail_revision":detailRevision,
            "privacy_revision":privacyRevision,"selection_revision":selectionRevision,"data_revision":dataRevision,
            "disclosure_version":selected || selectionRevision > 0 ? 2 : 0,"selected":selected,
            "can_read":selected && canRead && ready,"can_write":managing && canWrite && ready,"can_manage":managing,
            "viewer_id":scope.userID!.uuidString.lowercased()]
        if receiptAlteration == "unknown" { r["extra"] = 1 }
        if receiptAlteration == "actor" { r["viewer_id"] = UUID().uuidString }
        if receiptAlteration == "source" { r["source_workout_id"] = source!.uuidString }
        return r
    }
    func perform(_ request: WorkoutSharedMetricsRPCRequest) async throws -> Data {
        calls.append(request); if let error { throw error }
        let params = try JSONSerialization.jsonObject(with: request.parameters) as! [String: Any]
        let expected = params["p_expected"] as? [String: Any]
        var response: Any
        switch request.function {
        case "soom_shared_metrics_ready_v2": response = ready
        case "soom_shared_metrics_receipt_v2": response = prepared && (scope.userID == owner || canRead) ? [receipt()] : []
        case "soom_prepare_shared_metrics_v2": prepared = true; mutations += 1; response = [receipt()]
        case "soom_select_shared_metrics_v2":
            guard NSDictionary(dictionary: expected ?? [:]).isEqual(to: receipt()) else { throw URLError(.badServerResponse) }
            selected = params["p_selected"] as! Bool; selectionRevision += 1; dataRevision += 1; payload = nil; mutations += 1; response = [receipt()]
        case "put_shared_workout_metrics_v2":
            guard !rejectPut else { didRejectPut = true; throw URLError(.cannotParseResponse) }
            guard NSDictionary(dictionary: expected ?? [:]).isEqual(to: receipt()) else { throw URLError(.badServerResponse) }
            payload = params["p_input"] as? [String: Any]; dataRevision += 1; mutations += 1
            if losePutReply { losePutReply = false; throw URLError(.networkConnectionLost) }
            response = [receipt()]
        case "soom_shared_metrics_v2":
            guard NSDictionary(dictionary: expected ?? [:]).isEqual(to: receipt()) else { throw URLError(.badServerResponse) }
            response = payload.map { [["receipt":receipt(),"payload":$0]] } ?? []
        default: throw WorkoutSharedMetricsRPCError.missingFunction
        }
        let data = try JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed, .sortedKeys])
        await Task.yield(); await suspendedResponse?(request.function); afterResponse?(request.function)
        return data
    }
}

private struct MetricsSDKNoAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class MetricsSDKHTTPFixture: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var captured: [URLRequest] = []
        private var status = 200, body = "[]", failure = false
        func reset(status: Int, body: String, networkFailure: Bool = false) {
            lock.lock(); defer { lock.unlock() }
            captured = []; self.status = status; self.body = body; failure = networkFailure
        }
        func receive(_ request: URLRequest) -> (Int, String, Bool) {
            lock.lock(); defer { lock.unlock() }; captured.append(request); return (status, body, failure)
        }
        func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "metrics-sdk.invalid", request.url?.path.hasPrefix("/rest/v1/rpc/") == true else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
            captured.httpBody = data
        }
        let (status, body, failure) = Self.state.receive(captured)
        if failure { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
