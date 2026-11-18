import XCTest
import Supabase
import SwiftData
@testable import SOOM

@MainActor final class AccountActivitySyncCandidateTests: XCTestCase {
    func testServerAuthorizationFailuresStopTheBatchRatherThanSkipCards() {
        for code in ["42501", "PGRST301", "PGRST302", "PGRST303"] {
            XCTAssertThrowsError(try AccountActivitySyncReport.rethrowGlobal(PostgrestError(code:code,message:"synthetic"))) {
                XCTAssertEqual($0 as? AccountActivitySyncError,.unauthorized)
            }
        }
        XCTAssertNoThrow(try AccountActivitySyncReport.rethrowGlobal(PostgrestError(code:"23505",message:"synthetic card conflict")))
    }
    func testBothBatchModesStopOnGenerationChangeBetweenSuccessfulCards() async throws {
        for isolated in [false,true] {
            let f=BatchFixture(); let first=f.input(), second=f.input()
            f.switchAfterSuccessfulStage=true
            do {
                if isolated { _=try await f.worker.reconcileIsolated([first,second]) }
                else { _=try await f.worker.reconcile([first,second]) }
                XCTFail("a batch cannot adopt a new account generation")
            } catch { XCTAssertEqual(error as? AccountActivitySyncError,.accountChanged) }
            XCTAssertEqual(f.stageCalls,1)
            XCTAssertNotNil(f.saved[first.canonicalID]); XCTAssertNil(f.saved[second.canonicalID])
        }
    }
    func testEmptyIsolatedFlushStillRequiresAuthorityAndHonorsCancellation() async {
        let f=BatchFixture(); f.grant=nil
        do { _=try await f.engine.flushIsolated(); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivitySyncError,.unauthorized) }
        let g=BatchFixture()
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _=try await g.engine.flushIsolated(); XCTFail() }
            catch { XCTAssertTrue(error is CancellationError) }
        }.value
        XCTAssertEqual(g.lookupCalls,0); XCTAssertEqual(g.stageCalls,0)
    }
    func testIsolatedReconcileSkipsInvalidAndStagesValid() async throws {
        let f=BatchFixture()
        let invalid=f.input(duration: -1), valid=f.input()
        let report=try await f.worker.reconcileIsolated([invalid,valid])
        XCTAssertEqual(report.completed,1)
        XCTAssertEqual(report.failedCanonicalIDs,[invalid.canonicalID])
        XCTAssertEqual(Set(f.saved.keys),[valid.canonicalID])
        XCTAssertTrue(try f.box.entries(owner:f.owner).isEmpty)
    }
    func testIsolatedTimeoutKeepsIntentAndOtherCardProgressesThenReadConfirms() async throws {
        let f=BatchFixture(); let uncertain=f.input(), valid=f.input()
        f.timeoutID=uncertain.canonicalID
        let report=try await f.worker.reconcileIsolated([uncertain,valid])
        XCTAssertEqual(report.completed,1)
        XCTAssertEqual(report.failedCanonicalIDs,[uncertain.canonicalID])
        let pending=try XCTUnwrap(f.box.entries(owner:f.owner).first)
        XCTAssertEqual(pending.payload.p_canonical_id,uncertain.canonicalID)
        XCTAssertTrue(pending.outcomeUncertain)
        f.timeoutID=nil
        let retried=try await f.worker.reconcileIsolated([uncertain,valid])
        XCTAssertEqual(retried.completed,1); XCTAssertTrue(retried.failedCanonicalIDs.isEmpty)
        XCTAssertEqual(f.stageCalls,2); XCTAssertTrue(try f.box.entries(owner:f.owner).isEmpty)
    }
    func testIsolatedAccountSwitchDuringFailedWriteStopsRemainingCards() async throws {
        let f=BatchFixture(); let first=f.input(), second=f.input()
        f.switchAndFailID=first.canonicalID
        do { _=try await f.worker.reconcileIsolated([first,second]); XCTFail() }
        catch { XCTAssertEqual(error as? AccountActivitySyncError,.accountChanged) }
        XCTAssertEqual(f.stageCalls,1)
        XCTAssertNil(f.saved[second.canonicalID])
        XCTAssertEqual(try f.box.entries(owner:f.owner).count,1)
    }
    func testIsolatedAliasConflictRejectsBeforeAnyTransport() async {
        let f=BatchFixture(); let first=f.input()
        let second=AccountActivityStageInput(canonicalID:UUID(),sourceIDs:first.sourceIDs,sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:nil,deleted:false)
        do { _=try await f.worker.reconcileIsolated([first,second]); XCTFail() } catch {}
        XCTAssertEqual(f.lookupCalls,0); XCTAssertEqual(f.stageCalls,0)
    }
    func testCanonicalBatchPreservesValidWorkoutAndReportsMalformedGroup() {
        let date=Date(timeIntervalSince1970:1000)
        func workout(duration:Double, at:Date) -> UnifiedWorkout {
            UnifiedWorkout(id:UUID(),externalId:nil,source:.soomLocal,workoutType:.yoga,
                startDate:at,endDate:at.addingTimeInterval(10),durationSeconds:duration,distanceMeters:nil,
                activeEnergyKcal:nil,averageHeartRate:nil,maxHeartRate:nil,averageSpeedMetersPerSecond:nil,
                elevationGainMeters:nil,dataQuality:.complete,createdAt:date,updatedAt:date)
        }
        let valid=workout(duration:10,at:date), invalid=workout(duration:Double.nan,at:date.addingTimeInterval(1000))
        let batch=AccountActivityStageInput.canonicalBatch([valid,invalid])
        XCTAssertEqual(batch.inputs.map(\.canonicalID),[valid.id])
        XCTAssertEqual(batch.rejectedCanonicalIDs,[invalid.id])
        XCTAssertNil(batch.inputs.first?.distanceMeters)
    }
    func testProductionBuildGateAndLeaseControlQueueWithoutNetwork() async throws {
        let f=Fixture(),engine=AccountActivitySyncCandidate(transport:f,outbox:f.box,authorization:{f.grant})
        if AccountActivitySyncReleaseGate.productionReady {
            try engine.enqueue(f.payload)
            XCTAssertEqual(try f.box.entries(owner:f.owner).count,1)
        } else {
            XCTAssertThrowsError(try engine.enqueue(f.payload)) {XCTAssertEqual($0 as? AccountActivitySyncError,.disabled)}
            XCTAssertTrue(try f.box.entries(owner:f.owner).isEmpty)
        }
        XCTAssertEqual(f.calls,0)
        let invalid=Fixture();invalid.grant=nil
        let blocked=AccountActivitySyncCandidate(transport:invalid,outbox:invalid.box,authorization:{invalid.grant})
        XCTAssertThrowsError(try blocked.enqueue(invalid.payload))
        do {_=try await blocked.flush();XCTFail("invalid lease must never send")} catch {}
        XCTAssertTrue(try invalid.box.entries(owner:invalid.owner).isEmpty);XCTAssertEqual(invalid.calls,0)
    }
    func testMissingDistanceNeverInventsZero() throws {
        let f=Fixture(); try f.engine.enqueue(f.make(distance:nil))
        XCTAssertNil(try f.box.entries(owner:f.owner).first?.payload.p_distance_meters)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(f.make(distance:nil))) as? [String:Any])
        XCTAssertTrue(object["p_distance_meters"] is NSNull)
    }
    func testAuthorizationRequiredForOldRecords() throws {
        let f=Fixture(); f.grant=nil
        XCTAssertThrowsError(try f.engine.enqueue(f.payload)); XCTAssertEqual(f.calls,0)
    }
    func testQueueIsDurableAndSameIntentIdempotent() async throws {
        let f=Fixture(); try f.engine.enqueue(f.payload); try f.engine.enqueue(f.payload)
        let reopened=AccountActivityStageOutbox(directory:f.directory)
        XCTAssertEqual(try reopened.entries(owner:f.owner).count,1)
        let count=try await f.engine.flush(); XCTAssertEqual(count,1)
        XCTAssertEqual(f.stageCalls,1); XCTAssertTrue(try reopened.entries(owner:f.owner).isEmpty)
    }
    func testTimeoutThenReadConfirmsNoDuplicateStage() async throws {
        let f=Fixture(); f.timeoutAfterWrite=true; try f.engine.enqueue(f.payload)
        do { _=try await f.engine.flush(); XCTFail() } catch {}
        XCTAssertTrue(try XCTUnwrap(f.box.entries(owner:f.owner).first).outcomeUncertain)
        f.timeoutAfterWrite=false
        let count=try await f.engine.flush(); XCTAssertEqual(count,1); XCTAssertEqual(f.stageCalls,1)
    }
    func testAccountChangeKeepsPendingAndStops() async throws {
        let f=Fixture(); try f.engine.enqueue(f.payload); f.switchOnLookup=true
        do { _=try await f.engine.flush(); XCTFail() } catch {}
        XCTAssertEqual(f.stageCalls,0); XCTAssertEqual(try f.box.entries(owner:f.owner).count,1)
    }
    func testRevisionConflictDoesNotOverwrite() async throws {
        let f=Fixture(); f.saved=f.lookup(revision:7,deleted:false); try f.engine.enqueue(f.payload)
        do { _=try await f.engine.flush(); XCTFail() } catch {}
        XCTAssertEqual(f.stageCalls,0)
    }
    func testTombstoneCannotRestore() async throws {
        let f=Fixture(); f.saved=f.lookup(revision:1,deleted:true); try f.engine.enqueue(f.make(revision:1))
        do { _=try await f.engine.flush(); XCTFail() } catch {}
        XCTAssertEqual(f.stageCalls,0)
    }
    func testGrantExpiresDuringLookupBeforeStage() async throws {
        let f=Fixture(); var now=Date()
        f.grant = .init(ownerID:f.owner,evidenceReference:"synthetic-only",earliestActivity:.distantPast,expiresAt:now.addingTimeInterval(1),permitsOwnerPrivateStaging:true)
        let engine=AccountActivitySyncCandidate(fixtureTransport:f,outbox:f.box,authorization:{f.grant},clock:{now})
        try engine.enqueue(f.payload)
        f.onLookup = { now=now.addingTimeInterval(2) }
        do { _=try await engine.flush(); XCTFail() } catch {}
        XCTAssertEqual(f.stageCalls,0)
    }
    func testOrchestrationPastSnapshotThenLateAliasKeepsCardAndRevision() async throws {
        let f=Fixture(); let worker=AccountActivitySyncOrchestrator(engine:f.engine)
        let first=AccountActivityStageInput(canonicalID:f.canonical,sourceIDs:[f.canonical],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:nil,deleted:false)
        let n=try await worker.reconcile([first]); XCTAssertEqual(n,1)
        let noChange=try await worker.reconcile([first]); XCTAssertEqual(noChange,0)
        let extra=UUID()
        let late=AccountActivityStageInput(canonicalID:f.canonical,sourceIDs:[f.canonical,extra],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:nil,deleted:false)
        let updated=try await worker.reconcile([late]); XCTAssertEqual(updated,1)
        XCTAssertEqual(f.saved?.revision,2); XCTAssertEqual(f.saved?.card_id,f.card)
        XCTAssertEqual(Set(f.saved?.source_ids ?? []),Set([f.canonical,extra]))
    }
    func testOrchestrationWithoutAuthorityDoesNotReadOrQueue() async {
        let f=Fixture(); f.grant=nil
        let input=AccountActivityStageInput(canonicalID:f.canonical,sourceIDs:[f.canonical],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:100,deleted:false)
        do { _=try await AccountActivitySyncOrchestrator(engine:f.engine).reconcile([input]); XCTFail() } catch {}
        XCTAssertEqual(f.calls,0)
    }
    func testOrchestrationRejectsSourceSharedAcrossCanonicalGroups() async {
        let f=Fixture(); let other=UUID()
        let a=AccountActivityStageInput(canonicalID:f.canonical,sourceIDs:[f.canonical],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:100,deleted:false)
        let b=AccountActivityStageInput(canonicalID:other,sourceIDs:[other,f.canonical],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:100,deleted:false)
        do { _=try await AccountActivitySyncOrchestrator(engine:f.engine).reconcile([a,b]); XCTFail() } catch {}
        XCTAssertEqual(f.calls,0)
    }
    func testCanonicalMapperUsesActivityEngineWithoutInventingDistance() throws {
        let date=Date(timeIntervalSince1970:1000)
        let w=UnifiedWorkout(id:UUID(),externalId:nil,source:.soomLocal,workoutType:.yoga,
            startDate:date,endDate:date.addingTimeInterval(10.9),durationSeconds:10.9,distanceMeters:nil,
            activeEnergyKcal:nil,averageHeartRate:nil,maxHeartRate:nil,averageSpeedMetersPerSecond:nil,
            elevationGainMeters:nil,dataQuality:.complete,createdAt:date,updatedAt:date)
        let rows=try AccountActivityStageInput.canonicalInputs([w])
        XCTAssertEqual(rows.map(\.canonicalID),UnifiedWorkoutDeduplicationEngine().canonicalGroups([w]).map{ $0.workout.id })
        XCTAssertEqual(rows.first?.durationSeconds,10); XCTAssertNil(rows.first?.distanceMeters)
        XCTAssertEqual(rows.first?.sport,"yoga")
    }
    func testCanonicalIDChangeAliasConflictRemainsPendingWithoutGuessingMerge() async throws {
        let f=Fixture(); f.aliasConflict=true
        let other=UUID()
        let row=AccountActivityStageInput(canonicalID:other,sourceIDs:[other,f.canonical],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:100,deleted:false)
        do { _=try await AccountActivitySyncOrchestrator(engine:f.engine).reconcile([row]); XCTFail() } catch {}
        let pending=try XCTUnwrap(f.box.entries(owner:f.owner).first)
        XCTAssertEqual(pending.payload.p_canonical_id,other); XCTAssertTrue(pending.outcomeUncertain)
        XCTAssertNil(f.saved)
    }
    func testPendingPayloadCannotBeOverwrittenByLateSource() throws {
        let f=Fixture(); try f.engine.enqueue(f.payload)
        XCTAssertThrowsError(try f.engine.enqueue(f.make(distance:42)))
        XCTAssertEqual(try f.box.entries(owner:f.owner).first?.payload,f.payload)
    }
}

