import Supabase
import XCTest
@testable import SOOM

final class SupabaseClientProviderTests: XCTestCase {
    func testUnconfiguredEnvironmentDoesNotCreateClient() {
        let provider = SupabaseClientProvider(environment: .local)

        XCTAssertEqual(provider.state, .unconfigured)
        XCTAssertNil(provider.makeClient())
    }

    func testPlaceholderValuesDoNotCreateClient() {
        let environment = AuthEnvironment(
            environment: .development,
            supabaseURL: URL(string: "https://example.supabase.co"),
            supabaseAnonKey: "$(SOOM_SUPABASE_ANON_KEY)",
            redirectScheme: "$(SOOM_AUTH_REDIRECT_SCHEME)"
        )
        let provider = SupabaseClientProvider(environment: environment)

        XCTAssertEqual(provider.state, .unconfigured)
        XCTAssertNil(provider.makeClient())
    }

    func testConfiguredMockValuesCreateClient() {
        let configuration = SupabaseAuthConfiguration(
            projectURL: URL(string: "https://example.supabase.co"),
            anonKey: "anon-test-key"
        )
        let provider = SupabaseClientProvider(configuration: configuration)

        XCTAssertEqual(provider.state, .ready)
        XCTAssertNotNil(provider.makeClient())
    }

    func testProviderDoesNotUseRecoveryCalculator() {
        let provider = SupabaseClientProvider(configuration: .empty)

        XCTAssertNil(provider.makeClient())
    }

    func testHostlessProjectURLDegradesInsteadOfCrashing() {
        // Regression for the fatal error SupabaseClient(supabaseURL:) throws
        // on a hostless URL — this must resolve to .unconfigured/nil well
        // before that constructor is ever reached.
        let configuration = SupabaseAuthConfiguration(projectURL: URL(string: "https:"), anonKey: "anon-test-key")
        let provider = SupabaseClientProvider(configuration: configuration)

        XCTAssertEqual(provider.state, .unconfigured)
        XCTAssertNil(provider.makeClient())
    }

    func testMatchingFeatureProvidersReuseExactAuthOwnedClient() throws {
        let registry = SupabaseAppClientRegistry()
        let configuration = configuration(host: "auth-owner.supabase.co")
        let owner = try XCTUnwrap(SupabaseClientProvider(configuration: configuration, clientRegistry: registry).makeClient())
        registry.install(owner, configuration: configuration)
        let feed = SupabaseClientProvider(configuration: configuration, clientRegistry: registry).makeClient()
        let comments = SupabaseClientProvider(configuration: configuration, clientRegistry: registry).makeClient()
        XCTAssertTrue(feed === owner)
        XCTAssertTrue(comments === owner)
    }

    func testDifferentURLOrKeyCannotReuseAnotherEnvironmentSession() throws {
        let registry = SupabaseAppClientRegistry()
        let original = configuration(host: "first-project.supabase.co")
        let owner = try XCTUnwrap(SupabaseClientProvider(configuration: original, clientRegistry: registry).makeClient())
        registry.install(owner, configuration: original)
        let otherURL = SupabaseClientProvider(configuration: configuration(host: "second-project.supabase.co"), clientRegistry: registry).makeClient()
        var changedKey = original
        changedKey.anonKey = "different-test-key"
        let otherKey = SupabaseClientProvider(configuration: changedKey, clientRegistry: registry).makeClient()
        XCTAssertFalse(otherURL === owner)
        XCTAssertFalse(otherKey === owner)
    }

    func testReplacingAndRemovingAppRegistrationDiscardOldClient() throws {
        let registry = SupabaseAppClientRegistry()
        let firstConfiguration = configuration(host: "first-project.supabase.co")
        let first = try XCTUnwrap(SupabaseClientProvider(configuration: firstConfiguration, clientRegistry: registry).makeClient())
        registry.install(first, configuration: firstConfiguration)
        let nextConfiguration = configuration(host: "next-project.supabase.co")
        let next = try XCTUnwrap(SupabaseClientProvider(configuration: nextConfiguration, clientRegistry: registry).makeClient())
        registry.install(next, configuration: nextConfiguration)
        XCTAssertNil(registry.client(for: firstConfiguration))
        XCTAssertTrue(registry.client(for: nextConfiguration) === next)
        registry.install(nil, configuration: .empty)
        XCTAssertNil(registry.client(for: nextConfiguration))
        XCTAssertFalse(SupabaseClientProvider(configuration: nextConfiguration, clientRegistry: registry).makeClient() === next)
    }

