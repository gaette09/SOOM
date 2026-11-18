import XCTest
import CoreLocation
@testable import SOOM

final class FeedItemTests: XCTestCase {
    func testSharedDetailIdentityDoesNotCarryPersonalWorkoutOrInventMeasurements() {
        let source = UUID(), author = UUID(), postID = UUID()
        let post = FeedPostDTO(id: postID, userId: author, sourceWorkoutId: source, sport: .running,
            title: "공유 운동", body: "공개 설명", distanceMeters: 5000, durationSeconds: 1800,
            averageHeartRate: 145, visibility: .mutual, createdAt: Date(timeIntervalSince1970: 1800000000))
        let record = WorkoutDetailSharedRecord(item: FeedPostBundleDTO(post: post).makeFeedItem(currentUserId: UUID()))
        XCTAssertEqual(record.layoutIdentity.id, postID)
        XCTAssertNotEqual(record.layoutIdentity.id, source)
        XCTAssertEqual(record.item.authorId, author)
        XCTAssertEqual(record.item.visibility.feedPostVisibility, .mutual)
        XCTAssertEqual(record.metrics.first?.value, "5.00 km")
        XCTAssertEqual(record.metrics.last?.value, "145 bpm")
        XCTAssertEqual(record.layoutIdentity.aiSummary, "")
        XCTAssertTrue(record.layoutIdentity.route.isEmpty)
        XCTAssertTrue(record.layoutIdentity.samples.isEmpty)
        XCTAssertTrue(record.layoutIdentity.splits.isEmpty)
        XCTAssertTrue(record.layoutIdentity.achievements.isEmpty)
        XCTAssertFalse(record.hasRouteImage)
    }

    func testSharedDetailMissingMetricsRemainUnknownAndInvalidHeartRateIsOmitted() {
        for rate in [nil, -1, 0, 301] as [Int?] {
            let post = FeedPostDTO(id: UUID(), userId: UUID(), sport: .running, title: "미측정 기록",
                averageHeartRate: rate, createdAt: Date())
            let record = WorkoutDetailSharedRecord(item: FeedPostBundleDTO(post: post).makeFeedItem(currentUserId: UUID()))
            XCTAssertEqual(record.metrics.map(\.value), ["—", "—", "—"])
            XCTAssertFalse(record.hasRouteImage)
        }
    }


    func testNewestFirstCommentHydrationPreservesBadgeAndChronologicalConversation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let post = FeedPostDTO(id: UUID(), userId: UUID(), sport: .running, title: "Run", createdAt: now)
        let recent = FeedCommentDTO(id: UUID(), postId: post.id, userId: UUID(), body: "new", createdAt: now.addingTimeInterval(-60))
        let old = FeedCommentDTO(id: UUID(), postId: post.id, userId: UUID(), body: "old", createdAt: now.addingTimeInterval(-86_400))
        let item = FeedPostBundleDTO(post: post, comments: [recent, old]).makeFeedItem()
        XCTAssertEqual(item.comments.map(\.id), [old.id, recent.id])
        XCTAssertTrue(item.hasRecentComment(now: now))
    }

    func testCommentNewBadgeExpiresAfterTwelveHoursAndIgnoresFutureDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var item = FeedMockData.items[0]
        item.comments = [FeedComment(id: UUID(), authorId: UUID(), body: "new", createdAt: now.addingTimeInterval(-43_199), isViewerAuthor: false)]
        XCTAssertTrue(item.hasRecentComment(now: now))
        XCTAssertFalse(item.hasRecentComment(now: now.addingTimeInterval(1)))
        item.comments = [FeedComment(id: UUID(), authorId: UUID(), body: "future", createdAt: now.addingTimeInterval(1), isViewerAuthor: false)]
        XCTAssertFalse(item.hasRecentComment(now: now))
        item.comments = []
        XCTAssertFalse(item.hasRecentComment(now: now))
    }

    func testCheersPreserveFirstPeopleOrderAndHydrateTheirIdentity() {
        let postID = UUID(), first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = FeedProfileDTO(id: first, displayName: "첫 응원자", handle: "first", avatarPath: "profile.jpg")
        let rows = [(fourth, 40.0), (second, 20.0), (first, 10.0), (third, 30.0), (first, 50.0)].map { author, seconds in
            FeedReactionDTO(id: UUID(), postId: postID, userId: author, reactionType: "cheer", createdAt: start.addingTimeInterval(seconds))
        }
        let other = FeedReactionDTO(id: UUID(), postId: postID, userId: UUID(), reactionType: "night", createdAt: start)
        let bundle = FeedPostBundleDTO(post: FeedPostDTO(id: postID, userId: UUID(), sport: .running, title: "Run", createdAt: start),
            reactions: rows + [other], comments: [FeedCommentDTO(id: UUID(), postId: postID, userId: first, body: "nice", createdAt: start)])
        let item = bundle.makeFeedItem(profilesByID: [first: profile])
        XCTAssertEqual(item.orderedCheers.compactMap(\.authorId), [first, second, third, fourth])
        XCTAssertEqual(Array(item.orderedCheers.prefix(3)).compactMap(\.authorId), [first, second, third])
        XCTAssertEqual(item.orderedCheers.first?.profile, profile)
        XCTAssertEqual(item.comments.first?.profile, profile)
        XCTAssertEqual(Set(bundle.previewProfileIDs), Set([bundle.post.userId, first, second, third]))
    }

    func testFeedItemKeepsVisibilityAndWorkoutCardData() {
        let item = FeedMockData.items[0]

        XCTAssertEqual(item.visibility, .followers)

        guard case .workoutSession(let card) = item.cardData else {
            return XCTFail("Expected workout session card data")
        }

        XCTAssertEqual(card.visibility, item.visibility)
        XCTAssertEqual(card.workoutType, .running)
    }

    func testFeedItemKeepsWeeklyProgressCardData() {
        let item = FeedMockData.items[1]

        guard case .weeklyProgress(let card) = item.cardData else {
            return XCTFail("Expected weekly progress card data")
        }

        XCTAssertEqual(item.itemType, .weeklyProgress)
        XCTAssertEqual(card.visibility, item.visibility)
        XCTAssertFalse(card.progressMessage.isEmpty)
    }

    func testFeedViewSortsItemsByNewestFirst() {
        let older = FeedMockData.items[2]
        let newer = FeedMockData.items[0]

        let view = FeedView(items: [older, newer])

        XCTAssertEqual(view.items.map(\.id), [newer.id, older.id])
    }

    func testLateImportedOlderWorkoutStaysBehindNewerWorkout() {
        var importedLast = FeedMockData.items[0]
        var newerWorkout = FeedMockData.items[2]
        importedLast.activityDate = Date(timeIntervalSince1970: 1_000)
        newerWorkout.activityDate = Date(timeIntervalSince1970: 2_000)

        let view = FeedView(items: [importedLast, newerWorkout])

        XCTAssertEqual(view.items.map(\.id), [newerWorkout.id, importedLast.id])
    }

    func testFirstJourneyPromptsUseWarmNonEmptyCopy() {
        let prompts: [SOOMFirstJourneyPrompt] = [
            .feed,
            .activity,
            .club,
            .profile
        ]

        prompts.forEach { prompt in
            XCTAssertFalse(prompt.title.isEmpty)
            XCTAssertFalse(prompt.message.isEmpty)
            XCTAssertFalse(prompt.iconName.isEmpty)
        }

        let joinedCopy = prompts.map { "\($0.title) \($0.message)" }.joined(separator: " ")
        ["아직 아무도", "기록 없음", "0개", "실패", "경쟁", "랭킹"].forEach { word in
            XCTAssertFalse(joinedCopy.contains(word), "First journey copy should avoid cold empty-state tone: \(word)")
        }
    }
}

