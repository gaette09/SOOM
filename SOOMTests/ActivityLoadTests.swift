import XCTest
import CryptoKit
import SwiftData
@testable import SOOM

@MainActor
final class ActivityLoadTests: XCTestCase {
    let calendar = ActivityLoadRules.calendar("Asia/Seoul")
    var base: Date { ISO8601DateFormatter().date(from: "2026-01-01T03:00:00Z")! }
    var now: Date { base.addingTimeInterval(3600) }
    func workout(id: UUID = UUID(), at: Date? = nil, seconds: Double = 1800, hr: Double? = 150,
                 updated: Date? = nil, source: UnifiedDataSource = .appleHealthKit, excluded: Bool = false) -> UnifiedWorkout {
        let start = at ?? base
        return UnifiedWorkout(id: id, externalId: id.uuidString, source: source, workoutType: .running,
            startDate: start, endDate: start.addingTimeInterval(max(1, seconds)), durationSeconds: seconds,
            distanceMeters: 5000, activeEnergyKcal: 200, averageHeartRate: hr, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .complete, isExcludedFromAnalysis: excluded,
            createdAt: start, updatedAt: updated ?? start.addingTimeInterval(max(1, seconds)))
    }
    func rating(_ w: UnifiedWorkout, value: Int = 4, seconds: Double? = nil) -> WorkoutEffortConfirmation {
        var c = WorkoutEffortConfirmation(value: value, confirmedAt: w.endDate.addingTimeInterval(1800), revision: UUID())
        c.scaleVersion = ActivityLoadRules.scaleVersion; c.reviewedDurationSeconds = seconds ?? w.durationSeconds
        c.durationPolicy = value == 0 ? ActivityLoadRules.legacyDurationPolicy : ActivityLoadRules.durationPolicy; c.inputControlVersion = value == 0 ? nil : ActivityLoadRules.manualInputVersion; c.workoutStart = w.startDate; c.workoutEnd = w.endDate
        c.unit = ActivityLoadRules.intensityUnit; c.origin = "user"; return c
    }
    func history(_ count: Int) -> (rows: [UnifiedWorkout], ratings: [UUID: WorkoutEffortConfirmation], journal: ActivityLoadJournal, asOf: Date) {
        var rows: [UnifiedWorkout] = [], ratings: [UUID: WorkoutEffortConfirmation] = [:]
        var journal = ActivityLoadJournal.empty(zone: calendar.timeZone.identifier)
        for i in 0..<count {
            let w = workout(at: calendar.date(byAdding: .day, value: i, to: base)!)
            rows.append(w); ratings[w.id] = rating(w)
            let key = ActivityLoadRules.dayKey(w.startDate, calendar: calendar)
            journal.approvals[key] = .init(fingerprint: ActivityLoadCalculator.fingerprint([w], zone: journal.timeZoneID), kind: .recordsReviewed, confirmedAt: w.endDate.addingTimeInterval(3600))
        }
        return (rows, ratings, journal, calendar.startOfDay(for: calendar.date(byAdding: .day, value: count, to: base)!))
    }
    func build(_ h: (rows: [UnifiedWorkout], ratings: [UUID: WorkoutEffortConfirmation], journal: ActivityLoadJournal, asOf: Date)) -> ActivityLoadSnapshot {
        ActivityLoadCalculator.build(workouts: h.rows, confirmations: h.ratings, journal: h.journal, maximum: 200, asOf: h.asOf, historyDays: h.rows.count)
    }
    func testStoredComparisonFlowsThroughMapperAndEditorWithoutMutatingHealthOrAccount() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let a=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let b=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let target=workout(at:base.addingTimeInterval(10*86400),hr:150),at=target.endDate.addingTimeInterval(3600)
        for i in 1...7 {
            let w=workout(at:base.addingTimeInterval(Double(i)*86400),hr:nil)
            let row=UnifiedWorkoutPersistenceMapper().makeRecord(from:w)
            var detail=WorkoutTelemetry(workoutID:w.id,source:w.source)
            detail.samples=[.init(timestamp:w.startDate.addingTimeInterval(10),heartRateBPM:Double(120+2*i)),
                            .init(timestamp:w.endDate.addingTimeInterval(-10),heartRateBPM:Double(140+2*i))]
            row.telemetryData=try JSONEncoder().encode(detail);a.mainContext.insert(row)
        }
        try a.mainContext.save()
        let reader=ActivityLoadStoredHeartRateReader(context:a.mainContext,scope:"synthetic-comparison")
        let result=try reader.effortComparisonAssessment(for:target,directory:root,maximum:nil,at:at,allowed:{true},calendar:calendar)
        XCTAssertEqual(result.availability,.ready);XCTAssertEqual(result.candidateCount,7);XCTAssertEqual(result.eligibleCount,7)
        let range=try XCTUnwrap(result.range)
        // Independently: stored meanHRs132...144 -> SOOM6.6...7.2.
        XCTAssertEqual(try XCTUnwrap(range.referenceMean),6.9,accuracy:1e-10)
        XCTAssertEqual(range.lower,6.75,accuracy:1e-10);XCTAssertEqual(range.upper,7.05,accuracy:1e-10)
        let editor=WorkoutEffortEditor(workoutID:target.id,store:FileWorkoutEffortStore(scopeDirectory:root),
            sessionContext:.init(target),automaticEstimate:ActivityLoadEstimate.automatic(target,maximum:nil,at:at))
        await editor.load();editor.refreshScoreComparison(result.range,assessment:result);editor.begin()
        XCTAssertEqual(editor.usualRange,range);XCTAssertEqual(editor.comparisonAssessment?.eligibleCount,7)
        XCTAssertEqual(editor.draft,7.5);XCTAssertFalse(editor.canSave)
        editor.cancel();XCTAssertNil(editor.confirmation)
        let other=try ActivityLoadStoredHeartRateReader(context:b.mainContext,scope:"other-account")
            .effortComparisonAssessment(for:target,directory:root.appendingPathComponent("other"),maximum:nil,at:at,allowed:{true},calendar:calendar)
        XCTAssertEqual(other.availability,.insufficient);XCTAssertEqual(other.eligibleCount,0);XCTAssertNil(other.range)
        XCTAssertThrowsError(try reader.effortComparisonAssessment(for:target,directory:root,maximum:nil,at:at,allowed:{false},calendar:calendar))
        XCTAssertFalse(a.mainContext.hasChanges);XCTAssertFalse(b.mainContext.hasChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
        print("SOOM_RANGE_PIPELINE stored7->eligible7->editor; mean6.9 Q25=6.75 Q75=7.05; otherAccount0; no writes")
    }

    func testComparisonAssessmentSeparatesIncompleteTargetMissingEvidenceAndReadFailure() async {
        let target=workout(at:base.addingTimeInterval(10*86400)),at=target.endDate.addingTimeInterval(3600)
        let pending=WorkoutEffortScoreComparison.assessment(for:target,workouts:[],confirmations:[:],maximum:nil,at:target.startDate,calendar:calendar)
        XCTAssertEqual(pending.availability,.awaitingCompletedRecord);XCTAssertNil(pending.range)
        let excluded=workout(at:target.startDate,excluded:true)
        XCTAssertEqual(WorkoutEffortScoreComparison.assessment(for:excluded,workouts:[],confirmations:[:],maximum:nil,at:at,calendar:calendar).availability,.excludedRecord)
        let four=(1...4).map{workout(at:base.addingTimeInterval(Double($0)*86400))}
        let partial=WorkoutEffortScoreComparison.assessment(for:target,workouts:four,confirmations:[:],maximum:nil,at:at,calendar:calendar)
        XCTAssertEqual(partial.candidateCount,4);XCTAssertEqual(partial.eligibleCount,4);XCTAssertEqual(partial.availability,.insufficient)
        XCTAssertTrue(partial.message.contains("4개"));XCTAssertNil(partial.range)
        let editor=WorkoutEffortEditor(workoutID:target.id,store:FixtureWorkoutEffortStore())
        await editor.load();editor.refreshScoreComparison(nil,assessment:partial)
        XCTAssertFalse(editor.historyUnavailable);XCTAssertEqual(editor.comparisonAssessment,partial)
        editor.refreshScoreComparison(nil,unavailable:true)
        XCTAssertTrue(editor.historyUnavailable);XCTAssertNil(editor.comparisonAssessment)
    }

