import XCTest
import Supabase
@testable import SOOM

/// Exercises the production Supabase SDK query/encoding path, with all HTTP
/// intercepted locally. These checks complement, rather than replace, live RLS tests.
@MainActor
final class FeedSupabaseTransportTests: XCTestCase {
    private let owner = UUID()
    private let workout = UUID()

    private var draft: FeedShareDraft {
        FeedShareDraft(id: UUID(), sourceWorkoutId: workout, sport: .cycling,
                      title: "저녁 라이딩", body: "한강에서 👋", distanceMeters: 2_000,
                      durationSeconds: 600, averagePaceSecondsPerKm: 300,
                      routePreviewPayload: nil, photoPlaceholders: [], tags: [],
                      visibility: .privateOnly, createdAt: Date())
    }

    private func receipt(_ ids: [UUID]) -> String {
        "[" + ids.map { "{\"id\":\"\($0.uuidString)\"}" }.joined(separator: ",") + "]"
    }

    func testUnverifiedSocialStopsRemoteReadAndWriteBeforeAnyHTTPRequest() async throws {
        let owner=UUID(),fixture=try FeedHTTPFixture(owner:UUID(),replies:[])
        defer { fixture.close() }
        CommunitySafetyStore.shared.setViewerID(owner)
        CommunitySafetyStore.shared.setSocialVerified(false,owner:owner)
        do {
            try await SupabaseFeedPostManagementRemote(client:fixture.client).editPost(id:UUID(),ownerID:owner,title:"기록",description:"")
            XCTFail("Unverified write must not reach HTTP")
        } catch { XCTAssertEqual(error as? CommunitySafetyError,.socialUnverified) }
        do {
            try await SupabaseFeedPostManagementRemote(client:fixture.client).fetchPost(id:UUID(),viewerID:owner).map { _ in XCTFail("Unverified read") }
            XCTFail("Unverified read must not reach HTTP")
        } catch { XCTAssertEqual(error as? CommunitySafetyError,.socialUnverified) }
        XCTAssertTrue(fixture.exchange.requests.isEmpty)
    }

