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
        XCTAssertNil(item.sourceWorkoutId)

        guard case .workoutSession(let card) = item.cardData else {
            return XCTFail("Expected workout session card")
        }

        XCTAssertEqual(card.visibility, .publicFeed)
        XCTAssertEqual(card.workoutType, .running)
        XCTAssertTrue(card.staticRoutePreview?.routeExists == true)
        XCTAssertFalse(card.recoveryMessage.contains("82"))
    }

    func testFeedPostBundleSetsAuthorIdAndIsNotALocalDraft() {
        let authorId = UUID(uuidString: "585B05E6-EFC0-4813-B018-B2325B0BA476")!
        let bundle = FeedPostBundleDTO(post: makePost())

        let item = bundle.makeFeedItem()

        XCTAssertEqual(item.authorId, authorId)
        XCTAssertFalse(item.isLocalDraft)
    }

    func testFeedPostBundleMarksViewerHasCheeredWhenCurrentUserHasACheerReaction() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            reactions: [
                FeedReactionDTO(
                    id: UUID(),
                    postId: postId,
                    userId: currentUserId,
                    reactionType: "cheer",
                    createdAt: Date(timeIntervalSince1970: 1_800_420_100)
                )
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: currentUserId)

        XCTAssertTrue(item.viewerHasCheered)
    }

    func testFeedPostBundleDoesNotMarkViewerHasCheeredForAnotherUsersReaction() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let someoneElse = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            reactions: [
                FeedReactionDTO(
                    id: UUID(),
                    postId: postId,
                    userId: someoneElse,
                    reactionType: "cheer",
                    createdAt: Date(timeIntervalSince1970: 1_800_420_100)
                )
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: currentUserId)

        XCTAssertFalse(item.viewerHasCheered)
    }

    func testFeedPostBundlePassesThroughSourceWorkoutId() {
        let sourceWorkoutId = UUID(uuidString: "1F5B6D2D-3F1E-4A5A-9C31-8B2D6C5C1234")!
        let post = FeedPostDTO(
            id: UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!,
            userId: UUID(uuidString: "585B05E6-EFC0-4813-B018-B2325B0BA476")!,
            sourceWorkoutId: sourceWorkoutId,
            sport: .running,
            title: "아침 러닝",
            createdAt: Date(timeIntervalSince1970: 1_800_420_000)
        )
        let bundle = FeedPostBundleDTO(post: post)

        let item = bundle.makeFeedItem()

        XCTAssertEqual(item.sourceWorkoutId, sourceWorkoutId)
    }

    func testFeedPostBundleMapsAllCommentsInInputOrder() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let comments = [
            makeComment(postId: postId, body: "첫 댓글", timestamp: 1_800_420_100),
            makeComment(postId: postId, body: "두 번째 댓글", timestamp: 1_800_420_200),
            makeComment(postId: postId, body: "세 번째 댓글", timestamp: 1_800_420_300)
        ]
        let bundle = FeedPostBundleDTO(post: makePost(id: postId), comments: comments)

        let item = bundle.makeFeedItem()

        XCTAssertEqual(item.comments, comments.map(\.feedComment))
        XCTAssertEqual(item.comments.map(\.body), ["첫 댓글", "두 번째 댓글", "세 번째 댓글"])
        XCTAssertEqual(item.microComment, comments.first?.body)
    }

    func testFeedPostBundlePreservesCommentCount() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let comments = [
            makeComment(postId: postId, body: "첫 댓글", timestamp: 1_800_420_100),
            makeComment(postId: postId, body: "두 번째 댓글", timestamp: 1_800_420_200),
            makeComment(postId: postId, body: "세 번째 댓글", timestamp: 1_800_420_300)
        ]

        for expectedCount in [0, 1, 3] {
            let bundle = FeedPostBundleDTO(
                post: makePost(id: postId),
                comments: Array(comments.prefix(expectedCount))
            )

            XCTAssertEqual(bundle.makeFeedItem().comments.count, expectedCount)
        }
    }

    func testFeedCommentDTOMapsToFeedComment() {
        let id = UUID(uuidString: "993CE858-83C4-470B-88E2-6EB43453E890")!
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let authorId = UUID(uuidString: "67959CF2-A5A9-4117-81BF-CBFB78629814")!
        let createdAt = Date(timeIntervalSince1970: 1_800_420_200)
        let dto = FeedCommentDTO(
            id: id,
            postId: postId,
            userId: authorId,
            body: "좋은 흐름이에요.",
            createdAt: createdAt
        )

        let comment = dto.feedComment

        XCTAssertEqual(comment.id, id)
        XCTAssertEqual(comment.authorId, authorId)
        XCTAssertEqual(comment.body, "좋은 흐름이에요.")
        XCTAssertEqual(comment.createdAt, createdAt)
    }

    func testVisibilityMapsToShareableVisibility() {
        XCTAssertEqual(FeedPostVisibility.privatePost.shareableVisibility, .privateOnly)
        XCTAssertEqual(FeedPostVisibility.followers.shareableVisibility, .followers)
        XCTAssertEqual(FeedPostVisibility.publicPost.shareableVisibility, .publicFeed)
    }

    func testShareableVisibilityMapsToFeedPostVisibility() {
        XCTAssertEqual(ShareableWorkoutVisibility.privateOnly.feedPostVisibility, .privatePost)
        XCTAssertEqual(ShareableWorkoutVisibility.publicFeed.feedPostVisibility, .publicPost)
    }

    func testFollowersVisibilityMapsToPrivatePostUntilFollowGraphExists() {
        // No `follows` table exists yet, so `feed_posts_select_owner_or_public`
        // would make a `followers`-visibility row visible to nobody but the
        // owner. Posting it as `.privatePost` keeps the DB row honest about
        // what the RLS actually enforces.
        XCTAssertEqual(ShareableWorkoutVisibility.followers.feedPostVisibility, .privatePost)
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

    private func makeComment(postId: UUID, body: String, timestamp: TimeInterval) -> FeedCommentDTO {
        FeedCommentDTO(
            id: UUID(),
            postId: postId,
            userId: UUID(),
            body: body,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}