@MainActor private final class Fixture: AccountActivityStageTransport {
    let owner=UUID(), canonical=UUID(), card=UUID()
    let date=Date(timeIntervalSince1970:1_700_000_000)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("activity-sync-fixture-"+UUID().uuidString)
    lazy var box=AccountActivityStageOutbox(directory:directory)
    lazy var grant: AccountActivityStagingAuthorization? = .init(ownerID:owner,evidenceReference:"synthetic-only",earliestActivity:.distantPast,expiresAt:.distantFuture,permitsOwnerPrivateStaging:true)
    lazy var context: AccountActivitySyncContext? = .init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:1,retired:false)
    lazy var engine=AccountActivitySyncCandidate(fixtureTransport:self,outbox:box,authorization:{[weak self] in self?.grant})
    var saved: AccountActivityStageLookup?
    var timeoutAfterWrite=false, switchOnLookup=false, aliasConflict=false
    var calls=0,stageCalls=0
    var onLookup: (() -> Void)?
    var payload: AccountActivityStagePayload { make() }
    func make(distance:Double?=100,revision:Int64=0) -> AccountActivityStagePayload {
        .init(p_canonical_id:canonical,p_source_ids:[canonical],p_expected_revision:revision,p_sport:"running",p_activity_at:date,p_duration_seconds:10,p_distance_meters:distance,p_deleted:false)
    }
    func lookup(revision:Int64,deleted:Bool) -> AccountActivityStageLookup {
        .init(owner_id:owner,card_id:card,canonical_id:canonical,source_ids:[canonical],revision:revision,sport:"running",activity_at:date,duration_seconds:10,distance_meters:100,deleted:deleted)
    }
    func lookup(canonicalID:UUID) async throws -> AccountActivityStageLookup? {
        calls += 1; onLookup?()
        if switchOnLookup { context=nil }
        return saved
    }
    func lookupSource(sourceID:UUID) async throws -> AccountActivityStageLookup? {
        guard let saved,saved.source_ids.contains(sourceID) else{return nil};return saved
    }
    func stage(_ payload:AccountActivityStagePayload) async throws -> AccountActivityStageReceipt {
        calls += 1; stageCalls += 1
        if aliasConflict { throw AccountActivitySyncError.pendingConflict }
        saved = .init(owner_id:owner,card_id:card,canonical_id:payload.p_canonical_id,source_ids:payload.p_source_ids,
            revision:payload.p_expected_revision+1,sport:payload.p_sport,activity_at:payload.p_activity_at,
            duration_seconds:payload.p_duration_seconds,distance_meters:payload.p_distance_meters,deleted:payload.p_deleted)
        if timeoutAfterWrite { throw URLError(.timedOut) }
        return .init(version:1,card_id:card,canonical_id:canonical,revision:payload.p_expected_revision+1,staged:true,release_ready:false)
    }
}

