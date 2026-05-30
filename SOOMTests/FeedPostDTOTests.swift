import XCTest
@testable import SOOM

final class FeedPostDTOTests: XCTestCase {
    func testDefaultVisibilityIsPrivate() {
        let post = makePost()

        XCTAssertEqual(post.visibility, .privatePost)
    }

    func testFeedPostBundleMapsToFeedItemWithoutPrivateRecoveryCue() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let bundle = FeedPostBundleDTO(
            post: makePost(
                id: postId,
                sport: .running,
                title: "비 온 뒤 강변 러닝",
                body: "오늘은 호흡이 먼저였어요.",
                visibility: .publicPost
            ),
            media: [
                FeedPostMediaDTO(
                    id: UUID(uuidString: "C08370FD-4FD7-42A0-BE38-599CF2621E3D")!,
                    postId: postId,
                    mediaType: .route,
                    previewPayload: FeedMediaPreviewPayloadDTO(routeLabel: "강변 route"),
                    sortOrder: 0
                ),
                FeedPostMediaDTO(
                    id: UUID(uuidString: "B113B8F8-0278-439A-9F2E-4F09419E5B7F")!,
                    postId: postId,
                    mediaType: .photo,
                    previewPayload: FeedMediaPreviewPayloadDTO(title: "강변", tone: .water),
                    sortOrder: 1
                )
            ],
            reactions: [
                FeedReactionDTO(
                    id: UUID(uuidString: "B1773DB5-36D0-4CA7-A5C7-0AF7A2B59715")!,
                    postId: postId,
                    userId: UUID(uuidString: "67959CF2-A5A9-4117-81BF-CBFB78629814")!,
                    reactionType: "cheer",
                    createdAt: Date(timeIntervalSince1970: 1_800_420_100)
                )
            ],
            comments: [
                FeedCommentDTO(
                    id: UUID(uuidString: "993CE858-83C4-470B-88E2-6EB43453E890")!,
                    postId: postId,
                    userId: UUID(uuidString: "67959CF2-A5A9-4117-81BF-CBFB78629814")!,
                    body: "좋은 흐름이에요.",
                    createdAt: Date(timeIntervalSince1970: 1_800_420_200)
                )
            ]
        )

        let item = bundle.makeFeedItem(authorName: "민서", authorHandle: "@steady")

        XCTAssertEqual(item.id, postId)
        XCTAssertEqual(item.visibility, .publicFeed)
        XCTAssertEqual(item.authorName, "민서")
        XCTAssertEqual(item.photoPlaceholders.count, 1)
        XCTAssertEqual(item.reactions.first?.symbol, "👏")
        XCTAssertEqual(item.microComment, "좋은 흐름이에요.")
        XCTAssertNil(item.recoveryCue)

        guard case .workoutSession(let card) = item.cardData else {
            return XCTFail("Expected workout session card")
        }

        XCTAssertEqual(card.visibility, .publicFeed)
        XCTAssertEqual(card.workoutType, .running)
        XCTAssertTrue(card.staticRoutePreview?.routeExists == true)
        XCTAssertFalse(card.recoveryMessage.contains("82"))
    }

    func testVisibilityMapsToShareableVisibility() {
        XCTAssertEqual(FeedPostVisibility.privatePost.shareableVisibility, .privateOnly)
        XCTAssertEqual(FeedPostVisibility.followers.shareableVisibility, .followers)
        XCTAssertEqual(FeedPostVisibility.publicPost.shareableVisibility, .publicFeed)
    }

    private func makePost(
        id: UUID = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!,
        sport: UnifiedWorkoutType = .cycling,
        title: String = "퇴근 후 라이딩",
        body: String? = nil,
        visibility: FeedPostVisibility = .privatePost
    ) -> FeedPostDTO {
        FeedPostDTO(
            id: id,
            userId: UUID(uuidString: "585B05E6-EFC0-4813-B018-B2325B0BA476")!,
            sport: sport,
            title: title,
            body: body,
            distanceMeters: 12_300,
            durationSeconds: 2_760,
            averagePaceSecondsPerKm: nil,
            averageHeartRate: 142,
            routeSummary: FeedRouteSummaryDTO(title: "강변 route", distanceText: "12.30 km", fallbackStyle: .cycling, routeExists: true),
            visibility: visibility,
            createdAt: Date(timeIntervalSince1970: 1_800_420_000)
        )
    }
}
