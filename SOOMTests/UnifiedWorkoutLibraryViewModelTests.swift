import SwiftUI
import UIKit
import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutLibraryViewModelTests: XCTestCase {
    func testLoadRecentWorkoutsPopulatesWorkouts() async {
        let workouts = [
            makeWorkout(type: .running),
            makeWorkout(type: .cycling)
        ]
        let store = FakeUnifiedWorkoutLibraryStore(workouts: workouts)
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts, workouts)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadRecentWorkoutsKeepsEmptyState() async {
        let viewModel = UnifiedWorkoutLibraryViewModel(
            store: FakeUnifiedWorkoutLibraryStore(workouts: [])
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStoreFailureSetsErrorMessage() async {
        let viewModel = UnifiedWorkoutLibraryViewModel(
            store: FakeUnifiedWorkoutLibraryStore(error: SampleError.fetchFailed)
        )

        await viewModel.loadRecentWorkouts()

        XCTAssertTrue(viewModel.workouts.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testUsesThirtyDaysAsDefaultRecentRange() async {
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(store.requestedDays, 30)
    }

    func testExcludesDirectRecordWorkoutsFromImportedLibrary() async {
        let importedWorkout = makeWorkout(type: .running, source: .appleHealthKit)
        let directWorkout = makeWorkout(type: .cycling, source: .soomLocal)
        let manualWorkout = makeWorkout(type: .walking, source: .manual)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [importedWorkout, directWorkout, manualWorkout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts, [importedWorkout])
    }

    func testPreservesExcludedFromAnalysisState() async {
        let excludedWorkout = makeWorkout(type: .swimming, isExcludedFromAnalysis: true)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [excludedWorkout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()

        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, true)
    }

    func testToggleExcludedMarksWorkoutExcluded() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(store.markedExclusionState[workout.id], true)
        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleExcludedMarksWorkoutIncluded() async {
        let workout = makeWorkout(type: .cycling, isExcludedFromAnalysis: true)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(store.markedExclusionState[workout.id], false)
        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, false)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleExcludedFailureSetsErrorMessage() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(
            workouts: [workout],
            markError: SampleError.markFailed
        )
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertEqual(viewModel.workouts.first?.isExcludedFromAnalysis, false)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testToggleExcludedDoesNotDeleteOrMergeWorkouts() async {
        let workout = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)

        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        XCTAssertFalse(store.didDeleteWorkout)
        XCTAssertFalse(store.didSaveWorkout)
        XCTAssertFalse(store.didSaveWorkouts)
    }

    func testToggleExcludedPreservesAllWorkoutAndCardMetadata() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = UnifiedWorkout(
            id: UUID(), externalId: "imported-session", source: .strava, workoutType: .cycling,
            startDate: start, endDate: start.addingTimeInterval(3_600), durationSeconds: 3_600,
            distanceMeters: 20_000, activeEnergyKcal: 450, averageHeartRate: 145, maxHeartRate: 170,
            averageSpeedMetersPerSecond: 5.5, elevationGainMeters: 200,
            averagePowerWatts: 180, averageCadence: 85, routeMissingReason: .externalSourceRouteNotShared,
            dataQuality: .partial, createdAt: start, updatedAt: start,
            companionNames: ["민수"], userTitle: "한강 라이딩", userDescription: "강변을 따라 달렸어요.",
            sharingVisibilityRaw: "public", isBookmarked: true, deviceName: "Garmin Edge", locationName: "서울 영등포구")
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [workout])
        let viewModel = UnifiedWorkoutLibraryViewModel(store: store)
        await viewModel.loadRecentWorkouts()
        await viewModel.toggleExcluded(id: workout.id)

        let result = try XCTUnwrap(viewModel.workouts.first)
        XCTAssertTrue(result.isExcludedFromAnalysis)
        XCTAssertNotEqual(result.updatedAt, workout.updatedAt)
        // Exclusion and its modification time are the only permitted changes,
        // including future Codable metadata fields added to UnifiedWorkout.
        func preservedFields(_ value: UnifiedWorkout) throws -> NSDictionary {
            var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            fields.removeValue(forKey: "isExcludedFromAnalysis")
            fields.removeValue(forKey: "updatedAt")
            return fields as NSDictionary
        }
        XCTAssertEqual(try preservedFields(result), try preservedFields(workout))
        XCTAssertEqual(store.markedExclusionState[workout.id], true)
    }

    func makeWorkout(
        type: UnifiedWorkoutType,
        source: UnifiedDataSource = .appleHealthKit,
        isExcludedFromAnalysis: Bool = false
    ) -> UnifiedWorkout {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(45 * 60)

        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: 45 * 60,
            distanceMeters: 10_000,
            activeEnergyKcal: 500,
            averageHeartRate: 145,
            maxHeartRate: 168,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 70,
            dataQuality: .partial,
            isExcludedFromAnalysis: isExcludedFromAnalysis,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private final class FakeUnifiedWorkoutLibraryStore: UnifiedWorkoutStore {
    var workouts: [UnifiedWorkout]
    var error: Error?
    var continuation: CheckedContinuation<[UnifiedWorkout], Never>?
    var suspendsNext = false
    var failSuspendedFetch = false
    var fetchCount = 0
    private let markError: Error?
    private(set) var requestedDays: Int?
    private(set) var markedExclusionState: [UUID: Bool] = [:]
    private(set) var didDeleteWorkout = false
    private(set) var didSaveWorkout = false
    private(set) var didSaveWorkouts = false

    init(
        workouts: [UnifiedWorkout] = [],
        error: Error? = nil,
        markError: Error? = nil
    ) {
        self.workouts = workouts
        self.error = error
        self.markError = markError
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        didSaveWorkout = true
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        didSaveWorkouts = true
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        requestedDays = days
        fetchCount += 1
        if suspendsNext {
            suspendsNext = false
            let snapshot = await withCheckedContinuation { continuation = $0 }
            if failSuspendedFetch { failSuspendedFetch = false; throw SampleError.fetchFailed }
            return snapshot
        }

        if let error {
            throw error
        }

        return workouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {
        if let markError {
            throw markError
        }

        markedExclusionState[id] = isExcluded
    }

    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        didDeleteWorkout = true
    }

    func deleteAllWorkouts() async throws {}
}

private enum SampleError: Error {
    case fetchFailed
    case markFailed
}

extension UnifiedWorkoutLibraryViewModelTests {
    func testFailedRefreshKeepsPreviousRecordsAndRetryRecovers() async {
        let old = makeWorkout(type: .running), fresh = makeWorkout(type: .cycling)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [old])
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        await model.loadRecentWorkouts(); store.error = SampleError.fetchFailed
        await model.loadRecentWorkouts()
        XCTAssertEqual(model.workouts, [old]); XCTAssertNotNil(model.errorMessage)
        store.error = nil; store.workouts = [fresh]
        await model.loadRecentWorkouts()
        XCTAssertEqual(model.workouts, [fresh]); XCTAssertNil(model.errorMessage)
    }
    func testMutationDuringSnapshotQueuesOneFreshFollowUpAndReentryDoesNot() async {
        let old = makeWorkout(type: .running), fresh = makeWorkout(type: .cycling)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [old]); store.suspendsNext = true
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        let first = Task { await model.loadRecentWorkouts() }
        while store.continuation == nil { await Task.yield() }
        await model.loadRecentWorkouts()
        XCTAssertEqual(store.fetchCount, 1)
        store.workouts = [fresh]
        await model.loadRecentWorkouts(requiresFollowUp: true)
        await model.loadRecentWorkouts(requiresFollowUp: true)
        store.continuation?.resume(returning: [old]); store.continuation = nil
        await first.value
        XCTAssertEqual(store.fetchCount, 2); XCTAssertEqual(model.workouts, [fresh]); XCTAssertFalse(model.isLoading)
    }
}

extension UnifiedWorkoutLibraryViewModelTests {
    func testQueuedSuccessClearsFailureFromPreviousFetch() async {
        let fresh = makeWorkout(type: .running)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [fresh])
        store.suspendsNext = true; store.failSuspendedFetch = true
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        let first = Task { await model.loadRecentWorkouts() }
        while store.continuation == nil { await Task.yield() }
        await model.loadRecentWorkouts(requiresFollowUp: true)
        store.continuation?.resume(returning: []); store.continuation = nil
        await first.value
        XCTAssertEqual(store.fetchCount, 2); XCTAssertEqual(model.workouts, [fresh]); XCTAssertNil(model.errorMessage)
    }
}


