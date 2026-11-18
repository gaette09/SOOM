import SwiftUI
import SwiftData
import UIKit
import XCTest
@testable import SOOM

@MainActor
final class UnifiedWorkoutDuplicateReviewViewModelTests: XCTestCase {
    func testLoadCreatesDuplicateCandidates() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(source: .garmin, startDate: startDate, externalId: "garmin-ride"),
            makeWorkout(source: .appleHealthKit, startDate: startDate.addingTimeInterval(120), externalId: "health-ride")
        ]
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertEqual(viewModel.candidates.first?.preferredSource, .garmin)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadKeepsEmptyStateWhenThereAreNoDuplicates() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(type: .running, source: .appleHealthKit, startDate: startDate, distanceMeters: 10_000),
            makeWorkout(type: .cycling, source: .garmin, startDate: startDate.addingTimeInterval(3_600), distanceMeters: 42_000)
        ]
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(
            store: FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        )

        await viewModel.loadDuplicateCandidates()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStoreFailureSetsErrorMessage() async {
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(
            store: FakeUnifiedWorkoutDuplicateReviewStore(error: SampleError.fetchFailed)
        )

        await viewModel.loadDuplicateCandidates()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.errorTitle, "중복 후보를 불러오지 못했어요")
    }

    func testUsesNinetyDaysAsDefaultRecentRange() async {
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: [])
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(store.requestedDays, 90)
    }

    func testLoadDoesNotDeleteMergeOrMarkWorkouts() async {
        let startDate = Date()
        let workouts = [
            makeWorkout(source: .garmin, startDate: startDate, externalId: "garmin-ride"),
            makeWorkout(source: .appleHealthKit, startDate: startDate.addingTimeInterval(60), externalId: "health-ride")
        ]
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: workouts)
        let viewModel = UnifiedWorkoutDuplicateReviewViewModel(store: store)

        await viewModel.loadDuplicateCandidates()

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertFalse(store.didMarkExcludedFromAnalysis)
        XCTAssertFalse(store.didDeleteWorkout)
        XCTAssertFalse(store.didSaveWorkout)
    }

    func testFailedResolutionLeavesCandidateAndOriginalsAvailableForRetry() async throws {
        let start = Date()
        let first = makeWorkout(source: .appleHealthKit, startDate: start)
        let second = makeWorkout(source: .soomLocal, startDate: start.addingTimeInterval(60))
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: [first, second])
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: store)
        model.applyResolution = { _, _, _ in throw SampleError.fetchFailed }
        await model.loadDuplicateCandidates()
        let candidate = try XCTUnwrap(model.candidates.first)
        await model.resolve(candidate, primaryID: first.id)
        XCTAssertEqual(model.candidates.count, 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isResolving)
        XCTAssertEqual(model.errorTitle, "대표 기록을 변경하지 못했어요")
        XCTAssertFalse(store.didDeleteWorkout)
        XCTAssertFalse(store.didMarkExcludedFromAnalysis)
    }

    func testReopenedScreenOffersUnfinishedPublicationRequestAgain() async throws {
        let start = Date()
        var primary = makeWorkout(source: .appleHealthKit, startDate: start)
        var secondary = makeWorkout(source: .soomLocal, startDate: start.addingTimeInterval(60))
        let request = UUID()
        primary.preferredWorkoutID = primary.id
        secondary.preferredWorkoutID = primary.id
        primary.resolutionRequestID = request
        secondary.resolutionRequestID = request
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: FakeUnifiedWorkoutDuplicateReviewStore(workouts: [primary, secondary]))
        await model.loadDuplicateCandidates()
        let candidate = try XCTUnwrap(model.candidates.first)
        XCTAssertEqual(candidate.primaryWorkout.id, primary.id)
        XCTAssertEqual(candidate.duplicateWorkout.id, secondary.id)
        XCTAssertEqual(model.candidates.count, 1)
    }

    func testThreeResolvedSourcesRemainSelectableForChangingRepresentative() async throws {
        let start = Date()
        var watch = makeWorkout(source: .appleHealthKit, startDate: start)
        var phone = makeWorkout(source: .soomLocal, startDate: start.addingTimeInterval(-240))
        var third = makeWorkout(source: .garmin, startDate: start.addingTimeInterval(60))
        watch.preferredWorkoutID = watch.id
        phone.preferredWorkoutID = watch.id
        third.preferredWorkoutID = watch.id
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: FakeUnifiedWorkoutDuplicateReviewStore(workouts: [watch, phone, third]))
        await model.loadDuplicateCandidates()
        XCTAssertEqual(model.candidates.count, 2)
        XCTAssertEqual(Set(model.candidates.map { $0.duplicateWorkout.id }), Set([phone.id, third.id]))
        XCTAssertTrue(model.candidates.allSatisfy { $0.primaryWorkout.id == watch.id })
    }

    func testProfileOnlyRepresentativeAndSplitOnlyCommitLocalMetadataPreservingSourcesAndPrivacy() async throws {
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,HealthCloudOutboxRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        HealthCloudJournal.register(container,userID:UUID())
        let context=container.mainContext,store=SwiftDataUnifiedWorkoutStore(modelContext:context)
        var a=makeWorkout(source:.garmin,startDate:Date()),b=makeWorkout(source:.appleHealthKit,startDate:Date())
        a.sharingVisibilityRaw="source_review_pending";b.sharingVisibilityRaw="private"
        try await store.saveWorkouts([a,b])
        let ids=Set([a.id,b.id])
        try ProfileOnlyLocalDuplicateResolution.apply(memberIDs:ids,primaryID:a.id,keepSeparate:false,context:context,validate:{})
        for original in [a,b] {
            let fetched=try await store.fetchWorkout(id:original.id)
            let saved=try XCTUnwrap(fetched)
            XCTAssertEqual(saved.preferredWorkoutID,a.id);XCTAssertNil(saved.resolutionRequestID)
            XCTAssertEqual(saved.sharingVisibilityRaw,original.sharingVisibilityRaw)
            XCTAssertEqual(saved.averageHeartRate,original.averageHeartRate);XCTAssertEqual(saved.distanceMeters,original.distanceMeters)
            XCTAssertEqual(saved.externalId,original.externalId);XCTAssertEqual(saved.source,original.source)
        }
        try ProfileOnlyLocalDuplicateResolution.apply(memberIDs:ids,primaryID:nil,keepSeparate:true,context:context,validate:{})
        let records=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>())
        XCTAssertEqual(records.count,2);XCTAssertTrue(records.allSatisfy{$0.keepSeparate==true && $0.preferredWorkoutID==nil && $0.resolutionRequestID==nil})
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<HealthCloudOutboxRecord>()).filter{$0.kind=="workout"}.map(\.recordKey)),Set(ids.map{$0.uuidString.lowercased()}))
    }
    func testProfileOnlyLocalResolutionRejectsOwnerChangeAndMissingMembersBeforeMutation() async throws {
        let container=try ModelContainer(for:UnifiedWorkoutRecord.self,HealthCloudOutboxRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        HealthCloudJournal.register(container,userID:UUID())
        let context=container.mainContext,store=SwiftDataUnifiedWorkoutStore(modelContext:context),a=makeWorkout(source:.garmin,startDate:Date())
        try await store.saveWorkout(a)
        XCTAssertThrowsError(try ProfileOnlyLocalDuplicateResolution.apply(memberIDs:[a.id],primaryID:a.id,keepSeparate:false,context:context,validate:{throw CommunitySafetyError.accountChanged}))
        XCTAssertThrowsError(try ProfileOnlyLocalDuplicateResolution.apply(memberIDs:[a.id,UUID()],primaryID:a.id,keepSeparate:false,context:context,validate:{}))
        let fetched=try await store.fetchWorkout(id:a.id)
        let unchanged=try XCTUnwrap(fetched);XCTAssertNil(unchanged.preferredWorkoutID)
    }

    private func makeWorkout(
        type: UnifiedWorkoutType = .cycling,
        source: UnifiedDataSource,
        startDate: Date,
        externalId: String = UUID().uuidString,
        distanceMeters: Double = 41_700
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: source,
            workoutType: type,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(90 * 60),
            durationSeconds: 90 * 60,
            distanceMeters: distanceMeters,
            activeEnergyKcal: 720,
            averageHeartRate: 148,
            maxHeartRate: 172,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: 77,
            dataQuality: .partial,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private final class FakeUnifiedWorkoutDuplicateReviewStore: UnifiedWorkoutStore {
    private let workouts: [UnifiedWorkout]
    private let error: Error?
    private(set) var requestedDays: Int?
    private(set) var didMarkExcludedFromAnalysis = false
    private(set) var didDeleteWorkout = false
    private(set) var didSaveWorkout = false

    init(
        workouts: [UnifiedWorkout] = [],
        error: Error? = nil
    ) {
        self.workouts = workouts
        self.error = error
    }

    func saveWorkout(_ workout: UnifiedWorkout) async throws {
        didSaveWorkout = true
    }

    func saveWorkouts(_ workouts: [UnifiedWorkout]) async throws {
        didSaveWorkout = true
    }

    func fetchRecentWorkouts(days: Int) async throws -> [UnifiedWorkout] {
        requestedDays = days

        if let error {
            throw error
        }

        return workouts
    }

    func fetchWorkout(id: UUID) async throws -> UnifiedWorkout? { nil }
    func fetchByExternalId(_ externalId: String, source: UnifiedDataSource) async throws -> UnifiedWorkout? { nil }

    func markExcludedFromAnalysis(id: UUID, isExcluded: Bool) async throws {
        didMarkExcludedFromAnalysis = true
    }

    func updateCompanions(id: UUID, names: [String]) async throws {}

    func deleteWorkout(id: UUID) async throws {
        didDeleteWorkout = true
    }

    func deleteAllWorkouts() async throws {}
}

private enum SampleError: Error {
    case fetchFailed
}

extension UnifiedWorkoutDuplicateReviewViewModelTests {
    func testResolutionFeedbackIdentifiesSelectionAndDoesNotSurviveANewFailedAction() async throws {
        let first = makeWorkout(source: .garmin, startDate: Date())
        let second = makeWorkout(source: .appleHealthKit, startDate: first.startDate.addingTimeInterval(60))
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: [first, second])
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: store)
        model.applyResolution = { _, _, _ in }
        await model.loadDuplicateCandidates(); let candidate = try XCTUnwrap(model.candidates.first)
        await model.resolve(candidate, primaryID: first.id)
        XCTAssertEqual(model.resolutionTitle, "대표 선택 완료")
        XCTAssertTrue(model.resolutionSelection?.contains(first.recordingSourceLabel) == true)
        XCTAssertTrue(model.resolutionMessage?.contains("원본은 모두 보관") == true)
        model.applyResolution = { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        await model.resolve(candidate, primaryID: second.id)
        XCTAssertNil(model.resolutionMessage); XCTAssertNil(model.resolutionSelection); XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(store.didDeleteWorkout); XCTAssertFalse(store.didMarkExcludedFromAnalysis)
    }
}


extension UnifiedWorkoutDuplicateReviewViewModelTests {
    func testNativeResolutionFeedbackWithExistingFloatingTabInsetAtMaximumText() async throws {
        let first = makeWorkout(source: .garmin, startDate: Date(timeIntervalSince1970: 1793404800))
        let second = makeWorkout(source: .appleHealthKit, startDate: first.startDate.addingTimeInterval(60))
        let store = FakeUnifiedWorkoutDuplicateReviewStore(workouts: [first, second])
        let model = UnifiedWorkoutDuplicateReviewViewModel(store: store)
        model.applyResolution = { _, _, _ in } // no real workout write or publication
        await model.loadDuplicateCandidates(); let candidate = try XCTUnwrap(model.candidates.first)
        await model.resolve(candidate, primaryID: first.id)
        XCTAssertTrue(model.resolutionSelection?.contains(first.recordingSourceLabel) == true)
        let root = NavigationStack { UnifiedWorkoutDuplicateReviewView(viewModel: model) }
            .environment(\.soomBottomOverlayInset, 72)
            .environment(\.dynamicTypeSize, .accessibility5)
            .overlay(alignment: .bottom) { Text("SYNTHETIC 72pt existing tab overlay").frame(height: 72).frame(maxWidth: .infinity).background(Color.purple) }
        let host = UIHostingController(rootView: root); host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 874))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200)); host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "F original duplicate view native maximum text existing overlay fixture NOT root integration"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertFalse(store.didDeleteWorkout); XCTAssertFalse(store.didMarkExcludedFromAnalysis)
    }
}