@MainActor private final class BatchFixture: AccountActivityStageTransport {
    let owner=UUID(), date=Date(timeIntervalSince1970:1_700_000_000)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("activity-batch-"+UUID().uuidString)
    lazy var box=AccountActivityStageOutbox(directory:directory)
    private lazy var storedContext:AccountActivitySyncContext? = .init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:1,retired:false)
    var context:AccountActivitySyncContext? {
        get {
            let value=storedContext
            if contextReadsUntilSwitch>0 {
                contextReadsUntilSwitch -= 1
                if contextReadsUntilSwitch==0 {
                    storedContext = .init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:2,retired:false)
                }
            }
            return value
        }
        set { storedContext=newValue }
    }
    var switchAfterSuccessfulStage=false
    private var contextReadsUntilSwitch=0
    lazy var grant:AccountActivityStagingAuthorization? = .init(ownerID:owner,evidenceReference:"synthetic",earliestActivity:.distantPast,expiresAt:.distantFuture,permitsOwnerPrivateStaging:true)
    lazy var engine=AccountActivitySyncCandidate(fixtureTransport:self,outbox:box,authorization:{[weak self] in self?.grant})
    lazy var worker=AccountActivitySyncOrchestrator(engine:engine)
    var saved=[UUID:AccountActivityStageLookup]()
    var timeoutID:UUID?, switchAndFailID:UUID?
    var stageCalls=0, lookupCalls=0
    var lookupIDs=[UUID]()
    var afterSuccessfulStage:(() -> Void)?
    var beforeLookup: (() async -> Void)?
    var beforeSourceLookup: (() -> Void)?
    func input(duration:Int=10) -> AccountActivityStageInput {
        let id=UUID()
        return .init(canonicalID:id,sourceIDs:[id],sport:"running",activityAt:date,durationSeconds:duration,distanceMeters:nil,deleted:false)
    }
    func lookup(canonicalID:UUID) async throws -> AccountActivityStageLookup? {
        lookupCalls += 1;lookupIDs.append(canonicalID); await beforeLookup?(); return saved[canonicalID]
    }
    func lookupSource(sourceID:UUID) async throws -> AccountActivityStageLookup? {
        beforeSourceLookup?()
        return saved.values.first { $0.source_ids.contains(sourceID) }
    }
    func stage(_ payload:AccountActivityStagePayload) async throws -> AccountActivityStageReceipt {
        stageCalls += 1
        if switchAndFailID==payload.p_canonical_id { context=nil; throw URLError(.timedOut) }
        let row=AccountActivityStageLookup(owner_id:owner,card_id:saved[payload.p_canonical_id]?.card_id ?? UUID(),
            canonical_id:payload.p_canonical_id,source_ids:payload.p_source_ids,revision:payload.p_expected_revision+1,
            sport:payload.p_sport,activity_at:payload.p_activity_at,duration_seconds:payload.p_duration_seconds,
            distance_meters:payload.p_distance_meters,deleted:payload.p_deleted)
        saved[payload.p_canonical_id]=row
        if timeoutID==payload.p_canonical_id { throw URLError(.timedOut) }
        // Both per-card checks see generation 1, then the next batch boundary
        // sees generation 2. This deterministically exercises the inter-card gap.
        if switchAfterSuccessfulStage { contextReadsUntilSwitch=2 }
        afterSuccessfulStage?()
        return .init(version:1,card_id:row.card_id,canonical_id:row.canonical_id,revision:row.revision,staged:true,release_ready:false)
    }
}