    func testReshareUpdatesEveryExistingPostWithOwnerAndWorkoutFilters() async throws {
        let ids = [UUID(), UUID()]
        let fixture = try FeedHTTPFixture(owner: owner, replies: [receipt(ids), receipt(ids)])
        defer { fixture.close() }
        try await SupabaseFeedRemoteClient(client: fixture.client, expectedPostingUserID: owner)
            .postPublicPost(draft, visibility: .privatePost)
        let requests = fixture.exchange.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "PATCH"])
        for request in requests {
            XCTAssertEqual(request.path, "/rest/v1/feed_posts")
            XCTAssertEqual(request.query["user_id"]?.lowercased(), "eq.\(owner.uuidString.lowercased())")
            XCTAssertEqual(request.query["source_workout_id"]?.lowercased(), "eq.\(workout.uuidString.lowercased())")
            XCTAssertEqual(request.query["select"], "id")
        }
        let body = try XCTUnwrap(requests.last).jsonBody()
        XCTAssertEqual(body["visibility"] as? String, "private")
        XCTAssertEqual(body["user_id"] as? String, owner.uuidString)
        XCTAssertEqual(body["body"] as? String, draft.body)
        XCTAssertNil(body["id"], "Updating legacy rows must preserve their individual IDs")
    }

    func testNewShareRetryUsesStableAccountWorkoutID() async throws {
        let stableID = SupabaseWorkoutRecordRemote.postID(owner: owner, workout: workout)
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[]", receipt([stableID]), "[]", receipt([stableID])])
        defer { fixture.close() }
        let remote = SupabaseFeedRemoteClient(client: fixture.client, expectedPostingUserID: owner)
        try await remote.postPublicPost(draft, visibility: .privatePost)
        try await remote.postPublicPost(draft, visibility: .privatePost)
        let writes = fixture.exchange.requests.filter { $0.method == "POST" }
        XCTAssertEqual(writes.count, 2)
        for write in writes {
            XCTAssertEqual(try write.jsonBody()["id"] as? String, stableID.uuidString)
            XCTAssertEqual(write.query["on_conflict"], "id")
            XCTAssertTrue(write.prefer.contains("resolution=merge-duplicates"))
            XCTAssertTrue(write.prefer.contains("return=representation"))
        }
    }

    func testReshareRejectsMissingReceiptForOneOfMultipleExistingPosts() async throws {
        let ids = [UUID(), UUID()]
        let fixture = try FeedHTTPFixture(owner: owner, replies: [receipt(ids), receipt([ids[0]])])
        defer { fixture.close() }
        do {
            try await SupabaseFeedRemoteClient(client: fixture.client)
                .postPublicPost(draft, visibility: .privatePost)
            XCTFail("Partial server confirmation must not be reported as success")
        } catch WorkoutRecordManagementError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fixture.exchange.requests.count, 2)
    }

    func testNewShareRejectsEmptyWriteReceipt() async throws {
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[]", "[]"])
        defer { fixture.close() }
        do {
            try await SupabaseFeedRemoteClient(client: fixture.client)
                .postPublicPost(draft, visibility: .privatePost)
            XCTFail("An empty result must not confirm a saved post")
        } catch WorkoutRecordManagementError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCapturedAccountMismatchStopsShareAndManagementBeforeHTTP() async throws {
        let fixture = try FeedHTTPFixture(owner: UUID(), replies: [])
        defer { fixture.close() }
        do {
            try await SupabaseFeedRemoteClient(client: fixture.client, expectedPostingUserID: owner)
                .postPublicPost(draft, visibility: .publicPost)
            XCTFail("Account mismatch must reject sharing")
        } catch CommunitySafetyError.accountChanged {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            try await SupabaseFeedPostManagementRemote(client: fixture.client)
                .setBookmark(postID: UUID(), viewerID: owner, isSaved: true)
            XCTFail("Account mismatch must reject management")
        } catch CommunitySafetyError.accountChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.exchange.requests.isEmpty)
    }

    func testBookmarkRetriesUseInsertOrIgnoreAndRemovalIsOwnerScoped() async throws {
        let post = UUID()
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["", "", ""])
        defer { fixture.close() }
        let remote = SupabaseFeedPostManagementRemote(client: fixture.client)
        try await remote.setBookmark(postID: post, viewerID: owner, isSaved: true)
        try await remote.setBookmark(postID: post, viewerID: owner, isSaved: true)
        try await remote.setBookmark(postID: post, viewerID: owner, isSaved: false)
        let requests = fixture.exchange.requests
        XCTAssertEqual(requests.map(\.method), ["POST", "POST", "DELETE"])
        for write in requests.prefix(2) {
            XCTAssertEqual(write.path, "/rest/v1/feed_bookmarks")
            XCTAssertEqual(write.query["on_conflict"], "post_id,user_id")
            XCTAssertTrue(write.prefer.contains("resolution=ignore-duplicates"))
            XCTAssertEqual(try write.jsonBody()["user_id"] as? String, owner.uuidString)
            XCTAssertEqual(try write.jsonBody()["post_id"] as? String, post.uuidString)
        }
        let deletion = try XCTUnwrap(requests.last)
        XCTAssertEqual(deletion.query["user_id"]?.lowercased(), "eq.\(owner.uuidString.lowercased())")
        XCTAssertEqual(deletion.query["post_id"]?.lowercased(), "eq.\(post.uuidString.lowercased())")
    }

    func testManagementEditsOnlyRequestedFieldsAndScopesEveryWrite() async throws {
        let post = UUID()
        let fixture = try FeedHTTPFixture(owner: owner, replies: Array(repeating: receipt([post]), count: 3))
        defer { fixture.close() }
        let remote = SupabaseFeedPostManagementRemote(client: fixture.client)
        try await remote.editPost(id: post, ownerID: owner, title: "수정", description: "설명 👋")
        try await remote.setVisibility(postID: post, ownerID: owner, visibility: .privatePost)
        try await remote.deletePost(id: post, ownerID: owner)
        let requests = fixture.exchange.requests
        XCTAssertEqual(requests.map(\.method), ["PATCH", "PATCH", "DELETE"])
        XCTAssertEqual(Set(try requests[0].jsonBody().keys), ["title", "body"])
        XCTAssertEqual(try requests[0].jsonBody()["body"] as? String, "설명 👋")
        XCTAssertEqual(Set(try requests[1].jsonBody().keys), ["visibility"])
        for request in requests {
            XCTAssertEqual(request.query["id"]?.lowercased(), "eq.\(post.uuidString.lowercased())")
            XCTAssertEqual(request.query["user_id"]?.lowercased(), "eq.\(owner.uuidString.lowercased())")
            XCTAssertEqual(request.query["select"], "id")
            XCTAssertTrue(request.prefer.contains("return=representation"))
        }
    }

    func testManagementRejectsEmptyEditPrivacyAndDeleteReceipts() async throws {
        let post = UUID()
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[]", "[]", "[]"])
        defer { fixture.close() }
        let remote = SupabaseFeedPostManagementRemote(client: fixture.client)
        for operation in 0..<3 {
            do {
                switch operation {
                case 0: try await remote.editPost(id: post, ownerID: owner, title: "수정", description: "")
                case 1: try await remote.setVisibility(postID: post, ownerID: owner, visibility: .privatePost)
                default: try await remote.deletePost(id: post, ownerID: owner)
                }
                XCTFail("No matching server row must not be reported as success")
            } catch FeedPostManagementError.contentUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(fixture.exchange.requests.count, 3)
    }

    func testAvatarRemovalSendsExplicitNullAndRequiresMatchingReceipt() async throws {
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[{\"avatar_path\":null}]"])
        defer { fixture.close() }
        let result = try await SupabaseProfileStore(client: fixture.client).updateAvatar(nil, expectedUserID: owner)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.exchange.requests.count, 1)
        let request = try XCTUnwrap(fixture.exchange.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/update_profile_avatar_v1")
        let body = try request.jsonBody()
        XCTAssertEqual(body["p_expected_user_id"] as? String, owner.uuidString)
        XCTAssertTrue(body["p_avatar_path"] is NSNull, "Removing the photo must send SQL null instead of omitting the argument")
    }

    func testAvatarReadIsOwnerScopedAndEmptyMutationReceiptFails() async throws {
        let path = owner.uuidString.lowercased() + "/10000000-0000-0000-0000-000000000001.jpg"
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[{\"avatar_path\":\"\(path)\"}]", "[]"])
        defer { fixture.close() }
        let store = SupabaseProfileStore(client: fixture.client)
        let restored = await store.readAvatarPath(expectedUserID: owner)
        XCTAssertEqual(restored, path)
        let read = try XCTUnwrap(fixture.exchange.requests.first)
        XCTAssertEqual(read.path, "/rest/v1/profiles")
        XCTAssertEqual(read.query["select"], "avatar_path")
        XCTAssertEqual(read.query["id"]?.lowercased(), "eq." + owner.uuidString.lowercased())
        do {
            _ = try await store.updateAvatar(nil, expectedUserID: owner)
            XCTFail("An empty response cannot confirm removal")
        } catch ProfileAvatarError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testAvatarAccountMismatchStopsReadAndWriteBeforeHTTP() async throws {
        let fixture = try FeedHTTPFixture(owner: UUID(), replies: [])
        defer { fixture.close() }
        let store = SupabaseProfileStore(client: fixture.client)
        let result = await store.readAvatarPath(expectedUserID: owner)
        XCTAssertNil(result)
        do {
            _ = try await store.updateAvatar(nil, expectedUserID: owner)
            XCTFail("A stale editor cannot remove another account's photo")
        } catch ProfileAvatarError.accountChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.exchange.requests.isEmpty)
    }

    func testWorkoutPhotoReadStopsBeforeHTTPAfterAccountMismatch() async throws {
        let fixture = try FeedHTTPFixture(owner: UUID(), replies: [])
        defer { fixture.close() }
        do {
            _ = try await WorkoutPhotoService(client: fixture.client).load(workoutID: workout, ownerID: owner)
            XCTFail("Must not read another account's photos")
        } catch CommunitySafetyError.accountChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.exchange.requests.isEmpty)
    }

    func testWorkoutPhotoReplacementRequiresMatchingServerReceipt() async throws {
        let post = UUID(), photo = UUID()
        let path = WorkoutPhotoPolicy.path(ownerID: owner, postID: post, photoID: photo)
        let postJSON = "[{\"id\":\"\(post)\",\"user_id\":\"\(owner)\",\"source_workout_id\":\"\(workout)\",\"sport\":\"running\",\"title\":\"운동\",\"visibility\":\"private\",\"created_at\":\"2026-09-22T00:00:00Z\"}]"
        let mediaJSON = "[{\"id\":\"\(photo)\",\"post_id\":\"\(post)\",\"media_type\":\"photo\",\"storage_path\":\"\(path)\",\"sort_order\":0}]"
        let fixture = try FeedHTTPFixture(owner: owner, replies: [postJSON, mediaJSON, "[]"])
        defer { fixture.close() }
        let value = UnifiedWorkout(id: workout, externalId: nil, source: .soomLocal, workoutType: .running,
            startDate: Date(), endDate: Date(), durationSeconds: 60, distanceMeters: 100,
            activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil, averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil, dataQuality: .partial, createdAt: Date(), updatedAt: Date())
        do {
            try await WorkoutPhotoService(client: fixture.client).replace(workout: value, ownerID: owner,
                photos: [WorkoutPhotoDraft(reference: .init(id: photo, storagePath: path))], expectedPhotoIDs: [photo])
            XCTFail("Empty server receipt cannot confirm a retained photo")
        } catch WorkoutPhotoError.uploadUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        let requests = fixture.exchange.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "GET", "POST"])
        let mutation = try XCTUnwrap(requests.last)
        XCTAssertEqual(mutation.path, "/rest/v1/rpc/replace_workout_photos_v1")
        let body = try mutation.jsonBody()
        XCTAssertEqual(body["p_post_id"] as? String, post.uuidString)
        XCTAssertEqual(body["p_expected_photo_ids"] as? [String], [photo.uuidString])
        XCTAssertEqual((body["p_photos"] as? [[String: Any]])?.first?["storage_path"] as? String, path)
    }
}

