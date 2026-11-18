import XCTest
import UIKit

final class WorkoutEffortHapticPolicyTests: XCTestCase {
    func testPresentationMemoryIsBoundedAndClearedWithItsAccountRoot() {
        let memory = WorkoutDetailPresentationStore(), id = UUID()
        memory.update(id) { $0.charts = true; $0.scroll = 420; $0.sheet = .expanded }
        memory.update(id) { $0.splits = true }
        XCTAssertEqual(memory.value(id).scroll, 420)
        XCTAssertTrue(memory.value(id).charts && memory.value(id).splits)
        for _ in 0..<24 { memory.update(UUID()) { $0.charts = true } }
        XCTAssertFalse(memory.value(id).charts)
        memory.update(id) { $0.charts = true }
        memory.clear()
        XCTAssertFalse(memory.value(id).charts)
        XCTAssertFalse(WorkoutDetailPresentationStore().value(id).charts)
    }
    func testMovementIsQuietAndRateLimitedWhileIntegerStepIsDistinct() {
        var policy = WorkoutEffortHapticPolicy()
        policy.begin(2)
        XCTAssertEqual(policy.update(2.1, at: 0, reduced: false), .movement)
        XCTAssertNil(policy.update(2.2, at: 0.01, reduced: false))
        XCTAssertEqual(policy.update(3, at: 0.09, reduced: false), .step)
        XCTAssertNil(policy.update(3, at: 1, reduced: false))
        XCTAssertEqual(policy.update(2.7, at: 1.1, reduced: false), .movement)
    }
    func testReducedMotionKeepsDiscreteMicroAndStepPulsesAndEndResets() {
        var policy = WorkoutEffortHapticPolicy()
        policy.begin(4)
        XCTAssertEqual(policy.update(4.2, at: 1, reduced: true), .movement)
        XCTAssertEqual(policy.update(5, at: 1.1, reduced: true), .step)
        policy.end()
        XCTAssertNil(policy.update(8, at: 2, reduced: false))
        XCTAssertNil(policy.update(.nan, at: 3, reduced: false))
    }
    func testDenseDragDoesNotEmitPerPixelOrForStationaryHold() {
        var policy = WorkoutEffortHapticPolicy(); policy.begin(1)
        let pulses = (1...900).compactMap { index in
            policy.update(1 + Double(index) / 100, at: Double(index) / 900, reduced: false)
        }
        XCTAssertLessThanOrEqual(pulses.count, 94) // 83 quiet pulses/sec + bounded integer ticks
        for time in 2...20 { XCTAssertNil(policy.update(10, at: Double(time), reduced: false)) }
    }
}
@testable import SOOM