    func testReleaseIndependentArithmeticOracleAndInvalidBoundaries() throws {
        // Constants independently checked using decimal arithmetic in the release
        // audit. Expected values do not call another implementation function.
        let w=workout(seconds:2700,hr:150)
        let personal=ActivityLoadSession.resolve(w,confirmation:nil,maximum:180,at:w.endDate.addingTimeInterval(3600))
        XCTAssertEqual(try XCTUnwrap(personal.intensity),8.333333333333334,accuracy:1e-12)
        XCTAssertEqual(try XCTUnwrap(personal.amount),375,accuracy:1e-9)
        let prior=ActivityLoadSession.resolve(workout(seconds:1800,hr:150),confirmation:nil,maximum:nil,at:base.addingTimeInterval(7200))
        XCTAssertEqual(prior.intensity,7.5);XCTAssertEqual(prior.amount,225)
        let boundaries:[(Double,Double?)]=[(29,nil),(30,1.5),(150,7.5),(200,10),(250,10),(251,nil),(.nan,nil),(.infinity,nil)]
        for (bpm,expected) in boundaries {
            XCTAssertEqual(ActivityLoadEstimate.automatic(workout(hr:bpm),maximum:nil,at:now)?.value,expected)
        }
        XCTAssertEqual(ActivityLoadEstimate.automatic(workout(hr:180),maximum:180,at:now)?.value,10)
        XCTAssertNil(ActivityLoadEstimate.automatic(workout(hr:181),maximum:180,at:now))
        XCTAssertNil(ActivityLoadEstimate.automatic(workout(hr:150),maximum:0,at:now))
        let target=calibrationWorkout(day:10,hr:nil),rows=(1...3).map{calibrationWorkout(day:$0,hr:nil)}
        let ratings=Dictionary(uniqueKeysWithValues:zip(rows,[4,6,8]).map{($0.0.id,rating($0.0,value:$0.1))})
        let at=target.endDate.addingTimeInterval(3600)
        let history=ActivityLoadHistoryReference.resolve(for:target,workouts:rows,confirmations:ratings,at:at)
        let copied=ActivityLoadSession.resolve(target,confirmation:nil,maximum:nil,at:at,history:history)
        XCTAssertEqual(copied.intensity,6);XCTAssertEqual(copied.amount,180)
        XCTAssertNil(ActivityLoadSession.resolve(target,confirmation:nil,maximum:nil,at:at).intensity)
        print("SOOM_RELEASE_ORACLE personal=8.333333333333334/375AU prior=7.5/225AU history=6/180AU absent=nil; bounds pass")
    }
    func testReleaseIndependentTimezoneDailySumAndPartialUnknownAreNotCompleteDayTotals() throws {
        let utc=ActivityLoadRules.calendar("UTC"),seoul=ActivityLoadRules.calendar("Asia/Seoul")
        let first=workout(at:ISO8601DateFormatter().date(from:"2026-10-28T14:00:00Z")!,seconds:1800,hr:150)
        let second=workout(at:ISO8601DateFormatter().date(from:"2026-10-28T15:30:00Z")!,seconds:1200,hr:150)
        let at=ISO8601DateFormatter().date(from:"2026-10-30T00:00:00Z")!
        let ratings=[second.id:rating(second,value:6)]
        let u=ActivityLoadCalculator.build(workouts:[first,second],confirmations:ratings,journal:.empty(zone:"UTC"),maximum:nil,asOf:at,historyDays:5)
        let k=ActivityLoadCalculator.build(workouts:[first,second],confirmations:ratings,journal:.empty(zone:"Asia/Seoul"),maximum:nil,asOf:at,historyDays:5)
        let ud=try XCTUnwrap(u.days.first{$0.key == "2026-10-28"})
        XCTAssertEqual(ud.recordedSubtotal,345);XCTAssertNil(ud.daily);XCTAssertNil(ud.smoothed)
        XCTAssertEqual(ActivityLoadGraphMetric.recordedDays.stateLabel(ud),"기록 기준 · 누락 미확인")
        XCTAssertEqual(k.days.first{$0.key == "2026-10-28"}?.recordedSubtotal,225)
        XCTAssertEqual(k.days.first{$0.key == "2026-10-29"}?.recordedSubtotal,120)
        XCTAssertEqual(utc.startOfDay(for:first.startDate),utc.startOfDay(for:second.startDate))
        XCTAssertNotEqual(seoul.startOfDay(for:first.startDate),seoul.startOfDay(for:second.startDate))
        let absent=workout(at:first.endDate.addingTimeInterval(900),seconds:600,hr:nil)
        let partial=ActivityLoadCalculator.build(workouts:[first,absent],confirmations:[:],journal:.empty(zone:"UTC"),maximum:nil,asOf:at,historyDays:5)
        let day=try XCTUnwrap(partial.days.first{$0.sessions.count == 2})
        XCTAssertEqual(day.sessions.first{$0.id == first.id}?.intensity,7.5)
        XCTAssertNil(day.sessions.first{$0.id == absent.id}?.intensity)
        XCTAssertNil(day.recordedSubtotal);XCTAssertNil(ActivityLoadGraphMetric.recordedDays.value(day))
        print("SOOM_RELEASE_ORACLE UTC345_unreviewed KST225plus120; partial keeps known7.5 but total=nil, never complete/rest zero")
    }
    func testReleaseStoredHRManualOverrideSaveRestartClearAndSourcePreservation() async throws {
        let w=workout(at:Date().addingTimeInterval(-86400),seconds:1800,hr:nil)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let row=UnifiedWorkoutPersistenceMapper().makeRecord(from:w)
        var detail=WorkoutTelemetry(workoutID:w.id,source:w.source)
        detail.samples=[.init(timestamp:w.startDate.addingTimeInterval(10),heartRateBPM:140),.init(timestamp:w.endDate.addingTimeInterval(-10),heartRateBPM:160)]
        row.telemetryData=try JSONEncoder().encode(detail);container.mainContext.insert(row);try container.mainContext.save()
        let original=row.telemetryData,reader=ActivityLoadStoredHeartRateReader(context:container.mainContext,scope:"synthetic-audit")
        let provider:([UnifiedWorkout])throws->[UUID:ActivityLoadHeartRateInput]={try reader.read($0)}
        let source=ActivityLoadTestStore(rows:[w]),model=ActivityLoadViewModel(directory:root)
        await model.reload(store:source,maximum:nil,storedHeartRates:provider)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.intensity,7.5)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.amount,225)
        let editor=WorkoutEffortEditor(workoutID:w.id,store:FileWorkoutEffortStore(scopeDirectory:root),sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.automatic(w,maximum:nil,at:Date(),stored:try provider([w])[w.id]))
        await editor.load();editor.begin();editor.preview(6);let didSave=await editor.save();XCTAssertTrue(didSave)
        let restarted=ActivityLoadViewModel(directory:root)
        await restarted.reload(store:source,maximum:nil,storedHeartRates:provider)
        XCTAssertEqual(restarted.snapshot?.days.flatMap(\.sessions).first?.intensity,6)
        XCTAssertEqual(restarted.snapshot?.days.flatMap(\.sessions).first?.amount,180)
        let saved=try XCTUnwrap(FileWorkoutEffortStore(scopeDirectory:root).load(workoutID:w.id))
        XCTAssertEqual(saved.value,6);XCTAssertEqual(saved.unit,ActivityLoadRules.intensityUnit)
        let didClear=await editor.clearConfirmation();XCTAssertTrue(didClear)
        let cleared=ActivityLoadViewModel(directory:root);await cleared.reload(store:source,maximum:nil,storedHeartRates:provider)
        XCTAssertEqual(cleared.snapshot?.days.flatMap(\.sessions).first?.intensity,7.5)
        XCTAssertEqual(cleared.snapshot?.days.flatMap(\.sessions).first?.amount,225)
        XCTAssertEqual(row.telemetryData,original);XCTAssertNil(row.averageHeartRate);XCTAssertFalse(container.mainContext.hasChanges)
        print("SOOM_RELEASE_ORACLE storedHR140,160=>7.5/225AU; persisted manual6=>180AU afterrestart; clear=>7.5/225AU; raw unchanged")
    }
    func testReleaseIndependentCommonRangeQuantileAndCalibrationArithmetic() throws {
        let target=calibrationWorkout(day:10),rows=(1...5).map{calibrationWorkout(day:$0,hr:Double($0*40))},at=target.endDate.addingTimeInterval(3600)
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:target,workouts:rows,confirmations:[:],maximum:nil,at:at,calendar:calendar))
        XCTAssertEqual(range.lower,4);XCTAssertEqual(range.upper,8);XCTAssertEqual(range.automaticCount,5)
        let edited=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:target,workouts:rows,confirmations:[rows[1].id:rating(rows[1],value:9)],maximum:nil,at:at,calendar:calendar))
        XCTAssertEqual(edited.lower,6);XCTAssertEqual(edited.upper,9);XCTAssertEqual(edited.count,5);XCTAssertEqual(edited.automaticCount,4)
        let teachers=(1...5).map{calibrationWorkout(day:$0,hr:40)}
        let labels=Dictionary(uniqueKeysWithValues:zip(teachers,[3,4,5,6,10]).map{($0.0.id,rating($0.0,value:$0.1))})
        let inputs=ActivityLoadCalibrationInputs.read(workouts:teachers,confirmations:labels,maximum:nil,at:at,zone:calendar.timeZone.identifier)
        let ledger=ActivityLoadCalibrationLedger.empty().updated(inputs:inputs,maximum:nil,at:at)
        XCTAssertEqual(ledger.states[UnifiedWorkoutType.running.rawValue]?.offset,0.25)
        let later=at.addingTimeInterval(7*86400),after=ledger.updated(inputs:inputs,maximum:nil,at:later)
        XCTAssertEqual(after.states[UnifiedWorkoutType.running.rawValue]?.offset,0.5)
        XCTAssertEqual(after.updated(inputs:inputs,maximum:nil,at:later).states[UnifiedWorkoutType.running.rawValue]?.offset,0.5)
        print("SOOM_RELEASE_ORACLE range[2,4,6,8,10]=>Q25=4,Q75=8; override4to9=>6,9; residualmedian3*5/15=1 limited0.25 then0.5")
    }

    func comparisonFixture() -> (target:UnifiedWorkout,rows:[UnifiedWorkout],at:Date) {
        let target=calibrationWorkout(day:10)
        let rows=(1...5).map { calibrationWorkout(day:$0+3,hr:Double(80+$0*20)) }
        return (target,rows,target.endDate.addingTimeInterval(3600))
    }
    private func comparisonCopy(_ w: UnifiedWorkout, id: UUID = UUID(), source: UnifiedDataSource? = nil,
                                externalID: String? = nil, preferred: UUID? = nil, emptySummary: Bool = false,
                                quality: UnifiedDataQuality? = nil) -> UnifiedWorkout {
        UnifiedWorkout(id:id,externalId:externalID ?? w.externalId,source:source ?? w.source,workoutType:w.workoutType,
            startDate:w.startDate,endDate:w.endDate,durationSeconds:w.durationSeconds,
            distanceMeters:emptySummary ? nil : w.distanceMeters,activeEnergyKcal:emptySummary ? nil : w.activeEnergyKcal,
            averageHeartRate:emptySummary ? nil : w.averageHeartRate,maxHeartRate:emptySummary ? nil : w.maxHeartRate,
            averageSpeedMetersPerSecond:nil,elevationGainMeters:nil,dataQuality:quality ?? w.dataQuality,
            createdAt:w.createdAt,updatedAt:w.updatedAt,preferredWorkoutID:preferred)
    }
    func testComparisonSameProviderCopiesCountOneInsteadOfDisqualifyingEverySession() throws {
        let f=comparisonFixture(),copies=f.rows.map{comparisonCopy($0)}
        XCTAssertEqual(ActivityLoadCalculator.canonical(f.rows+copies).count,5)
        XCTAssertNotNil(ActivityLoadEstimate.automatic(f.target,maximum:nil,at:f.at))
        let result=WorkoutEffortScoreComparison.assessment(for:f.target,workouts:f.rows+copies,confirmations:[:],maximum:nil,at:f.at,calendar:calendar)
        XCTAssertEqual(result.eligibleCount,5,"Five known source identities must not become zero just because an import retained copies")
        let range=try XCTUnwrap(result.range);XCTAssertEqual(range.count,5);XCTAssertEqual(range.lower,6);XCTAssertEqual(range.upper,8)
    }
    func testComparisonOwnerResolvedSourcesCountOneWithoutFusingMeasurements() throws {
        let f=comparisonFixture(),primaries=f.rows.map{comparisonCopy($0,id:$0.id,preferred:$0.id)}
        let copies=primaries.map{comparisonCopy($0,source:.strava,externalID:UUID().uuidString,preferred:$0.id)}
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:primaries+copies,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(range.count,5);XCTAssertEqual(range.lower,6);XCTAssertEqual(range.upper,8)
    }
    func testComparisonStoredHRRemainsUsableAfterOriginallyMissingSummary() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        defer { withExtendedLifetime(container) {} }
        let context=container.mainContext
        let f=comparisonFixture();var original:[Data]=[]
        for (index,w) in f.rows.enumerated() {
            let empty=comparisonCopy(w,id:w.id,emptySummary:true,quality:.missing)
            let row=UnifiedWorkoutPersistenceMapper().makeRecord(from:empty)
            var telemetry=WorkoutTelemetry(workoutID:empty.id,source:empty.source)
            telemetry.samples=[.init(timestamp:empty.startDate.addingTimeInterval(10),heartRateBPM:Double(100+20*index)),
                               .init(timestamp:empty.endDate.addingTimeInterval(-10),heartRateBPM:Double(100+20*index))]
            let encoded=try JSONEncoder().encode(telemetry)
            row.telemetryData=encoded;original.append(encoded);context.insert(row)
        }
        try context.save()
        let reader=ActivityLoadStoredHeartRateReader(context:context,scope:"synthetic-stale-summary")
        let result=try reader.effortComparisonAssessment(for:f.target,directory:root,maximum:nil,at:f.at,allowed:{true},calendar:calendar)
        XCTAssertEqual(result.eligibleCount,5)
        let range=try XCTUnwrap(result.range);XCTAssertEqual(range.lower,6);XCTAssertEqual(range.upper,8)
        let persisted=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertTrue(persisted.allSatisfy{$0.dataQualityRaw == UnifiedDataQuality.missing.rawValue && $0.averageHeartRate == nil})
        XCTAssertEqual(Set(persisted.compactMap(\.telemetryData)),Set(original));XCTAssertFalse(context.hasChanges)
        let editor=WorkoutEffortEditor(workoutID:f.target.id,store:FileWorkoutEffortStore(scopeDirectory:root),
            sessionContext:.init(f.target),automaticEstimate:ActivityLoadEstimate.automatic(f.target,maximum:nil,at:f.at))
        await editor.load();editor.refreshScoreComparison(range,assessment:result);editor.begin()
        XCTAssertEqual(editor.usualRange,range);XCTAssertFalse(editor.canSave)
        var interaction=EffortScaleInteraction();interaction.press()
        XCTAssertTrue(interaction.showsHatching(hasRange:editor.usualRange != nil))
        editor.cancel();XCTAssertNil(editor.confirmation);XCTAssertFalse(context.hasChanges)
    }
    func testComparisonCanonicalCrossProviderCopiesDoNotInflateIndependentCount() throws {
        let f=comparisonFixture(),copies=f.rows.map{comparisonCopy($0,source:.strava,externalID:UUID().uuidString)}
        XCTAssertEqual(ActivityLoadCalculator.canonical(f.rows+copies).count,5)
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows+copies,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(range.count,5);XCTAssertEqual(range.lower,6);XCTAssertEqual(range.upper,8)
        let three=Array(f.rows.prefix(3)),threeCopies=three.map{comparisonCopy($0)}
        let insufficient=WorkoutEffortScoreComparison.assessment(for:f.target,workouts:three+threeCopies,confirmations:[:],maximum:nil,at:f.at,calendar:calendar)
        XCTAssertEqual(insufficient.candidateCount,3);XCTAssertEqual(insufficient.eligibleCount,3);XCTAssertNil(insufficient.range)
    }
    func testComparisonSeparateOverlappingSessionsStayExcludedWithObservableReason() {
        let f=comparisonFixture(),overlap=workout(at:f.rows[0].startDate.addingTimeInterval(120),hr:220,source:.manual)
        let result=WorkoutEffortScoreComparison.assessment(for:f.target,workouts:f.rows+[overlap],confirmations:[:],maximum:nil,at:f.at,calendar:calendar)
        XCTAssertEqual(result.candidateCount,6);XCTAssertEqual(result.eligibleCount,4);XCTAssertEqual(result.exclusions[.overlap],2);XCTAssertNil(result.range)
        XCTAssertTrue(result.message.contains("별개 운동 시간 겹침 2개"))
        XCTAssertTrue(result.message.contains("직접 입력을 추가해야 하는 것은 아니에요"))
    }
    func testComparisonMissingSummaryStillNeedsActualScoreEvidence() throws {
        let f=comparisonFixture(),rows=f.rows.map{comparisonCopy($0,id:$0.id,emptySummary:true,quality:.missing)}
        let none=WorkoutEffortScoreComparison.assessment(for:f.target,workouts:rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar)
        XCTAssertEqual(none.eligibleCount,0);XCTAssertEqual(none.exclusions[.missingScore],5);XCTAssertNil(none.range)
        let invalid=Dictionary(uniqueKeysWithValues:rows.map{($0.id,ActivityLoadHeartRateInput(value:.nan,evidence:"stored_summary_v1"))})
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:[:],maximum:nil,at:f.at,storedHeartRates:invalid,calendar:calendar))
        let labels=Dictionary(uniqueKeysWithValues:rows.enumerated().map{($0.element.id,rating($0.element,value:4+$0.offset))})
        let manual=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:labels,maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(manual.count,5);XCTAssertEqual(manual.automaticCount,0);XCTAssertEqual(manual.lower,5);XCTAssertEqual(manual.upper,7)
    }
    func testComparisonDoesNotPromoteUnknownOrEstimatedRecordMetadata() {
        let f=comparisonFixture()
        for quality in [UnifiedDataQuality.unknown,.estimated] {
            let rows=Array(f.rows.dropFirst())+[comparisonCopy(f.rows[0],id:f.rows[0].id,quality:quality)]
            let result=WorkoutEffortScoreComparison.assessment(for:f.target,workouts:rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar)
            XCTAssertEqual(result.eligibleCount,4);XCTAssertEqual(result.exclusions[.quality],1);XCTAssertNil(result.range)
        }
    }
    func testAutomaticComparisonNeedsNoManualRatingsAndDoesNotWeightTime() throws {
        let f=comparisonFixture()
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(range.count,5);XCTAssertEqual(range.automaticCount,5);XCTAssertEqual(range.initialEstimateCount,5)
        XCTAssertEqual(range.lower,6);XCTAssertEqual(range.upper,8)
        XCTAssertEqual(range.displayTitle,"점수 추정 범위")
        let longer=f.rows.map{workout(id:$0.id,at:$0.startDate,seconds:7200,hr:$0.averageHeartRate)}
        let differentTimes=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:longer,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(differentTimes.lower,range.lower);XCTAssertEqual(differentTimes.upper,range.upper)
    }
    func testComparisonFinalManualOverridesOneAutomaticThenClearRestoresOneValue() throws {
        let f=comparisonFixture(),w=f.rows[1],rating=rating(f.rows[1],value:9)
        let edited=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[w.id:rating],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(edited.count,5);XCTAssertEqual(edited.automaticCount,4);XCTAssertEqual(edited.lower,7);XCTAssertEqual(edited.upper,9)
        var cleared=rating;cleared.isCleared=true
        let restored=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[w.id:cleared],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(restored.automaticCount,5);XCTAssertEqual(restored.lower,6);XCTAssertEqual(restored.upper,8)
    }
    func testComparisonExcludesSelfFutureWrongSportOldAndConflictingOrOverlappingRecords() throws {
        let f=comparisonFixture()
        let extras=[f.target,calibrationWorkout(day:11,hr:240),calibrationWorkout(day:9,hr:240,sport:.cycling),calibrationWorkout(day:-12,hr:240)]
        let valid=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows+extras,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(valid.count,5);XCTAssertEqual(valid.upper,8)
        let bad=workout(id:f.rows[0].id,at:f.rows[0].startDate,hr:220)
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows+[bad],confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        let overlap=workout(at:f.rows[0].startDate.addingTimeInterval(120),hr:220,source:.manual)
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows+[overlap],confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
    }
    func testComparisonNeverFillsNoHRFromARepeatedHistoricalPriorAndNeverCountsLegacyZero() throws {
        let f=comparisonFixture(),rows=f.rows.map{calibrationWorkout(day:calendar.dateComponents([.day],from:base,to:$0.startDate).day!,hr:nil,id:$0.id)}
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        var labels=Dictionary(uniqueKeysWithValues:rows.map{($0.id,rating($0,value:6))})
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:labels,maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(range.count,5);XCTAssertEqual(range.automaticCount,0);XCTAssertEqual(range.displayTitle,"최근 점수 범위")
        labels[rows[0].id]=rating(rows[0],value:0)
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:labels,maximum:nil,at:f.at,calendar:calendar))
        XCTAssertEqual(labels[rows[0].id]?.value,0,"Legacy input is preserved, not rewritten to fit a new comparison")
    }
    func testComparisonUsesFreshCommonModelAndStoredHRInsteadOfOldSavedAutomaticNumbers() throws {
        let f=comparisonFixture(),rows=(1...5).map{calibrationWorkout(day:$0,hr:nil)}
        let stored=Dictionary(uniqueKeysWithValues:rows.map{($0.id,ActivityLoadHeartRateInput(value:150,evidence:"stored_summary_v1"))})
        let prior=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:[:],maximum:nil,at:f.at,storedHeartRates:stored,calendar:calendar))
        let personal=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:[:],maximum:180,at:f.at,storedHeartRates:stored,calendar:calendar))
        XCTAssertEqual(prior.lower,7.5);XCTAssertEqual(personal.lower,10*150/180,accuracy:0.00001)
        XCTAssertNotEqual(prior.comparisonVersion,personal.comparisonVersion)
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:rows,confirmations:[:],maximum:100,at:f.at,storedHeartRates:stored,calendar:calendar),"Invalid personal settings are never silently replaced by a product prior")
    }
    func testComparisonAdapterIsAccountLocalReadOnlyAndRejectsScopeCancellation() throws {
        let f=comparisonFixture(),mapper=UnifiedWorkoutPersistenceMapper()
        let a=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let b=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        for w in f.rows {a.mainContext.insert(mapper.makeRecord(from:w))};try a.mainContext.save()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reader=ActivityLoadStoredHeartRateReader(context:a.mainContext,scope:"A")
        let range=try reader.effortComparison(for:f.target,directory:root,maximum:nil,at:f.at,allowed:{true},calendar:calendar)
        XCTAssertEqual(range?.count,5);XCTAssertEqual(range?.automaticCount,5)
        XCTAssertNil(try ActivityLoadStoredHeartRateReader(context:b.mainContext,scope:"B").effortComparison(for:f.target,directory:root.appendingPathComponent("B"),maximum:nil,at:f.at,allowed:{true},calendar:calendar))
        var checks=0
        XCTAssertThrowsError(try reader.effortComparison(for:f.target,directory:root,maximum:nil,at:f.at,allowed:{checks += 1;return checks < 3},calendar:calendar))
        XCTAssertFalse(a.mainContext.hasChanges);XCTAssertFalse(FileManager.default.fileExists(atPath:root.path),"Read-only comparison must not create a journal, receipt or annotation file")
    }
    func testComparisonRejectsAnOngoingTargetWithoutRelaxingTheCompletionGuard() {
        let f=comparisonFixture()
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[:],maximum:nil,at:f.target.startDate.addingTimeInterval(5),calendar:calendar))
        XCTAssertNotNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
    }

    func testComparisonRejectsOffsetLearnedFromTargetOrFutureAndAcceptsProvenEarlierKeys() throws {
        let f=comparisonFixture()
        var labels=Dictionary(uniqueKeysWithValues:f.rows.prefix(4).map{($0.id,rating($0,value:9))})
        labels[f.target.id]=rating(f.target,value:9)
        let inputs=ActivityLoadCalibrationInputs.read(workouts:f.rows+[f.target],confirmations:labels,maximum:nil,at:f.at,zone:calendar.timeZone.identifier)
        let contaminated=ActivityLoadCalibrationLedger.empty().updated(inputs:inputs,maximum:nil,at:f.at)
        XCTAssertEqual(contaminated.states[UnifiedWorkoutType.running.rawValue]?.pairCount,5)
        XCTAssertNil(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:labels,maximum:nil,at:f.at,calibration:contaminated,calendar:calendar),"Excluding the target point alone is insufficient if its label influenced the automatic offset")
        labels=Dictionary(uniqueKeysWithValues:f.rows.map{($0.id,rating($0,value:9))})
        let earlierInputs=ActivityLoadCalibrationInputs.read(workouts:f.rows,confirmations:labels,maximum:nil,at:f.at,zone:calendar.timeZone.identifier)
        let heldOut=ActivityLoadCalibrationLedger.empty().updated(inputs:earlierInputs,maximum:nil,at:f.at)
        let extra=calibrationWorkout(day:9,hr:150)
        let valid=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows+[extra],confirmations:labels,maximum:nil,at:f.at,calibration:heldOut,calendar:calendar))
        XCTAssertEqual(valid.count,6);XCTAssertEqual(valid.automaticCount,1)
    }

    func testComparisonEditorReopenNeverFallsBackToManualOnlyHistoryOrSavesAnEstimate() async throws {
        let f=comparisonFixture(),store=FixtureWorkoutEffortStore()
        let range=try XCTUnwrap(WorkoutEffortScoreComparison.build(for:f.target,workouts:f.rows,confirmations:[:],maximum:nil,at:f.at,calendar:calendar))
        let editor=WorkoutEffortEditor(workoutID:f.target.id,store:store,sessionContext:.init(f.target),automaticEstimate:ActivityLoadEstimate.automatic(f.target,maximum:nil,at:f.at))
        editor.refreshScoreComparison(range);await editor.load();editor.begin()
        XCTAssertEqual(editor.usualRange,range);XCTAssertNil(editor.selectedValue);XCTAssertFalse(editor.canSave)
        editor.cancel();editor.begin();XCTAssertEqual(editor.usualRange?.automaticCount,5);XCTAssertEqual(store.saveCount,0)
        editor.refreshScoreComparison(nil,unavailable:true);editor.cancel();editor.begin();XCTAssertNil(editor.usualRange);XCTAssertTrue(editor.historyUnavailable)
    }

    func testUnreviewedComputedScoresRemainVisibleWithoutInventingCompleteDays() throws {
        var h=history(8);h.ratings=[:];h.journal.approvals=[:]
        let journal=h.journal,snapshot=build(h)
        let metric=ActivityLoadGraphMetric(days:snapshot.days)
        XCTAssertEqual(metric,.recordedDays)
        XCTAssertEqual(ActivityLoadInputPlan(snapshot).automaticCount,8)
        for day in snapshot.days.filter(\.workoutPresent) {
            XCTAssertNil(day.daily);XCTAssertNil(day.smoothed);XCTAssertNil(day.lower);XCTAssertNil(day.upper)
            XCTAssertEqual(metric.value(day),225)
            XCTAssertEqual(metric.stateLabel(day),"기록 기준 · 누락 미확인")
            XCTAssertEqual(day.sessions.first?.intensity,7.5)
        }
        XCTAssertEqual(h.journal,journal,"Displaying records must not approve any missing/rest date")
    }
    func testRecordProjectionNeverTurnsMissingSessionsOrEmptyDatesIntoZero() throws {
        var h=history(4);h.ratings=[:];h.journal.approvals=[:]
        let missing=workout(at:h.rows[2].startDate,hr:nil);h.rows[2]=missing
        h.rows.remove(at:1)
        let snapshot=build(h),metric=ActivityLoadGraphMetric(days:[])
        let missingDay=try XCTUnwrap(snapshot.days.first{$0.sessions.contains{$0.id == missing.id}})
        XCTAssertNil(metric.value(missingDay));XCTAssertEqual(metric.stateLabel(missingDay),"점수 미산출 기록 포함")
        let empty=try XCTUnwrap(snapshot.days.first{!$0.workoutPresent && !$0.isForecast})
        XCTAssertNil(metric.value(empty));XCTAssertEqual(metric.stateLabel(empty),"이 날짜에 확인된 부하 없음")
    }
    func testRecordProjectionWithholdsPartialAndOverlappingDayTotals() throws {
        var h=history(2);h.ratings=[:];h.journal.approvals=[:]
        let partial=workout(at:h.rows[0].endDate.addingTimeInterval(7200),hr:nil);h.rows.append(partial)
        let metric=ActivityLoadGraphMetric(days:[]),snapshot=build(h)
        XCTAssertNil(metric.value(try XCTUnwrap(snapshot.days.first{$0.sessions.contains{$0.id == partial.id}})))
        var conflict=try XCTUnwrap(snapshot.days.first{$0.workoutPresent})
        conflict.cannotPreviewSubtotal=true;conflict.daily=100
        XCTAssertNil(metric.value(conflict),"A display fallback must not bypass the existing source conflict/overlap guard")
    }
    func testCompleteTrendProjectionAndExplicitZeroRemainSeparateFromUnreviewedRecords() throws {
        let snapshot=build(history(100)),metric=ActivityLoadGraphMetric(days:build(history(100)).days)
        XCTAssertEqual(metric,.recentTrend)
        let day=try XCTUnwrap(snapshot.days.first{$0.smoothed != nil})
        XCTAssertEqual(metric.value(day),day.smoothed)
        var zero=day;zero.daily=0;zero.smoothed=nil
        XCTAssertEqual(ActivityLoadGraphMetric.recordedDays.value(zero),0)
        zero.isForecast=true
        XCTAssertNil(ActivityLoadGraphMetric.recordedDays.value(zero))
    }
    func testInitialSelectionPrefersLatestRealWorkoutOnlyWhenTrendUnavailable() throws {
        var h=history(10);h.ratings=[:];h.journal.approvals=[:]
        h.rows.removeLast(3)
        let snapshot=build(h)
        let day=try XCTUnwrap(ActivityLoadGraphMetric.selectedDay(in:snapshot,selected:nil,calendar:calendar))
        XCTAssertTrue(day.workoutPresent);XCTAssertEqual(day.date,calendar.startOfDay(for:h.rows.last!.startDate))
        let empty=try XCTUnwrap(snapshot.days.last{!$0.workoutPresent && !$0.isForecast})
        XCTAssertEqual(ActivityLoadGraphMetric.selectedDay(in:snapshot,selected:empty.date,calendar:calendar)?.date,empty.date,"An explicitly selected empty date must stay selected, never inherit another date's score")
    }
    func testRecordProjectionRecomputesManualOverrideClearAndDeleteWithoutDoubleCounting() throws {
        var h=history(5);h.ratings=[:];h.journal.approvals=[:];let w=h.rows[3]
        func amount(_ input:(rows:[UnifiedWorkout],ratings:[UUID:WorkoutEffortConfirmation],journal:ActivityLoadJournal,asOf:Date)) throws -> Double? {
            let day=try XCTUnwrap(build(input).days.first{$0.sessions.contains{$0.id == w.id}})
            return ActivityLoadGraphMetric.recordedDays.value(day)
        }
        XCTAssertEqual(try amount(h),225)
        h.ratings[w.id]=rating(w,value:6);XCTAssertEqual(try amount(h),180)
        h.ratings=[:];XCTAssertEqual(try amount(h),225)
        h.rows.removeAll{$0.id == w.id}
        let deleted=build(h);XCTAssertFalse(deleted.days.flatMap(\.sessions).contains{$0.id == w.id})
    }
    func testUnreviewedInitialEstimateSourceLabelDoesNotLoseItsPriorMeaning() throws {
        var h=history(2);h.ratings=[:];h.journal.approvals=[:]
        let snapshot=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:h.journal,maximum:nil,asOf:h.asOf,historyDays:4)
        let day=try XCTUnwrap(snapshot.days.first( where: \.workoutPresent))
        XCTAssertEqual(day.inputSummary,"초기 추정 · 낮은 신뢰")
        XCTAssertEqual(ActivityLoadGraphMetric.recordedDays.value(day),225)
    }

    func testLegacySourceBoundaryPolicyReproduction() {
        var h = history(150); h.ratings = [:]
        let initial = legacyBuild(h); let w = h.rows[80]
        h.ratings[w.id] = rating(w, value: 9)
        let edited = legacyBuild(h)
        XCTAssertEqual(initial.days[80].daily, 150)
        XCTAssertEqual(edited.days[80].daily, 270)
        XCTAssertNil(edited.days[80].smoothed)
        XCTAssertNil(edited.days[107].smoothed)
        XCTAssertNotNil(edited.days[108].smoothed)
        XCTAssertNil(edited.days[135].upper)
        XCTAssertNotNil(edited.days[136].upper)
        let second = workout(at: w.startDate.addingTimeInterval(7200))
        h.rows.append(second)
        let key = ActivityLoadRules.dayKey(w.startDate, calendar: calendar)
        h.journal.approvals[key] = .init(fingerprint: ActivityLoadCalculator.fingerprint([w,second], zone:h.journal.timeZoneID),kind:.recordsReviewed,confirmedAt:h.asOf)
        let mixed = legacyBuild(h)
        XCTAssertNil(mixed.days.first { $0.key == key }?.daily)
        h.rows.removeLast(); h.journal.approvals[key] = .init(fingerprint:ActivityLoadCalculator.fingerprint([w],zone:h.journal.timeZoneID),kind:.recordsReviewed,confirmedAt:h.asOf)
        h.ratings = [:]; let cleared = legacyBuild(h)
        XCTAssertEqual(cleared.days[80].daily,initial.days[80].daily)
        XCTAssertEqual(cleared.days.map(\.smoothed),initial.days.map(\.smoothed))
        print("R03_BASELINE: auto150 -> manual270; smoothed missing day80...107; range missing day80...135; same-day automatic+manual daily=nil; clearing restores original complete curve")
    }

    func legacyBuild(_ h: (rows: [UnifiedWorkout], ratings: [UUID: WorkoutEffortConfirmation], journal: ActivityLoadJournal, asOf: Date)) -> LegacyR1ActivityLoadSnapshot {
        var j=LegacyR1ActivityLoadJournal.empty(zone:h.journal.timeZoneID)
        for (key,a) in h.journal.approvals {
            let rows=h.rows.filter{ActivityLoadRules.dayKey($0.startDate,calendar:calendar)==key}
            j.approvals[key] = .init(fingerprint:LegacyR1ActivityLoadCalculator.fingerprint(rows,zone:j.timeZoneID),kind:LegacyR1ActivityLoadDayApproval.Kind(rawValue:a.kind.rawValue)!,confirmedAt:a.confirmedAt)
        }
        let ratings=h.ratings.mapValues { old in var c=old;c.scaleVersion=LegacyR1ActivityLoadRules.scaleVersion;c.durationPolicy=LegacyR1ActivityLoadRules.durationPolicy;c.unit="sessionRPE_0_10";return c }
        return LegacyR1ActivityLoadCalculator.build(workouts:h.rows,confirmations:ratings,journal:j,maximum:200,asOf:h.asOf,historyDays:h.rows.count)
    }
    func legacyR3Build(_ h: (rows: [UnifiedWorkout], ratings: [UUID: WorkoutEffortConfirmation], journal: ActivityLoadJournal, asOf: Date)) -> LegacyR3ActivityLoadSnapshot {
        var j=LegacyR3ActivityLoadJournal.empty(zone:h.journal.timeZoneID)
        for (key,a) in h.journal.approvals {
            let rows=h.rows.filter{ActivityLoadRules.dayKey($0.startDate,calendar:calendar)==key}
            j.approvals[key] = .init(fingerprint:LegacyR3ActivityLoadCalculator.fingerprint(rows,zone:j.timeZoneID),kind:LegacyR3ActivityLoadDayApproval.Kind(rawValue:a.kind.rawValue)!,confirmedAt:a.confirmedAt)
        }
        let ratings=h.ratings.mapValues { old in var c=old;c.scaleVersion=LegacyR3ActivityLoadRules.scaleVersion;c.durationPolicy=LegacyR3ActivityLoadRules.durationPolicy;c.unit="sessionRPE_0_10";return c }
        return LegacyR3ActivityLoadCalculator.build(workouts:h.rows,confirmations:ratings,journal:j,maximum:200,asOf:h.asOf,historyDays:h.rows.count)
    }

    func testLegacyR3OneManualOverrideInAutomaticHistoryKeepsNumericCurveAndClearRestoresEverything() {
        var h=history(170); h.ratings=[:]
        let initial=legacyR3Build(h); let w=h.rows[80]
        h.ratings[w.id]=rating(w,value:9)
        let edited=legacyR3Build(h)
        XCTAssertEqual(edited.days[80].daily,270)
        XCTAssertEqual(edited.days.map { $0.smoothed != nil },initial.days.map { $0.smoothed != nil })
        XCTAssertEqual(edited.days[80].segment,initial.days[80].segment)
        XCTAssertEqual(edited.days[80].state,.mixed)
        XCTAssertNil(edited.days[80].lower); XCTAssertNil(edited.days[80].upper)
        XCTAssertTrue(edited.days[80].inputSummary.contains("혼합"))
        for i in 0..<80 {
            XCTAssertEqual(edited.days[i],initial.days[i],"Earlier raw/derived history is unchanged")
        }
        XCTAssertGreaterThan(edited.days[80].smoothed!,initial.days[80].smoothed!)
        XCTAssertGreaterThan(edited.days[107].smoothed!,initial.days[107].smoothed!)
        XCTAssertEqual(edited.days[108].smoothed!,initial.days[108].smoothed!,accuracy:1e-9)
        XCTAssertEqual(edited.days[108].state,.mixed,"Prior comparison window still contains a mixed-input smoothed value")
        XCTAssertNotNil(edited.days[164].lower,"Hold follows affected input windows, not a restarted history counter")
        XCTAssertEqual(edited.days[164].state,.inside)
        let sourceBefore=h.rows
        for _ in 0..<3 {
            h.ratings=[:]; let cleared=legacyR3Build(h)
            XCTAssertEqual(cleared.days.map(\.daily),initial.days.map(\.daily))
            XCTAssertEqual(cleared.days.map(\.smoothed),initial.days.map(\.smoothed))
            XCTAssertEqual(cleared.days.map(\.lower),initial.days.map(\.lower))
            XCTAssertEqual(cleared.days.map(\.upper),initial.days.map(\.upper))
            h.ratings[w.id]=rating(w,value:9)
            XCTAssertEqual(legacyR3Build(h).days[80].daily,270)
        }
        XCTAssertEqual(h.rows,sourceBefore)
        XCTAssertEqual(edited.days[80].sessions.first?.methodKey,LegacyR3ActivityLoadRules.manualMethod+":srpe_v1")
        XCTAssertEqual(edited.days[81].sessions.first?.methodKey,LegacyR3ActivityLoadRules.automaticMethod+":maxHR:200")
        XCTAssertEqual(edited.days[80].methodKey,edited.days[81].methodKey,"Input source is separate from aggregate contract")
    }
    func testSameDayEstimateAndOverrideUseOneInputAndRecalculateRangeWithoutSourceHold() {
        var h=history(100);h.ratings=[:];let w=h.rows[80],second=workout(at:h.rows[80].startDate.addingTimeInterval(7200));h.rows.append(second)
        let key=ActivityLoadRules.dayKey(w.startDate,calendar:calendar)
        h.journal.approvals[key] = .init(fingerprint:ActivityLoadCalculator.fingerprint([w,second],zone:h.journal.timeZoneID),kind:.recordsReviewed,confirmedAt:h.asOf)
        func day()->ActivityLoadDay {build(h).days.first{$0.key==key}!}
        XCTAssertEqual(day().daily,450)
        h.ratings[w.id]=rating(w,value:9)
        XCTAssertEqual(day().daily,495);XCTAssertNotNil(day().smoothed);XCTAssertNotNil(day().upper)
        XCTAssertEqual(day().state,.above);XCTAssertTrue(day().inputSummary.contains("사용자 수정"))
        XCTAssertEqual(Set(day().sessions.compactMap(\.methodKey)).count,2)
        h.ratings[w.id]=rating(w,value:9,seconds:900);XCTAssertEqual(day().daily,495,"Only the recorded workout duration is used")
        h.ratings[w.id]=rating(w,value:0);XCTAssertEqual(day().daily,225)
        h.ratings=[:];XCTAssertEqual(day().daily,450)
    }

    func testTodaysManualEditPreservesPrevious55DaysAndMissingRemainsMissing() {
        var h=history(100); h.ratings=[:]
        let today=workout(at:h.asOf.addingTimeInterval(6*3600));h.rows.append(today);h.asOf=h.asOf.addingTimeInterval(20*3600)
        let initial=build(h)
        h.ratings[today.id]=rating(today,value:8)
        let edited=build(h)
        let todayKey=ActivityLoadRules.dayKey(today.startDate,calendar:calendar)
        for before in initial.days.filter({ $0.key < todayKey }).suffix(55) {
            XCTAssertEqual(edited.days.first { $0.key==before.key },before)
        }
        let current=edited.days.first { $0.key==todayKey }!
        XCTAssertNil(current.daily,"Today is unfinished, not manufactured zero")
        XCTAssertEqual(current.sessions.first?.amount,240)
        let missing=workout(hr:nil)
        XCTAssertNil(ActivityLoadSession.resolve(missing,confirmation:nil,maximum:200,at:now).amount)
        XCTAssertEqual(ActivityLoadSession.resolve(workout(),confirmation:nil,maximum:nil,at:now).amount,225,"Authorized product prior fills missing baseline without duplicating time")
    }
    func testPersistedOverrideThenClearUsesLatestAutomaticParametersWithoutResetOrDoubleSum() async throws {
        let h=history(100); let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local=FileActivityLoadStore(scope:dir);try local.save(h.journal)
        let efforts=FileWorkoutEffortStore(scopeDirectory:dir)
        let source=ActivityLoadTestStore(rows:h.rows)
        let model=ActivityLoadViewModel(directory:dir,now:{h.asOf})
        await model.reload(store:source,maximum:200);let initial=model.snapshot!
        let w=h.rows[80];try await efforts.save(rating(w,value:9),workoutID:w.id)
        await model.reload(store:source,maximum:200)
        XCTAssertEqual(model.snapshot!.days.first{$0.key==initial.days.first{$0.sessions.contains{$0.id==w.id}}!.key}?.daily,270)
        XCTAssertEqual(model.snapshot!.days.filter{$0.smoothed != nil}.count,initial.days.filter{$0.smoothed != nil}.count)
        await model.reload(store:source,maximum:220)
        XCTAssertEqual(model.snapshot!.days.flatMap(\.sessions).first{$0.id==w.id}?.amount,270,"Parameter update never overwrites manual input")
        try await efforts.clear(workoutID:w.id)
        await model.reload(store:source,maximum:220)
        let current=model.snapshot!, fresh=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:h.journal,maximum:220,asOf:h.asOf)
        XCTAssertEqual(current.days.map(\.smoothed),fresh.days.map(\.smoothed))
        XCTAssertEqual(current.days.flatMap(\.sessions).first{$0.id==w.id}?.amount,ActivityLoadSession.resolve(w,confirmation:nil,maximum:220,at:h.asOf).amount)
        XCTAssertNil(try efforts.load(workoutID:w.id))
    }
    func testOverlappingRecordsAreDeduplicatedOrRequireExplicitResolutionNeverSilentlyDoubleTime() {
        let w=workout(), duplicate=workout(at:base.addingTimeInterval(3))
        XCTAssertEqual(ActivityLoadCalculator.canonical([w,duplicate]).count,1)
        let partial=workout(at:base.addingTimeInterval(600))
        var journal=ActivityLoadJournal.empty(zone:calendar.timeZone.identifier)
        let key=ActivityLoadRules.dayKey(w.startDate,calendar:calendar)
        journal.approvals[key] = .init(fingerprint:ActivityLoadCalculator.fingerprint([w,partial],zone:journal.timeZoneID),kind:.recordsReviewed,confirmedAt:base.addingTimeInterval(7200))
        let s=ActivityLoadCalculator.build(workouts:[w,partial],confirmations:[:],journal:journal,maximum:200,asOf:base.addingTimeInterval(86400),historyDays:2)
        let d=s.days.first{$0.key==key}!
        XCTAssertEqual(d.sessions.count,2);XCTAssertNil(d.daily)
        XCTAssertTrue(d.reason!.contains("겹치는"))
    }

    func testAutomaticIntensityHasNoDurationAndLoadUsesTimeOnce() {
        let a = workout(), b = workout(seconds: 3600)
        let ea = ActivityLoadEstimate.heartRate(a, maxHeartRate: 200, at: base.addingTimeInterval(7200))!
        let eb = ActivityLoadEstimate.heartRate(b, maxHeartRate: 200, at: base.addingTimeInterval(7200))!
        XCTAssertEqual(ea.value, 7.5, accuracy: 1e-12); XCTAssertEqual(ea.value, eb.value)
        XCTAssertEqual(ActivityLoadSession.resolve(a, confirmation: nil, maximum: 200, at: now).amount!, 225, accuracy: 1e-10)
        XCTAssertEqual(ActivityLoadSession.resolve(b, confirmation: nil, maximum: 200, at: base.addingTimeInterval(7200)).amount!, 450, accuracy: 1e-10)
    }
    func testNoSportOrDurationFallbackForMissingOrInvalidSensorAndBaseline() {
        for hr in [nil, Double.nan, -1, 201] as [Double?] {
            XCTAssertNil(ActivityLoadEstimate.heartRate(workout(hr: hr), maxHeartRate: 200, at: now))
        }
        XCTAssertNil(ActivityLoadEstimate.heartRate(workout(), maxHeartRate: nil, at: now))
        XCTAssertNil(ActivityLoadEstimate.heartRate(workout(), maxHeartRate: 0, at: now))
    }
    func testManualOverridesAutoAndLegacyIsNeverReinterpreted() {
        let w = workout(); let c = rating(w, value: 8)
        let actual = ActivityLoadSession.resolve(w, confirmation: c, maximum: 200, at: now)
        XCTAssertEqual(actual.amount!, 240, accuracy: 1e-10)
        XCTAssertTrue(actual.methodKey!.hasPrefix(ActivityLoadRules.manualMethod))
        XCTAssertEqual(ActivityLoadSession.resolve(w, confirmation: nil, maximum: 200, at: now).intensity, 7.5)
        let legacy = WorkoutEffortConfirmation(value: 8, confirmedAt: now, revision: UUID())
        XCTAssertEqual(ActivityLoadSession.resolve(w, confirmation: legacy, maximum: 200, at: now).amount,225)
        XCTAssertTrue(ActivityLoadSession.resolve(w, confirmation: legacy, maximum:200,at:now).sourceLabel.contains("이전 기준"))
    }
    func testZeroIsAValidRatingButMissingIsNotZero() {
        let w = workout(hr: nil), zero = rating(w, value: 0)
        XCTAssertEqual(ActivityLoadSession.resolve(w, confirmation: zero, maximum: nil, at: now).amount, 0)
        XCTAssertNil(ActivityLoadSession.resolve(w, confirmation: nil, maximum: nil, at: now).amount)
    }
    func testAnnotationDurationCannotOverrideRecordedTimeAndFutureOrChangedOriginalAreRejected() {
        let w = workout()
        for seconds in [0, -1, Double.nan, 7200] {
            XCTAssertEqual(ActivityLoadSession.resolve(w, confirmation: rating(w, seconds: seconds), maximum: 200, at: now).amount,120,"Obsolete annotation time is preserved but not used")
        }
        let future = ActivityLoadSession.resolve(w, confirmation: rating(w), maximum: 200, at: w.endDate)
        XCTAssertEqual(future.amount,225,"Future manual override remains unapplied; valid current source may still estimate")
        XCTAssertFalse(future.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) ?? true)
        XCTAssertEqual(ActivityLoadSession.resolve(workout(id: w.id, at: base.addingTimeInterval(1)), confirmation: rating(w), maximum: 200, at: now).amount,225,"Changed original rejects old manual input and uses valid current automatic evidence")
        XCTAssertNil(ActivityLoadSession.resolve(workout(seconds: 0), confirmation: nil, maximum: 200, at: now).amount)
    }
    func testFirstFiniteAverageAt28AndFirstPersonalRangeAt56() {
        let s = build(history(70));let actual = s.days.filter { !$0.isForecast }
        XCTAssertNil(actual[26].smoothed); XCTAssertEqual(actual[27].smoothed!, 120, accuracy: 1e-9)
        XCTAssertNil(actual[54].lower); XCTAssertEqual(actual[55].lower!, 120, accuracy: 1e-9)
        XCTAssertEqual(actual[55].upper!, 120, accuracy: 1e-9); XCTAssertEqual(actual[55].state, .inside)
    }
    func testMissingDayBreaksAndRequiresNew28And56DayRuns() {
        var h = history(150)
        h.journal.approvals.removeValue(forKey: ActivityLoadRules.dayKey(h.rows[70].startDate, calendar: calendar))
        let days = build(h).days
        XCTAssertNil(days[70].daily); XCTAssertNil(days[97].smoothed); XCTAssertNotNil(days[98].smoothed)
        XCTAssertNil(days[125].lower); XCTAssertNotNil(days[126].lower)
    }
    func testAllConfirmedZeroDaysDoNotInventPersonalRange() {
        let h = history(70);var journal = h.journal
        for day in journal.approvals.keys { journal.approvals[day] = .init(fingerprint: ActivityLoadCalculator.fingerprint([], zone: journal.timeZoneID), kind: .noWorkout, confirmedAt: h.asOf) }
        let s = ActivityLoadCalculator.build(workouts: [], confirmations: [:], journal: journal, maximum: nil, asOf: h.asOf, historyDays: 70)
        XCTAssertEqual(s.days[27].smoothed, 0); XCTAssertNil(s.days[69].lower)
    }
    func testAbsentLedgerNeverCreatesRestOrZero() {
        let s = ActivityLoadCalculator.build(workouts: [], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: now, historyDays: 60)
        XCTAssertTrue(s.days.allSatisfy { $0.daily == nil && $0.smoothed == nil })
    }
    func testExactBoundariesRawPrecisionAndFutureAreDistinct() {
        XCTAssertEqual(ActivityLoadState.classify(20, lower: 20, upper: 20), .inside)
        XCTAssertEqual(ActivityLoadState.classify(20.0.nextUp, lower: 10, upper: 20), .above)
        XCTAssertEqual(ActivityLoadState.classify(10.0.nextDown, lower: 10, upper: 20), .below)
        XCTAssertEqual(ActivityLoadState.classify(20, lower: 10, upper: 30, forecast: true), .forecast)
        XCTAssertEqual(ActivityLoadState.classify(.nan, lower: 10, upper: 30), .unknown)
        XCTAssertEqual(ActivityLoadState.classify(20, lower: nil, upper: nil), .building)
        XCTAssertEqual(ActivityLoadRules.quantile([0,10,20,30], 0.1), 3, accuracy: 1e-12)
    }
    func testDuplicateReimportDoesNotDoubleCountAndConflictsAreWithheld() {
        let h = history(70)
        var duplicate = h; duplicate.rows.append(h.rows[20])
        let original = build(h), same = build(duplicate)
        let key = original.days.first { $0.smoothed != nil }!.key
        XCTAssertEqual(original.days.first{$0.key==key}?.daily,same.days.first{$0.key==key}?.daily)
        var conflict = h; conflict.rows.append(workout(id:h.rows[20].id,at:h.rows[20].startDate,seconds:2400))
        let s = build(conflict)
        XCTAssertTrue(s.conflictingIDs.contains(h.rows[20].id))
        XCTAssertNil(s.days.first { $0.key == ActivityLoadRules.dayKey(h.rows[20].startDate,calendar:calendar) }?.daily)
    }
    func testManualEditRecalculatesButDoesNotChangeCompletenessFingerprint() {
        var h = history(100); let before=build(h); let original=h.rows[80]
        h.ratings[original.id]=rating(original,value:9)
        let after=build(h), key=ActivityLoadRules.dayKey(original.startDate,calendar:calendar)
        XCTAssertEqual(before.days.first{$0.key==key}?.fingerprint,after.days.first{$0.key==key}?.fingerprint)
        XCTAssertNotEqual(before.days.first{$0.key==key}?.daily,after.days.first{$0.key==key}?.daily)
        XCTAssertNotEqual(before.days.first{$0.key==key}?.smoothed,after.days.first{$0.key==key}?.smoothed)
        XCTAssertEqual(before.days.first{$0.key==key}?.upper,after.days.first{$0.key==key}?.upper) // today excluded from range
    }
    func testLegacyMixedMethodsCannotBeAddedToOneDailyLoad() {
        var h = history(70);let w=workout(at:h.rows[69].startDate.addingTimeInterval(7200))
        h.rows.append(w);let key=ActivityLoadRules.dayKey(w.startDate,calendar:calendar)
        h.journal.approvals[key] = .init(fingerprint:ActivityLoadCalculator.fingerprint([h.rows[69],w],zone:h.journal.timeZoneID),kind:.recordsReviewed,confirmedAt:h.asOf)
        let s=legacyBuild(h);XCTAssertNil(s.days.first{$0.key==key}?.daily)
    }
    func testChangedMaxHRRecomputesAllAutoHistoryWithOneSettingsVersion() {
        let h=history(70)
        let a=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:h.journal,maximum:200,asOf:h.asOf,historyDays:70)
        let b=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:h.journal,maximum:220,asOf:h.asOf,historyDays:70)
        XCTAssertNotEqual(a.days[60].smoothed,b.days[60].smoothed)
        XCTAssertTrue(b.days.filter{$0.daily != nil}.allSatisfy{$0.methodKey?.contains("220")==true})
    }
    func testConditionalForecastUsesFiniteWindowAndIsNeverObservedState() {
        var h=history(70);h.ratings[h.rows[42].id]=rating(h.rows[42],value:10)
        let s=build(h);let forecast=s.days.filter(\.isForecast)
        XCTAssertEqual(forecast.count,3);XCTAssertTrue(forecast.allSatisfy{$0.state == .forecast})
        let last=s.days.last{!$0.isForecast}!
        XCTAssertLessThan(forecast[0].smoothed!,last.smoothed! * pow(2,-1.0/7.0)) // exiting tail term
        XCTAssertEqual(forecast[0].lower,last.lower)
    }
    func testDSTAndMidnightKeepActualDurationAndOneStartDay() {
        let ny=ActivityLoadRules.calendar("America/New_York")
        for raw in ["2026-03-08T06:30:00Z","2026-11-01T05:30:00Z","2026-01-02T04:45:00Z"] {
            let start=ISO8601DateFormatter().date(from:raw)!, w=workout(at:start,seconds:3600)
            let c=rating(w);let session=ActivityLoadSession.resolve(w,confirmation:c,maximum:200,at:w.endDate.addingTimeInterval(3600))
            XCTAssertEqual(session.amount,240)
            var journal=ActivityLoadJournal.empty(zone:ny.timeZone.identifier);let key=ActivityLoadRules.dayKey(start,calendar:ny)
            journal.approvals[key] = .init(fingerprint:ActivityLoadCalculator.fingerprint([w],zone:journal.timeZoneID),kind:.recordsReviewed,confirmedAt:w.endDate.addingTimeInterval(3600))
            let snapshot=ActivityLoadCalculator.build(workouts:[w],confirmations:[w.id:c],journal:journal,maximum:200,asOf:w.endDate.addingTimeInterval(172800),historyDays:5)
            XCTAssertEqual(snapshot.days.filter{!$0.isForecast}.flatMap(\.sessions).count,1)
            XCTAssertEqual(snapshot.days.first{$0.key==key}?.daily,240)
        }
    }
    func testScopedJournalAndConfirmationSurviveRestartAndClearRetainsHistory() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a=dir.appendingPathComponent("A"),b=dir.appendingPathComponent("B"),id=UUID()
        let store=FileWorkoutEffortStore(scopeDirectory:a)
        let legacy=WorkoutEffortConfirmation(value:6,confirmedAt:now,revision:UUID())
        try await store.save(legacy,workoutID:id)
        XCTAssertEqual(try FileWorkoutEffortStore(scopeDirectory:a).load(workoutID:id),legacy)
        XCTAssertNil(try FileWorkoutEffortStore(scopeDirectory:b).load(workoutID:id))
        try await store.clear(workoutID:id)
        XCTAssertNil(try FileWorkoutEffortStore(scopeDirectory:a).load(workoutID:id))
        XCTAssertTrue(FileManager.default.fileExists(atPath:a.appendingPathComponent("WorkoutEffort/History/\(id.uuidString)").path))
        let blocked=FileActivityLoadStore(scope:b,allowed:{false})
        XCTAssertThrowsError(try blocked.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath:b.path))
    }
    func testEditorRequiresOnlyAnActualStepAndUsesRecordedDurationThenReturnsToAuto() async {
        let w=workout(),store=FixtureWorkoutEffortStore();store.delay = .zero
        store.value = .init(value:8,confirmedAt:now,revision:UUID())
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load();editor.begin();XCTAssertFalse(editor.canSave)
        editor.preview(8);XCTAssertTrue(editor.canSave)
        let saved=await editor.save();XCTAssertTrue(saved)
        XCTAssertEqual(editor.confirmation?.value,8);XCTAssertEqual(editor.confirmation?.reviewedDurationSeconds,w.durationSeconds)
        XCTAssertEqual(editor.confirmation?.durationPolicy,ActivityLoadRules.durationPolicy);XCTAssertEqual(editor.confirmation?.inputControlVersion,ActivityLoadRules.manualInputVersion)
        let cleared=await editor.clearConfirmation();XCTAssertTrue(cleared);XCTAssertEqual(editor.displayedValue,7.5)
    }
    func testDeletionRevokesApprovalPermanentlyEvenAfterOldReimport() {
        let h = history(70), w = h.rows[30], key = ActivityLoadRules.dayKey(h.rows[30].startDate, calendar: calendar)
        let deleted = ActivityLoadCalculator.reconciledJournal(h.journal, workouts: h.rows.filter { $0.id != w.id })
        XCTAssertNil(deleted.approvals[key])
        let replay = ActivityLoadCalculator.reconciledJournal(deleted, workouts: h.rows)
        XCTAssertNil(replay.approvals[key])
        let after = ActivityLoadCalculator.build(workouts: h.rows, confirmations: h.ratings, journal: replay, maximum: 200, asOf: h.asOf, historyDays: 70)
        XCTAssertNil(after.days.first { $0.key == key }?.daily)
    }
    func testTimezoneChangeReattributesOnceAndRequiresNewApprovals() {
        let h = history(70)
        let other = ActivityLoadJournal.empty(zone: "America/Los_Angeles")
        let s = ActivityLoadCalculator.build(workouts: h.rows, confirmations: h.ratings, journal: other, maximum: 200, asOf: h.asOf, historyDays: 72)
        XCTAssertTrue(s.days.allSatisfy { $0.daily == nil })
        XCTAssertEqual(s.days.flatMap(\.sessions).count, 70)
    }

    func testActualR03DesignFixtureMatchesComputedValuesNotAnImage() {
        #if DEBUG && targetEnvironment(simulator)
        let snapshot = ActivityLoadQAFixture.make()
        let day = snapshot.days.last { !$0.isForecast }!
        XCTAssertEqual(day.smoothed!, 59.95100571281071, accuracy: 1e-9)
        XCTAssertEqual(day.lower!, 39.29180422591855, accuracy: 1e-9)
        XCTAssertEqual(day.upper!, 58.77581415726615, accuracy: 1e-9)
        XCTAssertEqual(day.state, .above)
        let future = snapshot.days.filter(\.isForecast)
        XCTAssertEqual(future[0].smoothed!, 54.299044570513324, accuracy: 1e-9)
        #endif
    }

    func testInvalidSourceDateCannotBeSilentlyTreatedAsRest() {
        let w = workout(at: Date(timeIntervalSince1970: .nan))
        let snapshot = ActivityLoadCalculator.build(workouts: [w], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: 200, asOf: now, historyDays: 10)
        XCTAssertEqual(snapshot.invalidDateCount, 1)
        XCTAssertTrue(snapshot.days.allSatisfy { $0.daily == nil })
    }

    func testModelPersistsProvenanceAndAccountSwapCannotPublishStaleResult() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var allowed = true
        let source = ActivityLoadTestStore(rows: [workout()])
        let model = ActivityLoadViewModel(directory: dir, allowed: { allowed }, now: { self.now })
        await model.reload(store: source, maximum: 200)
        let receiptURL = dir.appendingPathComponent("ActivityLoad/last-calculation-v1.json")
        let receipt = try JSONDecoder().decode(ActivityLoadCalculationReceipt.self, from: Data(contentsOf: receiptURL))
        XCTAssertEqual(receipt.sessions.first?.unit, ActivityLoadRules.referenceUnit)
        XCTAssertEqual(receipt.sessions.first?.inputUnit, ActivityLoadRules.intensityUnit)
        XCTAssertEqual(receipt.referencePolicy, ActivityLoadRules.referenceVersion)
        XCTAssertEqual(receipt.schemaVersion, 3)
        XCTAssertEqual(receipt.sessions.first?.source, "appleHealthKit")
        XCTAssertEqual(receipt.sessions.first?.methodVersion, ActivityLoadRules.automaticMethod + ":maxHR:200")
        source.delay = .milliseconds(70)
        let pending = Task { await model.reload(store: source, maximum: 220) }
        await Task.yield(); allowed = false; await pending.value
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.methodKey, ActivityLoadRules.automaticMethod + ":maxHR:200")
        XCTAssertEqual(source.fetches, 2)
    }
    func testLateOlderReadCannotReplaceLatestGenerationAndFailureKeepsContent() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = ActivityLoadTestStore(rows: [workout()])
        let model = ActivityLoadViewModel(directory: dir, now: { self.now })
        source.delay = .milliseconds(100)
        let older = Task { await model.reload(store: source, maximum: 200) }
        await Task.yield(); source.delay = .zero
        await model.reload(store: source, maximum: 220); await older.value
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.methodKey, ActivityLoadRules.automaticMethod + ":maxHR:220")
        source.fails = true; await model.reload(store: source, maximum: 200)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.methodKey, ActivityLoadRules.automaticMethod + ":maxHR:220")
    }
    func testCancelledReloadCannotReplaceSnapshotOrPersistPartialInputs() async throws {
        let h=history(80), dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local=FileActivityLoadStore(scope:dir); try local.save(h.journal)
        let source=ActivityLoadTestStore(rows:h.rows),model=ActivityLoadViewModel(directory:dir,now:{h.asOf})
        await model.reload(store:source,maximum:200);let before=model.snapshot!.days
        let receiptURL=dir.appendingPathComponent("ActivityLoad/last-calculation-v1.json")
        let receiptBefore=try Data(contentsOf:receiptURL)
        source.rows=[];source.delay = .milliseconds(100)
        let pending=Task { await model.reload(store:source,maximum:200) }
        await Task.yield();pending.cancel();await pending.value
        XCTAssertEqual(model.snapshot!.days,before)
        XCTAssertEqual(try Data(contentsOf:receiptURL),receiptBefore)
        XCTAssertFalse(model.isLoading);XCTAssertNil(model.error)
    }
    func testIncompleteImportRevokesOnlyAffectedDayAndCannotInventRestOrReviveStaleApproval() async throws {
        let h=history(100), dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local=FileActivityLoadStore(scope:dir); try local.save(h.journal)
        let source=ActivityLoadTestStore(rows:h.rows),model=ActivityLoadViewModel(directory:dir,now:{h.asOf})
        await model.reload(store:source,maximum:200)
        let w=h.rows[80], key=ActivityLoadRules.dayKey(w.startDate,calendar:calendar)
        let preceding=model.snapshot!.days.filter{$0.key < key}
        source.rows.removeAll{$0.id==w.id};await model.reload(store:source,maximum:200)
        XCTAssertEqual(model.snapshot!.days.filter{$0.key < key},preceding)
        XCTAssertNil(model.snapshot!.days.first{$0.key==key}?.daily)
        XCTAssertNil(try local.load().approvals[key])
        source.rows=h.rows;await model.reload(store:source,maximum:200)
        XCTAssertNil(model.snapshot!.days.first{$0.key==key}?.daily,"Returning old rows must not revive invalidated completeness")
        model.approve(model.snapshot!.days.first{$0.key==key}!)
        XCTAssertEqual(model.snapshot!.days.first{$0.key==key}?.daily,225)
    }
    func testTwoAccountScopesWithSameWorkoutIDNeverShareOverrideOrReceipt() async throws {
        let h=history(80), root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a=root.appendingPathComponent("account-A"),b=root.appendingPathComponent("account-B")
        try FileActivityLoadStore(scope:a).save(h.journal);try FileActivityLoadStore(scope:b).save(h.journal)
        let w=h.rows[60];try await FileWorkoutEffortStore(scopeDirectory:a).save(rating(w,value:9),workoutID:w.id)
        let ma=ActivityLoadViewModel(directory:a,now:{h.asOf}),mb=ActivityLoadViewModel(directory:b,now:{h.asOf})
        await ma.reload(store:ActivityLoadTestStore(rows:h.rows),maximum:200)
        await mb.reload(store:ActivityLoadTestStore(rows:h.rows),maximum:200)
        XCTAssertEqual(ma.snapshot!.days.flatMap(\.sessions).first{$0.id==w.id}?.amount,270)
        XCTAssertEqual(mb.snapshot!.days.flatMap(\.sessions).first{$0.id==w.id}?.amount,225)
        let read:(URL)throws->ActivityLoadCalculationReceipt = { try JSONDecoder().decode(ActivityLoadCalculationReceipt.self,from:Data(contentsOf:$0.appendingPathComponent("ActivityLoad/last-calculation-v1.json"))) }
        XCTAssertEqual(try read(a).sessions.first{$0.workoutID==w.id}?.origin,"user")
        XCTAssertEqual(try read(b).sessions.first{$0.workoutID==w.id}?.origin,"estimated")
        XCTAssertNil(try FileWorkoutEffortStore(scopeDirectory:b).load(workoutID:w.id))
    }

    func testEffortReferencePersistsWhenExpandedAndNeverInventsRange() {
        // New explicit requirement: a real range is not conditional on keeping a
        // finger down. This changes presentation policy, not range eligibility.
        var state=EffortScaleInteraction()
        XCTAssertFalse(state.isExpanded);XCTAssertFalse(state.showsHatching(hasRange:true))
        state.press();XCTAssertTrue(state.isExpanded);XCTAssertTrue(state.showsHatching(hasRange:true))
        XCTAssertFalse(state.showsHatching(hasRange:false))
        state.drag();XCTAssertTrue(state.isDragging);XCTAssertTrue(state.showsHatching(hasRange:true))
        state.end();XCTAssertFalse(state.isDragging);XCTAssertTrue(state.showsHatching(hasRange:true))
        XCTAssertFalse(state.showsHatching(hasRange:false))
        state.drag();state.collapse();XCTAssertFalse(state.isExpanded);XCTAssertFalse(state.isDragging)
        state.end();XCTAssertFalse(state.showsHatching(hasRange:true))
    }

    func testUnifiedOverrideRecalculatesDailyCurveRangeAndColorThenLatestAutoRestores() {
        var h=history(170);h.ratings=[:];let original=h.rows[80],key=ActivityLoadRules.dayKey(original.startDate,calendar:calendar)
        let before=build(h)
        h.ratings[original.id]=rating(original,value:9)
        let edited=build(h),day=edited.days.first{$0.key==key}!
        XCTAssertEqual(day.daily,270);XCTAssertNotNil(day.lower);XCTAssertNotNil(day.upper);XCTAssertEqual(day.state,.above)
        XCTAssertEqual(edited.days.map{$0.smoothed != nil},before.days.map{$0.smoothed != nil})
        for d in before.days.filter({$0.key<key}) {XCTAssertEqual(edited.days.first{$0.key==d.key},d)}
        XCTAssertNotEqual(edited.days[95].upper,before.days[95].upper,"The same contract recomputes affected personal ranges")
        for _ in 0..<3 {
            h.ratings=[:];let restored=build(h)
            XCTAssertEqual(restored.days.map(\.daily),before.days.map(\.daily));XCTAssertEqual(restored.days.map(\.smoothed),before.days.map(\.smoothed))
            XCTAssertEqual(restored.days.map(\.upper),before.days.map(\.upper))
            h.ratings[original.id]=rating(original,value:9);XCTAssertEqual(build(h).days[80].daily,270)
        }
        let changed=workout(id:original.id,at:original.startDate,seconds:original.durationSeconds,hr:170,updated:h.asOf.addingTimeInterval(-1))
        h.rows[80]=changed
        let journal=ActivityLoadCalculator.reconciledJournal(h.journal,workouts:h.rows)
        XCTAssertNotNil(journal.approvals[key],"Measurement-only hydration does not revoke known membership/time")
        h.journal=journal;XCTAssertEqual(build(h).days[80].daily,270,"Automatic changes never overwrite a valid override")
        h.ratings=[:];let latest=build(h).days[80]
        XCTAssertEqual(latest.daily,255);XCTAssertEqual(latest.sessions.first?.intensity,8.5)
        XCTAssertEqual(latest.sessions.first?.automaticValue,8.5)
    }
    func testTodayOverrideUpdatesProvisionalTotalAndGraphWithoutClosingOrChangingPriorDays() {
        var h=history(100);h.ratings=[:]
        let w=workout(at:h.asOf.addingTimeInterval(6*3600));h.rows.append(w);h.asOf=h.asOf.addingTimeInterval(20*3600)
        let before=build(h),key=ActivityLoadRules.dayKey(w.startDate,calendar:calendar)
        h.ratings[w.id]=rating(w,value:8)
        let after=build(h),day=after.days.first{$0.key==key}!
        XCTAssertNil(day.daily);XCTAssertEqual(day.recordedSubtotal,240);XCTAssertTrue(day.isProvisional)
        XCTAssertNotNil(day.smoothed);XCTAssertNotEqual(day.smoothed,before.days.first{$0.key==key}?.smoothed)
        XCTAssertNotNil(day.upper);XCTAssertEqual(day.state,.above)
        for old in before.days.filter({$0.key<key}).suffix(55){XCTAssertEqual(after.days.first{$0.key==old.key},old)}
    }
    func testOldZeroAndLegacyValuesArePreservedNotSilentlyOverriddenOrRescaled() async throws {
        let w=workout(),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=FileWorkoutEffortStore(scopeDirectory:dir)
        var old=rating(w,value:0);old.scaleVersion=ActivityLoadRules.legacySessionScale;old.unit="sessionRPE_0_10"
        try await store.save(old,workoutID:w.id);XCTAssertEqual(try store.load(workoutID:w.id),old)
        let session=ActivityLoadSession.resolve(w,confirmation:old,maximum:200,at:now)
        XCTAssertEqual(session.intensity,7.5);XCTAssertTrue(session.sourceLabel.contains("이전 기준"))
        XCTAssertEqual(try store.load(workoutID:w.id)?.value,0,"Automatic fallback never rewrites prior input")
        let missing=workout(id:w.id,hr:nil)
        XCTAssertNil(ActivityLoadSession.resolve(missing,confirmation:old,maximum:nil,at:now).intensity)
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load();XCTAssertEqual(editor.displayedValue,7.5);editor.begin();editor.cancel()
        XCTAssertEqual(try store.load(workoutID:w.id),old)
    }
    func testCompletenessFingerprintUpgradeIsExactAndIdempotent() {
        let h=history(70);var legacy=h.journal;legacy.completenessVersion=nil
        for key in legacy.approvals.keys {
            let rows=h.rows.filter{ActivityLoadRules.dayKey($0.startDate,calendar:calendar)==key};let a=legacy.approvals[key]!
            legacy.approvals[key] = .init(fingerprint:ActivityLoadCalculator.legacyFingerprint(rows,zone:legacy.timeZoneID),kind:a.kind,confirmedAt:a.confirmedAt)
        }
        let once=ActivityLoadCalculator.reconciledJournal(legacy,workouts:h.rows)
        XCTAssertEqual(once.approvals.count,h.journal.approvals.count);XCTAssertEqual(once.completenessVersion,ActivityLoadRules.completenessVersion)
        XCTAssertEqual(ActivityLoadCalculator.reconciledJournal(once,workouts:h.rows),once)
        let removed=ActivityLoadCalculator.reconciledJournal(legacy,workouts:Array(h.rows.dropFirst()))
        XCTAssertNil(removed.approvals[ActivityLoadRules.dayKey(h.rows[0].startDate,calendar:calendar)])
    }
    func testEditorAndCalculationBothRequireReconfirmationAfterOriginalTimeChanges() async {
        let end=Date().addingTimeInterval(-3600),start=end.addingTimeInterval(-1800)
        let workout=workout(at:start,seconds:1800)
        let store=FixtureWorkoutEffortStore()
        var c=rating(workout,value:9);c.workoutEnd=end.addingTimeInterval(-60);store.value=c
        let editor=WorkoutEffortEditor(workoutID:workout.id,store:store,sessionContext:.init(workout),automaticEstimate:ActivityLoadEstimate.heartRate(workout,maxHeartRate:200,at:Date()))
        await editor.load();XCTAssertEqual(editor.displayedValue,7.5);XCTAssertEqual(editor.displayedLabel,"자동 추정")
        XCTAssertTrue(editor.sourceLabel.contains("재확인"));XCTAssertEqual(ActivityLoadSession.resolve(workout,confirmation:c,maximum:200,at:Date()).amount,225)
        editor.begin();XCTAssertEqual(editor.draft,7.5);XCTAssertNil(editor.selectedValue);XCTAssertFalse(editor.canSave)
        editor.cancel();XCTAssertEqual(store.value,c)
    }

    func testReceiptKeepsOneInputUnitAndHashesChangedAutomaticEvidenceEvenUnderOverride() async throws {
        let h=history(80),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileActivityLoadStore(scope:dir).save(h.journal)
        let w=h.rows[60];try await FileWorkoutEffortStore(scopeDirectory:dir).save(rating(w,value:9),workoutID:w.id)
        let store=ActivityLoadTestStore(rows:h.rows),model=ActivityLoadViewModel(directory:dir,now:{h.asOf})
        func read() throws -> ActivityLoadCalculationReceipt {try JSONDecoder().decode(ActivityLoadCalculationReceipt.self,from:Data(contentsOf:dir.appendingPathComponent("ActivityLoad/last-calculation-v1.json")))}
        await model.reload(store:store,maximum:200);let first=try read()
        XCTAssertEqual(Set(first.sessions.map(\.inputUnit)),[ActivityLoadRules.intensityUnit])
        XCTAssertEqual(first.sessions.first{$0.workoutID==w.id}?.automaticIntensity,7.5)
        store.rows[60]=workout(id:w.id,at:w.startDate,seconds:w.durationSeconds,hr:170,updated:w.updatedAt)
        await model.reload(store:store,maximum:200);let second=try read()
        XCTAssertNotEqual(first.inputSnapshotID,second.inputSnapshotID)
        XCTAssertEqual(second.sessions.first{$0.workoutID==w.id}?.intensity,9)
        XCTAssertEqual(second.sessions.first{$0.workoutID==w.id}?.automaticIntensity,8.5)
        XCTAssertEqual(model.snapshot!.days.flatMap(\.sessions).first{$0.id==w.id}?.amount,270)
    }

    func testOpeningAndCancelPreserveAutomaticSevenPointFiveWithoutDisplayingOrSavingARoundedStep() async {
        let w=workout(),store=FixtureWorkoutEffortStore();store.delay = .zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load();XCTAssertEqual(editor.displayedValue,7.5);XCTAssertEqual(editor.displayedLabel,"자동 추정")
        for _ in 0..<3 {
            editor.begin();XCTAssertEqual(editor.draft,7.5);XCTAssertNil(editor.selectedValue)
            XCTAssertEqual(editor.draftScoreLabel,"선택 전");XCTAssertFalse(editor.scoreAccessibilityValue.contains("7.5"));XCTAssertFalse(editor.canSave)
            let ignored=await editor.save();XCTAssertFalse(ignored);editor.cancel()
        }
        XCTAssertEqual(store.saveCount,0);XCTAssertNil(store.value);XCTAssertEqual(editor.displayedValue,7.5)
    }
    func testEveryManualStepOneThroughTenSavesImmediatelyWithOnlyRecordedTime() async {
        let w=workout(),store=FixtureWorkoutEffortStore();store.delay = .zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load()
        for step in 1...10 {
            editor.begin();XCTAssertFalse(editor.canSave);editor.preview(Double(step));XCTAssertEqual(editor.selectedValue,step);XCTAssertTrue(editor.canSave)
            let saved=await editor.save();XCTAssertTrue(saved);XCTAssertEqual(store.value?.value,step)
            XCTAssertEqual(store.value?.reviewedDurationSeconds,1800);XCTAssertEqual(store.value?.inputControlVersion,ActivityLoadRules.manualInputVersion)
            XCTAssertEqual(ActivityLoadSession.resolve(w,confirmation:store.value,maximum:200,at:Date()).amount,Double(step)*30)
        }
        let cleared=await editor.clearConfirmation();XCTAssertTrue(cleared);XCTAssertEqual(editor.displayedValue,7.5)
    }
    func testStepAdjustmentCancelAndLatestAutomaticValueNeverBecomeAnImplicitOverride() async {
        let w=workout(),store=FixtureWorkoutEffortStore();store.delay = .zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load();editor.begin();editor.adjustScore(1);XCTAssertEqual(editor.selectedValue,8);editor.cancel()
        editor.begin();XCTAssertNil(editor.selectedValue);XCTAssertEqual(editor.draft,7.5);editor.adjustScore(-1);XCTAssertEqual(editor.selectedValue,7);editor.cancel()
        let changed=workout(id:w.id,hr:170),latest=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(changed),automaticEstimate:ActivityLoadEstimate.heartRate(changed,maxHeartRate:200,at:now))
        await latest.load();latest.begin();XCTAssertEqual(latest.draft,8.5);XCTAssertNil(latest.selectedValue);XCTAssertFalse(latest.canSave)
        latest.preview(9);let saved=await latest.save();XCTAssertTrue(saved);let cleared=await latest.clearConfirmation();XCTAssertTrue(cleared);XCTAssertEqual(latest.displayedValue,8.5)
    }
    func testHistoricZeroIsPreservedAndNeverTurnedIntoOneByOpeningOrCancel() async {
        let w=workout(hr:nil),store=FixtureWorkoutEffortStore();store.delay = .zero
        let zero=rating(w,value:0);store.value=zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w))
        await editor.load();XCTAssertEqual(editor.displayedValue,0);XCTAssertTrue(editor.displayedLabel.contains("0점"))
        editor.begin();XCTAssertEqual(editor.draft,0);XCTAssertNil(editor.selectedValue);XCTAssertFalse(editor.canSave);XCTAssertTrue(editor.draftScoreLabel.contains("보존"))
        let ignored=await editor.save();XCTAssertFalse(ignored);editor.cancel();XCTAssertEqual(store.value,zero)
        XCTAssertEqual(ActivityLoadSession.resolve(w,confirmation:zero,maximum:nil,at:now).amount,0)
        editor.begin();editor.preview(1);let saved=await editor.save();XCTAssertTrue(saved);XCTAssertEqual(store.value?.value,1,"Only an explicit new selection may replace the old zero")
        let cleared=await editor.clearConfirmation();XCTAssertTrue(cleared);XCTAssertNil(editor.displayedValue)
    }
    func testMissingInputIsNotZeroAndNewZeroStampIsRejected() async {
        let w=workout(hr:nil),store=FixtureWorkoutEffortStore();store.delay = .zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w))
        await editor.load();editor.begin();XCTAssertNil(editor.draft);XCTAssertNil(editor.selectedValue);XCTAssertFalse(editor.canSave)
        let ignored=await editor.save();XCTAssertFalse(ignored);XCTAssertNil(store.value)
        var invalid=rating(w,value:0);invalid.inputControlVersion=ActivityLoadRules.manualInputVersion;invalid.durationPolicy=ActivityLoadRules.durationPolicy
        XCTAssertNil(ActivityLoadSession.resolve(w,confirmation:invalid,maximum:nil,at:now).amount)
        editor.preview(1);let saved=await editor.save();XCTAssertTrue(saved);XCTAssertEqual(store.value?.value,1)
    }
    func testLegacyInputNeedsActualNewStepAndArchivesOriginalWithoutExtraQuestions() async throws {
        let w=workout(),directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),old=WorkoutEffortConfirmation(value:4,confirmedAt:now,revision:UUID())
        let store=FileWorkoutEffortStore(scopeDirectory:directory);try await store.save(old,workoutID:w.id)
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now))
        await editor.load();editor.begin();XCTAssertNil(editor.selectedValue);XCTAssertFalse(editor.canSave)
        let ignored=await editor.save();XCTAssertFalse(ignored);editor.cancel();XCTAssertEqual(try store.load(workoutID:w.id),old)
        editor.begin();editor.preview(6);let saved=await editor.save();XCTAssertTrue(saved);XCTAssertEqual(try store.load(workoutID:w.id)?.value,6)
        XCTAssertEqual(try store.load(workoutID:w.id)?.reviewedDurationSeconds,w.durationSeconds)
        let history=directory.appendingPathComponent("WorkoutEffort/History/"+w.id.uuidString)
        let preserved=try FileManager.default.contentsOfDirectory(at:history,includingPropertiesForKeys:nil).map {try JSONDecoder().decode(WorkoutEffortConfirmation.self,from:Data(contentsOf:$0))};XCTAssertTrue(preserved.contains(old))
    }
    func testMissingRecordedTimeKeepsSelectedStepButCannotInventLoadOrAskForTime() async {
        let w=workout(seconds:0,hr:nil),store=FixtureWorkoutEffortStore();store.delay = .zero
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w))
        await editor.load();editor.begin();editor.preview(9);XCTAssertTrue(editor.canSave)
        let saved=await editor.save();XCTAssertTrue(saved);XCTAssertNil(store.value?.reviewedDurationSeconds)
        let session=ActivityLoadSession.resolve(w,confirmation:store.value,maximum:nil,at:Date())
        XCTAssertEqual(session.intensity,9);XCTAssertNil(session.amount);XCTAssertTrue(session.reason?.contains("기록된 운동 시간") == true)
    }
    func testNumericStepAnchorsAndNamedRangesDoNotClaimPhysiologicalMeasurements() {
        for n in 1...10 {let label=WorkoutEffortStyle.title(n)+WorkoutEffortStyle.description(n);for old in ["힘들었어요","호흡이","대화할","온 힘을"]{XCTAssertFalse(label.contains(old))}}
        XCTAssertTrue(WorkoutEffortStyle.title(0).contains("보존"));XCTAssertTrue(WorkoutEffortStyle.description(10).contains("측정값은 아니"))
        let range=WorkoutEffortUsualRange(lower:4,upper:6,count:7);XCTAssertEqual(range.relation(to:7,label:"내 입력 점수 범위"),"내 입력 점수 범위 이상")
    }

    func testJournalTimeZoneChoiceAndConfirmationSurviveProcessRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = FileActivityLoadStore(scope: dir)
        var journal = try local.load(defaultZone: "Asia/Seoul")
        journal.approvals["2026-01-01"] = .init(fingerprint: "synthetic", kind: .noWorkout, confirmedAt: now)
        try local.save(journal)
        XCTAssertEqual(try FileActivityLoadStore(scope: dir).load(defaultZone: "America/New_York"), journal)
    }

}