    func testConcurrentRegistryReadsKeepConfigurationAndClientPaired() throws {
        let registry = SupabaseAppClientRegistry()
        let firstConfiguration = configuration(host: "first-project.supabase.co")
        let secondConfiguration = configuration(host: "second-project.supabase.co")
        let first = try XCTUnwrap(SupabaseClientProvider(configuration: firstConfiguration, clientRegistry: registry).makeClient())
        let second = try XCTUnwrap(SupabaseClientProvider(configuration: secondConfiguration, clientRegistry: registry).makeClient())
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index.isMultiple(of: 2) {
                registry.install(first, configuration: firstConfiguration)
            } else {
                registry.install(second, configuration: secondConfiguration)
            }
            if let match = registry.client(for: firstConfiguration) { XCTAssertTrue(match === first) }
            if let match = registry.client(for: secondConfiguration) { XCTAssertTrue(match === second) }
        }
    }

    func testNewContractTravelsOnActualSDKRESTRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MutualContractHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = SupabaseClient(supabaseURL: URL(string: "https://contract-fixture.invalid")!,
            supabaseKey: "local-contract-fixture-key", options: SupabaseClientProvider.clientOptions(session: session))
        let response = try await client.from("feed_posts").select("id").execute()
        XCTAssertEqual(String(data: response.data, encoding: .utf8), "[]")
        let signed = try await client.storage.from("workout-photos").createSignedURL(path: "fixture.jpg", expiresIn: 60)
        XCTAssertEqual(signed.host, "contract-fixture.invalid")
        let bytes = try await client.storage.from("workout-photos").download(path: "fixture.jpg")
        XCTAssertEqual(bytes, Data("fixture".utf8))
    }

    private func configuration(host: String) -> SupabaseAuthConfiguration {
        SupabaseAuthConfiguration(projectURL: URL(string: "https://\(host)"), anonKey: "isolated-test-key")
    }

}