@MainActor
final class WorkoutEffortTests: XCTestCase {
    func testReferenceMeanUsesActualObservationsRatherThanRangeMidpoint() throws {
        let now=Date()
        let values=[1,1,2,3,10].map{WorkoutEffortConfirmation(value:$0,confirmedAt:now.addingTimeInterval(-86400),revision:UUID())}
        let range=try XCTUnwrap(WorkoutEffortUsualRange.build(values,now:now))
        XCTAssertEqual(range.lower,1);XCTAssertEqual(range.upper,3)
        XCTAssertEqual(try XCTUnwrap(range.referenceMean),3.4,accuracy:1e-12)
        XCTAssertNotEqual(range.referenceMean,(range.lower+range.upper)/2)
        XCTAssertNil(WorkoutEffortUsualRange(lower:4,upper:6,count:7).referenceMean,
                     "A fixture or legacy range without observations must not invent an average marker")
    }
    func testMissingValueStaysUnselectedAndCancelDoesNotPersist() async {
        let store = FixtureWorkoutEffortStore(), id = UUID()
        let editor = WorkoutEffortEditor(workoutID:id,store:store,reader:store)
        await editor.load(); editor.begin()
        XCTAssertNil(editor.draft); XCTAssertFalse(editor.canSave)
        editor.preview(8.3); XCTAssertEqual(editor.selectedValue,8)
        XCTAssertNil(editor.confirmation); XCTAssertNil(store.value)
        editor.cancel(); editor.begin()
        XCTAssertNil(editor.draft); XCTAssertEqual(store.saveCount,0)
    }
    func testAppleObservationAndEstimateRemainSeparateFromConfirmation() async {
        for origin in [WorkoutEffortObservation.Origin.apple,.appleEstimate] {
            let store = FixtureWorkoutEffortStore(), id=UUID()
            let observation = WorkoutEffortObservation(value:6.5,origin:origin,sampleID:UUID(),workoutID:id,observedAt:Date())
            store.observed=observation
            let editor=WorkoutEffortEditor(workoutID:id,store:store,reader:store)
            await editor.load();editor.begin();editor.preview(9);editor.cancel()
            XCTAssertEqual(editor.displayedValue,6.5);XCTAssertEqual(editor.observation,observation)
            editor.begin();editor.preview(7);let success=await editor.save()
            XCTAssertTrue(success);XCTAssertEqual(editor.confirmation?.value,7)
            XCTAssertEqual(editor.observation,observation);XCTAssertEqual(store.observed,observation)
        }
    }
    func testFailureRetainsDraftAndPriorValueThenRetrySucceeds() async {
        let store=FixtureWorkoutEffortStore();store.value = .init(value:4,confirmedAt:Date(),revision:UUID());store.failsNextSave=true
        let editor=WorkoutEffortEditor(workoutID:UUID(),store:store,reader:store)
        await editor.load();editor.begin();editor.preview(8)
        let first=await editor.save();XCTAssertFalse(first)
        XCTAssertEqual(editor.draft,8);XCTAssertEqual(editor.confirmation?.value,4)
        XCTAssertTrue(editor.isEditing);XCTAssertNotNil(editor.error)
        let second=await editor.save();XCTAssertTrue(second);XCTAssertEqual(store.value?.value,8)
        XCTAssertFalse(editor.isEditing)
    }
    func testPendingSaveBlocksDuplicateCancelAndDraftMutation() async {
        let store=FixtureWorkoutEffortStore();store.delay = .milliseconds(150)
        let editor=WorkoutEffortEditor(workoutID:UUID(),store:store,reader:store)
        await editor.load();editor.begin();editor.preview(6)
        let first=Task { await editor.save() }
        await Task.yield()
        XCTAssertTrue(editor.isSaving)
        editor.cancel();editor.preview(2)
        let duplicate=await editor.save();XCTAssertFalse(duplicate)
        XCTAssertTrue(editor.isEditing);XCTAssertEqual(editor.draft,6)
        let success=await first.value;XCTAssertTrue(success);XCTAssertEqual(store.saveCount,1)
    }
    func testNonFiniteInputAndMismatchedObservationCannotEnterDraft() async {
        let store=FixtureWorkoutEffortStore()
        store.observed = .init(value:8,origin:.apple,sampleID:UUID(),workoutID:UUID(),observedAt:Date())
        let editor=WorkoutEffortEditor(workoutID:UUID(),store:store,reader:store)
        await editor.load();XCTAssertNil(editor.observation);editor.begin()
        editor.preview(.nan);XCTAssertNil(editor.draft)
        editor.preview(-100);XCTAssertEqual(editor.selectedValue,1)
        editor.preview(100);XCTAssertEqual(editor.selectedValue,10)
    }
    func testLocalRoundTripAccountIsolationAndRevokedScope() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var active=true
        let a=FileWorkoutEffortStore(scopeDirectory:root.appendingPathComponent("a"),canAccess:{active})
        let b=FileWorkoutEffortStore(scopeDirectory:root.appendingPathComponent("b"))
        let id=UUID(),rating=WorkoutEffortConfirmation(value:7,confirmedAt:Date(timeIntervalSince1970:100),revision:UUID())
        try await a.save(rating,workoutID:id)
        XCTAssertEqual(try a.load(workoutID:id),rating);XCTAssertNil(try b.load(workoutID:id))
        let reopened=FileWorkoutEffortStore(scopeDirectory:root.appendingPathComponent("a"))
        XCTAssertEqual(try reopened.load(workoutID:id),rating)
        active=false
        do { try await a.save(.init(value:2,confirmedAt:Date(),revision:UUID()),workoutID:id);XCTFail("Retired account must reject writes") } catch {}
        XCTAssertEqual(try reopened.load(workoutID:id),rating)
    }
    func testCorruptLocalRecordBlocksOverwriteAndCanRetry() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=FileWorkoutEffortStore(scopeDirectory:root),id=UUID()
        try FileManager.default.createDirectory(at:store.directory,withIntermediateDirectories:true)
        let file=store.directory.appendingPathComponent(id.uuidString+".json")
        try Data("invalid".utf8).write(to:file)
        let editor=WorkoutEffortEditor(workoutID:id,store:store)
        await editor.load();editor.begin();XCTAssertFalse(editor.isEditing);XCTAssertNotNil(editor.error)
        try FileManager.default.removeItem(at:file)
        await editor.load();editor.begin();XCTAssertTrue(editor.isEditing)
    }
}