@MainActor
private final class ActivityLoadTestStore: UnifiedWorkoutStore {
    var rows: [UnifiedWorkout]
    var delay: Duration = .zero
    var fails = false
    var fetches = 0
    var requestedDays: [Int] = []
    var filterRelativeTo: Date?
    init(rows: [UnifiedWorkout]) { self.rows = rows }
    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        fetches += 1; requestedDays.append(days)
        let snapshot = filterRelativeTo.map { reference in rows.filter { $0.startDate >= reference.addingTimeInterval(-Double(days) * 86400) } } ?? rows, delay = delay
        if delay != .zero { try await Task.sleep(for: delay) }
        if fails { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }
    func saveWorkout(_ workout: UnifiedWorkout) async throws { rows.append(workout) }
    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws { rows += workouts }
    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { rows.first { $0.id == id } }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { rows.first { $0.externalId == externalId && $0.source == source } }
    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {}
    func updateCompanions(id: UUID, names: [String]) async throws {}
    func deleteWorkout(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func deleteAllWorkouts() async throws { rows = [] }
}


// Frozen R1 calculation contract; test-only, not app code.
import Foundation
import CryptoKit
import SwiftData

/// Local descriptive units. A heart-rate proxy is not a measured subjective RPE.
/// Never feeds the legacy duration-dependent RelativeEffort back into this model.
enum LegacyR1ActivityLoadRules {
    static let aggregateVersion = "finite28_hl7_q10q90_past56_v1"
    static let scaleVersion = "soom_session_global_0_10_kr_v1"
    static let manualMethod = "soom_srpe_reviewed_duration_v1"
    static let automaticMethod = "soom_mean_hr_proxy_v1"
    static let durationPolicy = "user_reviewed_session_seconds_v1"
    static let changed = Notification.Name("SOOM.LegacyR1ActivityLoad.localInputsChanged")
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
    }
    static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        let position = Double(sorted.count - 1) * fraction
        let i = Int(position), next = min(i + 1, sorted.count - 1)
        return sorted[i] + (sorted[next] - sorted[i]) * (position - Double(i))
    }
}

