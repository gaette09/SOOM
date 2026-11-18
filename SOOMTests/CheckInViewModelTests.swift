import XCTest
@testable import SOOM

@MainActor
final class CheckInViewModelTests: XCTestCase {
    func testSaveAppendsCheckInToMockStore() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MockRecoveryCheckInStore(referenceDate: referenceDate, checkIns: [])
        let viewModel = CheckInViewModel(
            store: store,
            now: { referenceDate }
        )

        viewModel.fatigueLevel = 4
        viewModel.sleepQuality = 2
        viewModel.muscleSoreness = 3
        viewModel.moodLevel = 5
        viewModel.note = "  다리가 조금 무거움  "

        await viewModel.save()

        let savedCheckIns = try await store.fetchRecentCheckIns(days: 1)
        XCTAssertEqual(savedCheckIns.count, 1)
        XCTAssertEqual(savedCheckIns.first?.fatigueLevel, 4)
        XCTAssertEqual(savedCheckIns.first?.sleepQuality, 2)
        XCTAssertEqual(savedCheckIns.first?.muscleSoreness, 3)
        XCTAssertEqual(savedCheckIns.first?.moodLevel, 5)
        XCTAssertEqual(savedCheckIns.first?.note, "다리가 조금 무거움")
        XCTAssertEqual(viewModel.confirmationMessage, "오늘의 회복 해석이 더 정확해졌어요.")
    }
}

private actor ControlledCheckInDraftStore: RecoveryCheckInEditableStore {
    var attempts: [RecoveryCheckIn] = []
    var records: [UUID: RecoveryCheckIn] = [:]
    var failures: Int
    var delayed: Bool
    var waiter: CheckedContinuation<Void, Never>?
    init(failures: Int = 0, delayed: Bool = false) { self.failures = failures; self.delayed = delayed }
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] { Array(records.values) }
    func saveCheckIn(_ value: RecoveryCheckIn) async throws {
        attempts.append(value)
        if delayed { await withCheckedContinuation { waiter = $0 } }
        if failures > 0 { failures -= 1; throw CocoaError(.fileWriteUnknown) }
        records[value.id] = value
    }
    func updateCheckIn(_ value: RecoveryCheckIn) async throws { try await saveCheckIn(value) }
    func deleteCheckIn(id: UUID) async throws { records.removeValue(forKey: id) }
    func deleteAllCheckIns() async throws { records = [:] }
    func release() { delayed = false; waiter?.resume(); waiter = nil }
    var calls: Int { attempts.count }
}

