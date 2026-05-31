import XCTest
@testable import SOOM

final class FeedShareDraftTests: XCTestCase {
    private let workoutID = UUID(uuidString: "B7D4B479-6FBB-41C3-AE1D-61B0A2670F08")!
    private let draftID = UUID(uuidString: "EF537BBA-3C37-4654-8B47-B3846D7D08D8")!
    private let now = Date(timeIntervalSince1970: 1_800_100_000)

    func testUnifiedWorkoutBuildsPrivateFeedShareDraft() {
        let builder = FeedShareDraftBuilder(
            dateProvider: { self.now },
            idProvider: { self.draftID }
        )

        let draft = builder.build(from: workout(distanceMeters: 8_200, durationSeconds: 2_460))

        XCTAssertEqual(draft.id, draftID)
        XCTAssertEqual(draft.sourceWorkoutId, workoutID)
        XCTAssertEqual(draft.sport, .cycling)
        XCTAssertEqual(draft.title, "오늘의 라이딩")
        XCTAssertEqual(draft.body, "가볍게 리듬을 이어간 기록.")
        XCTAssertEqual(draft.distanceMeters, 8_200)
        XCTAssertEqual(draft.durationSeconds, 2_460)
        XCTAssertEqual(draft.averagePaceSecondsPerKm, 300)
        XCTAssertEqual(draft.visibility, .draft)
        XCTAssertEqual(draft.createdAt, now)
        XCTAssertEqual(draft.routePreviewPayload?.distanceText, "8.2 km")
        XCTAssertTrue(draft.tags.contains("라이딩"))
    }

    func testDraftDoesNotIncludeRecoveryGuidanceInFeedFields() {
        let draft = FeedShareDraftBuilder(
            dateProvider: { self.now },
            idProvider: { self.draftID }
        ).build(from: workout(distanceMeters: nil, durationSeconds: 1_200))

        let item = draft.makeFeedItem()

        XCTAssertNil(item.recoveryCue)
        XCTAssertEqual(item.contextLabels.first?.title, "초안")
        XCTAssertEqual(item.visibility, .privateOnly)
        guard case .workoutSession(let card) = item.cardData else {
            return XCTFail("Expected draft to map into a workout session card")
        }
        XCTAssertEqual(card.visibility, .privateOnly)
        XCTAssertEqual(card.recoveryMessage, "개인 회복 코칭은 피드 초안에 포함하지 않아요.")
        XCTAssertEqual(card.distanceText, "거리 준비 중")
    }

    func testShareActionCreatesDraft() async throws {
        let store = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(
            builder: FeedShareDraftBuilder(
                dateProvider: { self.now },
                idProvider: { self.draftID }
            ),
            store: store
        )

        let draft = try await coordinator.handle(.shareToFeed, workout: workout())
        let savedDrafts = try await store.fetchDrafts()

        XCTAssertEqual(draft?.id, draftID)
        XCTAssertEqual(savedDrafts.map(\.id), [draftID])
    }

    func testLaterActionDoesNotCreateDraft() async throws {
        let store = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(store: store)

        let draft = try await coordinator.handle(.later, workout: workout())
        let savedDrafts = try await store.fetchDrafts()

        XCTAssertNil(draft)
        XCTAssertTrue(savedDrafts.isEmpty)
    }

    private func workout(
        distanceMeters: Double? = 8_200,
        durationSeconds: TimeInterval = 2_460
    ) -> UnifiedWorkout {
        UnifiedWorkout(
            id: workoutID,
            externalId: nil,
            source: .soomLocal,
            workoutType: .cycling,
            startDate: Date(timeIntervalSince1970: 1_800_090_000),
            endDate: Date(timeIntervalSince1970: 1_800_090_000 + durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: now,
            updatedAt: now
        )
    }
}

final class InMemoryFeedShareDraftStore: FeedShareDraftStoreProtocol {
    private(set) var drafts: [FeedShareDraft] = []

    func saveDraft(_ draft: FeedShareDraft) async throws {
        drafts.removeAll { $0.id == draft.id || $0.sourceWorkoutId == draft.sourceWorkoutId }
        drafts.append(draft)
        drafts.sort { $0.createdAt > $1.createdAt }
    }

    func fetchDrafts() async throws -> [FeedShareDraft] {
        drafts
    }
}
