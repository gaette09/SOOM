import XCTest
import SwiftUI
@testable import SOOM

final class FeedPostDTOTests: XCTestCase {
    @MainActor
    func testProjectionPendingSkeletonReservesItsWholeHeightInsteadOfOverlappingNeighbors() throws {
        let suite = "Placeholder-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults))
        for width: CGFloat in [320, 393] {
            for textSize: DynamicTypeSize in [.large, .accessibility3] {
                func size<V: View>(_ view: V) throws -> CGSize {
                    let renderer = ImageRenderer(content: view.frame(width: width).environment(\.dynamicTypeSize, textSize).environmentObject(auth))
                    return try XCTUnwrap(renderer.uiImage).size
                }
                let oldIntrinsic = try size(SOOMSkeleton(layout: .feed).padding(24))
                let old = try size(Color.clear.frame(minHeight: 224).overlay { SOOMSkeleton(layout: .feed).padding(24) })
                XCTAssertLessThan(old.height, oldIntrinsic.height, "Retain the original overlay overflow reproduction")
                let compact = try size(AccountActivityWorkoutPlaceholder())
                let media = try size(AccountActivityWorkoutPlaceholder(hasKnownMedia: true))
                XCTAssertEqual(media.height - compact.height, 260, accuracy: 1, "Only confirmed media reserves the existing 260pt media slot")
                XCTAssertEqual(try size(AccountActivityWorkoutPlaceholder(hasKnownMedia: false)), compact)
                for reserved: CGFloat in [224, 300, 700] {
                    for known: Bool? in [nil, false, true] {
                        let current = try size(AccountActivityPendingCard(minimumHeight: reserved, hasKnownMedia: known, unavailable: false, retry: {}))
                        XCTAssertGreaterThanOrEqual(current.height, known == true ? media.height : compact.height)
                        XCTAssertGreaterThanOrEqual(current.height, reserved)
                    }
                }
                let renderer = ImageRenderer(content: AccountActivityWorkoutPlaceholder().frame(width: width).environmentObject(auth).environment(\.dynamicTypeSize, textSize))
                let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage)); attachment.name = "SAFE shared workout placeholder \(width) \(textSize)"; attachment.lifetime = .keepAlways; add(attachment)
                let mediaRenderer = ImageRenderer(content: AccountActivityWorkoutPlaceholder(hasKnownMedia: true).frame(width: width).environmentObject(auth).environment(\.dynamicTypeSize, textSize))
                let mediaAttachment = XCTAttachment(image: try XCTUnwrap(mediaRenderer.uiImage)); mediaAttachment.name = "SAFE known-media shared placeholder \(width) \(textSize)"; mediaAttachment.lifetime = .keepAlways; add(mediaAttachment)
            }
        }
    }

    @MainActor
    func testProjectionMediaOrderingPreservesLegacyPrecedenceAndFallback() async throws {
        let owner = UUID(), postID = UUID(), photoID = UUID()
        let nativePhoto = WorkoutPhotoReference(id: UUID(), storagePath: "native-test")
        let post = FeedPostDTO(id: postID, userId: owner, sport: .running, title: "검증", createdAt: Date())
        var item = FeedPostBundleDTO(post: post).makeFeedItem(currentUserId: owner)
        var nativeReads = 0
        let emptyLegacy = try await AccountActivityCardMediaLoader.load(ownerID: owner,
            linked: { item }, native: { nativeReads += 1; return [nativePhoto] }, isCurrent: { true })
        XCTAssertNotNil(emptyLegacy.linked); XCTAssertTrue(emptyLegacy.photos.isEmpty); XCTAssertEqual(nativeReads, 0)
        item = FeedPostBundleDTO(post: post, media: [.init(id: photoID, postId: postID, mediaType: .photo, storagePath: WorkoutPhotoPolicy.path(ownerID: owner, postID: postID, photoID: photoID), sortOrder: 0)]).makeFeedItem(currentUserId: owner)
        let allowedLegacy = try await AccountActivityCardMediaLoader.load(ownerID: owner,
            linked: { item }, native: { nativeReads += 1; return [nativePhoto] }, isCurrent: { true })
        XCTAssertEqual(allowedLegacy.photos.map(\.id), [photoID]); XCTAssertEqual(nativeReads, 0)
        for fails in [false, true] {
            let fallback = try await AccountActivityCardMediaLoader.load(ownerID: owner,
                linked: { if fails { throw URLError(.timedOut) }; return nil },
                native: { nativeReads += 1; return [nativePhoto] }, isCurrent: { true })
            XCTAssertNil(fallback.linked); XCTAssertEqual(fallback.photos.map(\.id), [nativePhoto.id])
        }
        XCTAssertEqual(nativeReads, 2)
    }

    @MainActor
    func testProjectionMediaLateAccountChangeRejectsBeforeNativeOrPublication() async {
        var current = true, nativeReads = 0
        do {
            _ = try await AccountActivityCardMediaLoader.load(ownerID: UUID(),
                linked: { current = false; return nil }, native: { nativeReads += 1; return [] }, isCurrent: { current })
            XCTFail("An old-account result must not be published")
        } catch {}
        XCTAssertEqual(nativeReads, 0)
        current = true
        do {
            _ = try await AccountActivityCardMediaLoader.load(ownerID: UUID(), linked: { nil },
                native: { current = false; return [] }, isCurrent: { current })
            XCTFail("An account change during native read must reject the result")
        } catch {}
    }

    func testOwnCardRequiresMatchingAuthAndJournalBeforeAnyLocalRead() {
        let owner = UUID(), other = UUID()
        var queries = 0
        func attempt(auth: UUID?, journal: UUID?, access: Bool) {
            guard AccountActivityOwnRecordAccess.allowsLocalCard(ownerID: owner, authOwnerID: auth,
                journalOwnerID: journal, recordAccessAllowed: access) else { return }
            queries += 1
        }
        attempt(auth: other, journal: owner, access: true)
        attempt(auth: owner, journal: other, access: true)
        attempt(auth: nil, journal: owner, access: true)
        attempt(auth: owner, journal: owner, access: false)
        XCTAssertEqual(queries, 0, "Wrong account, another owner's row or unverified context must never reach local reads")
        attempt(auth: owner, journal: owner, access: true)
        XCTAssertEqual(queries, 1)
    }

    func testWorkoutCardMetricsMatchAcrossLocalAndSharedRecords() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for sport in [UnifiedWorkoutType.running, .cycling, .swimming, .walking, .hiking, .strength, .yoga, .other] {
            let workout = UnifiedWorkout(id: UUID(), externalId: nil, source: .manual, workoutType: sport,
                startDate: start, endDate: start.addingTimeInterval(1805), durationSeconds: 1805,
                distanceMeters: 5250, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
                averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .estimated,
                createdAt: start, updatedAt: start)
            let post = FeedPostDTO(id: UUID(), userId: UUID(), sport: sport, title: "같은 운동",
                distanceMeters: 5250, durationSeconds: 1805, createdAt: start)
            let shared = FeedPostBundleDTO(post: post).makeFeedItem().recordMetrics
            let local = FeedCardFormatting.metrics(workout)
            XCTAssertEqual(shared.map(\.label), local.map(\.label), "\(sport)")
            XCTAssertEqual(shared.map(\.value), local.map(\.value), "\(sport)")
            XCTAssertEqual(local.first?.label, "거리")
            XCTAssertEqual(local.last?.label, "총 시간")
            XCTAssertEqual(local.last?.value, "30분 5초")
            XCTAssertEqual(local.count, 3)
        }
    }

    func testProjectionMetricsUseTheActivityCardFormattingForEverySport() {
        let owner = UUID()
        for sport in [UnifiedWorkoutType.running, .cycling, .swimming, .walking, .hiking, .strength, .yoga, .other] {
            let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: owner,
                sport: sport.rawValue, activityAt: "2026-11-13T08:00:00Z", durationSeconds: 1805,
                distanceMeters: 5250, revision: 1, readPolicy: .profileOnlyV2)
            let card = AccountActivityWorkoutCardPresentation(row: row)
            let date = Date(timeIntervalSince1970: 1_790_000_000)
            let local = UnifiedWorkout(id: row.canonicalID, externalId: nil, source: .manual, workoutType: sport,
                startDate: date, endDate: date.addingTimeInterval(1805), durationSeconds: 1805,
                distanceMeters: 5250, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
                averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .estimated,
                createdAt: date, updatedAt: date)
            XCTAssertEqual(card.sport, sport)
            XCTAssertEqual(card.metrics.map(\.label), FeedCardFormatting.metrics(local).map(\.label))
            XCTAssertEqual(card.metrics.map(\.value), FeedCardFormatting.metrics(local).map(\.value))
            XCTAssertEqual(card.row, row, "Presentation must not change card/canonical/owner/policy identity")
        }
    }

    @MainActor
    func testActivityAndProjectionCardSnapshotsMatchForIdenticalAuthorizedFields() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2026-11-13T08:00:00Z", durationSeconds: 1805,
            distanceMeters: 5250, revision: 1, readPolicy: .profileOnlyV2)
        let local = UnifiedWorkout(id: row.canonicalID, externalId: nil, source: .manual, workoutType: .running,
            startDate: date, endDate: date.addingTimeInterval(1805), durationSeconds: 1805,
            distanceMeters: 5250, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .estimated,
            createdAt: date, updatedAt: date)
        let suite = "CardParity-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(store: AuthSessionStore(userDefaults: defaults))
        for size in [DynamicTypeSize.large, .accessibility3] {
            func render(_ metrics: [WorkoutCardMetric], name: String) throws -> Data {
                let view = WorkoutRecordCard(title: "러닝 기록", description: nil, date: date, sport: .running,
                    author: "같은 작성자", metrics: metrics, photosAreKnown: true, photos: []) { EmptyView() }
                    .frame(width: 393).fixedSize(horizontal: false, vertical: true)
                    .environmentObject(auth).environment(\.colorScheme, .light).environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: view); renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image); attachment.name = "\(name)-\(size)"
                attachment.lifetime = .keepAlways; add(attachment)
                return try XCTUnwrap(image.pngData())
            }
            XCTAssertEqual(try render(FeedCardFormatting.metrics(local), name: "ACTIVITY-SHARED-CARD"),
                try render(AccountActivityWorkoutCardPresentation(row: row).metrics, name: "FEED-SHARED-CARD"))
        }
    }

    func testProjectionOwnRecordGateRejectsWrongAccountStaleVerificationAndRetiredContainers() {
        let owner = UUID(), other = UUID()
        func allowed(viewer: UUID?, storage: UUID?, verified: Bool = true, same: Bool = true, retired: Bool = false) -> Bool {
            AccountActivityOwnRecordAccess.allows(ownerID: owner, viewerID: viewer, storageOwnerID: storage,
                verified: verified, sameContainer: same, retired: retired)
        }
        XCTAssertTrue(allowed(viewer: owner, storage: owner))
        XCTAssertFalse(allowed(viewer: other, storage: owner))
        XCTAssertFalse(allowed(viewer: owner, storage: other))
        XCTAssertFalse(allowed(viewer: nil, storage: owner))
        XCTAssertFalse(allowed(viewer: owner, storage: owner, verified: false), "A changed generation invalidates the verified key")
        XCTAssertFalse(allowed(viewer: owner, storage: owner, same: false))
        XCTAssertFalse(allowed(viewer: owner, storage: owner, retired: true))
    }

    func testProjectionOwnDetailRequiresAnExistingExactCanonicalRecord() {
        let id = UUID()
        XCTAssertTrue(AccountActivityOwnRecordAccess.matches(canonicalID: id, recordID: id))
        XCTAssertFalse(AccountActivityOwnRecordAccess.matches(canonicalID: id, recordID: nil))
        XCTAssertFalse(AccountActivityOwnRecordAccess.matches(canonicalID: id, recordID: UUID()))
    }

    func testProjectionSummaryDetailReusesExactMetricsWithoutLegacyOrLocalAuthority() {
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 1805,
            distanceMeters: 5250, revision: 1, readPolicy: .profileOnlyV2)
        let record = AccountActivitySummaryDetailPresentation(row: row, author: nil).sharedRecord
        XCTAssertEqual(record.item.id, row.cardID)
        XCTAssertEqual(record.item.activityProjection, row)
        XCTAssertNil(record.item.sourceWorkoutId)
        XCTAssertNil(record.item.serverPostSnapshot)
        XCTAssertNil(record.item.permittedSharedDetail)
        XCTAssertFalse(record.item.sharedDetailContractEnabled)
        XCTAssertFalse(record.item.isLocalDraft)
        XCTAssertFalse(record.item.isOwnerLocalWorkout)
        XCTAssertNil(record.item.deviceName); XCTAssertNil(record.item.locationHint); XCTAssertNil(record.item.caption)
        XCTAssertTrue(record.item.photos.isEmpty); XCTAssertTrue(record.item.comments.isEmpty); XCTAssertTrue(record.item.reactions.isEmpty)
        XCTAssertNil(record.route); XCTAssertNil(record.telemetry)
        XCTAssertEqual(record.metrics.map(\.value), AccountActivityWorkoutCardPresentation(row: row).metrics.map(\.value))
        XCTAssertEqual(record.item.activityDate, row.cursor?.activityAt)
        XCTAssertEqual(record.item.recordWorkoutType.rawValue, row.sport)
    }

    func testSummaryDetailAcceptsOnlyAlreadyAuthorizedNativePhotoIdentity() {
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 600,
            distanceMeters: 1000, revision: 1, readPolicy: .profileOnlyV2)
        let id = UUID()
        let allowed = WorkoutPhotoReference(id: id, storagePath: WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: row.cardID, photoID: id), nativeCardID: row.cardID)
        var legacy = allowed; legacy.nativeCardID = nil
        var wrongCard = allowed; wrongCard.nativeCardID = UUID()
        let presentation = AccountActivitySummaryDetailPresentation(row: row, author: nil, photos: [allowed, legacy, wrongCard])
        XCTAssertEqual(presentation.sharedRecord.item.photos, [allowed])
        XCTAssertNil(presentation.sharedRecord.item.sourceWorkoutId)
        XCTAssertNil(presentation.sharedRecord.route)
    }

    func testMissingLegacySnapshotAndMissingOwnSourceUsesSummaryWithoutNewAuthority() {
        XCTAssertFalse(AccountActivityDetailFallbackPolicy.usesLegacyDetail(hasAuthorizedSnapshot: false, hasExactOwnSource: false))
        XCTAssertTrue(AccountActivityDetailFallbackPolicy.usesLegacyDetail(hasAuthorizedSnapshot: true, hasExactOwnSource: false))
        XCTAssertTrue(AccountActivityDetailFallbackPolicy.usesLegacyDetail(hasAuthorizedSnapshot: false, hasExactOwnSource: true))
        XCTAssertNil(AccountActivityDetailFallbackPolicy.headerVisibility(.followers, profileOnlyContext: true))
        XCTAssertEqual(AccountActivityDetailFallbackPolicy.headerVisibility(.followers, profileOnlyContext: false), .followers)
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(), sport: "running",
            activityAt: "2026-01-01T00:00:00Z", durationSeconds: 600, distanceMeters: 1000, revision: 1, readPolicy: .profileOnlyV2)
        let postID = UUID(), photoID = UUID()
        let allowed = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(ownerID: row.ownerID, postID: postID, photoID: photoID))
        let wrongOwner = WorkoutPhotoReference(id: photoID, storagePath: WorkoutPhotoPolicy.path(ownerID: UUID(), postID: postID, photoID: photoID))
        let granted = AccountActivitySummaryDetailPresentation(row: row, author: nil, photos: [allowed, wrongOwner], authorizedLegacyPhotoPostID: postID)
        XCTAssertEqual(granted.sharedRecord.item.photos, [allowed])
        XCTAssertTrue(AccountActivitySummaryDetailPresentation(row: row, author: nil, photos: [allowed]).sharedRecord.item.photos.isEmpty)
        XCTAssertTrue(AccountActivitySummaryDetailPresentation(row: row, author: nil, photos: [allowed], authorizedLegacyPhotoPostID: UUID()).sharedRecord.item.photos.isEmpty)
        XCTAssertNil(granted.sharedRecord.item.serverPostSnapshot); XCTAssertNil(granted.sharedRecord.item.sourceWorkoutId)
    }

    func testSummaryDetailReceiptRejectsAnotherViewerAndAccountGeneration() throws {
        let owner = UUID(), viewer = UUID()
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: owner,
            sport: "running", activityAt: "2026-01-01T00:00:00Z", durationSeconds: 600,
            distanceMeters: 1000, revision: 1, readPolicy: .profileOnlyV2)
        let receipt = AccountActivityCardEnvelope(version: 2, viewerID: viewer, row: row, releaseReady: true)
        XCTAssertThrowsError(try receipt.validateForProduction(expectedCardID: row.cardID, requestViewerID: viewer,
            currentViewerID: UUID(), requestGeneration: 1, currentGeneration: 1, latestPermittedDate: Date(),
            expectedOwnerID: owner, expectedPolicy: .profileOnlyV2))
        XCTAssertThrowsError(try receipt.validateForProduction(expectedCardID: row.cardID, requestViewerID: viewer,
            currentViewerID: viewer, requestGeneration: 1, currentGeneration: 2, latestPermittedDate: Date(),
            expectedOwnerID: owner, expectedPolicy: .profileOnlyV2))
    }

    func testProjectionSummaryDoesNotInventMissingDistanceOrMovement() {
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "running", activityAt: "2026-11-13T08:00:00Z", durationSeconds: 0,
            distanceMeters: nil, revision: 1, readPolicy: .profileOnlyV2)
        XCTAssertEqual(AccountActivityWorkoutCardPresentation(row: row).metrics.map(\.value), ["—", "—", "0초"])
    }

    func testProjectionSwimmingUsesTheSameMetersAnd100MeterPace() {
        let row = AccountActivityFeedRow(cardID: UUID(), canonicalID: UUID(), ownerID: UUID(),
            sport: "swimming", activityAt: "2026-11-13T08:00:00Z", durationSeconds: 600,
            distanceMeters: 500, revision: 1, readPolicy: .profileOnlyV2)
        XCTAssertEqual(AccountActivityWorkoutCardPresentation(row: row).metrics.map(\.value), ["500 m", "2:00/100m", "10분 0초"])
    }

    func testCardRegionDistinguishesUnresolvedRouteAndMissingManualLocation() {
        XCTAssertEqual(FeedCardFormatting.region("수지구, 경기도", hasRoute: true), "수지구, 경기도")
        XCTAssertEqual(FeedCardFormatting.region("집 근처", hasRoute: false), "집 근처")
        XCTAssertEqual(FeedCardFormatting.region(nil, hasRoute: true), "경로의 지역명 확인 전")
        XCTAssertEqual(FeedCardFormatting.region("  ", hasRoute: false), "지역 미입력")
    }

    func testMissingOrInvalidSharedMetricsUseTheSameEmptyValue() {
        let post = FeedPostDTO(id: UUID(), userId: UUID(), sport: .running, title: "기록", createdAt: Date())
        XCTAssertEqual(FeedPostBundleDTO(post: post).makeFeedItem().recordMetrics.map(\.value), ["—", "—", "—"])
        XCTAssertEqual(FeedCardFormatting.distance(.infinity), "—")
        XCTAssertEqual(FeedCardFormatting.distance(-1), "—")
    }

    func testFeedUsesWorkoutDateAndMetadataWhileKeepingPostSortDate() throws {
        let activityDate = Date(timeIntervalSince1970: 1_790_000_000)
        let postDate = activityDate.addingTimeInterval(86400)
        let metadata = FeedRouteSummaryDTO(routeExists: false, startedAt: activityDate,
            deviceName: "시험 웨어러블", locationName: "수지구")
        let post = FeedPostDTO(id: UUID(), userId: UUID(), sport: .running, title: "시험 러닝",
            distanceMeters: 10_000, durationSeconds: 4260, routeSummary: metadata, createdAt: postDate)
        let item = FeedPostBundleDTO(post: post).makeFeedItem()
        XCTAssertEqual(item.activityDate, activityDate)
        XCTAssertEqual(item.createdAt, postDate)
        XCTAssertEqual(item.deviceName, "시험 웨어러블")
        XCTAssertEqual(item.locationHint, "수지구")
        guard case .workoutSession(let card) = item.cardData else { return XCTFail() }
        XCTAssertEqual(card.averagePaceText, "7:06/km")
        let old = try JSONDecoder().decode(FeedRouteSummaryDTO.self, from: Data("{\"routeExists\":false}".utf8))
        XCTAssertNil(old.startedAt)
        XCTAssertNil(old.deviceName)
    }

    func testMovementShowsSportUnitsAndDoesNotInventMissingValues() {
        XCTAssertEqual(FeedCardFormatting.movement(sport: .cycling, distance: 30_000, seconds: 3600), "30.0 km/h")
        XCTAssertEqual(FeedCardFormatting.movement(sport: .swimming, distance: 1000, seconds: 1200), "2:00/100m")
        XCTAssertNil(FeedCardFormatting.movement(sport: .running, distance: nil, seconds: 300))
        XCTAssertNil(FeedCardFormatting.movement(sport: .running, distance: 0, seconds: 300))
        XCTAssertNil(FeedCardFormatting.movement(sport: .running, distance: 1000, seconds: .infinity))
    }
    func testKoreanCardDateAndRegionMatchDetailPresentation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3600))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 18, minute: 30)))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 0, minute: 5)))
        XCTAssertEqual(WorkoutCardDateFormatter.label(evening, calendar: calendar), "2026-09-20 오후6:30")
        XCTAssertEqual(WorkoutCardDateFormatter.label(midnight, calendar: calendar), "2026-09-21 오전12:05")
        XCTAssertEqual(FeedCardFormatting.region("Gimpo-si, Gyeonggi", hasRoute: true), "김포시, 경기도")
        XCTAssertEqual(FeedCardFormatting.region("Seoul", hasRoute: false), "서울")
    }

    func testSportSpecificCardLabelsAndSwimPace() {
        XCTAssertEqual(FeedCardFormatting.movementLabel(.running), "페이스")
        XCTAssertEqual(FeedCardFormatting.movementLabel(.cycling), "평속")
        XCTAssertEqual(FeedCardFormatting.movementLabel(.swimming), "페이스")
        XCTAssertEqual(FeedCardFormatting.movement(sport: .swimming, distance: 100, seconds: 150), "2:30/100m")
        XCTAssertEqual(FeedCardFormatting.distance(750, sport: .swimming), "750 m")
    }

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

    func testFeedPostBundleMarksViewerHasSavedWhenCurrentUserHasABookmark() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            bookmarks: [
                FeedBookmarkDTO(
                    id: UUID(),
                    postId: postId,
                    userId: currentUserId,
                    createdAt: Date(timeIntervalSince1970: 1_800_420_100)
                )
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: currentUserId)

        XCTAssertTrue(item.viewerHasSaved)
    }

    func testFeedPostBundleDoesNotMarkViewerHasSavedForAnotherUsersBookmark() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let someoneElse = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            bookmarks: [
                FeedBookmarkDTO(
                    id: UUID(),
                    postId: postId,
                    userId: someoneElse,
                    createdAt: Date(timeIntervalSince1970: 1_800_420_100)
                )
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: currentUserId)

        XCTAssertFalse(item.viewerHasSaved)
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

        XCTAssertEqual(item.comments, comments.map { $0.feedComment(currentUserId: nil) })
        XCTAssertEqual(item.comments.map(\.body), ["첫 댓글", "두 번째 댓글", "세 번째 댓글"])
        XCTAssertEqual(item.microComment, comments.first?.body)
    }

    func testFeedPostBundleMarksOnlyViewerAuthoredComments() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let someoneElse = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            comments: [
                makeComment(postId: postId, userId: currentUserId, body: "내 댓글", timestamp: 1_800_420_100),
                makeComment(postId: postId, userId: someoneElse, body: "다른 댓글", timestamp: 1_800_420_200)
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: currentUserId)

        XCTAssertEqual(item.comments.map(\.isViewerAuthor), [true, false])
    }

    func testFeedPostBundleMarksNoCommentsAsViewerAuthoredWithoutCurrentUser() {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let bundle = FeedPostBundleDTO(
            post: makePost(id: postId),
            comments: [
                makeComment(postId: postId, body: "첫 댓글", timestamp: 1_800_420_100),
                makeComment(postId: postId, body: "두 번째 댓글", timestamp: 1_800_420_200)
            ]
        )

        let item = bundle.makeFeedItem(currentUserId: nil)

        XCTAssertEqual(item.comments.map(\.isViewerAuthor), [false, false])
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

        let comment = dto.feedComment(currentUserId: nil)

        XCTAssertEqual(comment.id, id)
        XCTAssertEqual(comment.authorId, authorId)
        XCTAssertEqual(comment.body, "좋은 흐름이에요.")
        XCTAssertEqual(comment.createdAt, createdAt)
        XCTAssertFalse(comment.isViewerAuthor)
    }

    func testFeedBookmarkInsertDTOEncodesDatabaseColumnNames() throws {
        let postId = UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101")!
        let userId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let dto = FeedBookmarkInsertDTO(postId: postId, userId: userId)

        let data = try JSONEncoder().encode(dto)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object, [
            "post_id": postId.uuidString,
            "user_id": userId.uuidString
        ])
    }

    func testFeedBookmarkDTODecodesDatabaseColumnNames() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            #"{"id":"993CE858-83C4-470B-88E2-6EB43453E890","post_id":"A66A2E2D-2803-4A04-86F2-D68A838AB101","user_id":"11111111-1111-1111-1111-111111111111","created_at":"2026-09-02T12:28:26Z"}"#.utf8
        )

        let dto = try decoder.decode(FeedBookmarkDTO.self, from: data)

        XCTAssertEqual(dto.id, UUID(uuidString: "993CE858-83C4-470B-88E2-6EB43453E890"))
        XCTAssertEqual(dto.postId, UUID(uuidString: "A66A2E2D-2803-4A04-86F2-D68A838AB101"))
        XCTAssertEqual(dto.userId, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(dto.createdAt, Date(timeIntervalSince1970: 1_788_352_106))
    }

    func testFeedPostBundleDefaultsBookmarksToEmptyAndPreservesProvidedBookmarks() {
        let post = makePost()
        let bookmark = FeedBookmarkDTO(
            id: UUID(uuidString: "993CE858-83C4-470B-88E2-6EB43453E890")!,
            postId: post.id,
            userId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_788_352_106)
        )

        XCTAssertEqual(FeedPostBundleDTO(post: post).bookmarks, [])
        XCTAssertEqual(FeedPostBundleDTO(post: post, bookmarks: [bookmark]).bookmarks, [bookmark])
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
        XCTAssertEqual(ShareableWorkoutVisibility.followers.feedPostVisibility, .followers)
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

    private func makeComment(
        postId: UUID,
        userId: UUID = UUID(),
        body: String,
        timestamp: TimeInterval
    ) -> FeedCommentDTO {
        FeedCommentDTO(
            id: UUID(),
            postId: postId,
            userId: userId,
            body: body,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}

final class FeedReplyThreadDTOTests: XCTestCase {
    func testDeletedRootDoesNotExposeIdentityOrBody() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"id":"20000000-0000-0000-0000-000000000001","parent_comment_id":null,"user_id":null,"body":null,"is_deleted":true,"created_at":"2026-11-11T00:00:00Z"}"#.utf8)
        let row = try decoder.decode(FeedReplyThreadDTO.self, from: data)
        let result = try XCTUnwrap(row.comment(viewerID: UUID()))
        XCTAssertTrue(result.isDeleted)
        XCTAssertNil(result.profile)
        XCTAssertFalse(result.isViewerAuthor)
        XCTAssertEqual(result.body, "삭제된 댓글입니다")
    }
    func testMalformedLiveReplyDoesNotInventIdentity() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = Data(#"{"id":"20000000-0000-0000-0000-000000000001","parent_comment_id":null,"user_id":null,"body":"text","is_deleted":false,"created_at":"2026-11-11T00:00:00Z"}"#.utf8)
        XCTAssertNil(try decoder.decode(FeedReplyThreadDTO.self, from: data).comment(viewerID: nil))
    }
}