@MainActor final class AccountActivityAutomaticSyncTests: XCTestCase {
    func testDesiredSnapshotSurvivesRestartBeforeAnyTransportLookup() throws {
        let f=BatchFixture(), input=f.input()
        let q=AccountActivityAutomaticQueue(directory:f.directory)
        XCTAssertEqual(try q.record(owner:f.owner,inputs:[input],deletedSourceIDs:[]),1)
        XCTAssertEqual(f.lookupCalls,0);XCTAssertEqual(f.stageCalls,0)
        let resumed=AccountActivityAutomaticQueue(directory:f.directory)
        XCTAssertEqual(try resumed.load(owner:f.owner).pending[input.canonicalID]?.input,input)
        XCTAssertTrue(try resumed.load(owner:UUID()).pending.isEmpty)
    }
    func testRepeatedIdenticalSnapshotKeepsMutationIdentity() throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try q.record(owner:f.owner,inputs:[input],deletedSourceIDs:[])
        let first=try q.load(owner:f.owner)
        try q.record(owner:f.owner,inputs:[input],deletedSourceIDs:[])
        XCTAssertEqual(try q.load(owner:f.owner),first)
    }
    func testOlderAcknowledgementCannotRemoveNewerEdit() throws {
        let f=BatchFixture(),old=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        try q.record(owner:f.owner,inputs:[old],deletedSourceIDs:[])
        let mutation=try XCTUnwrap(q.load(owner:f.owner).pending[old.canonicalID])
        let updated=AccountActivityStageInput(canonicalID:old.canonicalID,sourceIDs:old.sourceIDs,sport:old.sport,
            activityAt:old.activityAt,durationSeconds:20,distanceMeters:123,deleted:false)
        try q.record(owner:f.owner,inputs:[updated],deletedSourceIDs:[])
        try q.acknowledge([mutation],owner:f.owner)
        XCTAssertEqual(try q.load(owner:f.owner).pending[old.canonicalID]?.input,updated)
    }
    func testMissingSnapshotNeverDeletesAndExplicitAllAliasTombstonesDo() throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        try q.record(owner:f.owner,inputs:[input],deletedSourceIDs:[])
        try q.acknowledge(Array(q.load(owner:f.owner).pending.values),owner:f.owner)
        try q.record(owner:f.owner,inputs:[],deletedSourceIDs:[])
        XCTAssertTrue(try q.load(owner:f.owner).pending.isEmpty)
        try q.record(owner:f.owner,inputs:[],deletedSourceIDs:Set(input.sourceIDs))
        let deleted=try XCTUnwrap(q.load(owner:f.owner).pending[input.canonicalID]?.input)
        XCTAssertTrue(deleted.deleted);XCTAssertEqual(deleted.sourceIDs,input.sourceIDs)
        XCTAssertEqual(deleted.activityAt,input.activityAt)
    }
    func testPartialAliasDeletionAndDedupeSwitchNeverInventTombstone() throws {
        let f=BatchFixture(),base=f.input(),alias=UUID(),q=AccountActivityAutomaticQueue(directory:f.directory)
        let old=AccountActivityStageInput(canonicalID:base.canonicalID,sourceIDs:[base.canonicalID,alias],sport:base.sport,
            activityAt:base.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        try q.record(owner:f.owner,inputs:[old],deletedSourceIDs:[])
        try q.acknowledge(Array(q.load(owner:f.owner).pending.values),owner:f.owner)
        try q.record(owner:f.owner,inputs:[],deletedSourceIDs:[base.canonicalID])
        XCTAssertTrue(try q.load(owner:f.owner).pending.isEmpty)
        let survivor=AccountActivityStageInput(canonicalID:alias,sourceIDs:[alias],sport:base.sport,
            activityAt:base.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        try q.record(owner:f.owner,inputs:[survivor],deletedSourceIDs:[base.canonicalID,alias])
        XCTAssertFalse(try XCTUnwrap(q.load(owner:f.owner).known[base.canonicalID]).deleted)
        XCTAssertFalse(try XCTUnwrap(q.load(owner:f.owner).pending[alias]).input.deleted)
    }
    func testAliasCollisionRejectsWholeSnapshotWithoutReplacingDurableQueue() throws {
        let f=BatchFixture(),first=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        try q.record(owner:f.owner,inputs:[first],deletedSourceIDs:[])
        let prior=try q.load(owner:f.owner),id=UUID()
        let conflict=AccountActivityStageInput(canonicalID:id,sourceIDs:[id,first.canonicalID],sport:first.sport,
            activityAt:first.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        XCTAssertThrowsError(try q.record(owner:f.owner,inputs:[first,conflict],deletedSourceIDs:[]))
        XCTAssertEqual(try q.load(owner:f.owner),prior)
    }
    func testWorkerPersistsSynchronouslyThenStagesAndAcknowledges() async throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},
            snapshot:{.init(batch:.init(inputs:[input]),deletedSourceIDs:[])})
        worker.request()
        XCTAssertEqual(f.lookupCalls,0)
        XCTAssertEqual(try q.load(owner:f.owner).pending.count,1)
        await worker.waitUntilIdle()
        XCTAssertEqual(f.stageCalls,1);XCTAssertEqual(worker.pendingCount,0)
        XCTAssertTrue(try q.load(owner:f.owner).pending.isEmpty)
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(f.stageCalls,1)
    }
    func testWorkerTimeoutRetainsBothQueuesAndRetryConfirmsWithoutDuplicateWrite() async throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        f.timeoutID=input.canonicalID
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},
            snapshot:{.init(batch:.init(inputs:[input]),deletedSourceIDs:[])})
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,1);XCTAssertEqual(try f.box.entries(owner:f.owner).count,1)
        f.timeoutID=nil
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,0);XCTAssertEqual(f.stageCalls,1)
    }
    func testReinstalledQueueResolvesExplicitDeletedSourceByOwnerAlias() async throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        _=try await f.worker.reconcile([input])
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},
            snapshot:{.init(batch:.init(),deletedSourceIDs:Set(input.sourceIDs))})
        worker.request();await worker.waitUntilIdle()
        XCTAssertTrue(try XCTUnwrap(f.saved[input.canonicalID]).deleted)
        XCTAssertEqual(f.stageCalls,2);XCTAssertEqual(worker.pendingCount,0)
        XCTAssertTrue(try q.load(owner:f.owner).pending.isEmpty)
    }
    func testMissingAuthorizationDoesNotEvenReadOrPersistSnapshot() async throws {
        let f=BatchFixture(),q=AccountActivityAutomaticQueue(directory:f.directory)
        f.grant=nil
        var reads=0
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},snapshot:{
            reads += 1;return .init(batch:.init(),deletedSourceIDs:[])
        })
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(reads,0);XCTAssertEqual(f.lookupCalls,0)
        XCTAssertTrue(try q.load(owner:f.owner).known.isEmpty)
        XCTAssertNotNil(worker.lastError)
    }
    func testContextSwitchAfterPersistenceStopsNetworkAndKeepsOldOwnerQueue() async throws {
        let f=BatchFixture(),input=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},
            snapshot:{.init(batch:.init(inputs:[input]),deletedSourceIDs:[])})
        worker.request();f.context=nil
        await worker.waitUntilIdle()
        XCTAssertEqual(f.lookupCalls,0);XCTAssertEqual(f.stageCalls,0)
        XCTAssertEqual(try q.load(owner:f.owner).pending.count,1)
    }
}