struct LegacyR1ActivityLoadEstimate: Equatable {
    let value: Double
    let method: String
    let settingsVersion: String
    let source: String
    let confidence: String
    let computedAt: Date
    var methodKey: String { method + ":" + settingsVersion }
    static func heartRate(_ workout: UnifiedWorkout, maxHeartRate: Int?, at: Date) -> Self? {
        guard let maximum = maxHeartRate, (80...240).contains(maximum),
              let mean = workout.averageHeartRate, mean.isFinite, (30...250).contains(mean),
              mean <= Double(maximum), workout.endDate <= at, workout.endDate > workout.startDate else { return nil }
        // A versioned product proxy, not calibrated RPE or physiological risk.
        // Duration is intentionally absent. Coverage of a mean is not known.
        return Self(value: min(10, max(0, (mean / Double(maximum) - 0.5) * 20)),
                    method: LegacyR1ActivityLoadRules.automaticMethod, settingsVersion: "maxHR:\(maximum)",
                    source: workout.source.rawValue, confidence: "낮음 · 평균심박 기반",
                    computedAt: at)
    }
}

struct LegacyR1ActivityLoadSession: Identifiable, Equatable {
    let workout: UnifiedWorkout
    let intensity: Double?
    let durationSeconds: Double?
    let methodKey: String?
    let sourceLabel: String
    let reason: String?
    let revision: UUID?
    let confirmedAt: Date?
    var id: UUID { workout.id }
    var amount: Double? {
        guard let intensity, let durationSeconds else { return nil }
        let result = intensity * durationSeconds / 60
        return result.isFinite && result >= 0 ? result : nil
    }
    static func resolve(_ workout: UnifiedWorkout, confirmation: WorkoutEffortConfirmation?,
                        maximum: Int?, at: Date) -> Self {
        func result(_ value: Double?, _ duration: Double?, _ method: String?, _ source: String, _ reason: String?) -> Self {
            Self(workout: workout, intensity: value, durationSeconds: duration, methodKey: method,
                 sourceLabel: source, reason: reason, revision: confirmation?.revision, confirmedAt: confirmation?.confirmedAt)
        }
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard !workout.isExcludedFromAnalysis, workout.endDate <= at, workout.updatedAt <= at, elapsed.isFinite, elapsed > 0 else {
            return result(nil, nil, nil, "미확인", "운동 시간 또는 완료 상태 확인 필요")
        }
        if let c = confirmation {
            guard c.scaleVersion == LegacyR1ActivityLoadRules.scaleVersion else {
                return result(nil, nil, nil, "이전 1–10 기록", "새 전체 세션 기준으로 다시 확인해 주세요")
            }
            guard (0...10).contains(c.value), c.confirmedAt <= at, c.confirmedAt >= workout.endDate,
                  c.workoutStart == workout.startDate, c.workoutEnd == workout.endDate,
                  c.durationPolicy == LegacyR1ActivityLoadRules.durationPolicy, c.unit == "sessionRPE_0_10", c.origin == "user",
                  let duration = c.reviewedDurationSeconds, duration.isFinite, duration > 0, duration <= elapsed + 1 else {
                return result(nil, nil, nil, "직접 확인", "시간·원본 변경 또는 입력 시각 재확인 필요")
            }
            return result(Double(c.value), duration, LegacyR1ActivityLoadRules.manualMethod + ":srpe_v1", "직접 확인 · 체감 AU", nil)
        }
        guard workout.durationSeconds.isFinite, workout.durationSeconds > 0, workout.durationSeconds <= elapsed + 1,
              let estimate = LegacyR1ActivityLoadEstimate.heartRate(workout, maxHeartRate: maximum, at: at) else {
            return result(nil, nil, nil, "추정 불가", "개인 최대심박·평균심박이 필요해요")
        }
        return result(estimate.value, workout.durationSeconds, estimate.methodKey, "자동 추정 · HR-proxy AU · 낮은 신뢰", nil)
    }
}

struct LegacyR1ActivityLoadDayApproval: Codable, Equatable {
    enum Kind: String, Codable { case recordsReviewed, noWorkout, excludedOnly }
    let fingerprint: String
    let kind: Kind
    let confirmedAt: Date
}
struct LegacyR1ActivityLoadJournal: Codable, Equatable {
    let schemaVersion: Int
    var timeZoneID: String
    var timeZoneRevision: UUID
    var approvals: [String: LegacyR1ActivityLoadDayApproval]
    static func empty(zone: String) -> Self {
        Self(schemaVersion: 1, timeZoneID: zone, timeZoneRevision: UUID(), approvals: [:])
    }
}
enum LegacyR1ActivityLoadState: String, Equatable {
    case below, inside, above, building, unknown, forecast
    var label: String {
        switch self {
        case .below: "↓  범위보다 낮음"
        case .inside: "•  범위 안"
        case .above: "↑  범위보다 높음"
        case .building: "…  기준 쌓는 중"
        case .unknown: "—  미확인"
        case .forecast: "○  예상 · 운동 없음"
        }
    }
    static func classify(_ value: Double?, lower: Double?, upper: Double?, forecast: Bool = false) -> Self {
        if forecast { return .forecast }
        guard let value, value.isFinite, value >= 0 else { return .unknown }
        guard let lower, let upper, lower.isFinite, upper.isFinite, lower <= upper else { return .building }
        return value < lower ? .below : value > upper ? .above : .inside
    }
}
struct LegacyR1ActivityLoadDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let key: String
    let fingerprint: String
    let sessions: [LegacyR1ActivityLoadSession]
    let rawCount: Int
    var daily: Double?
    var smoothed: Double?
    var lower: Double?
    var upper: Double?
    var methodKey: String?
    var reason: String?
    var segment: Int = 0
    var bandGroup: Int = 0
    var isForecast = false
    var workoutPresent: Bool { !sessions.isEmpty }
    var state: LegacyR1ActivityLoadState {
        if isForecast { return .forecast }
        if daily != nil && smoothed == nil { return .building }
        return LegacyR1ActivityLoadState.classify(smoothed, lower: lower, upper: upper)
    }
}
struct LegacyR1ActivityLoadSnapshot {
    let days: [LegacyR1ActivityLoadDay]
    let timeZoneID: String
    let asOf: Date
    let recent: [UnifiedWorkout]
    let legacyCount: Int
    let conflictingIDs: Set<UUID>
    var invalidDateCount = 0
}