extension FeedSupabaseTransportTests {
    func testClubPublicFeedNeverQueriesWithoutMembers() async throws {
        let fixture = try FeedHTTPFixture(owner: owner, replies: [])
        defer { fixture.close() }
        let result = try await SupabaseFeedRemoteClient(client: fixture.client)
            .fetchPublicMemberPosts(authorIDs: [], viewerID: owner, limit: 20)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(fixture.exchange.requests.isEmpty)
    }

    func testClubPublicFeedChunksEveryMemberAndBoundsPostLimit() async throws {
        let members = (0..<201).map { _ in UUID() }
        let fixture = try FeedHTTPFixture(owner: owner, replies: ["[]", "[]", "[]"])
        defer { fixture.close() }
        _ = try await SupabaseFeedRemoteClient(client: fixture.client)
            .fetchPublicMemberPosts(authorIDs: members + [members[0]], viewerID: owner, limit: 500)
        let reads = fixture.exchange.requests
        XCTAssertEqual(reads.count, 3)
        for read in reads {
            XCTAssertEqual(read.path, "/rest/v1/feed_posts")
            XCTAssertEqual(read.query["visibility"], "eq.public")
            XCTAssertEqual(read.query["limit"], "50")
            XCTAssertNil(read.query["or"], "An owner exception would expose own private posts in the club")
            XCTAssertTrue((read.query["user_id"] ?? "").hasPrefix("in.("))
        }
        let filters = reads.compactMap { $0.query["user_id"] }.joined().lowercased()
        for id in members { XCTAssertTrue(filters.contains(id.uuidString.lowercased())) }
    }

    func testClubPublicFeedRejectsPrivateAndNonMemberRowsBeforeHydration() async throws {
        let outsider = UUID()
        let rows = """
        [{"id":"\(UUID())","user_id":"\(owner)","sport":"running","title":"private","visibility":"private","created_at":"2026-09-22T00:00:00Z"},
         {"id":"\(UUID())","user_id":"\(outsider)","sport":"running","title":"outsider","visibility":"public","created_at":"2026-09-22T00:00:00Z"}]
        """
        let fixture = try FeedHTTPFixture(owner: owner, replies: [rows])
        defer { fixture.close() }
        let result = try await SupabaseFeedRemoteClient(client: fixture.client)
            .fetchPublicMemberPosts(authorIDs: [owner], viewerID: owner, limit: 20)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(fixture.exchange.requests.count, 1)
    }