@MainActor final class AccountActivityLocalSnapshotTests: XCTestCase {
    private func makeContainer(owner:UUID) throws -> ModelContainer {
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,HealthCloudOutboxRecord.self,
            configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        HealthCloudJournal.register(container,userID:owner)
        return container
    }
    private func workout(source:UnifiedDataSource,index:Int) -> UnifiedWorkout {
        let date=Date(timeIntervalSince1970:1_500_000_000+Double(index)*86400)
        return .init(id:UUID(),externalId:"source-\(index)",source:source,workoutType:.running,
            startDate:date,endDate:date.addingTimeInterval(100),durationSeconds:100,distanceMeters:123,
            activeEnergyKcal:nil,averageHeartRate:142,maxHeartRate:170,averageSpeedMetersPerSecond:nil,
            elevationGainMeters:nil,dataQuality:.complete,createdAt:date,updatedAt:date)
    }
    func testAllStoredSourceTypesAndOldDatesUseOneCanonicalSnapshotWithoutEditingOriginals() async throws {
        let owner=UUID(),container=try makeContainer(owner:owner),context=container.mainContext
        let store=SwiftDataUnifiedWorkoutStore(modelContext:context)
        let sources:[UnifiedDataSource]=[.appleHealthKit,.garmin,.googleHealth,.strava,.samsungHealth,.healthConnect,.soomLocal,.manual,.unknown]
        let originals=sources.enumerated().map{workout(source:$0.element,index:$0.offset)}
        try await store.saveWorkouts(originals)
        let before=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).map{UnifiedWorkoutPersistenceMapper().makeWorkout(from:$0)}.sorted{$0.id.uuidString<$1.id.uuidString}
        let snapshot=try AccountActivityLocalSnapshot.read(context:context,expected:.init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:1,retired:false))
        XCTAssertEqual(snapshot.batch.inputs.count,sources.count)
        XCTAssertEqual(Set(snapshot.batch.inputs.map(\.canonicalID)),Set(originals.map(\.id)))
        XCTAssertTrue(snapshot.batch.inputs.allSatisfy{$0.activityAt<Date().addingTimeInterval(-90*86400)})
        XCTAssertTrue(snapshot.deletedSourceIDs.isEmpty)
        let after=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>()).map{UnifiedWorkoutPersistenceMapper().makeWorkout(from:$0)}.sorted{$0.id.uuidString<$1.id.uuidString}
        XCTAssertEqual(before,after)
        // Minimal projection cannot include HR/GPS even though local originals do.
        let data=try JSONEncoder().encode(snapshot.batch.inputs)
        let json=try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertFalse(json.contains("heart"));XCTAssertFalse(json.contains("route"))
    }
    func testCloudRestoreAppearsWithoutLocalCommitAndOnlyExplicitUnconflictedDeletesPropagate() throws {
        let owner=UUID(),container=try makeContainer(owner:owner),context=container.mainContext
        let restored=workout(source:.appleHealthKit,index:1)
        let data=try HealthCloudPayload(workout:restored).encoded()
        try HealthCloudJournal.apply(kind:"workout",key:restored.id.uuidString.lowercased(),data:data,deleted:false,context:context)
        let deleted=UUID(),conflict=UUID()
        context.insert(HealthCloudOutboxRecord(kind:"workout",recordKey:deleted.uuidString,payload:nil,isDeleted:true))
        let conflicting=HealthCloudOutboxRecord(kind:"workout",recordKey:conflict.uuidString,payload:nil,isDeleted:true)
        conflicting.conflicted=true;context.insert(conflicting)
        try context.save()
        let snapshot=try AccountActivityLocalSnapshot.read(context:context,expected:.init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:1,retired:false))
        XCTAssertEqual(snapshot.batch.inputs.map(\.canonicalID),[restored.id])
        XCTAssertEqual(snapshot.deletedSourceIDs,[deleted])
    }
    func testWrongOwnerAndRetiredContainerAreRejectedBeforeSnapshot() throws {
        let owner=UUID(),container=try makeContainer(owner:owner),context=container.mainContext,other=UUID()
        XCTAssertThrowsError(try AccountActivityLocalSnapshot.read(context:context,expected:.init(ownerID:other,scopeID:other.uuidString.lowercased(),generation:1,retired:false)))
        HealthCloudJournal.retire(container)
        XCTAssertThrowsError(try AccountActivityLocalSnapshot.read(context:context,expected:.init(ownerID:owner,scopeID:owner.uuidString.lowercased(),generation:1,retired:false)))
    }
}