enum LegacyR1ActivityLoadCalculator {
    /// Fingerprint covers the current canonical/source snapshot, not annotations:
    /// rating edits recalculate immediately; import/delete/duration changes revoke completeness.
    static func canonical(_ rows: [UnifiedWorkout]) -> [UnifiedWorkout] {
        // Reuse canonical identity/representative choice, never fuse other providers' measurements.
        UnifiedWorkoutDeduplicationEngine().canonicalGroups(rows).map { group in
            group.sourceWorkouts.first(where: { $0.id == group.workout.id }) ?? group.workout
        }
    }
    static func reconciledJournal(_ journal: LegacyR1ActivityLoadJournal, workouts: [UnifiedWorkout]) -> LegacyR1ActivityLoadJournal {
        var result = journal
        let calendar = LegacyR1ActivityLoadRules.calendar(journal.timeZoneID)
        let byDay = Dictionary(grouping: canonical(workouts.filter { $0.startDate.timeIntervalSince1970.isFinite })) { LegacyR1ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        for (key, approval) in journal.approvals {
            if approval.fingerprint != fingerprint(byDay[key] ?? [], zone: journal.timeZoneID) {
                result.approvals.removeValue(forKey: key)
            }
        }
        return result
    }
    static func fingerprint(_ rows: [UnifiedWorkout], zone: String) -> String {
        let items = rows.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.source.rawValue)|\($0.externalId ?? "")|\($0.startDate.timeIntervalSince1970)|\($0.endDate.timeIntervalSince1970)|\($0.durationSeconds)|\($0.updatedAt.timeIntervalSince1970)|\($0.isExcludedFromAnalysis)"
        }
        return LegacyR1ActivityLoadRules.hash(zone + "|" + items.joined(separator: ";"))
    }

    static func build(workouts: [UnifiedWorkout], confirmations: [UUID: WorkoutEffortConfirmation],
                      journal: LegacyR1ActivityLoadJournal, maximum: Int?, asOf: Date, historyDays: Int = 180) -> LegacyR1ActivityLoadSnapshot {
        let calendar = LegacyR1ActivityLoadRules.calendar(journal.timeZoneID)
        let today = calendar.startOfDay(for: asOf)
        let start = calendar.date(byAdding: .day, value: -historyDays, to: today)!
        // Identical reimports count once. Equal-UUID conflicting payloads are not arbitrarily selected.
        var unique: [UUID: UnifiedWorkout] = [:], conflicts = Set<UUID>()
        let invalidDateCount = workouts.filter { !$0.startDate.timeIntervalSince1970.isFinite }.count
        for w in workouts where w.startDate.timeIntervalSince1970.isFinite {
            if let old = unique[w.id], old != w { conflicts.insert(w.id) } else { unique[w.id] = w }
        }
        let canonical = canonical(Array(unique.values))
        let byDay = Dictionary(grouping: canonical) { LegacyR1ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        var days: [LegacyR1ActivityLoadDay] = []
        for offset in 0...historyDays {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = LegacyR1ActivityLoadRules.dayKey(date, calendar: calendar)
            let raw = byDay[key] ?? []
            let included = raw.filter { !$0.isExcludedFromAnalysis }
            let sessions = included.map { LegacyR1ActivityLoadSession.resolve($0, confirmation: confirmations[$0.id], maximum: maximum, at: asOf) }
            let fingerprint = fingerprint(raw, zone: journal.timeZoneID)
            let approval = journal.approvals[key]
            let methods = Set(sessions.compactMap(\.methodKey))
            let amounts = sessions.compactMap(\.amount)
            var daily: Double?, reason: String?
            if invalidDateCount > 0 { reason = "날짜가 올바르지 않은 원본 기록을 확인해 주세요" }
            else if date == today { reason = "오늘은 아직 마감되지 않았어요" }
            else if raw.contains(where: { conflicts.contains($0.id) }) { reason = "같은 UUID의 원본 내용이 충돌해요" }
            else if approval?.fingerprint != fingerprint || approval!.confirmedAt > asOf { reason = "이 날짜의 기록·누락 상태 확인 필요" }
            else if sessions.isEmpty {
                if approval!.kind == .noWorkout && raw.isEmpty || approval!.kind == .excludedOnly && !raw.isEmpty {
                    daily = 0
                } else { reason = "운동 없음과 분석 제외를 구분해 확인해 주세요" }
            } else if approval!.kind != .recordsReviewed { reason = "가져온 운동 목록이 바뀌었어요" }
            else if amounts.count != sessions.count { reason = sessions.first(where: { $0.reason != nil })?.reason ?? "강도 또는 시간 미확인" }
            else if methods.count != 1 { reason = "체감과 자동 추정 방법은 합산하지 않아요" }
            else {
                let sum = amounts.reduce(0, +)
                if sum.isFinite { daily = sum } else { reason = "계산 가능한 범위를 벗어났어요" }
            }
            days.append(LegacyR1ActivityLoadDay(date: date, key: key, fingerprint: fingerprint, sessions: sessions, rawCount: raw.count,
                                         daily: daily, methodKey: methods.count == 1 ? methods.first : nil, reason: reason))
        }
        var segment = 0, key: String?, run: [Int] = [], bandGroup = 0, previousBand = false
        let lambda = pow(2.0, -1.0 / 7.0)
        let weights = (0..<28).map { pow(lambda, Double($0)) }, denominator = (0..<28).reduce(0.0) { $0 + pow(lambda, Double($1)) }
        for i in days.indices {
            guard let _ = days[i].daily else {
                segment += 1; key = nil; run = []; previousBand = false; continue
            }
            let nextKey = days[i].methodKey ?? key ?? LegacyR1ActivityLoadRules.manualMethod + ":srpe_v1"
            if key != nil && key != nextKey { segment += 1; run = []; previousBand = false }
            key = nextKey; days[i].methodKey = nextKey; days[i].segment = segment; run.append(i)
            guard run.count >= 28 else { continue }
            days[i].smoothed = zip(run.suffix(28).reversed(), weights).reduce(0) { $0 + days[$1.0].daily! * $1.1 } / denominator
            let prior = run.dropLast().suffix(56)
            let priorF = prior.compactMap { days[$0].smoothed }.sorted()
            let positiveSessions = prior.flatMap { days[$0].sessions }.filter { ($0.amount ?? 0) > 0 }.count
            let activeDays = prior.filter { days[$0].sessions.contains { ($0.amount ?? 0) > 0 } }.count
            if priorF.count >= 28 && positiveSessions >= 8 && activeDays >= 4 {
                days[i].lower = LegacyR1ActivityLoadRules.quantile(priorF, 0.1)
                days[i].upper = LegacyR1ActivityLoadRules.quantile(priorF, 0.9)
                if !previousBand { bandGroup += 1 }
                days[i].bandGroup = bandGroup; previousBand = true
            } else { previousBand = false }
        }
        // Forecast is a conditional finite-window calculation, never a rest observation.
        // Only a complete last closed day with an uninterrupted 28-day window can seed it.
        if let last = days.dropLast().last, last.smoothed != nil, last.daily != nil,
           !days.last!.workoutPresent {
            let closed = Array(days.dropLast())
            var window = Array(closed.suffix(28))
            if window.count == 28 && window.allSatisfy({ $0.daily != nil && $0.methodKey == last.methodKey }) {
                for step in 1...3 {
                    let date = calendar.date(byAdding: .day, value: step, to: last.date)!
                    var next = LegacyR1ActivityLoadDay(date: date, key: LegacyR1ActivityLoadRules.dayKey(date, calendar: calendar),
                        fingerprint: "", sessions: [], rawCount: 0, daily: 0, methodKey: last.methodKey, reason: "추가 운동이 없을 때의 조건 계산",
                        segment: last.segment, bandGroup: last.bandGroup, isForecast: true)
                    window.removeFirst(); window.append(next)
                    next.smoothed = zip(window.reversed(), weights).reduce(0) { $0 + $1.0.daily! * $1.1 } / denominator
                    next.lower = last.lower; next.upper = last.upper
                    if step == 1 { days.removeLast() }
                    days.append(next)
                }
            }
        }
        return LegacyR1ActivityLoadSnapshot(days: days, timeZoneID: journal.timeZoneID, asOf: asOf,
            recent: canonical.filter { !$0.isExcludedFromAnalysis && $0.endDate <= asOf }.sorted { $0.startDate > $1.startDate },
            legacyCount: confirmations.values.filter { $0.scaleVersion != LegacyR1ActivityLoadRules.scaleVersion }.count,
            conflictingIDs: conflicts, invalidDateCount: invalidDateCount)
    }
}


// Frozen R3 calculation contract; test-only, not app code.
import Foundation
import CryptoKit
import SwiftData

/// Local descriptive units. A heart-rate proxy is not a measured subjective RPE.
/// Never feeds the legacy duration-dependent RelativeEffort back into this model.
enum LegacyR3ActivityLoadRules {
    static let aggregateVersion = "finite28_hl7_q10q90_past56_v2"
    // Operational, provisional index. This is not calibrated equivalence of HR and RPE.
    // Source is provenance, not a new calculation contract or a continuity boundary.
    static let referenceVersion = "soom_selected_input_provisional_v2"
    static let referenceUnit = "SOOM_provisional_reference_AU"
    static func referenceKey(maximum: Int?) -> String { referenceVersion + ":maxHR:" + (maximum.map(String.init) ?? "none") }
    static let scaleVersion = "soom_session_global_0_10_kr_v1"
    static let manualMethod = "soom_srpe_reviewed_duration_v1"
    static let automaticMethod = "soom_mean_hr_proxy_v1"
    static let durationPolicy = "user_reviewed_session_seconds_v1"
    static let changed = Notification.Name("SOOM.LegacyR3ActivityLoad.localInputsChanged")
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
    }
    static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        let position = Double(sorted.count - 1) * fraction
        let i = Int(position), next = min(i + 1, sorted.count - 1)
        return sorted[i] + (sorted[next] - sorted[i]) * (position - Double(i))
    }
}

struct LegacyR3ActivityLoadEstimate: Equatable {
    let value: Double
    let method: String
    let settingsVersion: String
    let source: String
    let confidence: String
    let computedAt: Date
    var methodKey: String { method + ":" + settingsVersion }
    static func heartRate(_ workout: UnifiedWorkout, maxHeartRate: Int?, at: Date) -> Self? {
        guard let maximum = maxHeartRate, (80...240).contains(maximum),
              let mean = workout.averageHeartRate, mean.isFinite, (30...250).contains(mean),
              mean <= Double(maximum), workout.endDate <= at, workout.endDate > workout.startDate else { return nil }
        // A versioned product proxy, not calibrated RPE or physiological risk.
        // Duration is intentionally absent. Coverage of a mean is not known.
        return Self(value: min(10, max(0, (mean / Double(maximum) - 0.5) * 20)),
                    method: LegacyR3ActivityLoadRules.automaticMethod, settingsVersion: "maxHR:\(maximum)",
                    source: workout.source.rawValue, confidence: "낮음 · 평균심박 기반",
                    computedAt: at)
    }
}

struct LegacyR3ActivityLoadSession: Identifiable, Equatable {
    let workout: UnifiedWorkout
    let intensity: Double?
    let durationSeconds: Double?
    let methodKey: String?
    let sourceLabel: String
    let reason: String?
    let revision: UUID?
    let confirmedAt: Date?
    var id: UUID { workout.id }
    var amount: Double? {
        guard let intensity, let durationSeconds else { return nil }
        let result = intensity * durationSeconds / 60
        return result.isFinite && result >= 0 ? result : nil
    }
    static func resolve(_ workout: UnifiedWorkout, confirmation: WorkoutEffortConfirmation?,
                        maximum: Int?, at: Date) -> Self {
        func result(_ value: Double?, _ duration: Double?, _ method: String?, _ source: String, _ reason: String?) -> Self {
            Self(workout: workout, intensity: value, durationSeconds: duration, methodKey: method,
                 sourceLabel: source, reason: reason, revision: confirmation?.revision, confirmedAt: confirmation?.confirmedAt)
        }
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard !workout.isExcludedFromAnalysis, workout.endDate <= at, workout.updatedAt <= at, elapsed.isFinite, elapsed > 0 else {
            return result(nil, nil, nil, "미확인", "운동 시간 또는 완료 상태 확인 필요")
        }
        if let c = confirmation {
            guard c.scaleVersion == LegacyR3ActivityLoadRules.scaleVersion else {
                return result(nil, nil, nil, "이전 1–10 기록", "새 전체 세션 기준으로 다시 확인해 주세요")
            }
            guard (0...10).contains(c.value), c.confirmedAt <= at, c.confirmedAt >= workout.endDate,
                  c.workoutStart == workout.startDate, c.workoutEnd == workout.endDate,
                  c.durationPolicy == LegacyR3ActivityLoadRules.durationPolicy, c.unit == "sessionRPE_0_10", c.origin == "user",
                  let duration = c.reviewedDurationSeconds, duration.isFinite, duration > 0, duration <= elapsed + 1 else {
                return result(nil, nil, nil, "직접 확인", "시간·원본 변경 또는 입력 시각 재확인 필요")
            }
            return result(Double(c.value), duration, LegacyR3ActivityLoadRules.manualMethod + ":srpe_v1", "직접 확인 · 체감 0–10", nil)
        }
        guard workout.durationSeconds.isFinite, workout.durationSeconds > 0, workout.durationSeconds <= elapsed + 1,
              let estimate = LegacyR3ActivityLoadEstimate.heartRate(workout, maxHeartRate: maximum, at: at) else {
            return result(nil, nil, nil, "추정 불가", "개인 최대심박·평균심박이 필요해요")
        }
        return result(estimate.value, workout.durationSeconds, estimate.methodKey, "자동 추정 · HR 지수 0–10 · 낮은 신뢰", nil)
    }
}

struct LegacyR3ActivityLoadDayApproval: Codable, Equatable {
    enum Kind: String, Codable { case recordsReviewed, noWorkout, excludedOnly }
    let fingerprint: String
    let kind: Kind
    let confirmedAt: Date
}
struct LegacyR3ActivityLoadJournal: Codable, Equatable {
    let schemaVersion: Int
    var timeZoneID: String
    var timeZoneRevision: UUID
    var approvals: [String: LegacyR3ActivityLoadDayApproval]
    static func empty(zone: String) -> Self {
        Self(schemaVersion: 1, timeZoneID: zone, timeZoneRevision: UUID(), approvals: [:])
    }
}
enum LegacyR3ActivityLoadState: String, Equatable {
    case below, inside, above, building, unknown, forecast, mixed
    var label: String {
        switch self {
        case .below: "↓  범위보다 낮음"
        case .inside: "•  범위 안"
        case .above: "↑  범위보다 높음"
        case .building: "…  기준 쌓는 중"
        case .unknown: "—  미확인"
        case .forecast: "○  예상 · 운동 없음"
        case .mixed: "—  혼합 입력 · 범위 판단 보류"
        }
    }
    static func classify(_ value: Double?, lower: Double?, upper: Double?, forecast: Bool = false) -> Self {
        if forecast { return .forecast }
        guard let value, value.isFinite, value >= 0 else { return .unknown }
        guard let lower, let upper, lower.isFinite, upper.isFinite, lower <= upper else { return .building }
        return value < lower ? .below : value > upper ? .above : .inside
    }
}
struct LegacyR3ActivityLoadDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let key: String
    let fingerprint: String
    let sessions: [LegacyR3ActivityLoadSession]
    let rawCount: Int
    var daily: Double?
    var smoothed: Double?
    var lower: Double?
    var upper: Double?
    var methodKey: String?
    var reason: String?
    var segment: Int = 0
    var bandGroup: Int = 0
    var isForecast = false
    var estimatedInputCount = 0
    var userInputCount = 0
    var rangeHeldForMixedInputs = false
    var inputSummary: String {
        if estimatedInputCount > 0 && userInputCount > 0 { return "혼합 입력 · 추정 포함" }
        if estimatedInputCount > 0 { return "자동 추정 · 낮은 신뢰" }
        if userInputCount > 0 { return "사용자 체감 입력" }
        return "입력 확인 필요"
    }
    var workoutPresent: Bool { !sessions.isEmpty }
    var state: LegacyR3ActivityLoadState {
        if isForecast { return .forecast }
        if rangeHeldForMixedInputs { return .mixed }
        if daily != nil && smoothed == nil { return .building }
        return LegacyR3ActivityLoadState.classify(smoothed, lower: lower, upper: upper)
    }
}
struct LegacyR3ActivityLoadSnapshot {
    let days: [LegacyR3ActivityLoadDay]
    let timeZoneID: String
    let asOf: Date
    let recent: [UnifiedWorkout]
    let legacyCount: Int
    let conflictingIDs: Set<UUID>
    var invalidDateCount = 0
}

enum LegacyR3ActivityLoadCalculator {
    /// Fingerprint covers the current canonical/source snapshot, not annotations:
    /// rating edits recalculate immediately; import/delete/duration changes revoke completeness.
    static func canonical(_ rows: [UnifiedWorkout]) -> [UnifiedWorkout] {
        // Reuse canonical identity/representative choice, never fuse other providers' measurements.
        UnifiedWorkoutDeduplicationEngine().canonicalGroups(rows).map { group in
            group.sourceWorkouts.first(where: { $0.id == group.workout.id }) ?? group.workout
        }
    }
    static func reconciledJournal(_ journal: LegacyR3ActivityLoadJournal, workouts: [UnifiedWorkout]) -> LegacyR3ActivityLoadJournal {
        var result = journal
        let calendar = LegacyR3ActivityLoadRules.calendar(journal.timeZoneID)
        let byDay = Dictionary(grouping: canonical(workouts.filter { $0.startDate.timeIntervalSince1970.isFinite })) { LegacyR3ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        for (key, approval) in journal.approvals {
            if approval.fingerprint != fingerprint(byDay[key] ?? [], zone: journal.timeZoneID) {
                result.approvals.removeValue(forKey: key)
            }
        }
        return result
    }
    static func fingerprint(_ rows: [UnifiedWorkout], zone: String) -> String {
        let items = rows.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.source.rawValue)|\($0.externalId ?? "")|\($0.startDate.timeIntervalSince1970)|\($0.endDate.timeIntervalSince1970)|\($0.durationSeconds)|\($0.updatedAt.timeIntervalSince1970)|\($0.isExcludedFromAnalysis)"
        }
        return LegacyR3ActivityLoadRules.hash(zone + "|" + items.joined(separator: ";"))
    }

    static func build(workouts: [UnifiedWorkout], confirmations: [UUID: WorkoutEffortConfirmation],
                      journal: LegacyR3ActivityLoadJournal, maximum: Int?, asOf: Date, historyDays: Int = 180) -> LegacyR3ActivityLoadSnapshot {
        let calendar = LegacyR3ActivityLoadRules.calendar(journal.timeZoneID)
        let today = calendar.startOfDay(for: asOf)
        let start = calendar.date(byAdding: .day, value: -historyDays, to: today)!
        // Identical reimports count once. Equal-UUID conflicting payloads are not arbitrarily selected.
        var unique: [UUID: UnifiedWorkout] = [:], conflicts = Set<UUID>()
        let invalidDateCount = workouts.filter { !$0.startDate.timeIntervalSince1970.isFinite }.count
        for w in workouts where w.startDate.timeIntervalSince1970.isFinite {
            if let old = unique[w.id], old != w { conflicts.insert(w.id) } else { unique[w.id] = w }
        }
        let canonical = canonical(Array(unique.values))
        let byDay = Dictionary(grouping: canonical) { LegacyR3ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        var days: [LegacyR3ActivityLoadDay] = []
        for offset in 0...historyDays {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = LegacyR3ActivityLoadRules.dayKey(date, calendar: calendar)
            let raw = byDay[key] ?? []
            let included = raw.filter { !$0.isExcludedFromAnalysis }
            let sessions = included.map { LegacyR3ActivityLoadSession.resolve($0, confirmation: confirmations[$0.id], maximum: maximum, at: asOf) }
            let fingerprint = fingerprint(raw, zone: journal.timeZoneID)
            let approval = journal.approvals[key]
            let amounts = sessions.compactMap(\.amount)
            let unresolvedOverlap = included.indices.contains { a in
                included.indices.contains { b in
                    b > a && included[a].keepSeparate != true && included[b].keepSeparate != true &&
                    min(included[a].endDate, included[b].endDate).timeIntervalSince(max(included[a].startDate, included[b].startDate)) > 1
                }
            }
            var daily: Double?, reason: String?
            if invalidDateCount > 0 { reason = "날짜가 올바르지 않은 원본 기록을 확인해 주세요" }
            else if date == today { reason = "오늘은 아직 마감되지 않았어요" }
            else if raw.contains(where: { conflicts.contains($0.id) }) { reason = "같은 UUID의 원본 내용이 충돌해요" }
            else if approval?.fingerprint != fingerprint || approval!.confirmedAt > asOf { reason = "이 날짜의 기록·누락 상태 확인 필요" }
            else if sessions.isEmpty {
                if approval!.kind == .noWorkout && raw.isEmpty || approval!.kind == .excludedOnly && !raw.isEmpty {
                    daily = 0
                } else { reason = "운동 없음과 분석 제외를 구분해 확인해 주세요" }
            } else if approval!.kind != .recordsReviewed { reason = "가져온 운동 목록이 바뀌었어요" }
            else if unresolvedOverlap { reason = "겹치는 운동의 병합·분리를 먼저 확인해 주세요" }
            else if amounts.count != sessions.count { reason = sessions.first(where: { $0.reason != nil })?.reason ?? "강도 또는 시간 미확인" }
            else {
                let sum = amounts.reduce(0, +)
                if sum.isFinite { daily = sum } else { reason = "계산 가능한 범위를 벗어났어요" }
            }
            days.append(LegacyR3ActivityLoadDay(date: date, key: key, fingerprint: fingerprint, sessions: sessions, rawCount: raw.count,
                                         daily: daily, methodKey: daily == nil ? nil : LegacyR3ActivityLoadRules.referenceKey(maximum: maximum), reason: reason))
        }
        var segment = 0, key: String?, run: [Int] = [], bandGroup = 0, previousBand = false
        let lambda = pow(2.0, -1.0 / 7.0)
        let weights = (0..<28).map { pow(lambda, Double($0)) }, denominator = (0..<28).reduce(0.0) { $0 + pow(lambda, Double($1)) }
        for i in days.indices {
            guard let _ = days[i].daily else {
                segment += 1; key = nil; run = []; previousBand = false; continue
            }
            let nextKey = days[i].methodKey ?? key ?? LegacyR3ActivityLoadRules.referenceKey(maximum: maximum)
            if key != nil && key != nextKey { segment += 1; run = []; previousBand = false }
            key = nextKey; days[i].methodKey = nextKey; days[i].segment = segment; run.append(i)
            // Keep numeric continuity. Native provenance is retained for interpretation below.
            let inputs = run.suffix(28).flatMap { days[$0].sessions }
            days[i].estimatedInputCount = inputs.filter { $0.methodKey?.hasPrefix(LegacyR3ActivityLoadRules.automaticMethod) == true }.count
            days[i].userInputCount = inputs.filter { $0.methodKey?.hasPrefix(LegacyR3ActivityLoadRules.manualMethod) == true }.count
            guard run.count >= 28 else { continue }
            days[i].smoothed = zip(run.suffix(28).reversed(), weights).reduce(0) { $0 + days[$1.0].daily! * $1.1 } / denominator
            let prior = run.dropLast().suffix(56)
            let priorF = prior.compactMap { days[$0].smoothed }.sorted()
            let positiveSessions = prior.flatMap { days[$0].sessions }.filter { ($0.amount ?? 0) > 0 }.count
            let activeDays = prior.filter { days[$0].sessions.contains { ($0.amount ?? 0) > 0 } }.count
            // Comparing HR-proxy and subjective inputs is not validated. Never turn a
            // provisional combined number into a seemingly comparable percentile/state.
            let usesEstimate = days[i].estimatedInputCount > 0 || prior.contains { days[$0].smoothed != nil && days[$0].estimatedInputCount > 0 }
            let usesUser = days[i].userInputCount > 0 || prior.contains { days[$0].smoothed != nil && days[$0].userInputCount > 0 }
            if usesEstimate && usesUser {
                days[i].rangeHeldForMixedInputs = true
                days[i].reason = "잠정 참고값은 연속 계산하지만 혼합 입력의 개인 범위·상태색은 판단하지 않아요"
                previousBand = false
            } else if priorF.count >= 28 && positiveSessions >= 8 && activeDays >= 4 {
                days[i].lower = LegacyR3ActivityLoadRules.quantile(priorF, 0.1)
                days[i].upper = LegacyR3ActivityLoadRules.quantile(priorF, 0.9)
                if !previousBand { bandGroup += 1 }
                days[i].bandGroup = bandGroup; previousBand = true
            } else { previousBand = false }
        }
        // Forecast is a conditional finite-window calculation, never a rest observation.
        // Only a complete last closed day with an uninterrupted 28-day window can seed it.
        if let last = days.dropLast().last, last.smoothed != nil, last.daily != nil,
           !days.last!.workoutPresent {
            let closed = Array(days.dropLast())
            var window = Array(closed.suffix(28))
            if window.count == 28 && window.allSatisfy({ $0.daily != nil && $0.methodKey == last.methodKey }) {
                for step in 1...3 {
                    let date = calendar.date(byAdding: .day, value: step, to: last.date)!
                    var next = LegacyR3ActivityLoadDay(date: date, key: LegacyR3ActivityLoadRules.dayKey(date, calendar: calendar),
                        fingerprint: "", sessions: [], rawCount: 0, daily: 0, methodKey: last.methodKey, reason: "추가 운동이 없을 때의 조건 계산",
                        segment: last.segment, bandGroup: last.bandGroup, isForecast: true)
                    window.removeFirst(); window.append(next)
                    next.smoothed = zip(window.reversed(), weights).reduce(0) { $0 + $1.0.daily! * $1.1 } / denominator
                    next.lower = last.lower; next.upper = last.upper
                    if step == 1 { days.removeLast() }
                    days.append(next)
                }
            }
        }
        return LegacyR3ActivityLoadSnapshot(days: days, timeZoneID: journal.timeZoneID, asOf: asOf,
            recent: canonical.filter { !$0.isExcludedFromAnalysis && $0.endDate <= asOf }.sorted { $0.startDate > $1.startDate },
            legacyCount: confirmations.values.filter { $0.scaleVersion != LegacyR3ActivityLoadRules.scaleVersion }.count,
            conflictingIDs: conflicts, invalidDateCount: invalidDateCount)
    }
}