final class WorkoutEffortRangeAndGeometryTests: XCTestCase {
    func testReferenceCalloutFitsAtBothEndsAndEmphasisStopsAtSelection() {
        for width in [240.0, 320, 430] {
            for callout in [126.0, 220, 500] {
                for value in [1.0, 5, 10] {
                    for expansion in [0.0, 1] {
                        let center = EffortScaleGeometry.calloutCenter(value, width: width, calloutWidth: callout, expansion: expansion)
                        let half = min(width, callout) / 2
                        XCTAssertGreaterThanOrEqual(center - half, 0)
                        XCTAssertLessThanOrEqual(center + half, width)
                    }
                }
            }
        }
        let range = WorkoutEffortUsualRange(lower: 4, upper: 6, count: 7)
        XCTAssertEqual(EffortScaleGeometry.emphasis(8, range: range), 6...8)
        XCTAssertEqual(EffortScaleGeometry.emphasis(2, range: range), 2...4)
        XCTAssertNil(EffortScaleGeometry.emphasis(4, range: range))
        XCTAssertNil(EffortScaleGeometry.emphasis(6, range: range))
        XCTAssertNil(EffortScaleGeometry.emphasis(.nan, range: range))
        for amount in [0.0, 0.5, 1] {
            let rect = CGRect(x: 0, y: 0, width: 230, height: 64)
            let bounds = EffortWedge(amount: amount).path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX)
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX)
            XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY)
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY)
        }
    }
    func testSparseHistoryNeverDrawsRangeAndWedgeActuallyExpands() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rating = WorkoutEffortConfirmation(value: 7, confirmedAt: now.addingTimeInterval(-86400), revision: UUID())
        for history in [[], [rating]] {
            XCTAssertNil(WorkoutEffortUsualRange.build(history, now: now))
            var state = EffortScaleInteraction()
            XCTAssertFalse(state.showsHatching(hasRange: false))
            state.press(); state.drag(); XCTAssertFalse(state.showsHatching(hasRange: false))
            state.end(); XCTAssertTrue(state.isExpanded); XCTAssertFalse(state.showsHatching(hasRange: false))
        }
        let rect = CGRect(x: 0, y: 0, width: 280, height: 64)
        let compact = EffortWedge(amount: 0.18).path(in: rect).boundingRect
        let expanded = EffortWedge(amount: 0.65).path(in: rect).boundingRect
        XCTAssertGreaterThan(expanded.height, compact.height * 2)
        XCTAssertEqual(WorkoutEffortStyle.title(7, isManualSelection: true), "많이 힘들었어요")
        XCTAssertEqual(WorkoutEffortStyle.title(7), "높은 쪽 점수")
        XCTAssertFalse(WorkoutEffortStyle.description(7).contains("숨"))
        XCTAssertEqual(WorkoutEffortStyle.title(nil, isManualSelection: true), "점수를 선택해 주세요")
    }

    func testRangeMinimumCountDateBoundariesAndEqualValues() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(byAdding: .day, value: -21, to: now)!
        func rating(_ value: Int, at date: Date) -> WorkoutEffortConfirmation {
            .init(value: value, confirmedAt: date, revision: UUID())
        }
        let recent = (0..<4).map { _ in rating(5, at: now.addingTimeInterval(-1)) }
        XCTAssertNil(WorkoutEffortUsualRange.build(recent, now: now, calendar: calendar))
        let exactMinimum = recent + [rating(5, at: start)]
        let range = WorkoutEffortUsualRange.build(exactMinimum + [rating(1, at: start.addingTimeInterval(-1)), rating(10, at: now)], now: now, calendar: calendar)
        XCTAssertEqual(range?.count, 5)
        XCTAssertEqual(range?.lower, 5); XCTAssertEqual(range?.upper, 5)
        XCTAssertEqual(range?.relation(to: 5), "평소 범위 안")
        XCTAssertEqual(range?.relation(to: 4), "평소 범위 미만")
        XCTAssertEqual(range?.relation(to: 6), "평소 범위 이상")
        let extremes = [1, 1, 5, 10, 10].map { rating($0, at: start) }
        let fullRange = WorkoutEffortUsualRange.build(extremes, now: now, calendar: calendar)
        XCTAssertEqual(fullRange?.lower, 1); XCTAssertEqual(fullRange?.upper, 10)
        XCTAssertEqual(fullRange?.relation(to: 1), "평소 범위 안")
        XCTAssertEqual(fullRange?.relation(to: 10), "평소 범위 안")
    }
    func testRangeUsesOnlyRecentValidConfirmationsAndDoesNotInventSparseRange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func rating(_ value: Int, days: Double = 1) -> WorkoutEffortConfirmation {
            .init(value: value, confirmedAt: now.addingTimeInterval(-days * 86400), revision: UUID())
        }
        XCTAssertNil(WorkoutEffortUsualRange.build([rating(4), rating(6)], now: now))
        let input = [3,4,4,5,6,6,10].map { rating($0) } + [rating(1, days: 22), rating(1, days: -1), rating(99)]
        let range = WorkoutEffortUsualRange.build(input, now: now)
        XCTAssertEqual(range?.lower, 4); XCTAssertEqual(range?.upper, 6); XCTAssertEqual(range?.count, 7)
        XCTAssertEqual(range?.relation(to: 7), "평소 범위 이상")
        XCTAssertEqual(range?.relation(to: 6), "평소 범위 안")
        XCTAssertEqual(range?.relation(to: 3), "평소 범위 미만")
    }
    func testExpansionMaintainsOrderedTicksAndExpandedTouchRoundTrip() {
        for width in [240.0, 320, 430] {
            for value in 1...10 {
                let x = EffortScaleGeometry.x(Double(value), width: width, expansion: 1)
                XCTAssertEqual(EffortScaleGeometry.value(at: x, width: width), Double(value), accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(x, 22); XCTAssertLessThanOrEqual(x, width - 22)
            }
            let rest = EffortScaleGeometry.x(2, width: width, expansion: 0) - EffortScaleGeometry.x(1, width: width, expansion: 0)
            let pressed = EffortScaleGeometry.x(2, width: width, expansion: 1) - EffortScaleGeometry.x(1, width: width, expansion: 1)
            XCTAssertGreaterThan(pressed, rest)
        }
    }
    func testHapticRampDistinctAndNoDuplicateAtTickOrAfterEnd() {
        for value in 1...9 {
            XCTAssertLessThan(WorkoutEffortHapticPolicy.intensity(.movement, value: Double(value)), WorkoutEffortHapticPolicy.intensity(.movement, value: Double(value + 1)))
            XCTAssertLessThan(WorkoutEffortHapticPolicy.intensity(.step, value: Double(value)), WorkoutEffortHapticPolicy.intensity(.step, value: Double(value + 1)))
            XCTAssertLessThan(WorkoutEffortHapticPolicy.intensity(.movement, value: Double(value)), WorkoutEffortHapticPolicy.intensity(.step, value: Double(value)))
        }
        var p = WorkoutEffortHapticPolicy(); p.begin(2)
        XCTAssertEqual(p.update(3, at: 0, reduced: false), .step)
        XCTAssertNil(p.update(3.01, at: 0.01, reduced: false))
        XCTAssertNil(p.update(3.01, at: 2, reduced: false))
        p.end(); XCTAssertNil(p.update(4, at: 3, reduced: false)); XCTAssertNil(p.update(5, at: 4, reduced: false))
    }
}