final class AccountActivityV2StageWireTests: XCTestCase {
    func testFlatRPCParametersPreserveNilDistanceAndExactProfileLease() throws {
        let id=UUID(),payload=AccountActivityStagePayload(p_canonical_id:id,p_source_ids:[id],p_expected_revision:7,
            p_sport:"swimming",p_activity_at:Date(timeIntervalSince1970:1_700_000_000),p_duration_seconds:600,p_distance_meters:nil,p_deleted:false)
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AccountActivityV2StageParameters(payload:payload,profileRevision:12))) as? [String:Any])
        XCTAssertEqual(Set(json.keys),["p_canonical_id","p_source_ids","p_expected_revision","p_sport","p_activity_at","p_duration_seconds","p_distance_meters","p_deleted","p_expected_profile_revision"])
        XCTAssertEqual(json["p_expected_profile_revision"] as? Int,12)
        XCTAssertEqual(json["p_expected_revision"] as? Int,7)
        XCTAssertTrue(json["p_distance_meters"] is NSNull)
        XCTAssertNil(json["payload"]);XCTAssertNil(json["owner_id"])
    }
    func testV2ReceiptDecodesSummaryFailureWithoutPretendingItWasNotStaged() throws {
        let id=UUID(),json="""
        {"version":2,"card_id":"\(id)","canonical_id":"\(id)","revision":1,"staged":true,"release_ready":false,"summary_authorized":false,"profile_revision":9}
        """
        let receipt=try JSONDecoder().decode(AccountActivityStageReceipt.self,from:Data(json.utf8))
        XCTAssertTrue(receipt.staged);XCTAssertEqual(receipt.summary_authorized,false)
        XCTAssertEqual(receipt.version,2);XCTAssertFalse(receipt.release_ready)
    }
}