extension ActivityLoadTests {
    func testMissingOneBaselineDoesNotDemand58ManualOverridesAndDoesNotInventIt() {
        let h=history(58)
        let missing=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:.empty(zone:"Asia/Seoul"),maximum:nil,asOf:h.asOf,historyDays:58)
        let plan=ActivityLoadInputPlan(missing)
        XCTAssertEqual(plan.baseline.count,0);XCTAssertEqual(plan.recordInputs.count,0)
        XCTAssertEqual(plan.automaticCount,58);XCTAssertEqual(plan.initialCount,58)
        XCTAssertTrue(plan.sessions.allSatisfy{$0.intensity == 7.5 && $0.automaticSource?.hasPrefix("product_prior:") == true})
        XCTAssertTrue(missing.days.allSatisfy{$0.daily == nil},"New estimate never manufactures import completeness")
        let ready=ActivityLoadCalculator.build(workouts:h.rows,confirmations:[:],journal:.empty(zone:"Asia/Seoul"),maximum:200,asOf:h.asOf,historyDays:58)
        let automatic=ActivityLoadInputPlan(ready)
        XCTAssertEqual(automatic.automaticCount,58);XCTAssertEqual(automatic.recordInputs.count,0);XCTAssertTrue(automatic.baseline.isEmpty)
        XCTAssertTrue(automatic.sessions.allSatisfy{$0.intensity == 7.5 && $0.amount == 225})
        XCTAssertTrue(ready.days.allSatisfy{$0.daily == nil},"No import completeness or rest-day evidence is fabricated by making intensity available")
    }
    func testMissingRecordHeartRateIsDifferentFromMissingPersonalBaseline() {
        let h=history(3),w=workout(at:h.rows[0].startDate,hr:nil)
        let snapshot=ActivityLoadCalculator.build(workouts:[w,h.rows[1],h.rows[2]],confirmations:[:],journal:h.journal,maximum:nil,asOf:h.asOf,historyDays:3)
        let p=ActivityLoadInputPlan(snapshot);XCTAssertEqual(p.baseline.count,0);XCTAssertEqual(p.initialCount,2);XCTAssertEqual(p.recordInputs.map(\.id),[w.id])
        XCTAssertEqual(p.recordInputs.first?.automaticIssue,.missingHeartRate)
        XCTAssertNil(ActivityLoadSession.resolve(w,confirmation:nil,maximum:nil,at:h.asOf).amount)
    }
    func testStoredMeasuredSamplesFillOnlyTheReadProjectionAndKeepTimeOnce() {
        let w=workout(hr:nil)
        var telemetry=WorkoutTelemetry(workoutID:w.id,source:w.source)
        telemetry.samples=[.init(timestamp:w.startDate.addingTimeInterval(10),heartRateBPM:140,source:w.source),.init(timestamp:w.endDate.addingTimeInterval(-10),heartRateBPM:160,source:w.source)]
        let input=ActivityLoadHeartRateInput.stored(workout:w,telemetry:telemetry)!
        XCTAssertEqual(input.value,150);XCTAssertNil(w.averageHeartRate)
        let value=ActivityLoadSession.resolve(w,confirmation:nil,maximum:200,at:now,stored:input)
        XCTAssertEqual(value.intensity,7.5);XCTAssertEqual(value.amount,225);XCTAssertTrue(value.confidence.contains("표본"))
        XCTAssertTrue(value.methodKey?.contains("stored_samples_mean_v1") == true)
        XCTAssertEqual(ActivityLoadSession.resolve(w,confirmation:nil,maximum:nil,at:now,stored:input).amount,225,"Stored samples support the authorized low-confidence product prior, not personal HRmax")
    }
    func testStoredSamplesRejectWrongIdentitySourceOutOfWindowInvalidAndSingleReading() {
        let w=workout(hr:nil);var t=WorkoutTelemetry(workoutID:w.id,source:w.source)
        t.samples=[.init(timestamp:w.startDate,heartRateBPM:140),.init(timestamp:w.endDate,heartRateBPM:160)]
        var wrong=t;wrong.workoutID=UUID();XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
        wrong=t;wrong.source = .manual;XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
        wrong=t;wrong.samples=[.init(timestamp:w.startDate.addingTimeInterval(-600),heartRateBPM:140),.init(timestamp:w.endDate.addingTimeInterval(600),heartRateBPM:160)]
        XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
        wrong=t;wrong.samples=[.init(timestamp:w.startDate,heartRateBPM:Double.nan),.init(timestamp:w.endDate,heartRateBPM:0)]
        XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
        wrong=t;wrong.samples=Array(t.samples.prefix(1));XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
        wrong=t;wrong.samples=[t.samples[0],t.samples[0]];XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:wrong))
    }
    func testExistingSummaryWinsAndMeasuredPeakNeverBecomesPersonalMaximum() {
        let w=workout();let other=ActivityLoadHeartRateInput(value:100,evidence:"stored_samples_mean_v1")
        XCTAssertEqual(ActivityLoadEstimate.heartRate(w,maxHeartRate:200,at:now,stored:other)?.value,7.5)
        XCTAssertNil(ActivityLoadEstimate.heartRate(w,maxHeartRate:nil,at:now,stored:other))
        XCTAssertEqual(ActivityLoadEstimate.issue(w,maxHeartRate:100,at:now),.abovePersonalMaximum)
    }
    func testRecordedAverageSummaryRequiresBPMAndRetainsItsEvidence() {
        let w=workout(hr:nil);var t=WorkoutTelemetry(workoutID:w.id,source:w.source)
        t.summaryMetrics=[.init(key:"averageHeartRate",label:"평균 심박",value:150,unit:"bpm")]
        XCTAssertEqual(ActivityLoadHeartRateInput.stored(workout:w,telemetry:t)?.evidence,"stored_summary_v1")
        t.summaryMetrics=[.init(key:"averageHeartRate",label:"평균 심박",value:150,unit:"watts")]
        XCTAssertNil(ActivityLoadHeartRateInput.stored(workout:w,telemetry:t))
    }
    func testLocalTelemetryReadDoesNotWriteOriginalOrCloudAndKeepsAccountsSeparate() throws {
        let a=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let b=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let w=workout(hr:nil),mapper=UnifiedWorkoutPersistenceMapper(),record=mapper.makeRecord(from:w)
        var t=WorkoutTelemetry(workoutID:w.id,source:w.source);t.samples=[.init(timestamp:w.startDate,heartRateBPM:140),.init(timestamp:w.endDate,heartRateBPM:160)]
        record.telemetryData=try JSONEncoder().encode(t);a.mainContext.insert(record);try a.mainContext.save()
        b.mainContext.insert(mapper.makeRecord(from:w));try b.mainContext.save()
        let before=record.telemetryData
        XCTAssertEqual(try ActivityLoadStoredHeartRateReader(context:a.mainContext).read([w])[w.id]?.value,150)
        XCTAssertTrue(try ActivityLoadStoredHeartRateReader(context:b.mainContext).read([w]).isEmpty)
        XCTAssertNil(record.averageHeartRate);XCTAssertEqual(record.updatedAt,w.updatedAt);XCTAssertEqual(record.telemetryData,before)
        XCTAssertFalse(a.mainContext.hasChanges);XCTAssertFalse(b.mainContext.hasChanges)
    }
    func testModelReloadMergesStoredEvidenceOnceAndManualOverrideStillWins() async throws {
        let w=workout(hr:nil),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=ActivityLoadViewModel(directory:dir,now:{self.now});var reads=0
        let provider:([UnifiedWorkout]) throws -> [UUID:ActivityLoadHeartRateInput]={ rows in reads += 1;XCTAssertEqual(rows.map(\.id),[w.id]);return [w.id:.init(value:150,evidence:"stored_samples_mean_v1")] }
        await model.reload(store:ActivityLoadTestStore(rows:[w]),maximum:200,storedHeartRates:provider)
        XCTAssertEqual(reads,1);XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.amount,225)
        try await FileWorkoutEffortStore(scopeDirectory:dir).save(rating(w,value:6),workoutID:w.id)
        await model.reload(store:ActivityLoadTestStore(rows:[w]),maximum:200,storedHeartRates:provider)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.amount,180)
        try await FileWorkoutEffortStore(scopeDirectory:dir).clear(workoutID:w.id)
        await model.reload(store:ActivityLoadTestStore(rows:[w]),maximum:200,storedHeartRates:provider)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.amount,225)
    }
    func testCancelledScopeNeverPublishesStoredHeartRateProjection() async {
        let w=workout(hr:nil);var allowed=true
        let model=ActivityLoadViewModel(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),allowed:{allowed},now:{self.now})
        await model.reload(store:ActivityLoadTestStore(rows:[w]),maximum:200,storedHeartRates:{_ in allowed=false;return [w.id:.init(value:150,evidence:"stored_samples_mean_v1")]})
        XCTAssertNil(model.snapshot)
    }
    func testInvalidManualPreservesOriginalButDoesNotBlockFreshAutomaticEvidence() {
        let w=workout();var c=rating(w,value:10);c.workoutEnd=w.endDate.addingTimeInterval(-60)
        let original=c;let session=ActivityLoadSession.resolve(w,confirmation:c,maximum:200,at:now)
        XCTAssertEqual(session.intensity,7.5);XCTAssertEqual(session.amount,225);XCTAssertEqual(c,original)
        XCTAssertFalse(session.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) ?? true)
        XCTAssertTrue(session.sourceLabel.contains("보존"))
        XCTAssertNil(ActivityLoadSession.resolve(workout(hr:nil),confirmation:c,maximum:200,at:now).amount)
    }
    func testRefreshingAutomaticEvidenceNeverChangesManualOrActiveDraft() async {
        let w=workout(at:Date().addingTimeInterval(-7200));let store=FixtureWorkoutEffortStore()
        let c=rating(w,value:6);store.value=c
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w))
        await editor.load();editor.refreshAutomaticEstimate(.init(value:7.5,method:ActivityLoadRules.automaticMethod,settingsVersion:"maxHR:200",source:"synthetic",confidence:"낮음",computedAt:Date()))
        XCTAssertEqual(editor.displayedValue,6);editor.begin();editor.preview(4);let draft=editor.draft
        editor.refreshAutomaticEstimate(.init(value:7,method:ActivityLoadRules.automaticMethod,settingsVersion:"maxHR:210",source:"synthetic",confidence:"낮음",computedAt:Date()))
        XCTAssertEqual(editor.draft,draft);XCTAssertEqual(store.value,c);editor.cancel();XCTAssertEqual(store.value,c)
    }
}

extension ActivityLoadTests {
    func testPrivateHealthKitCacheCanFeedGraphOnlyWithinOwnerRevisionAndTTLWithoutNewReadOrWrite() async throws {
        let w=workout(hr:nil),container=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let row=UnifiedWorkoutPersistenceMapper().makeRecord(from:w);container.mainContext.insert(row);try container.mainContext.save()
        var clock=now;let cache=HealthKitDetailReadCache(now:{clock})
        let key=HealthKitDetailReadCache.Key(scope:"a",workoutID:w.id,externalID:w.externalId!,revision:w.updatedAt,needsRoute:false)
        var t=WorkoutTelemetry(workoutID:w.id,source:w.source);t.samples=[.init(timestamp:w.startDate,heartRateBPM:140),.init(timestamp:w.endDate,heartRateBPM:160)]
        var queries=0
        _=try await cache.read(key:key){queries += 1;return HealthKitDetailReadResult(telemetry:t)}
        XCTAssertEqual(try ActivityLoadStoredHeartRateReader(context:container.mainContext,scope:"a",cache:cache).read([w])[w.id]?.value,150)
        XCTAssertTrue(try ActivityLoadStoredHeartRateReader(context:container.mainContext,scope:"b",cache:cache).read([w]).isEmpty)
        let changed=workout(id:w.id,hr:nil,updated:w.updatedAt.addingTimeInterval(1))
        XCTAssertTrue(try ActivityLoadStoredHeartRateReader(context:container.mainContext,scope:"a",cache:cache).read([changed]).isEmpty)
        clock=clock.addingTimeInterval(31)
        XCTAssertTrue(try ActivityLoadStoredHeartRateReader(context:container.mainContext,scope:"a",cache:cache).read([w]).isEmpty)
        XCTAssertEqual(queries,1,"Graph reuses cached evidence and never calls its loader")
        XCTAssertNil(row.averageHeartRate);XCTAssertNil(row.telemetryData);XCTAssertFalse(container.mainContext.hasChanges)
    }
}


// All fixtures below are synthetic and permission/network free.
extension ActivityLoadTests {
    func calibrationWorkout(day: Int, hr: Double? = 150, sport: UnifiedWorkoutType = .running,
                            quality: UnifiedDataQuality = .complete, id: UUID = UUID()) -> UnifiedWorkout {
        let start = calendar.date(byAdding: .day, value: day, to: base)!
        return UnifiedWorkout(id: id, externalId: id.uuidString, source: .appleHealthKit, workoutType: sport,
            startDate: start, endDate: start.addingTimeInterval(1800), durationSeconds: 1800,
            distanceMeters: 5000, activeEnergyKcal: nil, averageHeartRate: hr, maxHeartRate: 230,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: quality,
            createdAt: start, updatedAt: start.addingTimeInterval(1800))
    }
    func calibrationInputs(_ rows: [UnifiedWorkout], maximum: Int? = 200, value: Int = 10,
                           at: Date? = nil, ratings: [UUID: WorkoutEffortConfirmation]? = nil) -> ActivityLoadCalibrationInputs {
        .read(workouts: rows, confirmations: ratings ?? Dictionary(uniqueKeysWithValues: rows.map { ($0.id, rating($0, value: value)) }),
              maximum: maximum, at: at ?? base.addingTimeInterval(10 * 86400), zone: calendar.timeZone.identifier)
    }
    func testBaselineUsesOnlyActualAdultAgeOrValidExplicitSettingWithoutWritingSettings() {
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum: nil))
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum: nil, actualAdultAgeYears: 17))
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum: nil, actualAdultAgeYears: 101))
        let age = ActivityLoadBaseline.resolve(personalMaximum: nil, actualAdultAgeYears: 40)!
        XCTAssertEqual(age.maximumBPM, 180); XCTAssertEqual(age.origin, .adultAgeEstimate)
        let saved = ActivityLoadBaseline.resolve(personalMaximum: 200, actualAdultAgeYears: 40)!
        XCTAssertEqual(saved.maximumBPM, 200); XCTAssertEqual(saved.origin, .userSetting)
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum: 0, actualAdultAgeYears: 40), "Invalid explicit input is not silently replaced")
        let w = calibrationWorkout(day: 0)
        let estimate = ActivityLoadEstimate.heartRate(w, baseline: age, at: now)!
        XCTAssertEqual(estimate.value, 10 * 150 / 180, accuracy: 1e-9)
        XCTAssertTrue(estimate.confidence.contains("개인 오차")); XCTAssertTrue(estimate.source.contains("adultAgeEstimate"))
        XCTAssertNil(ActivityLoadEstimate.heartRate(w, maxHeartRate: nil, at: now), "Observed peak 230 is not personal HRmax")
    }
    func testFourExplicitRatingsWithHRCanBeCountedWithoutInventingABaseline() {
        let rows = (0..<4).map { calibrationWorkout(day: $0) }
        let inputs = calibrationInputs(rows, maximum: nil)
        XCTAssertEqual(inputs.summaries.count, 1)
        XCTAssertEqual(inputs.summaries[0].sport, .running)
        XCTAssertEqual(inputs.summaries[0].validHeartRatePairs, 4)
        XCTAssertEqual(inputs.summaries[0].usableBasePairs, 4); XCTAssertFalse(inputs.summaries[0].ready)
        XCTAssertTrue(ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: nil, at: base.addingTimeInterval(10 * 86400)).states.isEmpty)
        let manual = ActivityLoadSession.resolve(rows[0], confirmation: rating(rows[0], value: 6), maximum: nil, at: now)
        XCTAssertEqual(manual.intensity, 6); XCTAssertEqual(manual.amount, 180)
    }
    func testCalibrationNeedsFiveExplicitPairsAndThreeDaysAndNeverUsesAutomaticAcceptance() {
        let rows = (0..<5).map { calibrationWorkout(day: $0) }
        XCTAssertTrue(calibrationInputs(rows).summaries[0].ready)
        XCTAssertFalse(calibrationInputs(Array(rows.prefix(4))).summaries[0].ready)
        var ratings = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, rating($0)) })
        ratings[rows[0].id]!.inputControlVersion = nil
        let legacy = calibrationInputs(rows, ratings: ratings)
        XCTAssertEqual(legacy.pairs.count, 4); XCTAssertFalse(legacy.summaries[0].ready)
        XCTAssertTrue(calibrationInputs(rows, ratings: [:]).pairs.isEmpty)
        // Five non-overlapping sessions on only two days still cannot start learning.
        let twoDays = (0..<5).map { index in workout(at: base.addingTimeInterval(Double(index / 3) * 86400 + Double(index % 3) * 7200)) }
        XCTAssertFalse(calibrationInputs(twoDays).summaries[0].ready)
    }
    func testCalibrationRejectsConflictingDuplicatesAndOverlapsEvenIfKeptSeparate() {
        let first = calibrationWorkout(day: 0), second = calibrationWorkout(day: 1)
        let exact = calibrationInputs([first, second, first], ratings: [first.id: rating(first), second.id: rating(second)])
        XCTAssertEqual(exact.pairs.count, 2)
        let conflicting = calibrationWorkout(day: 0, hr: 120, id: first.id)
        XCTAssertEqual(calibrationInputs([first, conflicting, second], ratings: [first.id: rating(first), second.id: rating(second)]).pairs.count, 1)
        var overlapping = workout(at: first.startDate.addingTimeInterval(60)); overlapping.keepSeparate = true
        XCTAssertTrue(calibrationInputs([first, overlapping]).pairs.isEmpty)
    }
    func testCalibrationRejectsEstimatedSparseInvalidFutureClearedAndStaleSourcePairs() {
        let good = calibrationWorkout(day: 0), estimated = calibrationWorkout(day: 1, quality: .estimated)
        let invalid = calibrationWorkout(day: 2, hr: 300), missing = calibrationWorkout(day: 3, hr: nil)
        var c = rating(good); c.isCleared = true
        XCTAssertTrue(calibrationInputs([good], ratings: [good.id: c]).pairs.isEmpty)
        c = rating(good); c.workoutEnd = good.endDate.addingTimeInterval(1)
        XCTAssertTrue(calibrationInputs([good], ratings: [good.id: c]).pairs.isEmpty)
        XCTAssertTrue(calibrationInputs([estimated, invalid, missing]).pairs.isEmpty)
        XCTAssertTrue(calibrationInputs([good], at: base).pairs.isEmpty)
        XCTAssertTrue(calibrationInputs([good], at: base.addingTimeInterval(100 * 86400)).pairs.isEmpty)
        let sparse = ActivityLoadCalibrationInputs.read(workouts: [missing], confirmations: [missing.id: rating(missing)], maximum: 200,
            at: base.addingTimeInterval(10 * 86400), zone: "Asia/Seoul", stored: [missing.id: .init(value: 150, evidence: "stored_samples_mean_v1")])
        XCTAssertTrue(sparse.pairs.isEmpty, "Unknown sample coverage can display a low-confidence estimate but does not train calibration")
    }
    func testCalibrationSportIsolationAndAboveBaselineDoNotLearnAnHRmax() {
        let run = (0..<5).map { calibrationWorkout(day: $0) }, bike = (5..<9).map { calibrationWorkout(day: $0, sport: .cycling) }
        let at = base.addingTimeInterval(12 * 86400), inputs = calibrationInputs(run + bike, at: at)
        let ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at)
        XCTAssertNotNil(ledger.states["running"]); XCTAssertNil(ledger.states["cycling"])
        let above = (0..<5).map { calibrationWorkout(day: $0, hr: 220) }
        let unsafe = calibrationInputs(above)
        XCTAssertEqual(unsafe.summaries[0].validHeartRatePairs, 5); XCTAssertEqual(unsafe.summaries[0].usableBasePairs, 0)
        XCTAssertTrue(ActivityLoadCalibrationLedger.empty().updated(inputs: unsafe, maximum: 200, at: at).states.isEmpty)
    }
    func testCalibrationMedianShrinkageAndWeeklyCapCannotBeBypassedByRepeatedReload() {
        let at = base.addingTimeInterval(10 * 86400), rows = (0..<5).map { calibrationWorkout(day: $0) }
        let inputs = calibrationInputs(rows, at: at)
        var ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at)
        XCTAssertEqual(ledger.states["running"]!.offset, 0.25, accuracy: 1e-9)
        let first = ledger
        for i in 0..<100 { ledger = ledger.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(Double(i))) }
        XCTAssertEqual(ledger, first, "Same inputs do not churn state or accumulate adjustments")
        ledger = ledger.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(6 * 86400))
        XCTAssertEqual(ledger.states["running"]!.offset, 0.25)
        ledger = ledger.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(7 * 86400))
        XCTAssertEqual(ledger.states["running"]!.offset, 0.5)
        for week in 2...10 { ledger = ledger.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(Double(week * 7) * 86400)) }
        XCTAssertEqual(ledger.states["running"]!.offset, 2.5 * 5 / 15, accuracy: 1e-9, "Residual is shrunk by n/(n+10), not promoted to measured RPE")
        XCTAssertLessThanOrEqual(abs(ledger.states["running"]!.offset), 2)
    }
    func testCalibrationRemovalBaselineChangeAndClockRollbackInvalidateOldInfluence() {
        let at = base.addingTimeInterval(10 * 86400), rows = (0..<5).map { calibrationWorkout(day: $0) }, inputs = calibrationInputs(rows)
        let first = ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at)
        let grown = first.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(7 * 86400))
        XCTAssertEqual(grown.states["running"]!.offset, 0.5)
        let removed = calibrationInputs(Array(rows.dropLast()))
        XCTAssertTrue(grown.updated(inputs: removed, maximum: 200, at: at.addingTimeInterval(8 * 86400)).states.isEmpty)
        let rebased = grown.updated(inputs: calibrationInputs(rows, maximum: 220), maximum: 220, at: at.addingTimeInterval(8 * 86400))
        XCTAssertEqual(rebased.states["running"]!.offset, 0.25, "Prior baseline offset must not be applied twice")
        XCTAssertTrue(grown.updated(inputs: inputs, maximum: nil, at: at).states.isEmpty)
        let rolled = grown.updated(inputs: inputs, maximum: 200, at: at)
        XCTAssertEqual(rolled.states["running"]!.offset, 0.25)
    }
    func testCalibratedEstimateManualLockDurationOnceAndFreshness() {
        let at = base.addingTimeInterval(10 * 86400), rows = (0..<5).map { calibrationWorkout(day: $0) }
        let ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: calibrationInputs(rows), maximum: 200, at: at)
        let w = rows[0], baseEstimate = ActivityLoadEstimate.heartRate(w, maxHeartRate: 200, at: at)!
        let auto = ledger.applying(to: baseEstimate, sport: .running, at: at)!
        XCTAssertEqual(auto.value, 7.75); XCTAssertTrue(auto.confidence.contains("제품 가설"))
        XCTAssertEqual(ledger.applying(to: baseEstimate, sport: .cycling, at: at), baseEstimate)
        XCTAssertEqual(ledger.applying(to: baseEstimate, sport: .running, at: at.addingTimeInterval(86401)), baseEstimate)
        XCTAssertEqual(ledger.applying(to: baseEstimate, sport: .running, at: at.addingTimeInterval(-1)), baseEstimate)
        let manual = ActivityLoadSession.resolve(w, confirmation: rating(w, value: 3), maximum: 200, at: at, calibration: ledger)
        XCTAssertEqual(manual.intensity, 3); XCTAssertEqual(manual.amount, 90); XCTAssertEqual(manual.automaticValue, 7.75)
        let cleared = ActivityLoadSession.resolve(w, confirmation: nil, maximum: 200, at: at, calibration: ledger)
        XCTAssertEqual(cleared.intensity, 7.75); XCTAssertEqual(cleared.amount, 232.5)
        XCTAssertEqual(w.averageHeartRate, 150); XCTAssertEqual(w.maxHeartRate, 230)
    }
    func testCalibrationStorageIsScopedReversibleAndContainsNoRawMeasurements() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = FileActivityLoadStore(scope: root.appendingPathComponent("A")), b = FileActivityLoadStore(scope: root.appendingPathComponent("B"))
        let at = base.addingTimeInterval(10 * 86400), rows = (0..<5).map { calibrationWorkout(day: $0) }
        let ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: calibrationInputs(rows), maximum: 200, at: at)
        try a.saveCalibration(ledger)
        XCTAssertEqual(try a.loadCalibration(), ledger); XCTAssertTrue(try b.loadCalibration().states.isEmpty)
        let data = try Data(contentsOf: a.scope.appendingPathComponent("ActivityLoad/score-calibration-v1.json"))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["annotationFingerprint", "ledger"]))
        let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["averageHeartRate", "latitude", "longitude", "manualValue", rows[0].id.uuidString] { XCTAssertFalse(text.contains(forbidden)) }
        try a.saveCalibration(.empty(enabled: false))
        XCTAssertFalse(try a.loadCalibration().enabled)
        XCTAssertEqual(a.automaticEstimate(rows[0], maximum: 200, at: at)?.value, 7.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.scope.appendingPathComponent("ActivityLoad/History").path))
        XCTAssertThrowsError(try FileActivityLoadStore(scope: root.appendingPathComponent("blocked"), allowed: { false }).saveCalibration(ledger))
        let efforts = FileWorkoutEffortStore(scopeDirectory: a.scope)
        try a.saveCalibration(ledger)
        try await efforts.save(rating(rows[0], value: 4), workoutID: rows[0].id)
        XCTAssertTrue(try a.loadCalibration().states.isEmpty, "A newer/cleared annotation invalidates prior influence even before graph reload")
        XCTAssertEqual(try efforts.load(workoutID: rows[0].id)?.value, 4)
    }
    func testModelCountsAndCalibratesExistingLoadedDataWithoutAdditionalFetchAndCanRevert() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let h = history(8), source = ActivityLoadTestStore(rows: h.rows)
        let efforts = FileWorkoutEffortStore(scopeDirectory: directory)
        for w in h.rows.prefix(5) { try await efforts.save(rating(w, value: 10), workoutID: w.id) }
        let model = ActivityLoadViewModel(directory: directory, now: { h.asOf })
        var storedReads = 0
        await model.reload(store: source, maximum: 200, storedHeartRates: { _ in storedReads += 1; return [:] })
        XCTAssertEqual(source.fetches, 1); XCTAssertEqual(storedReads, 1)
        XCTAssertEqual(model.calibrationSummaries.first?.validHeartRatePairs, 5)
        XCTAssertEqual(model.calibration.states["running"]?.offset, 0.25)
        let autoID = h.rows[6].id
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first { $0.id == autoID }?.intensity, 7.75)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first { $0.id == h.rows[0].id }?.intensity, 10)
        model.setAutomaticCalibrationEnabled(false)
        XCTAssertEqual(source.fetches, 1, "Local rollback recalculates from current inputs, without list refetch")
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first { $0.id == autoID }?.intensity, 7.5)
        XCTAssertEqual(try efforts.load(workoutID: h.rows[0].id)?.value, 10)
        let restart = ActivityLoadViewModel(directory: directory, now: { h.asOf })
        await restart.reload(store: source, maximum: 200)
        XCTAssertFalse(restart.calibration.enabled)
        XCTAssertEqual(restart.snapshot?.days.flatMap(\.sessions).first { $0.id == autoID }?.intensity, 7.5)
        XCTAssertEqual(try FileActivityLoadStore(scope: directory).automaticEstimate(h.rows[6], maximum: 200, at: h.asOf)?.value, 7.5)
    }
    func testCorruptCalibrationCannotHideManualOrBaseEstimateAndDoesNotOverwriteEvidence() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), w = workout()
        try await FileWorkoutEffortStore(scopeDirectory: dir).save(rating(w, value: 4), workoutID: w.id)
        let local = FileActivityLoadStore(scope: dir); try local.save(.empty(zone: "Asia/Seoul"))
        let file = dir.appendingPathComponent("ActivityLoad/score-calibration-v1.json"), corrupt = Data("invalid".utf8)
        try corrupt.write(to: file)
        let model = ActivityLoadViewModel(directory: dir, now: { self.now })
        await model.reload(store: ActivityLoadTestStore(rows: [w]), maximum: nil)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.intensity, 4)
        XCTAssertNotNil(model.calibrationNotice); XCTAssertEqual(try Data(contentsOf: file), corrupt)
        XCTAssertEqual(local.automaticEstimate(w, maximum: 200, at: now)?.value, 7.5)
    }
    func testNoBaselineAndNoFTPDoNotBlockManualOrRecordBrowsingAndNoFakeZero() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), w = calibrationWorkout(day: 0, sport: .cycling)
        let source = ActivityLoadTestStore(rows: [w]), model = ActivityLoadViewModel(directory: dir, now: { self.now })
        await model.reload(store: source, maximum: nil)
        XCTAssertEqual(model.snapshot?.recent.count, 1)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.intensity,7.5,"New product prior does not require HRmax or FTP")
        XCTAssertTrue(model.calibration.states.isEmpty)
        try await FileWorkoutEffortStore(scopeDirectory: dir).save(rating(w, value: 6), workoutID: w.id)
        await model.reload(store: source, maximum: nil)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions).first?.amount, 180)
        XCTAssertEqual(ActivityLoadEstimate.heartRate(w, maxHeartRate: 200, at: now)?.value, 7.5, "FTP/power are not HR model requirements")
    }
}