extension WorkoutEffortTests {
    func testRepeatedSaveForSameWorkoutCountsOnceButDistinctWorkoutsWithSameValueCountSeparately() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileWorkoutEffortStore(scopeDirectory: root), repeatedID = UUID(), currentID = UUID()
        for value in [2, 3, 7] {
            try await store.save(.init(value: value, confirmedAt: Date().addingTimeInterval(-60), revision: UUID()), workoutID: repeatedID)
        }
        let once = try store.history(excluding: currentID)
        XCTAssertEqual(once.count, 1); XCTAssertEqual(once.first?.value, 7)
        for _ in 0..<4 {
            try await store.save(.init(value: 7, confirmedAt: Date().addingTimeInterval(-60), revision: UUID()), workoutID: UUID())
        }
        let range = WorkoutEffortUsualRange.build(try store.history(excluding: currentID))
        XCTAssertEqual(range?.count, 5); XCTAssertEqual(range?.lower, 7); XCTAssertEqual(range?.upper, 7)
        XCTAssertEqual(try store.history(excluding: repeatedID).count, 4)
    }
    func testHistoryExcludesCurrentWorkoutAndOtherAccountsAndDoesNotChangeSaveFlow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileWorkoutEffortStore(scopeDirectory: root.appendingPathComponent("a")), id = UUID()
        for value in [3,4,5,6,7] { try await store.save(.init(value: value, confirmedAt: Date().addingTimeInterval(-60), revision: UUID()), workoutID: UUID()) }
        try await store.save(.init(value: 10, confirmedAt: Date(), revision: UUID()), workoutID: id)
        XCTAssertEqual(try store.history(excluding: id).count, 5)
        XCTAssertTrue(try FileWorkoutEffortStore(scopeDirectory: root.appendingPathComponent("b")).history(excluding: id).isEmpty)
        let editor = WorkoutEffortEditor(workoutID: id, store: store)
        await editor.load(); editor.begin()
        XCTAssertEqual(editor.usualRange?.upper, 6)
        editor.preview(2); editor.cancel()
        XCTAssertEqual(try store.load(workoutID: id)?.value, 10)
    }
    func testUnavailableHistoryDoesNotBlockEditingOrInventRange() async {
        let store = FixtureWorkoutEffortStore(); store.failsHistory = true
        let editor = WorkoutEffortEditor(workoutID: UUID(), store: store)
        await editor.load(); editor.begin(); editor.preview(8)
        XCTAssertNil(editor.usualRange); XCTAssertTrue(editor.historyUnavailable)
        XCTAssertTrue(editor.canSave)
        let saved = await editor.save(); XCTAssertTrue(saved)
    }
}