@MainActor final class AccountActivityCoordinatorTransitionTests: XCTestCase {
    private func worker(_ f:BatchFixture,_ input:AccountActivityStageInput) -> AccountActivityAutomaticSyncWorker {
        .init(queue:.init(directory:f.directory),orchestrator:f.worker,currentContext:{f.context},
              snapshot:{.init(batch:.init(inputs:[input]),deletedSourceIDs:[])})
    }
    func testReplacementWaitsForOldNetworkAndOnlyLatestConfigurationStarts() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var resume:CheckedContinuation<Void,Never>?
        let entered=expectation(description:"old network entered")
        f.beforeLookup={ await withCheckedContinuation {resume=$0;entered.fulfill()} }
        let first=worker(f,input)
        coordinator.configure(identity:"A",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{first})
        await fulfillment(of:[entered],timeout:2)
        var madeB=0,madeC=0
        coordinator.configure(identity:"B",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{madeB += 1;return self.worker(f,input)})
        coordinator.configure(identity:"C",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{madeC += 1;return self.worker(f,input)})
        XCTAssertEqual(madeB,0);XCTAssertEqual(madeC,0)
        f.beforeLookup=nil;resume?.resume()
        await coordinator.waitUntilConfigured();await coordinator.worker?.waitUntilIdle()
        XCTAssertEqual(madeB,0);XCTAssertEqual(madeC,1);XCTAssertEqual(coordinator.identity,"C")
        XCTAssertEqual(coordinator.worker?.pendingCount,0);XCTAssertEqual(f.stageCalls,1)
        coordinator.stop()
    }
    func testStopWhileReplacementWaitsNeverStartsNewWorker() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var resume:CheckedContinuation<Void,Never>?
        let entered=expectation(description:"old network entered")
        f.beforeLookup={await withCheckedContinuation {resume=$0;entered.fulfill()}}
        let first=worker(f,input)
        coordinator.configure(identity:"A",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{first})
        await fulfillment(of:[entered],timeout:2)
        var replacements=0
        coordinator.configure(identity:"B",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{replacements += 1;return self.worker(f,input)})
        coordinator.stop();f.beforeLookup=nil;resume?.resume();await first.waitUntilIdle()
        for _ in 0..<10 {await Task.yield()}
        XCTAssertEqual(replacements,0);XCTAssertNil(coordinator.worker);XCTAssertNil(coordinator.identity)
        XCTAssertEqual(f.stageCalls,0)
    }
    func testRunningHeldNetworkRenewsLeaseExactlyOnceAndWaitsForRetirement() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var resume:CheckedContinuation<Void,Never>?,refreshes=0
        let entered=expectation(description:"network held"),refreshed=expectation(description:"renewal requested")
        f.beforeLookup={await withCheckedContinuation {resume=$0;entered.fulfill()}}
        let first=worker(f,input)
        coordinator.configure(identity:"A",expiresAt:Date().addingTimeInterval(1.3),refreshPolicy:{refreshes += 1;refreshed.fulfill()},makeWorker:{first})
        await fulfillment(of:[entered,refreshed],timeout:3)
        XCTAssertEqual(refreshes,1);XCTAssertNil(coordinator.worker);XCTAssertNil(coordinator.identity)
        var replacements=0
        coordinator.configure(identity:"B",expiresAt:.distantFuture,refreshPolicy:{},makeWorker:{replacements += 1;return self.worker(f,input)})
        XCTAssertEqual(replacements,0)
        f.beforeLookup=nil;resume?.resume();await coordinator.waitUntilConfigured();await coordinator.worker?.waitUntilIdle()
        XCTAssertEqual(replacements,1);XCTAssertEqual(refreshes,1);XCTAssertEqual(f.stageCalls,1)
        coordinator.stop()
    }
    func testIdleWorkerDoesNotPollForLeaseRenewal() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var refreshes=0
        coordinator.configure(identity:"A",expiresAt:Date().addingTimeInterval(1.3),refreshPolicy:{refreshes += 1},makeWorker:{self.worker(f,input)})
        await coordinator.worker?.waitUntilIdle()
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(refreshes,0);XCTAssertEqual(coordinator.worker?.pendingCount,0)
        coordinator.stop()
    }
    func testStopCancelsScheduledRenewalWhileOldNetworkIsHeld() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var resume:CheckedContinuation<Void,Never>?,refreshes=0
        let entered=expectation(description:"network held")
        f.beforeLookup={await withCheckedContinuation {resume=$0;entered.fulfill()}}
        let first=worker(f,input)
        coordinator.configure(identity:"A",expiresAt:Date().addingTimeInterval(1.3),refreshPolicy:{refreshes += 1},makeWorker:{first})
        await fulfillment(of:[entered],timeout:2)
        coordinator.stop()
        try await Task.sleep(for:.milliseconds(500))
        XCTAssertEqual(refreshes,0);XCTAssertNil(coordinator.worker)
        f.beforeLookup=nil;resume?.resume();await first.waitUntilIdle()
        XCTAssertEqual(f.stageCalls,0)
    }
    func testExpiredLeaseAndExplicitRetryRefreshInsteadOfStartingAnotherWorker() async throws {
        let f=BatchFixture(),input=f.input(),coordinator=AccountActivityAutomaticSyncCoordinator()
        var refreshes=0,made=0
        coordinator.configure(identity:"A",expiresAt:.distantPast,refreshPolicy:{refreshes += 1},makeWorker:{made += 1;return self.worker(f,input)})
        await coordinator.worker?.waitUntilIdle()
        coordinator.request();coordinator.retry()
        XCTAssertEqual(refreshes,3);XCTAssertEqual(made,0)
        coordinator.stop()
    }
}