extension UnifiedWorkoutLibraryViewModelTests {
    func testInitialRevisionReentryPullAndMutationHaveExplicitReadCounts() async {
        let item = makeWorkout(type: .running), store = FakeUnifiedWorkoutLibraryStore()
        store.workouts = [item]
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        await model.loadIfNeeded(revision: 0); XCTAssertEqual(store.fetchCount, 1)
        for _ in 0..<100 { await model.loadIfNeeded(revision: 0); _ = model.workouts }
        XCTAssertEqual(store.fetchCount, 1); XCTAssertEqual(model.workouts, [item])
        await model.loadRecentWorkouts(); XCTAssertEqual(store.fetchCount, 2, "Pull refresh")
        await model.loadRecentWorkouts(requiresFollowUp: true); XCTAssertEqual(store.fetchCount, 3, "Record mutation")
        await model.loadIfNeeded(revision: 1); XCTAssertEqual(store.fetchCount, 4, "Changed local data revision")
        await model.loadIfNeeded(revision: 1); XCTAssertEqual(store.fetchCount, 4)
        let reopened = UnifiedWorkoutLibraryViewModel(store: store)
        await reopened.loadIfNeeded(revision: 1)
        XCTAssertEqual(store.fetchCount, 5, "Dismissed/recreated model intentionally has no global cache")
    }
    func testRevisionChangeDuringReadQueuesOnceAndFirstFailureDoesNotStampCache() async {
        let store = FakeUnifiedWorkoutLibraryStore()
        store.suspendsNext = true
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        let first = Task { await model.loadIfNeeded(revision: 0) }
        while store.continuation == nil { await Task.yield() }
        await model.loadIfNeeded(revision: 0); XCTAssertEqual(store.fetchCount, 1)
        await model.loadIfNeeded(revision: 1); await model.loadIfNeeded(revision: 1)
        store.continuation?.resume(returning: []); store.continuation = nil
        await first.value
        XCTAssertEqual(store.fetchCount, 2)
        await model.loadIfNeeded(revision: 1); XCTAssertEqual(store.fetchCount, 2)
        let failedStore = FakeUnifiedWorkoutLibraryStore(error: SampleError.fetchFailed)
        let failed = UnifiedWorkoutLibraryViewModel(store: failedStore)
        await failed.loadIfNeeded(revision: 7); XCTAssertNotNil(failed.errorMessage)
        failedStore.error = nil; await failed.loadIfNeeded(revision: 7)
        XCTAssertEqual(failedStore.fetchCount, 2); XCTAssertNil(failed.errorMessage)
        await failed.loadIfNeeded(revision: 7); XCTAssertEqual(failedStore.fetchCount, 2)
    }
}