extension ActivityLoadTests {
    func testNegativeCalibrationCannotCreateAutomaticZeroOrNoData() {
        let at = base.addingTimeInterval(30 * 86400)
        let rows = (0..<20).map { calibrationWorkout(day: $0, hr: 200) }
        let inputs = calibrationInputs(rows, value: 1, at: at)
        var ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at)
        for week in 1...8 { ledger = ledger.updated(inputs: inputs, maximum: 200, at: at.addingTimeInterval(Double(week * 7) * 86400)) }
        XCTAssertEqual(ledger.states["running"]!.offset, -2)
        let checkedAt = at.addingTimeInterval(56 * 86400)
        let low = ActivityLoadEstimate(value: 1.5, method: ActivityLoadRules.automaticMethod, settingsVersion: "maxHR:200", source: "synthetic", confidence: "낮음", computedAt: checkedAt)
        XCTAssertEqual(ledger.applying(to: low, sport: .running, at: checkedAt)?.value, 1, "Automatic correction stays in current 1–10 input range, not a legacy explicit zero or missing/rest marker")
        XCTAssertNil(ledger.applying(to: nil, sport: .running, at: checkedAt), "No evidence remains nil")
    }
}

extension ActivityLoadTests {
    func testCalibrationDoesNotApplyResidualsCalculatedWithADifferentPhysiologicalReference() {
        let at = base.addingTimeInterval(10 * 86400), rows = (0..<5).map { calibrationWorkout(day: $0) }
        let inputs = calibrationInputs(rows, maximum: 200, at: at)
        XCTAssertTrue(ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 220, at: at).states.isEmpty)
        XCTAssertNotNil(ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at).states["running"])
    }
    func testCalibrationDistinctDaysUseCurrentAnalysisTimeZoneAndDoNotInventExtraDays() {
        let formatter = ISO8601DateFormatter()
        let dates = ["2026-01-01T14:30:00Z", "2026-01-01T15:30:00Z", "2026-01-02T14:30:00Z", "2026-01-02T15:30:00Z", "2026-01-02T16:30:00Z"]
        let rows = dates.map { workout(at: formatter.date(from: $0)!) }, at = base.addingTimeInterval(5 * 86400)
        let ratings = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, rating($0, value: 10)) })
        let seoul = ActivityLoadCalibrationInputs.read(workouts: rows, confirmations: ratings, maximum: 200, at: at, zone: "Asia/Seoul")
        let pacific = ActivityLoadCalibrationInputs.read(workouts: rows, confirmations: ratings, maximum: 200, at: at, zone: "America/Los_Angeles")
        XCTAssertEqual(seoul.summaries.first?.distinctDays, 3); XCTAssertEqual(pacific.summaries.first?.distinctDays, 2)
        let old = ActivityLoadCalibrationLedger.empty().updated(inputs: seoul, maximum: 200, at: at)
        XCTAssertNotNil(old.states["running"])
        XCTAssertTrue(old.updated(inputs: pacific, maximum: 200, at: at).states.isEmpty)
    }
}

extension ActivityLoadTests {
    func testEditingOneSportRevalidatesOnlyItsDerivedOffsetAndPreservesOtherSportHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let run = (0..<5).map { calibrationWorkout(day: $0) }, bike = (5..<10).map { calibrationWorkout(day: $0, sport: .cycling) }
        let rows = run + bike, initialAt = base.addingTimeInterval(12 * 86400)
        let efforts = FileWorkoutEffortStore(scopeDirectory: directory), local = FileActivityLoadStore(scope: directory)
        var ratings = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, rating($0, value: 10)) })
        for w in rows { try await efforts.save(ratings[w.id]!, workoutID: w.id) }
        let firstInputs = calibrationInputs(rows, at: initialAt, ratings: ratings)
        let first = ActivityLoadCalibrationLedger.empty().updated(inputs: firstInputs, maximum: 200, at: initialAt)
        let grownAt = initialAt.addingTimeInterval(7 * 86400)
        let grown = first.updated(inputs: calibrationInputs(rows, at: grownAt, ratings: ratings), maximum: 200, at: grownAt)
        XCTAssertEqual(grown.states["cycling"]?.offset, 0.5); try local.saveCalibration(grown)
        ratings[run[0].id] = rating(run[0], value: 6)
        try await efforts.save(ratings[run[0].id]!, workoutID: run[0].id)
        XCTAssertTrue(try local.loadCalibration().states.isEmpty, "Detail fails closed until complete revalidation")
        let model = ActivityLoadViewModel(directory: directory, now: { grownAt.addingTimeInterval(86400) })
        let source = ActivityLoadTestStore(rows: rows)
        await model.reload(store: source, maximum: 200)
        XCTAssertEqual(model.calibration.states["cycling"]?.offset, 0.5, "A running edit must not restart cycling learning")
        XCTAssertEqual(model.calibration.states["running"]?.offset, 0.25, "Changed labels revoke prior influence only in the affected sport")
        XCTAssertEqual(try local.loadCalibration(), model.calibration)
        XCTAssertEqual(try efforts.load(workoutID: run[0].id)?.value, 6)
        XCTAssertEqual(source.fetches, 1)
    }
}

extension ActivityLoadTests {
    func testRealHealthKitMapperPartialSummaryDoesNotBlockValidHeartRatePairsAcrossSports() {
        let sports: [HealthKitWorkoutType] = [.running, .cycling, .swimming]
        let rows = sports.enumerated().flatMap { sportIndex, sport in
            (0..<5).map { index -> UnifiedWorkout in
                let start = base.addingTimeInterval(Double(sportIndex * 5 + index) * 86400)
                let raw = HealthKitWorkout(id: UUID(), workoutType: sport, startDate: start,
                    endDate: start.addingTimeInterval(1800), duration: 1800,
                    distance: nil, averageHeartRate: 150, calories: nil)
                return HealthKitWorkoutToUnifiedWorkoutMapper().map(raw, mappedAt: raw.endDate)
            }
        }
        XCTAssertTrue(rows.allSatisfy { $0.dataQuality == .partial })
        let at = base.addingTimeInterval(20 * 86400), inputs = calibrationInputs(rows, at: at)
        XCTAssertEqual(inputs.pairs.count, 15)
        XCTAssertEqual(Set(inputs.summaries.map { $0.sport.rawValue }), Set(["running", "cycling", "swimming"]))
        XCTAssertTrue(inputs.summaries.allSatisfy { $0.usableBasePairs == 5 && $0.ready })
        let ledger = ActivityLoadCalibrationLedger.empty().updated(inputs: inputs, maximum: 200, at: at)
        XCTAssertEqual(ledger.states.count, 3)
        XCTAssertTrue(ledger.states.values.allSatisfy { $0.offset == 0.25 })
    }
}


extension ActivityLoadTests {
    func testProductPriorHRFirstWorkoutIsLowConfidenceAndNeverChangesPhysiologyOrSource() {
        let w = workout(), original = w
        let estimate = ActivityLoadEstimate.automatic(w, maximum: nil, at: now)!
        XCTAssertEqual(estimate.value, 7.5); XCTAssertEqual(estimate.method, ActivityLoadRules.productPriorMethod)
        XCTAssertEqual(estimate.settingsVersion, ActivityLoadRules.productPriorMethod)
        XCTAssertTrue(estimate.source.hasPrefix("product_prior:")); XCTAssertTrue(estimate.confidence.contains("초기 추정"))
        XCTAssertEqual(w, original); XCTAssertNil(w.maxHeartRate)
        let session = ActivityLoadSession.resolve(w, confirmation: nil, maximum: nil, at: now)
        XCTAssertEqual(session.intensity,7.5); XCTAssertEqual(session.amount,225); XCTAssertNil(session.automaticIssue)
        XCTAssertTrue(session.sourceLabel.contains("초기 추정")); XCTAssertTrue(session.automaticSource!.contains("product_prior"))
    }
    func testProductPriorNeverReplacesExistingPersonalReferenceOrInvalidExplicitSetting() {
        let w = workout()
        XCTAssertEqual(ActivityLoadEstimate.automatic(w,maximum:220,at:now),ActivityLoadEstimate.heartRate(w,maxHeartRate:220,at:now))
        XCTAssertFalse(ActivityLoadEstimate.automatic(w,maximum:220,at:now)!.isInitial)
        XCTAssertNil(ActivityLoadEstimate.automatic(w,maximum:0,at:now));XCTAssertNil(ActivityLoadEstimate.automatic(w,maximum:100,at:now))
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum:nil),"No fake physiological baseline is installed")
    }
    func testProductPriorClampsOnlyValidHRAndRejectsInvalidFutureAndExcludedRecords() {
        XCTAssertEqual(ActivityLoadEstimate.automatic(workout(hr:250),maximum:nil,at:now)?.value,10)
        XCTAssertEqual(ActivityLoadEstimate.automatic(workout(hr:30),maximum:nil,at:now)?.value,1.5)
        for hr in [0.0,29,251,Double.nan,Double.infinity] {XCTAssertNil(ActivityLoadEstimate.automatic(workout(hr:hr),maximum:nil,at:now))}
        XCTAssertNil(ActivityLoadEstimate.automatic(workout(at:now),maximum:nil,at:now))
        let excluded=workout(excluded:true)
        XCTAssertNil(ActivityLoadEstimate.automatic(excluded,maximum:nil,at:now))
    }
    func testProductPriorTimeOccursOnlyOnceAndNeverUsesLegacyRelativeEffort() {
        let short=workout(seconds:600),long=workout(seconds:1800)
        let a=ActivityLoadSession.resolve(short,confirmation:nil,maximum:nil,at:now)
        let b=ActivityLoadSession.resolve(long,confirmation:nil,maximum:nil,at:now)
        XCTAssertEqual(a.intensity,b.intensity);XCTAssertEqual(a.amount,75);XCTAssertEqual(b.amount,225)
    }
    func testFirstRecordWithoutAnyHRorLabelsHasNoInventedScoreAndRemainsBrowsable() async {
        let w=workout(hr:nil),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=ActivityLoadViewModel(directory:dir,now:{self.now})
        await model.reload(store:ActivityLoadTestStore(rows:[w]),maximum:nil)
        let session=model.snapshot!.days.flatMap(\.sessions).first!
        XCTAssertNil(session.intensity);XCTAssertNil(session.amount);XCTAssertEqual(session.automaticIssue,.missingHeartRate)
        XCTAssertEqual(model.snapshot!.recent.map(\.id),[w.id]);XCTAssertEqual(ActivityLoadInputPlan(model.snapshot).recordInputs.count,1)
    }
    func priorFixture() -> (rows:[UnifiedWorkout],ratings:[UUID:WorkoutEffortConfirmation],target:UnifiedWorkout,at:Date) {
        let rows=(0..<3).map{calibrationWorkout(day:$0,hr:nil)}
        let ratings=Dictionary(uniqueKeysWithValues:zip(rows,[4,6,8]).map{($0.0.id,rating($0.0,value:$0.1))})
        return (rows,ratings,calibrationWorkout(day:5,hr:nil),base.addingTimeInterval(10*86400))
    }
    func historyEstimate(_ h:(rows:[UnifiedWorkout],ratings:[UUID:WorkoutEffortConfirmation],target:UnifiedWorkout,at:Date))->ActivityLoadEstimate? {
        let reference=ActivityLoadHistoryReference.resolve(for:h.target,workouts:h.rows,confirmations:h.ratings,at:h.at)
        return ActivityLoadEstimate.automatic(h.target,maximum:nil,at:h.at,history:reference)
    }
    func testNoHRUsesOnlyEarlierSameSportExplicitMedianAndCarriesProvenance() {
        let h=priorFixture(),e=historyEstimate(h)!
        XCTAssertEqual(e.value,6);XCTAssertEqual(e.method,ActivityLoadRules.historyPriorMethod)
        XCTAssertTrue(e.source.contains("explicit_same_sport_history:3:"));XCTAssertTrue(e.confidence.contains("현재 운동 측정 아님"))
        let ref=ActivityLoadHistoryReference.resolve(for:h.target,workouts:h.rows,confirmations:h.ratings,at:h.at)!
        XCTAssertEqual(ActivityLoadSession.resolve(h.target,confirmation:nil,maximum:nil,at:h.at,history:ref).amount,180)
    }
    func testOneExplicitPriorIsLowConfidenceAndNeverBecomesAValidatedMeasurement() {
        var h=priorFixture();h.rows=Array(h.rows.prefix(1));h.ratings=h.ratings.filter{$0.key==h.rows[0].id}
        let e=historyEstimate(h)!;XCTAssertEqual(e.value,4);XCTAssertTrue(e.isInitial);XCTAssertTrue(e.confidence.contains("1건"))
    }
    func testHistoryNeverIncludesSelfLaterOtherSportOrExpiredTeachers() {
        let h=priorFixture();let cycle=calibrationWorkout(day:0,hr:nil,sport:.cycling),late=calibrationWorkout(day:6,hr:nil)
        let old=calibrationWorkout(day:-100,hr:nil)
        let rows=[h.target,cycle,late,old],ratings=Dictionary(uniqueKeysWithValues:rows.map{($0.id,rating($0,value:10))})
        XCTAssertNil(ActivityLoadHistoryReference.resolve(for:h.target,workouts:rows,confirmations:ratings,at:h.at))
        XCTAssertNil(ActivityLoadEstimate.automatic(h.target,maximum:nil,at:h.at))
    }
    func testHistoryDeletionEditingAndClearImmediatelyChangeOnlyDerivedEstimate() {
        var h=priorFixture();let originals=h.rows,originalRatings=h.ratings
        XCTAssertEqual(historyEstimate(h)?.value,6)
        h.rows.removeLast();XCTAssertEqual(historyEstimate(h)?.value,5)
        h.ratings[h.rows[0].id]=rating(h.rows[0],value:8);XCTAssertEqual(historyEstimate(h)?.value,7)
        h.ratings.removeValue(forKey:h.rows[0].id);XCTAssertEqual(historyEstimate(h)?.value,6)
        h.ratings=[:];XCTAssertNil(historyEstimate(h));XCTAssertEqual(originals.count,3);XCTAssertEqual(originalRatings.count,3)
    }
    func testHistoryRejectsLegacyZeroImplicitAcceptedInvalidAndOverlappingTeachers() {
        let h=priorFixture();var ratings=h.ratings
        ratings[h.rows[0].id]=rating(h.rows[0],value:0)
        ratings[h.rows[1].id]!.inputControlVersion=nil
        ratings[h.rows[2].id]!.isCleared=true
        XCTAssertNil(ActivityLoadHistoryReference.resolve(for:h.target,workouts:h.rows,confirmations:ratings,at:h.at))
        let row=h.rows[0]
        // Random canonical preference must never determine whether an overlapping
        // teacher is accepted. Inspect original candidates before dedup selection.
        for _ in 0..<32 {
            let overlap=workout(at:row.startDate,hr:nil)
            XCTAssertNil(ActivityLoadHistoryReference.resolve(for:h.target,workouts:[row,overlap],confirmations:[row.id:h.ratings[row.id]!],at:h.at))
        }
    }
    func testHistoryReferenceCannotBeReusedForAnotherRecordRevisionDateOrAccount() {
        let h=priorFixture(),ref=ActivityLoadHistoryReference.resolve(for:h.target,workouts:h.rows,confirmations:h.ratings,at:h.at)!
        let other=calibrationWorkout(day:5,hr:nil)
        XCTAssertNil(ActivityLoadEstimate.automatic(other,maximum:nil,at:h.at,history:ref))
        let changed=workout(id:h.target.id,at:h.target.startDate,hr:nil,updated:h.target.updatedAt.addingTimeInterval(10))
        XCTAssertNil(ActivityLoadEstimate.automatic(changed,maximum:nil,at:h.at,history:ref))
        XCTAssertNil(ActivityLoadEstimate.automatic(h.target,maximum:nil,at:h.at.addingTimeInterval(1),history:ref))
    }
    func testInvalidHRDoesNotMasqueradeAsMissingToBorrowHistory() {
        let h=priorFixture(),invalid=workout(at:h.target.startDate,hr:Double.nan)
        let ref=ActivityLoadHistoryReference.resolve(for:invalid,workouts:h.rows,confirmations:h.ratings,at:h.at)!
        XCTAssertNil(ActivityLoadEstimate.automatic(invalid,maximum:nil,at:h.at,history:ref))
    }
    func testHRPriorCalibrationLearnsOnlyExplicitPairsWithoutInventingHRmaxOrFTP() {
        let rows=(0..<6).map{calibrationWorkout(day:$0)},at=base.addingTimeInterval(10*86400)
        let inputs=calibrationInputs(Array(rows.prefix(5)),maximum:nil,value:9,at:at)
        XCTAssertEqual(inputs.baselineKey,ActivityLoadRules.productPriorMethod);XCTAssertTrue(inputs.summaries[0].ready)
        let ledger=ActivityLoadCalibrationLedger.empty().updated(inputs:inputs,maximum:nil,at:at)
        XCTAssertEqual(ledger.states["running"]?.offset,0.25)
        let session=ActivityLoadSession.resolve(rows[5],confirmation:nil,maximum:nil,at:at,calibration:ledger)
        XCTAssertEqual(session.intensity,7.75);XCTAssertTrue(session.automaticSource!.hasPrefix("product_prior:"))
        XCTAssertEqual(ActivityLoadSession.resolve(rows[0],confirmation:rating(rows[0],value:3),maximum:nil,at:at,calibration:ledger).intensity,3)
        XCTAssertNil(ActivityLoadBaseline.resolve(personalMaximum:nil));XCTAssertTrue(rows.allSatisfy{$0.maxHeartRate==230},"Observed source peaks stay untouched")
    }
    func testNoHRHistoryEstimatesCannotTrainOrReceiveASecondHRResidualOffset() {
        let h=priorFixture(),ref=ActivityLoadHistoryReference.resolve(for:h.target,workouts:h.rows,confirmations:h.ratings,at:h.at)!
        let rows=(0..<5).map{calibrationWorkout(day:$0)}
        let inputs=calibrationInputs(rows,maximum:nil,value:9,at:h.at)
        let ledger=ActivityLoadCalibrationLedger.empty().updated(inputs:inputs,maximum:nil,at:h.at)
        XCTAssertEqual(ActivityLoadSession.resolve(h.target,confirmation:nil,maximum:nil,at:h.at,calibration:ledger,history:ref).intensity,6)
        let noHRInputs=ActivityLoadCalibrationInputs.read(workouts:h.rows+[h.target],confirmations:h.ratings,maximum:nil,at:h.at,zone:"Asia/Seoul")
        XCTAssertTrue(noHRInputs.pairs.isEmpty)
    }
    func testProductPriorAutomaticToManualClearPreservesOriginalAndLatestDecimal() async throws {
        let w=workout(),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),file=FileWorkoutEffortStore(scopeDirectory:dir)
        let estimate=ActivityLoadEstimate.automatic(w,maximum:nil,at:now)!
        let editor=WorkoutEffortEditor(workoutID:w.id,store:file,sessionContext:.init(w),automaticEstimate:estimate)
        await editor.load();XCTAssertEqual(editor.displayedValue,7.5);XCTAssertEqual(editor.displayedLabel,"초기 추정")
        editor.begin();editor.cancel();XCTAssertNil(try file.load(workoutID:w.id));XCTAssertEqual(editor.displayedValue,7.5)
        editor.begin();editor.preview(6);let didSave=await editor.save();XCTAssertTrue(didSave)
        XCTAssertEqual(editor.displayedValue,6)
        XCTAssertEqual(ActivityLoadSession.resolve(w,confirmation:try file.load(workoutID:w.id),maximum:nil,at:Date()).amount,180)
        let didClear=await editor.clearConfirmation();XCTAssertTrue(didClear);XCTAssertEqual(editor.displayedValue,7.5);XCTAssertEqual(w.averageHeartRate,150)
    }
    func testHistoryLocalReaderMatchesGraphWithoutGraphVisitAndNeverCrossesAccounts() async throws {
        let h=priorFixture(),a=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let b=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),other=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let efforts=FileWorkoutEffortStore(scopeDirectory:dir)
        for row in h.rows {a.mainContext.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from:row));try await efforts.save(h.ratings[row.id]!,workoutID:row.id)}
        try a.mainContext.save()
        let reader=ActivityLoadStoredHeartRateReader(context:a.mainContext)
        let ref=try reader.historicalReference(for:h.target,directory:dir,at:h.at,allowed:{true})
        XCTAssertEqual(ref?.value,6);XCTAssertFalse(a.mainContext.hasChanges)
        XCTAssertNil(try reader.historicalReference(for:h.target,directory:other,at:h.at,allowed:{true}))
        XCTAssertNil(try ActivityLoadStoredHeartRateReader(context:b.mainContext).historicalReference(for:h.target,directory:dir,at:h.at,allowed:{true}))
        XCTAssertThrowsError(try reader.historicalReference(for:h.target,directory:dir,at:h.at,allowed:{false}))
    }
    func testProductPriorReceiptPersistsSeparateProvenanceVersionAndDoesNotOverwriteManual() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),w=workout(),source=ActivityLoadTestStore(rows:[w])
        let model=ActivityLoadViewModel(directory:dir,now:{self.now})
        await model.reload(store:source,maximum:nil)
        let url=dir.appendingPathComponent("ActivityLoad/last-calculation-v1.json")
        var receipt=try JSONDecoder().decode(ActivityLoadCalculationReceipt.self,from:Data(contentsOf:url))
        XCTAssertEqual(receipt.sessions.first?.intensity,7.5);XCTAssertTrue(receipt.sessions.first!.automaticSource!.hasPrefix("product_prior:"))
        XCTAssertTrue(receipt.sessions.first!.methodVersion!.contains(ActivityLoadRules.productPriorMethod));XCTAssertEqual(receipt.sessions.first?.inputUnit,ActivityLoadRules.intensityUnit)
        let efforts=FileWorkoutEffortStore(scopeDirectory:dir),manual=rating(w,value:4)
        try await efforts.save(manual,workoutID:w.id);await model.reload(store:source,maximum:nil)
        receipt=try JSONDecoder().decode(ActivityLoadCalculationReceipt.self,from:Data(contentsOf:url))
        XCTAssertEqual(receipt.sessions.first?.intensity,4);XCTAssertEqual(try efforts.load(workoutID:w.id),manual)
        XCTAssertEqual(source.rows,[w]);XCTAssertEqual(source.fetches,2)
    }
    func testHistoricalFallbackSourceDeletionRecomputesWithoutManufacturingRestOrZero() async throws {
        let h=priorFixture(),dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file=FileWorkoutEffortStore(scopeDirectory:dir)
        for row in h.rows {try await file.save(h.ratings[row.id]!,workoutID:row.id)}
        let model=ActivityLoadViewModel(directory:dir,now:{h.at})
        await model.reload(store:ActivityLoadTestStore(rows:h.rows+[h.target]),maximum:nil)
        XCTAssertEqual(model.snapshot!.days.flatMap(\.sessions).first{$0.id==h.target.id}?.intensity,6)
        await model.reload(store:ActivityLoadTestStore(rows:[h.target]),maximum:nil)
        XCTAssertNil(model.snapshot!.days.flatMap(\.sessions).first{$0.id==h.target.id}?.intensity)
        XCTAssertTrue(model.snapshot!.days.allSatisfy{$0.daily==nil});XCTAssertEqual(model.snapshot?.recent.count,1)
    }
}