@MainActor final class AccountActivityCanonicalContinuityTests:XCTestCase {
    func testBenignRepresentativeChangePreservesExistingCardAndAcknowledgesLocalDesiredID() async throws {
        let f=BatchFixture(),original=f.input(),new=UUID()
        _=try await f.worker.reconcile([original])
        let oldCard=try XCTUnwrap(f.saved[original.canonicalID]).card_id
        let changed=AccountActivityStageInput(canonicalID:new,sourceIDs:[new,original.canonicalID],sport:original.sport,
            activityAt:original.activityAt,durationSeconds:99,distanceMeters:nil,deleted:false)
        let q=AccountActivityAutomaticQueue(directory:f.directory)
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},
            snapshot:{.init(batch:.init(inputs:[changed]),deletedSourceIDs:[])})
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,0);XCTAssertEqual(f.saved.count,1)
        XCTAssertEqual(f.saved[original.canonicalID]?.card_id,oldCard)
        XCTAssertEqual(f.saved[original.canonicalID]?.duration_seconds,99)
        XCTAssertEqual(Set(f.saved[original.canonicalID]?.source_ids ?? []),[new,original.canonicalID])
        XCTAssertNil(f.saved[new]);XCTAssertTrue(try q.load(owner:f.owner).pending.isEmpty)
        worker.request();await worker.waitUntilIdle();XCTAssertEqual(f.stageCalls,2)
    }
    func testOwnerSwitchDuringExactAliasLookupCannotStage() async throws {
        let f=BatchFixture(),a=f.input();_=try await f.worker.reconcile([a]);let calls=f.stageCalls
        f.beforeSourceLookup={f.context=nil}
        do {_=try await f.worker.reconcileIsolated([a]);XCTFail("owner change must abort batch")} catch {}
        XCTAssertEqual(f.stageCalls,calls)
    }
    func testTimeoutAfterRepresentativeChangeReusesSameCardWithoutSecondWrite() async throws {
        let f=BatchFixture(),a=f.input(),b=UUID();_=try await f.worker.reconcile([a])
        let changed=AccountActivityStageInput(canonicalID:b,sourceIDs:[a.canonicalID,b],sport:a.sport,activityAt:a.activityAt,durationSeconds:40,distanceMeters:nil,deleted:false)
        f.timeoutID=a.canonicalID
        let first=try await f.worker.reconcileIsolated([changed]);XCTAssertTrue(first.failedCanonicalIDs.contains(b))
        let calls=f.stageCalls;f.timeoutID=nil
        let second=try await f.worker.reconcileIsolated([changed]);XCTAssertTrue(second.failedCanonicalIDs.isEmpty)
        XCTAssertEqual(f.stageCalls,calls);XCTAssertEqual(f.saved.count,1)
        XCTAssertTrue(try f.box.entries(owner:f.owner).isEmpty)
    }
    func testTwoExistingServerCardsNeverMergeAutomatically() async throws {
        let f=BatchFixture(),a=f.input(),b=f.input();_=try await f.worker.reconcile([a,b])
        let calls=f.stageCalls,old=f.saved
        let merged=AccountActivityStageInput(canonicalID:a.canonicalID,sourceIDs:[a.canonicalID,b.canonicalID],sport:a.sport,
            activityAt:a.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        let result=try await f.worker.reconcileIsolated([merged])
        XCTAssertEqual(result.failedCanonicalIDs,[a.canonicalID]);XCTAssertEqual(f.stageCalls,calls)
        XCTAssertEqual(f.saved,old)
    }
    func testSplitOrMissingOldCanonicalCannotShrinkEstablishedAliasSet() async throws {
        let f=BatchFixture(),a=f.input(),b=UUID()
        let combined=AccountActivityStageInput(canonicalID:a.canonicalID,sourceIDs:[a.canonicalID,b],sport:a.sport,
            activityAt:a.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        _=try await f.worker.reconcile([combined]);let calls=f.stageCalls
        for id in [a.canonicalID,b] {
            let split=AccountActivityStageInput(canonicalID:id,sourceIDs:[id],sport:a.sport,activityAt:a.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
            let result=try await f.worker.reconcileIsolated([split]);XCTAssertEqual(result.failedCanonicalIDs,[id])
        }
        XCTAssertEqual(f.stageCalls,calls)
    }
    func testDeletedEstablishedCardIsNotRestoredByRepresentativeChange() async throws {
        let f=BatchFixture(),a=f.input(),b=UUID();_=try await f.worker.reconcile([a])
        let tombstone=AccountActivityStageInput(canonicalID:a.canonicalID,sourceIDs:a.sourceIDs,sport:a.sport,
            activityAt:a.activityAt,durationSeconds:10,distanceMeters:nil,deleted:true)
        _=try await f.worker.reconcile([tombstone]);let calls=f.stageCalls
        let changed=AccountActivityStageInput(canonicalID:b,sourceIDs:[a.canonicalID,b],sport:a.sport,activityAt:a.activityAt,durationSeconds:10,distanceMeters:nil,deleted:false)
        let result=try await f.worker.reconcileIsolated([changed])
        XCTAssertEqual(result.failedCanonicalIDs,[b]);XCTAssertEqual(f.stageCalls,calls)
    }
}


@MainActor final class AccountActivityDurableProgressTests:XCTestCase {
    private func inputs(_ f:BatchFixture,count:Int)->[AccountActivityStageInput] {
        (1...count).map { index in
            let id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",index))!
            return .init(canonicalID:id,sourceIDs:[id],sport:"running",activityAt:f.date,durationSeconds:10,distanceMeters:nil,deleted:false)
        }
    }
    func testSixteenAcknowledgedCardsAreNotRevisitedAfterLeaseCancellationAndRestart() async throws {
        let f=BatchFixture(),values=inputs(f,count:24),q=AccountActivityAutomaticQueue(directory:f.directory)
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},snapshot:{.init(batch:.init(inputs:values),deletedSourceIDs:[])})
        var resume:CheckedContinuation<Void,Never>?,held=false
        let entered=expectation(description:"seventeenth card held")
        f.beforeLookup={if f.stageCalls==16 && !held {held=true;await withCheckedContinuation {resume=$0;entered.fulfill()}}}
        worker.request();await fulfillment(of:[entered],timeout:10)
        XCTAssertEqual(try q.load(owner:f.owner).pending.count,8)
        worker.cancel();f.beforeLookup=nil;resume?.resume();await worker.waitUntilIdle()
        let priorReads=f.lookupIDs.count
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,0);XCTAssertEqual(f.stageCalls,24);XCTAssertEqual(f.saved.count,24)
        XCTAssertTrue(Set(f.lookupIDs.dropFirst(priorReads)).isDisjoint(with:Set(values.prefix(16).map(\.canonicalID))))
    }
    func testOneFailedCardDoesNotPreventLaterCardsDurableAcknowledgement() async throws {
        let f=BatchFixture(),values=inputs(f,count:6),q=AccountActivityAutomaticQueue(directory:f.directory)
        f.timeoutID=values[2].canonicalID
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},snapshot:{.init(batch:.init(inputs:values),deletedSourceIDs:[])})
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(Set(try q.load(owner:f.owner).pending.keys),[values[2].canonicalID]);XCTAssertEqual(f.stageCalls,6)
        f.timeoutID=nil;worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,0);XCTAssertEqual(f.stageCalls,6)
    }
    func testSuccessForCapturedMutationCannotAcknowledgeNewEditWrittenDuringNetwork() async throws {
        let f=BatchFixture(),a=f.input(),q=AccountActivityAutomaticQueue(directory:f.directory)
        let newer=AccountActivityStageInput(canonicalID:a.canonicalID,sourceIDs:a.sourceIDs,sport:a.sport,activityAt:a.activityAt,durationSeconds:20,distanceMeters:nil,deleted:false)
        var snapshot=a
        f.afterSuccessfulStage={snapshot=newer;try! q.record(owner:f.owner,inputs:[newer],deletedSourceIDs:[]);f.afterSuccessfulStage=nil}
        let worker=AccountActivityAutomaticSyncWorker(queue:q,orchestrator:f.worker,currentContext:{f.context},snapshot:{.init(batch:.init(inputs:[snapshot]),deletedSourceIDs:[])})
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(try q.load(owner:f.owner).pending[a.canonicalID]?.input,newer)
        worker.request();await worker.waitUntilIdle()
        XCTAssertEqual(worker.pendingCount,0);XCTAssertEqual(f.saved[a.canonicalID]?.duration_seconds,20)
    }
}