extension WorkoutEffortHapticPolicyTests {
    func testTwelveIntermediatePointsAndOneStrongIntegerInEachInterval() {
        for start in 1...9 {
            var policy = WorkoutEffortHapticPolicy(); policy.begin(Double(start))
            for point in 1...12 {
                XCTAssertEqual(policy.update(Double(start) + Double(point) / 13, at: Double(point) * 0.1, reduced: false), .movement)
            }
            XCTAssertEqual(policy.update(Double(start + 1), at: 1.4, reduced: false), .step)
            XCTAssertNil(policy.update(Double(start + 1), at: 2, reduced: false))
        }
    }
    func testReverseGridAndFastJumpHaveNoBurstOrStationaryReplay() {
        var policy = WorkoutEffortHapticPolicy(); policy.begin(5)
        for point in 1...12 {
            XCTAssertEqual(policy.update(5 - Double(point) / 13, at: Double(point) * 0.1, reduced: false), .movement)
        }
        XCTAssertEqual(policy.update(4, at: 1.4, reduced: false), .step)
        XCTAssertNil(policy.update(4.001, at: 2, reduced: false))
        XCTAssertEqual(policy.update(10, at: 3, reduced: false), .step)
        XCTAssertNil(policy.update(10, at: 4, reduced: false))
        XCTAssertNil(policy.update(1, at: 3.001, reduced: false))
        XCTAssertNil(policy.update(1, at: 5, reduced: false))
    }
    func testRevealConsumptionSurvivesViewReentryAndResetsOnlyClosedGroup() {
        let store = WorkoutDetailPresentationStore(), id = UUID(), other = UUID()
        let first = WorkoutRevealContext(store: store, workoutID: id)
        XCTAssertTrue(first.claim("charts.heartRate"))
        XCTAssertTrue(first.claim("splits.0"))
        XCTAssertTrue(first.claim("zones.Z1"))
        let recreated = WorkoutRevealContext(store: store, workoutID: id)
        XCTAssertFalse(recreated.claim("charts.heartRate"))
        recreated.reset("charts.")
        XCTAssertTrue(recreated.claim("charts.heartRate"))
        XCTAssertFalse(recreated.claim("splits.0"))
        XCTAssertFalse(recreated.claim("zones.Z1"))
        XCTAssertTrue(WorkoutRevealContext(store: store, workoutID: other).claim("charts.heartRate"))
        XCTAssertTrue(WorkoutRevealContext(store: WorkoutDetailPresentationStore(), workoutID: id).claim("charts.heartRate"))
        store.clear(); XCTAssertTrue(first.claim("charts.heartRate"))
    }
    func testStandardSheetLeavesMoreThanHalfOfMapAtEveryPhoneHeight() {
        XCTAssertEqual(WorkoutSheetMetrics.standardHeight(viewportHeight: 0), 0)
        XCTAssertEqual(WorkoutSheetMetrics.standardHeight(viewportHeight: 1), 0.48, accuracy: 0.001)
        for height in [CGFloat(480), 568, 667, 812, 852, 932, 1024] {
            let sheet = WorkoutSheetMetrics.standardHeight(viewportHeight: height)
            XCTAssertLessThanOrEqual(sheet / height, 0.48)
            XCTAssertGreaterThan(sheet, 190)
            let padding = WorkoutRouteCameraPadding.padding(for: .standard, sheetHeight: sheet,
                safeAreaInsets: .init(top: 47, leading: 0, bottom: 34, trailing: 0))
            XCTAssertEqual(padding.bottom, sheet + 68)
            XCTAssertEqual(padding.top, 159)
        }
    }
}