extension UnifiedWorkoutLibraryViewModelTests {
    func testNativeLibraryLoadingEmptyErrorRetryAndRetainedListUseOneOriginalView() async throws {
        // Production view + production VM + fake local store; not root navigation,
        // a HealthKit import, or an operational service test.
        let demo = ReviewDemoController.shared; demo.start(); defer { demo.exit() }
        let runtime = try XCTUnwrap(demo.runtime)
        let store = FakeUnifiedWorkoutLibraryStore(workouts: [])
        store.suspendsNext = true
        let model = UnifiedWorkoutLibraryViewModel(store: store)
        let loading = Task { await model.loadIfNeeded(revision: 0) }
        for _ in 0..<100 { if store.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(store.continuation); XCTAssertTrue(model.isLoading)
        let root = NavigationStack { UnifiedWorkoutLibraryView(viewModel: model) }
            .environmentObject(runtime.auth).environmentObject(runtime.storage)
            .modelContainer(runtime.storage.container)
        let host = UIHostingController(rootView: root); host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; window.layoutIfNeeded()
        func captureState(_ name: String) async throws {
            try await Task.sleep(for: .milliseconds(180)); host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "F production library native " + name + " synthetic store NOT whole-root proof"; attachment.lifetime = .keepAlways; add(attachment)
        }
        try await captureState("loading")
        XCTAssertEqual(store.fetchCount, 1, "Rendering/repeated loadIfNeeded must not duplicate the pending request")
        store.continuation?.resume(returning: []); store.continuation = nil; await loading.value
        XCTAssertFalse(model.isLoading); XCTAssertTrue(model.workouts.isEmpty); XCTAssertNil(model.errorMessage)
        try await captureState("true empty after completed load")
        store.error = SampleError.fetchFailed; await model.loadRecentWorkouts()
        XCTAssertEqual(store.fetchCount, 2); XCTAssertNotNil(model.errorMessage)
        try await captureState("failed read distinct from empty")
        store.error = nil; let workout = makeWorkout(type: .running); store.workouts = [workout]
        await model.loadRecentWorkouts()
        XCTAssertEqual(store.fetchCount, 3); XCTAssertNil(model.errorMessage); XCTAssertEqual(model.workouts.map(\.id), [workout.id])
        try await captureState("retry restored list")
        store.error = SampleError.fetchFailed; await model.loadRecentWorkouts()
        XCTAssertEqual(store.fetchCount, 4); XCTAssertEqual(model.workouts.map(\.id), [workout.id]); XCTAssertNotNil(model.errorMessage)
        try await captureState("refresh error preserves existing list")
        XCTAssertFalse(store.didDeleteWorkout); XCTAssertFalse(store.didSaveWorkout); XCTAssertFalse(store.didSaveWorkouts)
    }
}