extension ActivityLoadTests {
    func testProductPriorLegacyAnnotationDoesNotHideInitialProvenanceOrRewriteOldValue() async throws {
        let w=workout(),old=WorkoutEffortConfirmation(value:4,confirmedAt:now,revision:UUID())
        let session=ActivityLoadSession.resolve(w,confirmation:old,maximum:nil,at:now)
        XCTAssertEqual(session.intensity,7.5);XCTAssertTrue(session.sourceLabel.contains("초기 추정"))
        let store=FixtureWorkoutEffortStore();store.value=old
        let editor=WorkoutEffortEditor(workoutID:w.id,store:store,sessionContext:.init(w),automaticEstimate:ActivityLoadEstimate.automatic(w,maximum:nil,at:now))
        await editor.load();XCTAssertEqual(editor.displayedValue,7.5);XCTAssertTrue(editor.sourceLabel.contains("초기 추정"));editor.begin();editor.cancel();XCTAssertEqual(store.value,old)
    }
    func testPriorCalculatorVersionKeepsOldManualAndPersonalDerivedRecordsAndFillsOnlyNewMissingPath() {
        let h=history(60)
        let known=ActivityLoadCalculator.build(workouts:h.rows,confirmations:h.ratings,journal:h.journal,maximum:200,asOf:h.asOf,historyDays:60)
        let initial=ActivityLoadCalculator.build(workouts:h.rows,confirmations:h.ratings,journal:h.journal,maximum:nil,asOf:h.asOf,historyDays:60)
        XCTAssertEqual(known.days.map(\.daily),initial.days.map(\.daily));XCTAssertEqual(known.days.map(\.smoothed),initial.days.map(\.smoothed));XCTAssertEqual(known.days.map(\.upper),initial.days.map(\.upper))
        XCTAssertTrue(initial.days.flatMap(\.sessions).allSatisfy{$0.intensity==4 && $0.sourceLabel.contains("사용자")})
        XCTAssertEqual(h.ratings.count,60);XCTAssertEqual(h.rows.count,60)
    }
}


extension ActivityLoadTests {
    func testHistoryTeacherWarmupKeepsOldVisibleRecordConsistentWithDetailWithoutAnotherFetch() async throws {
        let teacher=calibrationWorkout(day:50,hr:nil),target=calibrationWorkout(day:100,hr:nil),at=base.addingTimeInterval(250*86400)
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),file=FileWorkoutEffortStore(scopeDirectory:dir)
        try await file.save(rating(teacher,value:6),workoutID:teacher.id)
        let source=ActivityLoadTestStore(rows:[teacher,target]);source.filterRelativeTo=at
        let model=ActivityLoadViewModel(directory:dir,now:{at});await model.reload(store:source,maximum:nil)
        XCTAssertEqual(source.fetches,1);XCTAssertEqual(source.requestedDays,[274])
        let visible=model.snapshot!.days.flatMap(\.sessions).first{$0.id==target.id}
        XCTAssertEqual(visible?.intensity,6,"Teacher outside old184-day query is inside target's90-day history")
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        container.mainContext.insert(UnifiedWorkoutPersistenceMapper().makeRecord(from:teacher));try container.mainContext.save()
        let reference=try ActivityLoadStoredHeartRateReader(context:container.mainContext).historicalReference(for:target,directory:dir,at:at,allowed:{true})
        XCTAssertEqual(visible?.intensity,ActivityLoadEstimate.automatic(target,maximum:nil,at:at,history:reference)?.value)
        XCTAssertFalse(container.mainContext.hasChanges)
    }
}

extension ActivityLoadTests {
    func testWeeklyProjectionShowsKnown105Point4WithoutPromotingIncompleteDay() throws {
        let valid = workout(seconds: 1020, hr: 124)
        let missing = workout(at: base.addingTimeInterval(7200), hr: nil)
        let snapshot = ActivityLoadCalculator.build(workouts: [valid, missing], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
        let day = try XCTUnwrap(snapshot.days.first { !$0.sessions.isEmpty })
        XCTAssertNil(day.daily); XCTAssertNil(day.recordedSubtotal); XCTAssertNil(day.smoothed)
        let records = ActivityLoadComputedRecords(day: day)
        XCTAssertEqual(try XCTUnwrap(records.subtotal), 105.4, accuracy: 1e-10)
        XCTAssertEqual(records.included.count, 1); XCTAssertEqual(records.issues[.missingScore], 1)
        let week = ActivityLoadWeekProjection(snapshot: snapshot, containing: base)
        XCTAssertEqual(try XCTUnwrap(week.subtotal), 105.4, accuracy: 1e-10)
        XCTAssertFalse(week.isComplete); XCTAssertNil(ActivityLoadWeekProjection.precedingThreeCompleteWeeksMean(snapshot: snapshot, before: week.start))
    }
    func testWeeklyProjectionExcludesOverlapsAndUUIDConflictsButKeepsIndependentRecord() throws {
        let a = workout(seconds: 1020, hr: 124), b = workout(at: base.addingTimeInterval(600), seconds: 1020, hr: 124)
        let independent = workout(at: base.addingTimeInterval(7200), seconds: 1020, hr: 124)
        func records(_ rows: [UnifiedWorkout]) throws -> ActivityLoadComputedRecords {
            let snapshot = ActivityLoadCalculator.build(workouts: rows, confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
            return ActivityLoadComputedRecords(day: try XCTUnwrap(snapshot.days.first { !$0.sessions.isEmpty }))
        }
        let overlap = try records([a,b,independent])
        XCTAssertEqual(try XCTUnwrap(overlap.subtotal), 105.4, accuracy: 1e-10); XCTAssertEqual(overlap.issues[.overlap], 2)
        let conflict = workout(id: a.id, seconds: 1020, hr: 130)
        let collided = try records([a,conflict,independent])
        XCTAssertEqual(try XCTUnwrap(collided.subtotal), 105.4, accuracy: 1e-10); XCTAssertEqual(collided.issues[.conflict], 1)
    }
    func testWeeklyProjectionUnlocatedRecordDoesNotHideKnownDateOrCompleteIt() throws {
        let valid = workout(seconds: 1020, hr: 124), invalid = workout(at: Date(timeIntervalSince1970: .nan))
        let snapshot = ActivityLoadCalculator.build(workouts: [valid,invalid], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
        let day = try XCTUnwrap(snapshot.days.first { !$0.sessions.isEmpty })
        XCTAssertTrue(day.cannotPreviewSubtotal); XCTAssertNil(day.recordedSubtotal); XCTAssertNil(day.daily)
        let week = ActivityLoadWeekProjection(snapshot: snapshot, containing: base)
        XCTAssertEqual(week.unlocatedCount, 1); XCTAssertFalse(week.isComplete)
        XCTAssertEqual(try XCTUnwrap(week.subtotal), 105.4, accuracy: 1e-10)
    }
    func testWeeklyProjectionDistinguishesLegacyExplicitZeroFromNoComputedRecords() throws {
        let w = workout(hr: nil), c = rating(w, value: 0)
        let snapshot = ActivityLoadCalculator.build(workouts: [w], confirmations: [w.id:c], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
        let week = ActivityLoadWeekProjection(snapshot: snapshot, containing: base)
        XCTAssertEqual(week.subtotal, 0); XCTAssertEqual(week.computedCount, 1); XCTAssertFalse(week.isComplete)
        let empty = ActivityLoadCalculator.build(workouts: [], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
        XCTAssertNil(ActivityLoadWeekProjection(snapshot: empty, containing: base).subtotal)
    }
    func testWeeklyCumulativeKeepsUnknownGapsAndFutureDaysEmpty() throws {
        let monday = ISO8601DateFormatter().date(from: "2026-11-02T03:00:00Z")!
        let a = workout(at: monday, seconds: 1200, hr: 150)
        let b = workout(at: monday.addingTimeInterval(2*86400), seconds: 1020, hr: 124)
        let snapshot = ActivityLoadCalculator.build(workouts: [a,b], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: b.endDate.addingTimeInterval(3600))
        let week = ActivityLoadWeekProjection(snapshot: snapshot, containing: b.startDate)
        XCTAssertEqual(try XCTUnwrap(week.subtotal), 255.4, accuracy: 1e-10)
        XCTAssertEqual(week.cumulative.map(\.index), [0,2]); XCTAssertNotEqual(week.cumulative[0].segment, week.cumulative[1].segment)
        XCTAssertNil(week.slots[1].amount); XCTAssertTrue(week.slots[3...6].allSatisfy { $0.isFuture && $0.amount == nil })
        XCTAssertEqual(week.elapsedIndex, 2); XCTAssertFalse(week.isComplete)
    }
    func testWeeklyProjectionRecomputesOverrideClearOriginalUpdateAndDeletion() throws {
        let w = workout(seconds: 1020, hr: 124)
        func total(_ rows:[UnifiedWorkout], _ ratings:[UUID:WorkoutEffortConfirmation]) -> Double? {
            let snapshot = ActivityLoadCalculator.build(workouts: rows, confirmations: ratings, journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
            return ActivityLoadWeekProjection(snapshot: snapshot, containing: base).subtotal
        }
        XCTAssertEqual(try XCTUnwrap(total([w],[:])),105.4,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(total([w],[w.id:rating(w,value:7)])),119,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(total([w],[:])),105.4,accuracy:1e-10)
        let updated = workout(id:w.id,seconds:1020,hr:130)
        XCTAssertEqual(try XCTUnwrap(total([updated],[w.id:rating(w,value:7)])),119,accuracy:1e-10)
        XCTAssertEqual(try XCTUnwrap(total([updated],[:])),110.5,accuracy:1e-10)
        XCTAssertNil(total([],[:]))
    }
    func testWeeklyProjectionUsesAnalysisTimeZoneAndRecordedSecondsAcrossDST() throws {
        let date=ISO8601DateFormatter().date(from:"2026-11-02T00:30:00Z")!, w=workout(at:date,seconds:1020,hr:124)
        func week(_ zone:String)->ActivityLoadWeekProjection {
            let snapshot=ActivityLoadCalculator.build(workouts:[w],confirmations:[:],journal:.empty(zone:zone),maximum:nil,asOf:date.addingTimeInterval(7200))
            return ActivityLoadWeekProjection(snapshot:snapshot,containing:date)
        }
        let seoul=week("Asia/Seoul"),la=week("America/Los_Angeles")
        XCTAssertEqual(seoul.cumulative.first?.index,0);XCTAssertEqual(la.cumulative.first?.index,6)
        XCTAssertEqual(try XCTUnwrap(seoul.subtotal),105.4,accuracy:1e-10);XCTAssertEqual(seoul.subtotal,la.subtotal)
        XCTAssertNotEqual(seoul.start,la.start)
    }
    func testWeeklyMeanRequiresExactlyThreeImmediatelyPrecedingCompleteWeeks() {
        let start=ActivityLoadWeekProjection.start(of:base,calendar:calendar)
        var days=(0..<21).map { index -> ActivityLoadDay in
            let date=calendar.date(byAdding:.day,value:index-21,to:start)!
            return ActivityLoadDay(date:date,key:ActivityLoadRules.dayKey(date,calendar:calendar),fingerprint:"synthetic",sessions:[],rawCount:0,daily:index%7==0 ? Double(200+100*(index/7)):0)
        }
        func snapshot()->ActivityLoadSnapshot { .init(days:days,timeZoneID:"Asia/Seoul",asOf:start,recent:[],legacyCount:0,conflictingIDs:[]) }
        XCTAssertEqual(ActivityLoadWeekProjection.precedingThreeCompleteWeeksMean(snapshot:snapshot(),before:start),300)
        days[8].daily=nil
        XCTAssertNil(ActivityLoadWeekProjection.precedingThreeCompleteWeeksMean(snapshot:snapshot(),before:start))
    }
}

extension ActivityLoadTests {
    func testWeeklyProjectionRejectsCrossMidnightOverlapEvenWhenStrictDaysWereReviewed() throws {
        let aStart=ISO8601DateFormatter().date(from:"2026-11-03T14:50:00Z")!
        let a=workout(at:aStart,seconds:2400,hr:124)
        let b=workout(at:aStart.addingTimeInterval(1200),seconds:1800,hr:124)
        let c=workout(at:aStart.addingTimeInterval(7200),seconds:1020,hr:124)
        let rows=[a,b,c],at=aStart.addingTimeInterval(2*86400)
        var journal=ActivityLoadJournal.empty(zone:"Asia/Seoul")
        for group in Dictionary(grouping:rows,by:{ActivityLoadRules.dayKey($0.startDate,calendar:calendar)}) {
            journal.approvals[group.key] = .init(fingerprint:ActivityLoadCalculator.fingerprint(group.value,zone:journal.timeZoneID),kind:.recordsReviewed,confirmedAt:at.addingTimeInterval(-1))
        }
        let snapshot=ActivityLoadCalculator.build(workouts:rows,confirmations:[:],journal:journal,maximum:nil,asOf:at)
        let week=ActivityLoadWeekProjection(snapshot:snapshot,containing:aStart)
        XCTAssertTrue(snapshot.days.filter{$0.workoutPresent}.allSatisfy{$0.daily != nil},"Preserve the legacy day contract while applying stricter display exclusions")
        XCTAssertEqual(week.issues[.overlap],2);XCTAssertEqual(week.computedCount,1)
        XCTAssertEqual(try XCTUnwrap(week.subtotal),105.4,accuracy:1e-10)
        XCTAssertTrue(week.slots.filter{$0.day?.workoutPresent == true}.allSatisfy{!$0.complete})
    }
    func testWeeklyProjectionDistinguishesInvalidDurationFromPendingCompletion() throws {
        let invalid=workout(seconds:0),pending=workout(at:base.addingTimeInterval(3600),seconds:1800)
        let snapshot=ActivityLoadCalculator.build(workouts:[invalid,pending],confirmations:[:],journal:.empty(zone:"Asia/Seoul"),maximum:nil,asOf:base.addingTimeInterval(3700))
        let day=try XCTUnwrap(snapshot.days.first{$0.workoutPresent})
        let records=ActivityLoadComputedRecords(day:day)
        XCTAssertEqual(records.issues[.invalidTime],1);XCTAssertEqual(records.issues[.pending],1)
        XCTAssertNil(records.subtotal)
    }
}


extension ActivityLoadTests {
    func testWeeklyConflictExclusionSurvivesCanonicalProviderReplacement() throws {
        let original = workout(seconds: 1020, hr: 124, source: .appleHealthKit)
        let conflicting = workout(id: original.id, seconds: 1020, hr: 130, source: .appleHealthKit)
        let representative = workout(seconds: 1020, hr: 124, source: .strava)
        let independent = workout(at: base.addingTimeInterval(7200), seconds: 1020, hr: 124)
        let snapshot = ActivityLoadCalculator.build(workouts: [original, conflicting, representative, independent], confirmations: [:], journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: base.addingTimeInterval(86400))
        let day = try XCTUnwrap(snapshot.days.first { $0.workoutPresent })
        XCTAssertTrue(day.sessions.contains { $0.id == representative.id })
        XCTAssertFalse(day.sessions.contains { $0.id == original.id })
        let projection = ActivityLoadComputedRecords(day: day)
        XCTAssertEqual(projection.issues[.conflict], 1)
        XCTAssertEqual(projection.included.map(\.id), [independent.id])
        XCTAssertEqual(try XCTUnwrap(projection.subtotal), 105.4, accuracy: 1e-10)
    }
}


extension ActivityLoadTests {
    func testPerformanceSyntheticActivityLoadMainActorGap() async throws {
        for count in [60, 180] {
            let h = history(count), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileActivityLoadStore(scope: dir).save(h.journal)
            let efforts = FileWorkoutEffortStore(scopeDirectory: dir)
            for w in h.rows { try await efforts.save(h.ratings[w.id]!, workoutID: w.id) }
            let source = ActivityLoadTestStore(rows: h.rows)
            let model = ActivityLoadViewModel(directory: dir, now: { h.asOf })
            for round in 0..<3 {
                let beat = Task { @MainActor in
                    var previous = ProcessInfo.processInfo.systemUptime, largestGap = 0.0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(2))
                        let current = ProcessInfo.processInfo.systemUptime
                        largestGap = max(largestGap, (current - previous) * 1000)
                        previous = current
                    }
                    return largestGap
                }
                await Task.yield()
                let start = ProcessInfo.processInfo.systemUptime
                await model.reload(store: source, maximum: 200)
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                try? await Task.sleep(for: .milliseconds(5))
                beat.cancel(); let largestGap = await beat.value
                XCTAssertNotNil(model.snapshot); XCTAssertNil(model.error)
                print("SOOM_PERF_ACTIVITY rows=\(count) round=\(round) elapsed_ms=\(elapsed) max_main_gap_ms=\(largestGap) input_reads=\(model.inputReadCount)")
            }
        }
    }
}


extension ActivityLoadTests {
    func testPerformanceRevisionCacheCountsAndExplicitRefresh() async throws {
        let h = history(180), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileActivityLoadStore(scope: dir).save(h.journal)
        let source = ActivityLoadTestStore(rows: h.rows)
        var clock = h.asOf
        let model = ActivityLoadViewModel(directory: dir, now: { clock })
        await model.reloadIfNeeded(revision: "source0:edit0", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 1)
        let before = model.snapshot?.days.flatMap(\.sessions)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { await model.reloadIfNeeded(revision: "source0:edit0", store: source, maximum: 200) }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        XCTAssertEqual(source.fetches, 1); XCTAssertEqual(model.cacheHitCount, 100)
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions), before)
        print("SOOM_PERF_CACHE rows=180 reentries=100 extra_fetches=0 total_ms=\(elapsed)")
        await model.reloadIfNeeded(revision: "source1:edit0", store: source, maximum: 200); XCTAssertEqual(source.fetches, 2)
        await model.reloadIfNeeded(revision: "source1:edit0", store: source, maximum: 190); XCTAssertEqual(source.fetches, 3)
        clock = clock.addingTimeInterval(86400)
        await model.reloadIfNeeded(revision: "source1:edit0", store: source, maximum: 190); XCTAssertEqual(source.fetches, 4)
        clock = clock.addingTimeInterval(-1)
        await model.reloadIfNeeded(revision: "source1:edit0", store: source, maximum: 190); XCTAssertEqual(source.fetches, 5)
        await model.reload(store: source, maximum: 190); XCTAssertEqual(source.fetches, 6, "Explicit refresh does not use the appearance cache")
        let other = ActivityLoadViewModel(directory: dir.appendingPathComponent("other"), now: { clock })
        await other.reloadIfNeeded(revision: "source1:edit0", store: source, maximum: 190); XCTAssertEqual(source.fetches, 7)
    }
    func testPerformanceCacheFailureRetryConcurrentRequestsAndRevocation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = ActivityLoadTestStore(rows: [workout()]); source.fails = true
        var allowed = true
        let model = ActivityLoadViewModel(directory: dir, allowed: { allowed }, now: { self.now })
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        XCTAssertNotNil(model.error)
        source.fails = false; source.delay = .milliseconds(30)
        let first = Task { await model.reloadIfNeeded(revision: "0", store: source, maximum: 200) }
        while source.fetches < 2 { await Task.yield() }
        let joined = Task { await model.reloadIfNeeded(revision: "0", store: source, maximum: 200) }
        await first.value; await joined.value
        XCTAssertEqual(source.fetches, 2); XCTAssertNil(model.error)
        let prior = model.snapshot?.days.flatMap(\.sessions)
        let revoked = Task { await model.reloadIfNeeded(revision: "1", store: source, maximum: 200) }
        while source.fetches < 3 { await Task.yield() }
        allowed = false; await revoked.value
        XCTAssertEqual(model.snapshot?.days.flatMap(\.sessions), prior)
        allowed = true
        await model.reloadIfNeeded(revision: "1", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 4, "Rejected work must not stamp a successful revision")
    }
    func testPerformanceCancelledAppearanceAndSupersededReadCannotStampCache() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = ActivityLoadTestStore(rows: [workout()]); source.delay = .milliseconds(50)
        let model = ActivityLoadViewModel(directory: dir, now: { self.now })
        let cancelled = Task { await model.reloadIfNeeded(revision: "0", store: source, maximum: 200) }
        while source.fetches < 1 { await Task.yield() }
        cancelled.cancel(); await cancelled.value
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.isLoading)
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200); XCTAssertEqual(source.fetches, 2)
        let old = Task { await model.reloadIfNeeded(revision: "1", store: source, maximum: 200) }
        while source.fetches < 3 { await Task.yield() }
        // A direct explicit read can replace the flight without changing its request key.
        source.rows = []; source.delay = .zero
        await model.reload(store: source, maximum: 200)
        await old.value
        XCTAssertTrue(model.snapshot?.recent.isEmpty == true)
        await model.reloadIfNeeded(revision: "1", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 5, "Superseded flight cannot attach its revision to another result")
    }
    func testPerformanceTemporalEqualityFutureCompletionAndZoneChange() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = workout(), source = ActivityLoadTestStore(rows: [w])
        var clock = w.endDate
        let model = ActivityLoadViewModel(directory: dir, now: { clock })
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 1, "An end/update equal to asOf is already included")
        clock = w.startDate.addingTimeInterval(1)
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200); XCTAssertEqual(source.fetches, 2)
        XCTAssertTrue(model.snapshot?.recent.isEmpty == true)
        clock = w.endDate
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200); XCTAssertEqual(source.fetches, 3)
        XCTAssertEqual(model.snapshot?.recent.map(\.id), [w.id])
        let nextZone = model.snapshot?.timeZoneID == "UTC" ? "Asia/Seoul" : "UTC"
        model.changeTimeZone(nextZone)
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200); XCTAssertEqual(source.fetches, 4)
        XCTAssertEqual(model.snapshot?.timeZoneID, nextZone)
    }
    func testPerformanceBatchRatingsPreserveManualZeroClearCorruptionAndAccountGate() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rows = [workout(), workout(), workout()], store = FileWorkoutEffortStore(scopeDirectory: dir)
        try await store.save(rating(rows[0], value: 4), workoutID: rows[0].id)
        try await store.save(rating(rows[1], value: 0), workoutID: rows[1].id)
        try await store.save(rating(rows[2], value: 7), workoutID: rows[2].id); try await store.clear(workoutID: rows[2].id)
        let before = try rows.map { try Data(contentsOf: store.directory.appendingPathComponent($0.id.uuidString + ".json")) }
        let values = try await store.load(workoutIDs: Set(rows.map(\.id)))
        XCTAssertEqual(values[rows[0].id]?.value, 4); XCTAssertEqual(values[rows[1].id]?.value, 0); XCTAssertNil(values[rows[2].id])
        XCTAssertEqual(try rows.map { try Data(contentsOf: store.directory.appendingPathComponent($0.id.uuidString + ".json")) }, before)
        do { _ = try await FileWorkoutEffortStore(scopeDirectory: dir, canAccess: { false }).load(workoutIDs: Set(rows.map(\.id))); XCTFail("Revoked scope") } catch {}
        try Data("invalid".utf8).write(to: store.directory.appendingPathComponent(rows[0].id.uuidString + ".json"))
        do { _ = try await store.load(workoutIDs: [rows[0].id]); XCTFail("Corrupt annotations must not become an empty success") } catch {}
    }
    func testPerformanceAsyncProjectionKeepsIndependentManualAmounts() async throws {
        let h = history(8), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileActivityLoadStore(scope: dir).save(h.journal)
        let effort = FileWorkoutEffortStore(scopeDirectory: dir)
        for w in h.rows { try await effort.save(h.ratings[w.id]!, workoutID: w.id) }
        let model = ActivityLoadViewModel(directory: dir, now: { h.asOf })
        await model.reload(store: ActivityLoadTestStore(rows: h.rows), maximum: 200)
        let sessions = try XCTUnwrap(model.snapshot?.days.flatMap(\.sessions))
        XCTAssertEqual(sessions.count, 8)
        for session in sessions { XCTAssertEqual(session.intensity, 4); XCTAssertEqual(session.amount, 120); XCTAssertEqual(session.durationSeconds, 1800) }
        XCTAssertEqual(sessions.compactMap(\.amount).reduce(0,+), 960)
        XCTAssertEqual(Set(model.snapshot?.recent.map(\.id) ?? []), Set(h.rows.map(\.id)))
    }
}


extension ActivityLoadTests {
    func testPerformanceCacheRespectsInclusiveCalibrationLookbackBoundary() async throws {
        let h = history(5), dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileActivityLoadStore(scope: dir).save(h.journal)
        let efforts = FileWorkoutEffortStore(scopeDirectory: dir)
        for w in h.rows { try await efforts.save(rating(w, value: 10), workoutID: w.id) }
        let cutoff = calendar.date(byAdding: .day, value: 90, to: h.rows[0].startDate)!
        var clock = cutoff.addingTimeInterval(-1)
        let source = ActivityLoadTestStore(rows: h.rows), model = ActivityLoadViewModel(directory: dir, now: { clock })
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        XCTAssertEqual(model.calibrationSummaries.first?.validHeartRatePairs, 5)
        clock = cutoff
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 1, "The teacher is still included at the exact 90-day boundary")
        clock = cutoff.addingTimeInterval(1)
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 2); XCTAssertEqual(model.calibrationSummaries.first?.validHeartRatePairs, 4)
        XCTAssertTrue(model.calibration.states.isEmpty)
    }
    func testPerformanceExplicitRecalculationCancelsFlightAndCorruptFallbackIsNotCached() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = ActivityLoadTestStore(rows: [workout()]), model = ActivityLoadViewModel(directory: dir, now: { self.now })
        await model.reloadIfNeeded(revision: "0", store: source, maximum: 200)
        source.delay = .milliseconds(30)
        let flight = Task { await model.reloadIfNeeded(revision: "1", store: source, maximum: 200) }
        while source.fetches < 2 { await Task.yield() }
        model.setAutomaticCalibrationEnabled(false)
        XCTAssertFalse(model.isLoading)
        await flight.value
        await model.reloadIfNeeded(revision: "1", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 3); XCTAssertFalse(model.calibration.enabled)
        let file = dir.appendingPathComponent("ActivityLoad/score-calibration-v1.json"), corrupt = Data("invalid".utf8)
        try corrupt.write(to: file)
        await model.reloadIfNeeded(revision: "2", store: source, maximum: 200)
        XCTAssertNotNil(model.calibrationNotice); XCTAssertNotNil(model.snapshot)
        await model.reloadIfNeeded(revision: "2", store: source, maximum: 200)
        XCTAssertEqual(source.fetches, 5, "Fallback output is preserved but failed calibration is retryable")
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