@MainActor
private final class AcceptanceEffortStore: WorkoutEffortStoring, WorkoutEffortReading {
    var loads = 0, reads = 0, histories = 0
    var suspend = true
    var gate: CheckedContinuation<WorkoutEffortObservation?, Error>?
    func load(workoutID: UUID) throws -> WorkoutEffortConfirmation? { loads += 1; return nil }
    func history(excluding workoutID: UUID) throws -> [WorkoutEffortConfirmation] { histories += 1; return [] }
    func save(_ value: WorkoutEffortConfirmation, workoutID: UUID) async throws {}
    func observation(workoutID: UUID) async throws -> WorkoutEffortObservation? {
        reads += 1
        if suspend { suspend = false; return try await withCheckedThrowingContinuation { gate = $0 } }
        return nil
    }
}

extension WorkoutEffortTests {
    func testConcurrentInitialEffortLoadAndRepeatedAppearanceCountOnce() async {
        let store = AcceptanceEffortStore()
        let editor = WorkoutEffortEditor(workoutID: UUID(), store: store, reader: store)
        let first = Task { await editor.load() }
        while store.gate == nil { await Task.yield() }
        await editor.load()
        let pendingLoads = store.loads, pendingReads = store.reads
        store.gate?.resume(returning: nil); store.gate = nil
        await first.value
        XCTAssertEqual(pendingLoads, 1)
        XCTAssertEqual(pendingReads, 1)
        for _ in 0..<100 { await editor.load(); _ = editor.displayedValue }
        XCTAssertEqual(store.loads, 1); XCTAssertEqual(store.reads, 1); XCTAssertEqual(store.histories, 1)
        editor.begin(); editor.preview(6); editor.cancel(); editor.begin(); editor.cancel()
        XCTAssertEqual(store.loads, 1); XCTAssertEqual(store.reads, 1)
        XCTAssertEqual(store.histories, 3, "Explicit editor opens refresh only local usual-range history")
    }
    func testEffortFailedInitialReadCanRetryAndNewEditorReadsItsOwnStore() async {
        let store = AcceptanceEffortStore(), id = UUID()
        let editor = WorkoutEffortEditor(workoutID: id, store: store, reader: store)
        let first = Task { await editor.load() }
        while store.gate == nil { await Task.yield() }
        store.gate?.resume(throwing: CocoaError(.fileReadUnknown)); store.gate = nil
        await first.value
        XCTAssertNotNil(editor.error); XCTAssertEqual(store.reads, 1)
        await editor.load(); XCTAssertNil(editor.error); XCTAssertEqual(store.reads, 2)
        let recreated = WorkoutEffortEditor(workoutID: id, store: store, reader: store)
        await recreated.load(); XCTAssertEqual(store.reads, 3, "New editor lifetime intentionally reads persistent state")
        let otherStore = AcceptanceEffortStore(); otherStore.suspend = false
        await WorkoutEffortEditor(workoutID: id, store: otherStore, reader: otherStore).load()
        XCTAssertEqual(otherStore.reads, 1); XCTAssertEqual(store.reads, 3)
    }
}


extension WorkoutEffortHapticPolicyTests {
    func testAcceptanceRevealClaimsDoNotReplayAcrossOneHundredRecreations() {
        let store = WorkoutDetailPresentationStore(), workout = UUID()
        let keys = ["charts.heartRate", "charts.speed", "zones.Z1", "splits.0", "sections.1"]
        var plays = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
        for _ in 0..<100 {
            let recreated = WorkoutRevealContext(store: store, workoutID: workout)
            for key in keys where recreated.claim(key) { plays[key, default: 0] += 1 }
        }
        XCTAssertTrue(plays.values.allSatisfy { $0 == 1 })
        let context = WorkoutRevealContext(store: store, workoutID: workout)
        context.reset("charts.")
        for key in keys where context.claim(key) { plays[key, default: 0] += 1 }
        XCTAssertEqual(plays["charts.heartRate"], 2); XCTAssertEqual(plays["charts.speed"], 2)
        XCTAssertEqual(plays["zones.Z1"], 1); XCTAssertEqual(plays["splits.0"], 1)
        store.clear(); XCTAssertTrue(context.claim("charts.heartRate"))
    }
}