    func testClubWorkoutFeedRequiresServerConfirmedMembershipBeforeReadingPosts() async throws {
        let club = UUID()
        let clubRow = "[{\"id\":\"\(club)\",\"owner_user_id\":\"\(UUID())\"}]"
        let fixture = try FeedHTTPFixture(owner: owner, replies: [clubRow, "[]"])
        defer { fixture.close() }
        do {
            _ = try await SupabaseClubWorkoutFeedRemote(client: fixture.client).fetch(clubID: club, viewerID: owner, limit: 20)
            XCTFail("A readable open club is not proof that the viewer is a member")
        } catch ClubWorkoutFeedError.membershipRequired {} catch { XCTFail("\(error)") }
        XCTAssertEqual(fixture.exchange.requests.map(\.path), ["/rest/v1/clubs", "/rest/v1/club_members"])
        XCTAssertEqual(fixture.exchange.requests.last?.query["club_id"]?.lowercased(), "eq.\(club.uuidString.lowercased())")
        XCTAssertEqual(fixture.exchange.requests.last?.query["user_id"]?.lowercased(), "eq.\(owner.uuidString.lowercased())")
    }

    func testClubWorkoutFeedPagesMembershipInsteadOfDroppingLargeClubMembers() async throws {
        let club = UUID()
        let clubRow = "[{\"id\":\"\(club)\",\"owner_user_id\":\"\(owner)\"}]"
        let viewerRow = "[{\"user_id\":\"\(owner)\"}]"
        let members = (0..<501).map { _ in UUID() }
        func memberJSON(_ ids: [UUID]) -> String {
            "[" + ids.map { "{\"user_id\":\"\($0)\"}" }.joined(separator: ",") + "]"
        }
        let replies = [clubRow, viewerRow, memberJSON(Array(members.prefix(500))), memberJSON([members[500]])]
            + Array(repeating: "[]", count: 6) + [clubRow, viewerRow]
        let fixture = try FeedHTTPFixture(owner: owner, replies: replies)
        defer { fixture.close() }
        let result = try await SupabaseClubWorkoutFeedRemote(client: fixture.client)
            .fetch(clubID: club, viewerID: owner, limit: 20)
        XCTAssertTrue(result.isEmpty)
        let memberPages = fixture.exchange.requests.filter { $0.path == "/rest/v1/club_members" && $0.query["user_id"] == nil }
        XCTAssertEqual(memberPages.count, 2)
        XCTAssertEqual(memberPages.map { $0.query["offset"] }, ["0", "500"])
        XCTAssertTrue(memberPages.allSatisfy { $0.query["limit"] == "500" })
        let publicQueries = fixture.exchange.requests.filter { $0.path == "/rest/v1/feed_posts" }
        XCTAssertEqual(publicQueries.count, 6)
        let filters = publicQueries.compactMap { $0.query["user_id"] }.joined().lowercased()
        XCTAssertTrue(filters.contains(members[500].uuidString.lowercased()))
    }

    func testClubWorkoutFeedRechecksClubAccessAfterRead() async throws {
        let club = UUID()
        let clubRow = "[{\"id\":\"\(club)\",\"owner_user_id\":\"\(owner)\"}]"
        let viewerRow = "[{\"user_id\":\"\(owner)\"}]"
        let fixture = try FeedHTTPFixture(owner: owner, replies: [clubRow, viewerRow, viewerRow, "[]", "[]"])
        defer { fixture.close() }
        do {
            _ = try await SupabaseClubWorkoutFeedRemote(client: fixture.client).fetch(clubID: club, viewerID: owner, limit: 20)
            XCTFail("A hidden/deleted club must invalidate the response")
        } catch ClubWorkoutFeedError.unavailable {} catch { XCTFail("\(error)") }
        XCTAssertEqual(fixture.exchange.requests.last?.path, "/rest/v1/clubs")
    }
}

private final class FeedHTTPMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}