@MainActor
final class CheckInFormDraftRegressionTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    func testCompletedDraftCannotSaveTwiceButChangedInputAndNewFormCanSave() async throws {
        let store = ControlledCheckInDraftStore()
        let model = CheckInViewModel(store: store, now: { self.day })
        model.fatigueLevel = 1; model.sleepQuality = 5; model.muscleSoreness = 2; model.moodLevel = 4; model.note = "  QA note  "
        await model.save(); XCTAssertTrue(model.hasSavedCurrentInput); XCTAssertFalse(model.canSave)
        await model.save(); let firstCount = await store.calls; XCTAssertEqual(firstCount, 1)
        model.note = "new note"; XCTAssertTrue(model.canSave)
        await model.save(); let changedCount = await store.calls; XCTAssertEqual(changedCount, 2)
        let next = CheckInViewModel(store: store, now: { self.day.addingTimeInterval(86400) })
        await next.save(); let rows = try await store.fetchRecentCheckIns(days: 7)
        XCTAssertEqual(rows.count, 3); XCTAssertTrue(rows.contains { $0.date == day.addingTimeInterval(86400) })
    }
    func testFailedDraftPreservesAllFieldsAndRetryReusesUUID() async throws {
        let store = ControlledCheckInDraftStore(failures: 1)
        let model = CheckInViewModel(store: store, now: { self.day })
        model.fatigueLevel = 2; model.sleepQuality = 4; model.muscleSoreness = 1; model.moodLevel = 5; model.note = "  same note  "
        await model.save(); XCTAssertNotNil(model.errorMessage); XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.note, "  same note  "); XCTAssertEqual(model.fatigueLevel, 2); XCTAssertEqual(model.sleepQuality, 4)
        XCTAssertEqual(model.muscleSoreness, 1); XCTAssertEqual(model.moodLevel, 5)
        await model.save(); let attempts = await store.attempts
        XCTAssertEqual(attempts.count, 2); XCTAssertEqual(attempts[0].id, attempts[1].id)
        XCTAssertEqual(attempts[1].note, "same note"); XCTAssertNil(model.errorMessage); XCTAssertNotNil(model.confirmationMessage)
        let rows = try await store.fetchRecentCheckIns(days: 1); XCTAssertEqual(rows.count, 1)
    }
    func testPendingSaveRejectsDuplicateAndLateSuccessCannotChangeDepartedForm() async {
        let store = ControlledCheckInDraftStore(delayed: true)
        let model = CheckInViewModel(store: store, now: { self.day })
        let task = Task { await model.save() }
        for _ in 0..<1000 { if await store.calls == 1 { break }; await Task.yield() }
        XCTAssertTrue(model.isSaving); await model.save(); let calls = await store.calls; XCTAssertEqual(calls, 1)
        model.stopPresenting(); await store.release(); await task.value
        XCTAssertNil(model.confirmationMessage); XCTAssertNil(model.errorMessage); XCTAssertFalse(model.isSaving)
        let fresh = CheckInViewModel(store: store, now: { self.day }); XCTAssertNil(fresh.confirmationMessage)
    }
    func testEditFailureRetryKeepsIdentityDateAndFields() async throws {
        let store = ControlledCheckInDraftStore(failures: 1)
        let original = RecoveryCheckIn(date: day, fatigueLevel: 3, sleepQuality: 3, muscleSoreness: 2, moodLevel: 3, note: "before")
        let model = CheckInEditViewModel(checkIn: original, store: store)
        model.fatigueLevel = 5; model.sleepQuality = 1; model.muscleSoreness = 4; model.moodLevel = 2; model.note = "  edit note  "
        let failed = await model.save(); XCTAssertNil(failed); XCTAssertNotNil(model.errorMessage); XCTAssertTrue(model.canSave)
        let result = await model.save(); let saved = try XCTUnwrap(result)
        XCTAssertEqual(saved.id, original.id); XCTAssertEqual(saved.date, day); XCTAssertEqual(saved.note, "edit note")
        XCTAssertEqual(saved.fatigueLevel, 5); XCTAssertEqual(saved.sleepQuality, 1); XCTAssertEqual(saved.muscleSoreness, 4); XCTAssertEqual(saved.moodLevel, 2)
    }
    func testLateEditFailureCannotPublishAfterDeparture() async {
        let store = ControlledCheckInDraftStore(failures: 1, delayed: true)
        let model = CheckInEditViewModel(checkIn: .init(date: day, fatigueLevel: 3, sleepQuality: 3, muscleSoreness: 2, moodLevel: 3), store: store)
        let task = Task { await model.save() }
        for _ in 0..<1000 { if await store.calls == 1 { break }; await Task.yield() }
        model.stopPresenting(); await store.release(); let saved = await task.value
        XCTAssertNil(saved); XCTAssertNil(model.errorMessage); XCTAssertNil(model.confirmationMessage)
    }
}

@MainActor
extension CheckInFormDraftRegressionTests {
    func testSameFormNextDayAllowsANewDailyRecordWithoutLosingOldInput() async throws {
        let store = ControlledCheckInDraftStore(); var current = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CheckInViewModel(store: store, now: { current })
        model.note = "daily note"; await model.save(); XCTAssertFalse(model.canSave)
        current = Calendar.current.date(byAdding: .day, value: 1, to: current)!
        model.refreshForCurrentDay(); XCTAssertTrue(model.canSave); XCTAssertEqual(model.note, "daily note")
        await model.save(); let rows = try await store.fetchRecentCheckIns(days: 7)
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        XCTAssertTrue(rows.contains { $0.date == current })
    }
}