extension WorkoutEffortHapticPolicyTests {
    func testIntegerPulseSurvivesQuietPulseTenMillisecondsEarlier() {
        var policy = WorkoutEffortHapticPolicy(); policy.begin(2.8)
        XCTAssertEqual(policy.update(2.9, at: 0, reduced: false), .movement)
        XCTAssertEqual(policy.update(3, at: 0.010, reduced: false), .step)
        XCTAssertNil(policy.update(3, at: 1, reduced: false))
    }
    func testThirteenGridPointsAtSixtyHzBothDirectionsAndWithReducedMotion() {
        for reduced in [false, true] {
            for direction in [-1.0, 1.0] {
                var policy = WorkoutEffortHapticPolicy(); let start = direction > 0 ? 4.0 : 5.0
                policy.begin(start)
                for point in 1...13 {
                    XCTAssertEqual(policy.update(start + direction * Double(point) / 13,
                        at: Double(point) / 60, reduced: reduced), point == 13 ? .step : .movement)
                }
            }
        }
    }
}

@MainActor
final class WorkoutEffortHapticDeliveryTests: XCTestCase {
    func testPreparedDriverReceivesTicksStopsWhileInactiveAndRestartsOnce() {
        let driver = EffortHapticSpy(); var now = 0.0; var active = true
        let haptics = WorkoutEffortHaptics(player: driver, clock: { now }, isActive: { active })
        haptics.prepare(); haptics.begin(2.8)
        haptics.move(2.9, reduced: false); now = 0.01; haptics.move(3, reduced: false)
        XCTAssertEqual(driver.pulses, [.movement, .step])
        XCTAssertGreaterThan(driver.intensities[1], driver.intensities[0])
        active = false; haptics.move(4, reduced: false)
        active = true; now = 1; haptics.move(5, reduced: false)
        XCTAssertEqual(driver.pulses.count, 2, "No stale gesture after interruption")
        haptics.begin(5); now = 2; haptics.move(6, reduced: true); haptics.end()
        now = 3; haptics.move(7, reduced: false)
        XCTAssertEqual(driver.pulses, [.movement, .step, .step]); XCTAssertGreaterThanOrEqual(driver.prepares, 3)
    }
}

@MainActor
private final class EffortHapticSpy: WorkoutEffortHapticPlaying {
    var prepares = 0
    var pulses: [WorkoutEffortHapticPolicy.Pulse] = []
    var intensities: [Double] = []
    func prepare() { prepares += 1 }
    func play(_ pulse: WorkoutEffortHapticPolicy.Pulse, intensity: Double) { pulses.append(pulse); intensities.append(intensity) }
    func end() {}
}