private struct FeedHTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let prefer: String
    let body: Data
    init(_ request: URLRequest) {
        method = request.httpMethod ?? ""
        path = request.url?.path ?? ""
        query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
        if let data = request.httpBody { body = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else { body = Data() }
    }
    func jsonBody() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private final class FeedHTTPExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [FeedHTTPRequest] = []
    private var replies: [String]
    init(replies: [String]) { self.replies = replies }
    var requests: [FeedHTTPRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func receive(_ request: URLRequest) -> String? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(FeedHTTPRequest(request))
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

private final class FeedHTTPRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var exchanges: [String: FeedHTTPExchange] = [:]
    func set(_ host: String, _ exchange: FeedHTTPExchange?) {
        lock.lock(); defer { lock.unlock() }; exchanges[host] = exchange
    }
    func get(_ host: String) -> FeedHTTPExchange? {
        lock.lock(); defer { lock.unlock() }; return exchanges[host]
    }
}

private final class FeedHTTPProtocol: URLProtocol {
    static let registry = FeedHTTPRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let exchange = Self.registry.get(url.host ?? ""), let body = exchange.receive(request) else {
            // Unexpected requests fail locally; the fixture never falls through to real networking.
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class FeedHTTPFixture {
    let client: SupabaseClient
    let exchange: FeedHTTPExchange
    private let host = UUID().uuidString.lowercased() + ".invalid"
    private let session: URLSession
    init(owner: UUID, replies: [String]) throws {
        CommunitySafetyStore.shared.setViewerID(owner)
        CommunitySafetyStore.shared.setSocialVerified(true,owner:owner)
        exchange = FeedHTTPExchange(replies: replies)
        let storage = FeedHTTPMemoryStorage()
        let now = Date()
        let user = User(id: owner, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                        createdAt: now, updatedAt: now)
        let authSession = Session(accessToken: "local-test-token", tokenType: "bearer", expiresIn: 3600,
                                  expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "local-test-refresh", user: user)
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        try storage.store(key: "feed-http-test", value: encoder.encode(authSession))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedHTTPProtocol.self]
        session = URLSession(configuration: configuration)
        client = SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "local-test-key",
                                options: .init(auth: .init(storage: storage, storageKey: "feed-http-test",
                                                           autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
                                               global: .init(session: session)))
        FeedHTTPProtocol.registry.set(host, exchange)
    }
    func close() { session.invalidateAndCancel(); FeedHTTPProtocol.registry.set(host, nil) }
}

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
        XCTAssertEqual(draft.title, "라이딩 기록")
        XCTAssertEqual(draft.body, "")
        XCTAssertEqual(draft.distanceMeters, 8_200)
        XCTAssertEqual(draft.durationSeconds, 2_460)
        XCTAssertEqual(draft.averagePaceSecondsPerKm, 300)
        XCTAssertEqual(draft.visibility, .draft)
        XCTAssertEqual(draft.createdAt, now)
        XCTAssertEqual(draft.routePreviewPayload?.distanceText, "8.2 km")
        XCTAssertTrue(draft.tags.contains("라이딩"))
    }

    func testDraftUsesEditedWorkoutTitleAndFullDescriptionInCardAndDetailFields() {
        var item = workout()
        item.userTitle = "  해 질 무렵 한강 라이딩  "
        item.userDescription = "천천히 돌아온 길. 다음에는 조금 더 멀리!"
        let draft = FeedShareDraftBuilder().build(from: item)
        XCTAssertEqual(draft.title, "해 질 무렵 한강 라이딩")
        XCTAssertEqual(draft.body, item.userDescription)
        let feedItem = draft.makeFeedItem()
        XCTAssertEqual(feedItem.caption, item.userDescription)
        guard case .workoutSession(let card) = feedItem.cardData else { return XCTFail("Expected workout card") }
        XCTAssertEqual(card.title, draft.title)
        XCTAssertEqual(card.primaryMessage, item.userDescription)
    }

    func testDraftPreservesUnicodeAndWhitespaceWithinUserDescription() {
        var item = workout()
        item.userTitle = "가족과 함께 👨‍👩‍👧‍👦"
        item.userDescription = String(repeating: "👨‍👩‍👧‍👦", count: 98) + " 한"
        let draft = FeedShareDraftBuilder().build(from: item)
        XCTAssertEqual(draft.title, item.userTitle)
        XCTAssertEqual(draft.body, item.userDescription)
        XCTAssertEqual(draft.body.count, 100)
    }

    func testMissingOrEmptyDescriptionNeverCreatesAnInventedCaption() {
        for description: String? in [nil, ""] {
            var item = workout()
            item.userDescription = description
            let draft = FeedShareDraftBuilder().build(from: item)
            XCTAssertTrue(draft.body.isEmpty)
            XCTAssertEqual(draft.makeFeedItem().caption, "")
        }
    }

    func testMissingOrWhitespaceOnlyTitleUsesExistingWorkoutDisplayTitle() {
        for title: String? in [nil, "  "] {
            var item = workout()
            item.userTitle = title
            let draft = FeedShareDraftBuilder().build(from: item)
            XCTAssertEqual(draft.title, "라이딩 기록")
        }
    }

    func testDraftFeedItemIsMarkedAsLocalDraft() {
        let draft = FeedShareDraftBuilder(
            dateProvider: { self.now },
            idProvider: { self.draftID }
        ).build(from: workout())

        let item = draft.makeFeedItem()

        XCTAssertTrue(item.isLocalDraft)
    }

    func testDraftDoesNotIncludeRecoveryGuidanceInFeedFields() {
        let draft = FeedShareDraftBuilder(
            dateProvider: { self.now },
            idProvider: { self.draftID }
        ).build(from: workout(distanceMeters: nil, durationSeconds: 1_200))

        let item = draft.makeFeedItem()

        XCTAssertNil(item.recoveryCue)
        XCTAssertEqual(item.sourceWorkoutId, workoutID)
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

        let outcome = try await coordinator.handle(.shareToFeed, workout: workout())
        let savedDrafts = try await store.fetchDrafts()

        XCTAssertEqual(outcome?.draft.id, draftID)
        XCTAssertEqual(outcome?.postedRemotely, false)
        XCTAssertEqual(outcome?.visibility, .privateOnly)
        XCTAssertEqual(savedDrafts.map(\.id), [draftID])
    }

    func testLaterActionDoesNotCreateDraftOrPublishWithExistingPublicPreference() async throws {
        let store = InMemoryFeedShareDraftStore()
        var receivedVisibilities: [FeedPostVisibility] = []
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(
                result: .success(()),
                receivedVisibility: { receivedVisibilities.append($0) }
            ),
            visibilityProvider: { .publicFeed }
        )

        let outcome = try await coordinator.handle(.later, workout: workout())
        let savedDrafts = try await store.fetchDrafts()

        XCTAssertNil(outcome)
        XCTAssertTrue(savedDrafts.isEmpty)
        XCTAssertTrue(receivedVisibilities.isEmpty, "Declining to share must never invoke the remote poster")
    }

    func testSuccessfulRemotePostSkipsLocalDraftToAvoidDuplicate() async throws {
        let store = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()))
        )

        let outcome = try await coordinator.handle(.shareToFeed, workout: workout())
        let savedDrafts = try await store.fetchDrafts()

        XCTAssertEqual(outcome?.postedRemotely, true)
        XCTAssertTrue(savedDrafts.isEmpty, "a successful remote post must not also write a local draft")
    }

    func testSuccessfulRemotePostUsesInjectedVisibilityProvider() async throws {
        let store = InMemoryFeedShareDraftStore()
        var receivedVisibilities: [FeedPostVisibility] = []
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(
                result: .success(()),
                receivedVisibility: { receivedVisibilities.append($0) }
            ),
            visibilityProvider: { .publicFeed }
        )

        let outcome = try await coordinator.handle(.shareToFeed, workout: workout())

        XCTAssertEqual(receivedVisibilities, [.publicPost])
        XCTAssertEqual(outcome?.visibility, .publicFeed)
    }

    func testSuccessfulRemotePostDefaultsToPrivateVisibilityProvider() async throws {
        let store = InMemoryFeedShareDraftStore()
        var receivedVisibilities: [FeedPostVisibility] = []
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(
                result: .success(()),
                receivedVisibility: { receivedVisibilities.append($0) }
            ),
            visibilityProvider: { .privateOnly }
        )

        let outcome = try await coordinator.handle(.shareToFeed, workout: workout())

        XCTAssertEqual(receivedVisibilities, [.privatePost])
        XCTAssertEqual(outcome?.visibility, .privateOnly)
    }

    func testSummaryMessageReflectsActualOutcome() {
        let localOnly = RecordShareOutcome(draft: makeDraft(), postedRemotely: false, visibility: .privateOnly)
        let remotePrivate = RecordShareOutcome(draft: makeDraft(), postedRemotely: true, visibility: .privateOnly)
        let remotePublic = RecordShareOutcome(draft: makeDraft(), postedRemotely: true, visibility: .publicFeed)

        XCTAssertEqual(localOnly.summaryMessage, "온라인에 게시되지 않았어요. 이 기기에 공유 초안으로 저장했어요.")
        XCTAssertEqual(remotePrivate.summaryMessage, "피드에 나만 보기로 게시했어요.")
        XCTAssertEqual(remotePublic.summaryMessage, "피드에 공개로 게시했어요.")
        var rankingPending = remotePublic
        rankingPending.rankingRegistrationPending = true
        XCTAssertTrue(rankingPending.postedRemotely)
        XCTAssertTrue(rankingPending.summaryMessage.contains("랭킹 반영은 대기 중"))
    }

    func testConfirmedPublicationLocalFinalizeFailureRemainsPublished() {
        var outcome = RecordShareOutcome(draft: makeDraft(), postedRemotely: true, visibility: .publicFeed)
        var attempts = 0
        outcome.finalizeConfirmedPublication {
            attempts += 1
            throw FeedRepositoryError.remoteFailed
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(outcome.postedRemotely)
        XCTAssertTrue(outcome.localFinalizationPending)
        XCTAssertTrue(outcome.summaryMessage.contains("피드에 공개로 게시했어요."))
        XCTAssertTrue(outcome.summaryMessage.contains("다시 게시하지 말고"))
    }

    func testLocalDraftDoesNotFinalizeRemotePublication() {
        var outcome = RecordShareOutcome(draft: makeDraft(), postedRemotely: false, visibility: .privateOnly)
        var called = false
        outcome.finalizeConfirmedPublication { called = true }
        XCTAssertFalse(called)
        XCTAssertFalse(outcome.localFinalizationPending)
    }

    func testUnconfirmedRemotePostNeverCreatesLocalFallback() async throws {
        let store = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(result: .failure(FeedRepositoryError.remoteFailed))
        )

        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("Unconfirmed remote publication must not be reported as a local-only draft")
        } catch { XCTAssertEqual(error as? RecordSharePublicationError, .resultUnconfirmed) }
        let savedDrafts = try await store.fetchDrafts()
        XCTAssertTrue(savedDrafts.isEmpty)
    }

    func testServerModerationAndSuspensionDoNotBecomeSuccessfulLocalShareDrafts() async throws {
        for message in ["SOOM_CONTENT_REJECTED", "SOOM_TEXT_TOO_LONG", "SOOM_ACCOUNT_SUSPENDED"] {
            let store = InMemoryFeedShareDraftStore()
            let rejection = SharePolicyRejection(description: message)
            let coordinator = RecordShareDraftCoordinator(
                store: store,
                remotePoster: StubFeedRemotePostPosting(result: .failure(rejection))
            )
            do {
                _ = try await coordinator.handle(.shareToFeed, workout: workout())
                XCTFail("Server rejection must propagate: \(message)")
            } catch { XCTAssertEqual(String(describing: error), message) }
            let drafts = try await store.fetchDrafts()
            XCTAssertTrue(drafts.isEmpty)
        }
    }

    func testFileStoreDeleteDraftRemovesOnlyTheMatchingDraft() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedShareDraftTests-\(UUID().uuidString).json")
        let store = FileFeedShareDraftStore(fileURL: fileURL)
        let kept = makeDraft(id: UUID(), sourceWorkoutId: UUID())
        let deleted = makeDraft(id: UUID(), sourceWorkoutId: UUID())

        try await store.saveDraft(kept)
        try await store.saveDraft(deleted)
        try await store.deleteDraft(id: deleted.id)
        let remaining = try await store.fetchDrafts()

        XCTAssertEqual(remaining.map(\.id), [kept.id])
    }

    func testFileStoreDeleteAllDraftsRemovesEverySavedDraft() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedShareDraftTests-\(UUID().uuidString).json")
        let store = FileFeedShareDraftStore(fileURL: fileURL)
        let draft = FeedShareDraftBuilder(
            dateProvider: { self.now },
            idProvider: { self.draftID }
        ).build(from: workout())

        try await store.saveDraft(draft)
        try await store.deleteAllDrafts()
        let remaining = try await store.fetchDrafts()

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFileStoreDeleteAllDraftsIsSafeWhenNothingWasEverSaved() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedShareDraftTests-\(UUID().uuidString).json")
        let store = FileFeedShareDraftStore(fileURL: fileURL)

        try await store.deleteAllDrafts()
        let remaining = try await store.fetchDrafts()

        XCTAssertTrue(remaining.isEmpty)
    }

    private func makeDraft(id: UUID? = nil, sourceWorkoutId: UUID? = nil) -> FeedShareDraft {
        let built = FeedShareDraftBuilder(dateProvider: { self.now }, idProvider: { id ?? self.draftID }).build(from: workout())
        guard let sourceWorkoutId else {
            return built
        }

        return FeedShareDraft(
            id: built.id,
            sourceWorkoutId: sourceWorkoutId,
            sport: built.sport,
            title: built.title,
            body: built.body,
            distanceMeters: built.distanceMeters,
            durationSeconds: built.durationSeconds,
            averagePaceSecondsPerKm: built.averagePaceSecondsPerKm,
            routePreviewPayload: built.routePreviewPayload,
            photoPlaceholders: built.photoPlaceholders,
            tags: built.tags,
            visibility: built.visibility,
            createdAt: built.createdAt
        )
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

    func deleteDraft(id: UUID) async throws {
        drafts.removeAll { $0.id == id }
    }

    func deleteAllDrafts() async throws {
        drafts.removeAll()
    }
}