/// Every request is intercepted; a missing opt-in is an HTTP failure, so this
/// verifies SDK transport rather than merely testing a constant dictionary.
private final class MutualContractHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "contract-fixture.invalid",
              request.value(forHTTPHeaderField: "x-soom-feed-contract") == "mutual-v1" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: String
        switch request.url?.path {
        case "/rest/v1/feed_posts": body = "[]"
        case "/storage/v1/object/sign/workout-photos/fixture.jpg":
            body = #"{"signedURL":"/object/sign/workout-photos/fixture.jpg?token=local-fixture"}"#
        case "/storage/v1/object/workout-photos/fixture.jpg": body = "fixture"
        default: client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PhotoNoCacheTransportTests: XCTestCase {
    private let base = URL(string: "https://photo-cache-fixture.invalid")!
    private func request(_ path: String = "/storage/v1/object/workout-photos/owner/photo.jpg") -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!.absoluteURL)
        request.httpMethod = "GET"
        request.setValue("Bearer synthetic-user-token", forHTTPHeaderField: "Authorization")
        request.setValue("synthetic-anon-key", forHTTPHeaderField: "apikey")
        request.setValue("detail-v1", forHTTPHeaderField: "x-soom-workout-contract")
        return request
    }
    func testProductionSessionInstallsRouterBeforeFirstRequestWithoutChangingDefaultRESTPolicy() {
        let config = LoadNetworkMetrics.session.configuration
        XCTAssertTrue(config.protocolClasses?.contains(where: { $0 == PhotoNoCacheURLProtocol.self }) == true)
        XCTAssertEqual(config.requestCachePolicy, .useProtocolCachePolicy)
        XCTAssertNotNil(config.urlCache)
    }
    func testExactOriginAndAuthenticatedPhotoPathsOnly() {
        PhotoNoCacheURLProtocol.register(projectURL: base)
        for path in ["/storage/v1/object/workout-photos/owner/p.jpg", "/storage/v1/object/info/workout-photos/owner/p.jpg", "/storage/v1/object/activity-photos-candidate/owner/card/p.jpg", "/storage/v1/object/info/activity-photos-candidate/owner/card/p.jpg"] {
            XCTAssertTrue(PhotoNoCacheURLProtocol.canInit(with: request(path)))
        }
        for path in ["https://photo-cache-fixture.invalid.evil.invalid/storage/v1/object/workout-photos/a/p.jpg", "http://photo-cache-fixture.invalid/storage/v1/object/workout-photos/a/p.jpg", "https://photo-cache-fixture.invalid:444/storage/v1/object/workout-photos/a/p.jpg", "/rest/v1/feed_posts", "/auth/v1/token", "/storage/v1/object/public/workout-photos/a/p.jpg", "/storage/v1/object/sign/workout-photos/a/p.jpg", "/storage/v1/object/workout-photos/a/p.jpg?token=synthetic", "/storage/v1/object/workout-photos/a/%2e%2e/p.jpg", "/storage/v1/object/workout-photos/a%2Fp.jpg", "/storage/v1/object/other/a/p.jpg"] {
            XCTAssertFalse(PhotoNoCacheURLProtocol.canInit(with: request(path)), path)
        }
        var unauthenticated = request(); unauthenticated.setValue(nil, forHTTPHeaderField: "Authorization")
        XCTAssertFalse(PhotoNoCacheURLProtocol.canInit(with: unauthenticated))
        var upload = request(); upload.httpMethod = "POST"
        XCTAssertFalse(PhotoNoCacheURLProtocol.canInit(with: upload))
    }
    func testNoCacheConfigurationHeadersAndRecursionFence() {
        PhotoNoCacheURLProtocol.register(projectURL: base)
        let config = PhotoNoCacheURLProtocol.forwardingConfiguration()
        XCTAssertNil(config.urlCache); XCTAssertNil(config.urlCredentialStorage); XCTAssertNil(config.httpCookieStorage)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
        let original = request(), forwarded = PhotoNoCacheURLProtocol.uncached(original)
        XCTAssertEqual(forwarded.value(forHTTPHeaderField: "Authorization"), original.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(forwarded.value(forHTTPHeaderField: "apikey"), original.value(forHTTPHeaderField: "apikey"))
        XCTAssertEqual(forwarded.value(forHTTPHeaderField: "x-soom-workout-contract"), "detail-v1")
        XCTAssertEqual(forwarded.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(forwarded.value(forHTTPHeaderField: "Cache-Control"), "no-store, no-cache, max-age=0")
        XCTAssertFalse(PhotoNoCacheURLProtocol.canInit(with: forwarded))
        XCTAssertEqual(original.cachePolicy, .useProtocolCachePolicy)
    }
    func testCacheableResponsesStillReachWireTwiceAndRetainAuth() async throws {
        PhotoNoCacheURLProtocol.register(projectURL: base)
        PhotoWireMock.reset()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        config.protocolClasses = [MockRoutedPhotoProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        for _ in 0..<2 {
            let (data, response) = try await session.data(for: request())
            XCTAssertEqual(data, Data("photo-pixels".utf8)); XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        let requests = PhotoWireMock.snapshot()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData && $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-user-token" && $0.value(forHTTPHeaderField: "apikey") == "synthetic-anon-key" })
        XCTAssertNil(config.urlCache?.cachedResponse(for: request()))
    }
    func testPreexistingUpperCacheCannotSatisfyPhotoAuthorizationRead() async throws {
        PhotoNoCacheURLProtocol.register(projectURL: base); PhotoWireMock.reset()
        let config = URLSessionConfiguration.ephemeral
        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)
        config.urlCache = cache; config.protocolClasses = [MockRoutedPhotoProtocol.self]
        let req = request("/storage/v1/object/info/workout-photos/owner/photo.jpg")
        let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control":"public, max-age=3600"])!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("stale-authorized-info".utf8)), for: req)
        XCTAssertNotNil(cache.cachedResponse(for: req))
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(for: req)
        XCTAssertNotEqual(data, Data("stale-authorized-info".utf8))
        XCTAssertEqual(PhotoWireMock.snapshot().count, 1)
    }
    func testSDKInfoDownloadAndRESTKeepContractAndAuthHeaders() async throws {
        PhotoNoCacheURLProtocol.register(projectURL: base); PhotoWireMock.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRoutedPhotoProtocol.self, PhotoWireMock.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let client = SupabaseClient(supabaseURL: base, supabaseKey: "synthetic-anon-key", options: SupabaseClientProvider.clientOptions(session: session))
        let info = try await client.storage.from("workout-photos").info(path: "owner/photo.jpg")
        XCTAssertEqual(info.version, "fixture-v1")
        _ = try await client.storage.from("activity-photos-candidate").download(path: "owner/card/photo.jpg")
        var rest = request("/rest/v1/feed_posts"); rest.cachePolicy = .useProtocolCachePolicy
        _ = try await session.data(for: rest)
        let seen = PhotoWireMock.snapshot()
        XCTAssertEqual(seen.count, 3)
        XCTAssertTrue(seen.prefix(2).allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData && $0.value(forHTTPHeaderField: "apikey") == "synthetic-anon-key" && $0.value(forHTTPHeaderField: "x-soom-workout-contract") == "detail-v1" })
        XCTAssertEqual(seen.last?.cachePolicy, .useProtocolCachePolicy)
        XCTAssertNil(seen.last?.value(forHTTPHeaderField: "Cache-Control"))
    }
    func testCancellationReachesForwardedTask() async throws {
        PhotoNoCacheURLProtocol.register(projectURL: base); PhotoWireMock.reset(delayed: true)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockRoutedPhotoProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let request = request()
        let task = Task { try await session.data(for: request) }
        for _ in 0..<100 { if !PhotoWireMock.snapshot().isEmpty { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(PhotoWireMock.snapshot().count, 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request cannot succeed") } catch {}
        for _ in 0..<100 { if PhotoWireMock.wasStopped { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(PhotoWireMock.wasStopped)
    }
    func testRedirectDelegateNeverForwardsEvenSameOriginCredentials() {
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        for url in ["https://outside-fixture.invalid/private", "https://photo-cache-fixture.invalid/other"] {
            let original = request()
            let subject = PhotoNoCacheURLProtocol(request: original, cachedResponse: nil, client: nil)
            let task = session.dataTask(with: original)
            var redirected = original; redirected.url = URL(string: url)!
            let response = HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
            var called = false
            subject.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { forwarded in
                called = true; XCTAssertNil(forwarded)
            }
            XCTAssertTrue(called)
        }
    }
    func testRedirectResponseIsRejectedWithoutSecondDestination() async throws {
        PhotoNoCacheURLProtocol.register(projectURL: base); PhotoWireMock.reset(status: 302)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockRoutedPhotoProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        do { _ = try await session.data(for: request()); XCTFail("Redirect must not succeed") } catch {}
        XCTAssertEqual(PhotoWireMock.snapshot().count, 1)
    }
}
private final class MockRoutedPhotoProtocol: PhotoNoCacheURLProtocol, @unchecked Sendable {
    override class func forwardingConfiguration() -> URLSessionConfiguration {
        let config = super.forwardingConfiguration(); config.protocolClasses = [PhotoWireMock.self]; return config
    }
}
private final class PhotoWireMock: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var seen: [URLRequest] = []
    private static var status = 200
    private static var delayed = false
    private static var stopped = false
    static var wasStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    static func reset(status: Int = 200, delayed: Bool = false) { lock.lock(); seen = []; self.status = status; self.delayed = delayed; stopped = false; lock.unlock() }
    static func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.seen.append(request); let code = Self.status; let delayed = Self.delayed; Self.lock.unlock()
        if delayed { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control":"public, max-age=3600", "Location":"https://outside-fixture.invalid/photo.jpg"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        let bytes = request.url!.path.contains("/object/info/") ? Data(#"{"id":"fixture","version":"fixture-v1","name":"photo.jpg"}"#.utf8) : Data("photo-pixels".utf8)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.lock.lock(); Self.stopped = true; Self.lock.unlock() }
}