@MainActor
final class WorkoutEffortGestureOwnershipTests: XCTestCase {
    private func hierarchy() -> (UIView, UIPanGestureRecognizer, UIScrollView, EffortTouchView) {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let sheetPan = UIPanGestureRecognizer(); parent.addGestureRecognizer(sheetPan)
        let scroll = UIScrollView(frame: parent.bounds); scroll.contentSize = CGSize(width: 400, height: 1400)
        parent.addSubview(scroll)
        let score = EffortTouchView(frame: CGRect(x: 20, y: 300, width: 360, height: 148)); scroll.addSubview(score)
        return (parent, sheetPan, scroll, score)
    }
    func testScoreTouchOwnsNativeAncestorPansButNotSiblingGesturesAndRestoresAfterEnd() {
        let (parent, sheetPan, scroll, score) = hierarchy()
        let sibling = UIView(), siblingPan = UIPanGestureRecognizer(); sibling.addGestureRecognizer(siblingPan); parent.addSubview(sibling)
        var ended = 0; score.onEnd = { ended += 1 }
        score.beginScorePan(); score.beginScorePan()
        XCTAssertTrue(score.isTrackingScore)
        XCTAssertFalse(sheetPan.isEnabled); XCTAssertFalse(scroll.panGestureRecognizer.isEnabled)
        XCTAssertTrue(siblingPan.isEnabled)
        XCTAssertTrue(score.gestureRecognizers!.allSatisfy(\.isEnabled))
        score.cancelInteraction()
        XCTAssertFalse(score.isTrackingScore); XCTAssertTrue(sheetPan.isEnabled); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        XCTAssertTrue(siblingPan.isEnabled); XCTAssertEqual(ended, 1)
        score.cancelInteraction(); XCTAssertEqual(ended, 1)
        withExtendedLifetime(parent) {}
    }
    func testPreviouslyDisabledParentPanStaysDisabledAndReentryCanOwnAgain() {
        let (parent, sheetPan, scroll, score) = hierarchy(); sheetPan.isEnabled = false
        score.beginScorePan(); score.cancelInteraction()
        XCTAssertFalse(sheetPan.isEnabled); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        score.beginScorePan(); XCTAssertFalse(scroll.panGestureRecognizer.isEnabled)
        score.cancelInteraction(); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled); XCTAssertFalse(sheetPan.isEnabled)
        withExtendedLifetime(parent) {}
    }
    func testDetachAndDisabledInteractionReleaseNativePansWithoutWaitingForTouchEnd() {
        let (parent, sheetPan, scroll, score) = hierarchy()
        score.beginScorePan(); score.removeFromSuperview()
        XCTAssertFalse(score.isTrackingScore); XCTAssertTrue(sheetPan.isEnabled); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        scroll.addSubview(score); score.beginScorePan(); score.acceptsTouches = false
        XCTAssertFalse(score.isTrackingScore); XCTAssertFalse(score.isUserInteractionEnabled)
        XCTAssertTrue(sheetPan.isEnabled); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        score.beginScorePan(); XCTAssertFalse(score.isTrackingScore)
        score.acceptsTouches = true; score.beginScorePan(); XCTAssertTrue(score.isTrackingScore)
        score.cancelInteraction(); withExtendedLifetime(parent) {}
    }
    func testWindowLossAndSimultaneousRecognizerPolicyCannotLeaveParentLocked() {
        let (parent, sheetPan, scroll, score) = hierarchy()
        let childPan = score.gestureRecognizers!.first!
        XCTAssertFalse(score.gestureRecognizer(childPan, shouldRecognizeSimultaneouslyWith: sheetPan))
        var evidence: EffortGestureEvidence?; score.onEvidence = { evidence = $0 }
        score.beginScorePan(); score.didMoveToWindow()
        XCTAssertTrue(sheetPan.isEnabled); XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        XCTAssertEqual(evidence?.ancestorPans, evidence?.restoredPans); XCTAssertTrue(evidence?.cancelled == true)
        withExtendedLifetime(parent) {}
    }
}

@MainActor
final class WorkoutEffortDirectionPriorityTests: XCTestCase {
    func testRawTouchDoesNotDisableScrollingAndPriorityIsLimitedToAncestorPans() {
        let parent = UIView(), scroll = UIScrollView(), score = EffortTouchView()
        parent.addSubview(scroll); scroll.addSubview(score)
        let parentPan = UIPanGestureRecognizer(); parent.addGestureRecognizer(parentPan)
        let unrelated = UIView(), unrelatedPan = UIPanGestureRecognizer(); unrelated.addGestureRecognizer(unrelatedPan)
        let childPan = score.gestureRecognizers!.first!
        score.beginInteraction()
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled); XCTAssertTrue(parentPan.isEnabled)
        XCTAssertTrue(score.gestureRecognizer(childPan, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
        XCTAssertTrue(score.gestureRecognizer(childPan, shouldBeRequiredToFailBy: parentPan))
        XCTAssertFalse(score.gestureRecognizer(childPan, shouldBeRequiredToFailBy: unrelatedPan))
        score.cancelInteraction()
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled); XCTAssertTrue(parentPan.isEnabled)
        withExtendedLifetime((parent, unrelated)) {}
    }
}

@MainActor
final class WorkoutEffortReactivationTests: XCTestCase {
    func testReactivationRestoresOwnRecognizerAfterInterruptedControlWasDisabled() {
        let parent = UIScrollView(), score = EffortTouchView()
        parent.addSubview(score)
        let ownPan = score.gestureRecognizers!.first!
        score.beginScorePan(); score.acceptsTouches = false
        XCTAssertFalse(score.isTrackingScore); XCTAssertFalse(ownPan.isEnabled)
        XCTAssertTrue(parent.panGestureRecognizer.isEnabled)
        score.acceptsTouches = true
        XCTAssertTrue(ownPan.isEnabled); XCTAssertTrue(score.isUserInteractionEnabled)
        score.beginScorePan(); XCTAssertTrue(score.isTrackingScore)
        XCTAssertFalse(parent.panGestureRecognizer.isEnabled)
        score.cancelInteraction(); XCTAssertTrue(parent.panGestureRecognizer.isEnabled)
    }
}