extension FeedItemTests {
    func testSharedSnapshotRemovesInteriorHomeReentryAndBreaksRouteSegments() {
        let raw = sharedSyntheticInput()
        let masked = raw.masked()
        XCTAssertEqual(raw.route.count, 7)
        XCTAssertEqual(masked.route.map(\.longitude), [0.005,0.006,0.006,0.008])
        XCTAssertEqual(masked.route.map(\.segment), [0,0,1,1])
        for point in masked.route {
            XCTAssertGreaterThanOrEqual(WorkoutSharedDetailInput.distance(point,raw.route.first!),200)
            XCTAssertGreaterThanOrEqual(WorkoutSharedDetailInput.distance(point,raw.route.last!),200)
        }
        XCTAssertEqual(masked.samples, raw.samples)
    }
    func testSharedSnapshotBreaksSparseLineCrossingPrivateOrigin() {
        var input = sharedSyntheticInput()
        input.route = [0,0.004,0.005,-0.005,-0.006,0].map {
            .init(latitude:0,longitude:$0,seconds:nil,altitude:nil,segment:0)
        }
        let masked = input.masked()
        XCTAssertEqual(masked.route.count,4)
        XCTAssertNotEqual(masked.route[1].segment,masked.route[2].segment)
    }
    func testSharedSnapshotRequiresMatchingPostRevisionAndFeatureAuthorization() {
        let id = UUID(); var post = FeedPostDTO(id:id,userId:UUID(),sport:.running,title:"Shared",createdAt:Date())
        post.sharedDetailRevision = 4
        let payload = sharedSyntheticInput().masked()
        var item = FeedPostBundleDTO(post:post,sharedDetail:.init(postID:id,revision:4,payload:payload),sharedDetailContractEnabled:true).makeFeedItem()
        XCTAssertNotNil(item.permittedSharedDetail)
        item.sharedDetailContractEnabled = false; XCTAssertNil(item.permittedSharedDetail)
        item.sharedDetailContractEnabled = true
        item.sharedDetail = .init(postID:id,revision:3,payload:payload); XCTAssertNil(item.permittedSharedDetail)
        item.sharedDetail = .init(postID:UUID(),revision:4,payload:payload); XCTAssertNil(item.permittedSharedDetail)
    }
    func testSharedSnapshotRetainsMeasuredExtremaAndHasNoPrivateDataKeys() throws {
        let data = try JSONEncoder().encode(sharedSyntheticInput().masked())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(Set(object.keys),["version","durationSeconds","distanceMeters","route","samples"])
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("sourceWorkoutId"))
        var post = FeedPostDTO(id:UUID(),userId:UUID(),sport:.cycling,title:"Shared",createdAt:Date())
        post.sharedDetailRevision = 1
        let record = WorkoutDetailSharedRecord(item:FeedPostBundleDTO(post:post,
            sharedDetail:.init(postID:post.id,revision:1,payload:sharedSyntheticInput().masked()),sharedDetailContractEnabled:true).makeFeedItem())
        let telemetry = try XCTUnwrap(record.telemetry)
        XCTAssertEqual(telemetry.samples.compactMap(\.heartRateBPM),[120,180,130])
        XCTAssertTrue(telemetry.heartRateZones.isEmpty)
        XCTAssertTrue(telemetry.intervals.isEmpty)
        XCTAssertEqual(telemetry.workoutID,post.id)
        XCTAssertEqual(record.measurementWorkout.id,post.id)
        XCTAssertNil(record.measurementWorkout.averageHeartRate)
    }
    func testLegacyFollowersDecodingNeverUpgradesToApprovedFollowerContent() {
        var post = FeedPostDTO(id:UUID(),userId:UUID(),sport:.running,title:"Legacy",visibility:.followers,createdAt:Date())
        XCTAssertEqual(FeedPostBundleDTO(post:post).makeFeedItem().visibility,.privateOnly)
        post.audienceContract = 1
        XCTAssertEqual(FeedPostBundleDTO(post:post).makeFeedItem().visibility,.followers)
    }
    func testSharedAndOwnerMaskedRouteKeepSamePlaybackGeometryWithoutDoubleTrim() throws {
        let raw = sharedSyntheticInput()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let ownerRoute = WorkoutRoute(workoutId: UUID(), source: .soomLocal, coordinates: raw.route.map {
            WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude,
                timestamp: $0.seconds.map { start.addingTimeInterval($0) }, segmentIndex: $0.segment)
        }, totalDistanceMeters: 800)
        let owner = RoutePrivacyMasker().mask(route: ownerRoute)
        let peer = try XCTUnwrap(WorkoutSharedDetailSnapshot(postID: UUID(), revision: 1, payload: raw.masked()).route(start: start))
        XCTAssertTrue(peer.privacyMaskApplied)
        XCTAssertEqual(owner.coordinates.map(\.longitude), peer.coordinates.map(\.longitude))
        XCTAssertEqual(owner.coordinates.map(\.segmentIndex), peer.coordinates.map(\.segmentIndex))
        XCTAssertEqual(RoutePrivacyMasker().mask(route: peer), peer)
        func segments(_ route: WorkoutRoute) -> [[CLLocationCoordinate2D]] {
            route.coordinateSegments.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
        }
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let a = WorkoutRoutePlayback.frame(segments: segments(owner), progress: progress)
            let b = WorkoutRoutePlayback.frame(segments: segments(peer), progress: progress)
            XCTAssertEqual(a.position?.latitude, b.position?.latitude)
            XCTAssertEqual(a.position?.longitude, b.position?.longitude)
            XCTAssertEqual(a.segments.map(\.count), b.segments.map(\.count))
        }
    }

    func testSharingBuildUsesOriginalEndpointsAndMatchesMaskedDisplayOnce() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), id = UUID()
        let raw = sharedSyntheticInput()
        let workout = UnifiedWorkout(id: id, externalId: nil, source: .soomLocal, workoutType: .running,
            startDate: start, endDate: start.addingTimeInterval(100), durationSeconds: 100,
            distanceMeters: 800, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial,
            createdAt: start, updatedAt: start)
        let route = WorkoutRoute(workoutId: id, source: .soomLocal, coordinates: raw.route.map {
            WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude,
                timestamp: $0.seconds.map { start.addingTimeInterval($0) }, segmentIndex: $0.segment)
        }, totalDistanceMeters: 800)
        let input = WorkoutSharedDetailInput.build(workout: workout, route: route, telemetry: nil)
        XCTAssertEqual(input.route.first?.longitude, route.coordinates.first?.longitude)
        XCTAssertEqual(input.route.last?.longitude, route.coordinates.last?.longitude)
        let display = RoutePrivacyMasker().mask(route: route)
        XCTAssertEqual(input.masked().route.map(\.longitude), display.coordinates.map(\.longitude))
        XCTAssertFalse(route.privacyMaskApplied)
        XCTAssertEqual(route.coordinates.count, 7)
    }

    private func sharedSyntheticInput() -> WorkoutSharedDetailInput {
        var input = WorkoutSharedDetailInput(durationSeconds:100,distanceMeters:800)
        input.route = [0,0.005,0.006,0.0001,0.006,0.008,0.03].enumerated().map { index,longitude in
            .init(latitude:0,longitude:longitude,seconds:Double(index)*10,altitude:nil,segment:0)
        }
        input.samples = [.init(seconds:0,heartRateBPM:120),.init(seconds:20,heartRateBPM:180),.init(seconds:100,heartRateBPM:130)]
        return input
    }
}