private struct StubFeedRemotePostPosting: FeedRemotePostPosting {
    let result: Result<Void, Error>
    let receivedVisibility: (FeedPostVisibility) -> Void

    init(result: Result<Void, Error>, receivedVisibility: @escaping (FeedPostVisibility) -> Void = { _ in }) {
        self.result = result
        self.receivedVisibility = receivedVisibility
    }

    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws {
        receivedVisibility(visibility)
        try result.get()
    }

    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws {}
}

private struct SharePolicyRejection: Error, CustomStringConvertible {
    let description: String
}

extension FeedShareDraftTests {
    func testAccountDraftFilesRemainIsolatedAcrossLateSaveAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOOM-Draft-Scope-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urlA = directory.appendingPathComponent("a/drafts.json")
        let urlB = directory.appendingPathComponent("b/drafts.json")
        let a = FileFeedShareDraftStore(fileURL: urlA)
        let b = FileFeedShareDraftStore(fileURL: urlB)
        let draft = FeedShareDraftBuilder().build(from: workout())
        try await a.saveDraft(draft)
        let before = try await b.fetchDrafts()
        XCTAssertTrue(before.isEmpty)
        try await a.saveDraft(draft)
        let after = try await b.fetchDrafts()
        XCTAssertTrue(after.isEmpty)
        let reopened = FileFeedShareDraftStore(fileURL: urlA)
        let restored = try await reopened.fetchDrafts()
        XCTAssertEqual(restored.map(\.id), [draft.id])
        try await b.deleteAllDrafts()
        let stillA = try await a.fetchDrafts()
        XCTAssertEqual(stillA.map(\.id), [draft.id])
        XCTAssertEqual(try urlA.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
}


extension FeedShareDraftTests {
    @MainActor
    func testResolvedRegionIsInDraftBeforePublicPostPreparation() async throws {
        let store = InMemoryFeedShareDraftStore()
        var steps: [String] = []
        let coordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(())),
            visibilityProvider: { .publicFeed },
            prepareWorkout: { value in
                steps.append("region")
                var resolved = value
                resolved.locationName = "경기도 김포시"
                return resolved
            },
            prepareRemoteShare: { value in
                XCTAssertEqual(value.locationName, "경기도 김포시")
                steps.append("route")
            })
        let result = try await coordinator.handle(.shareToFeed, workout: workout())
        XCTAssertEqual(steps, ["region", "route"])
        XCTAssertEqual(result?.draft.locationName, "경기도 김포시")
        XCTAssertEqual(result?.postedRemotely, true)
    }

    @MainActor
    func testAccountChangeDuringRegionPreparationStopsPublication() async throws {
        let scope = ShareTestAccountScope()
        let expectedOwner = scope.owner
        let store = InMemoryFeedShareDraftStore()
        var published = false
        let coordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()),
                receivedVisibility: { _ in published = true }),
            visibilityProvider: { .publicFeed },
            validateContext: { try scope.validate(expectedOwner) },
            prepareWorkout: { value in scope.owner = UUID(); return value })
        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("A changed account must not publish an enriched region")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertFalse(published)
        let drafts = try await store.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    @MainActor
    func testRoutePreparationCompletesBeforeExplicitPublicPost() async throws {
        let store = InMemoryFeedShareDraftStore()
        var steps: [String] = []
        let coordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()), receivedVisibility: { visibility in
                XCTAssertEqual(visibility, .publicPost)
                steps.append("publish")
            }), visibilityProvider: { .publicFeed },
            prepareRemoteShare: { value in
                XCTAssertEqual(value.id, self.workoutID)
                steps.append("masked image uploaded")
            })
        let result = try await coordinator.handle(.shareToFeed, workout: workout())
        XCTAssertEqual(steps, ["masked image uploaded", "publish"])
        XCTAssertEqual(result?.postedRemotely, true)
    }

    @MainActor
    func testPrivateGuestAndLaterActionsNeverUploadRouteSnapshot() async throws {
        var prepared = 0
        let store = InMemoryFeedShareDraftStore()
        let privateCoordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(())), visibilityProvider: { .privateOnly },
            prepareRemoteShare: { _ in prepared += 1 })
        _ = try await privateCoordinator.handle(.shareToFeed, workout: workout())
        let guestCoordinator = RecordShareDraftCoordinator(store: store, visibilityProvider: { .publicFeed },
            prepareRemoteShare: { _ in prepared += 1 })
        _ = try await guestCoordinator.handle(.shareToFeed, workout: workout())
        let publicCoordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(())), visibilityProvider: { .publicFeed },
            prepareRemoteShare: { _ in prepared += 1 })
        _ = try await publicCoordinator.handle(.later, workout: workout())
        XCTAssertEqual(prepared, 0)
    }

    @MainActor
    func testRoutePreparationFailureDoesNotPublishOrBecomeSuccessfulFallback() async throws {
        let store = InMemoryFeedShareDraftStore()
        var published = false
        let coordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()), receivedVisibility: { _ in published = true }),
            visibilityProvider: { .publicFeed },
            prepareRemoteShare: { _ in throw WorkoutRouteSnapshotError.unavailable })
        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("Failed route preparation must remain a retryable error")
        } catch { XCTAssertTrue(error is WorkoutRouteSnapshotError) }
        XCTAssertFalse(published)
        let drafts = try await store.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    @MainActor
    func testAccountChangeAfterRoutePreparationStopsVisibilityWriteAndFallback() async throws {
        let scope = ShareTestAccountScope()
        let originalOwner = scope.owner
        let store = InMemoryFeedShareDraftStore()
        var published = false
        let coordinator = RecordShareDraftCoordinator(store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()), receivedVisibility: { _ in published = true }),
            visibilityProvider: { .publicFeed }, validateContext: { try scope.validate(originalOwner) },
            prepareRemoteShare: { _ in scope.owner = UUID() })
        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("Changed account must not finish a public share")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertFalse(published)
        let drafts = try await store.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    @MainActor
    func testQueuedShareCannotUseAnAccountSelectedAfterTheButtonTap() async throws {
        let scope = ShareTestAccountScope()
        let originalOwner = scope.owner
        let store = InMemoryFeedShareDraftStore()
        var posted = false
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(result: .success(()), receivedVisibility: { _ in posted = true }),
            validateContext: { try scope.validate(originalOwner) }
        )
        scope.owner = UUID()

        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("A queued share must reject a different account before any side effect")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        XCTAssertFalse(posted)
        let drafts = try await store.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    @MainActor
    func testAccountChangeDuringRemoteResponsePreventsStaleSuccessAndLocalFallback() async throws {
        for remoteFailure in [false, true] {
            let scope = ShareTestAccountScope()
            let originalOwner = scope.owner
            let store = InMemoryFeedShareDraftStore()
            let remote = SuspendedShareTestPoster()
            let coordinator = RecordShareDraftCoordinator(
                store: store, remotePoster: remote,
                validateContext: { try scope.validate(originalOwner) }
            )
            let task = Task { try await coordinator.handle(.shareToFeed, workout: workout()) }
            await remote.waitUntilStarted()
            // Cover both switching to B and signing out while the request
            // is genuinely suspended, with success and error responses.
            scope.owner = remoteFailure ? UUID() : nil
            await remote.finish(error: remoteFailure ? FeedRepositoryError.remoteFailed : nil)

            do {
                _ = try await task.value
                XCTFail("The old account response must not publish success or create a fallback draft")
            } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
            let drafts = try await store.fetchDrafts()
            XCTAssertTrue(drafts.isEmpty)
        }
    }

    func testRemoteAccountRejectionNeverBecomesLocalFallbackWithoutAContextValidator() async throws {
        let store = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(
            store: store,
            remotePoster: StubFeedRemotePostPosting(result: .failure(CommunitySafetyError.accountChanged))
        )
        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("An explicit remote account rejection must propagate")
        } catch { XCTAssertEqual(error as? CommunitySafetyError, .accountChanged) }
        let drafts = try await store.fetchDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    @MainActor
    func testSameAccountNetworkFailureDoesNotInventLocalOnlyOutcome() async throws {
        let scope = ShareTestAccountScope()
        let originalOwner = scope.owner
        let originalStore = InMemoryFeedShareDraftStore()
        let otherStore = InMemoryFeedShareDraftStore()
        let coordinator = RecordShareDraftCoordinator(
            store: originalStore,
            remotePoster: StubFeedRemotePostPosting(result: .failure(FeedRepositoryError.remoteFailed)),
            validateContext: { try scope.validate(originalOwner) }
        )

        do {
            _ = try await coordinator.handle(.shareToFeed, workout: workout())
            XCTFail("Uncertain publication cannot become an automatic fallback")
        } catch { XCTAssertEqual(error as? RecordSharePublicationError, .resultUnconfirmed) }
        let originalDrafts = try await originalStore.fetchDrafts()
        let otherDrafts = try await otherStore.fetchDrafts()
        XCTAssertTrue(originalDrafts.isEmpty)
        XCTAssertTrue(otherDrafts.isEmpty)
    }
}

@MainActor
private final class ShareTestAccountScope {
    var owner: UUID? = UUID()
    func validate(_ expected: UUID?) throws {
        guard owner == expected else { throw CommunitySafetyError.accountChanged }
    }
}

private actor SuspendedShareTestPoster: FeedRemotePostPosting {
    private var completion: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func postPublicPost(_ draft: FeedShareDraft, visibility: FeedPostVisibility) async throws {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            hasStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(error: Error?) {
        if let error { completion?.resume(throwing: error) }
        else { completion?.resume() }
        completion = nil
    }

    func updatePostVisibility(sourceWorkoutId: UUID, visibility: FeedPostVisibility) async throws {}
}

extension FeedShareDraftTests {
    func testConfirmedDeletedAccountCannotRecreateDraftFile() async throws {
        let owner = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SOOM-Retired-Draft-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(owner.uuidString.lowercased()).appendingPathComponent("feed_share_drafts.json")
        let store = FileFeedShareDraftStore(fileURL: url)
        let draft = FeedShareDraftBuilder().build(from: workout())
        AccountDeletionWriteFence.shared.retire(owner)
        do {
            try await store.saveDraft(draft)
            XCTFail("A confirmed deleted account must reject a delayed draft save")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
