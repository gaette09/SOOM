import XCTest
@testable import SOOM

@MainActor final class Feed60AvatarResidentTests: XCTestCase {
    private func scope(_ generation: Int = 1, viewer: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, safety: Int = 2) -> SOOMMediaCacheScope {
        .init(viewerID: viewer, accountGeneration: generation, safetyRevision: safety)
    }
    func testSynchronousResidentReadHasNoLoadOrStatisticsSideEffects() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        var downloads = 0
        _ = try await cache.value(for: "avatar", scope: scope(), reusePresentation: false,
            authorize: { "v1" }, load: { downloads += 1; return (7, 5) })
        let hits = cache.statistics.hits, misses = cache.statistics.misses
        for _ in 0..<20 { XCTAssertEqual(cache.residentValue(for: "avatar", scope: scope(), version: "v1"), 7) }
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(cache.statistics.hits, hits)
        XCTAssertEqual(cache.statistics.misses, misses)
        XCTAssertEqual(cache.inFlightCount, 0)
    }
    func testResidentMissesUnknownVersionAccountGenerationSafetyAndVariant() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        _ = try await cache.value(for: "avatar", scope: scope(), authorize: { "v1" }, load: { (7, 5) })
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: nil))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: ""))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: "v2"))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(2), version: "v1"))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(viewer: UUID()), version: "v1"))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(safety: 3), version: "v1"))
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: "v1", variant: "other"))
    }
    func testRevocationAndMemoryPurgeRemoveSynchronousResidents() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        _ = try await cache.value(for: "avatar", scope: scope(), authorize: { "v1" }, load: { (7, 5) })
        cache.invalidateResource("avatar")
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: "v1"))
        _ = try await cache.value(for: "avatar", scope: scope(), authorize: { "v1" }, load: { (8, 5) })
        cache.invalidate() // Same pixel purge used by memory-warning/account handlers.
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: "v1"))
        XCTAssertEqual(cache.totalCost, 0)
    }
    func testNewVersionCannotRestoreOldResidentAndReportsOnlyChangingOwner() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 20, maximumCount: 2)
        var changed: [(String, String?)] = []
        cache.onResourceVersionChanged = { changed.append(($0, $1)) }
        _ = try await cache.value(for: "avatar", scope: scope(), reusePresentation: false, requestOwner: "first", authorize: { "v1" }, load: { (7, 5) })
        _ = try await cache.value(for: "avatar", scope: scope(), reusePresentation: false, requestOwner: "second", authorize: { "v2" }, load: { (8, 5) })
        XCTAssertNil(cache.residentValue(for: "avatar", scope: scope(), version: "v1"))
        XCTAssertEqual(cache.residentValue(for: "avatar", scope: scope(), version: "v2"), 8)
        XCTAssertEqual(changed.count, 1); XCTAssertEqual(changed.first?.1, "second")
    }
    func testResidentLookupNeverExpandsBudgetOrRevivesEvictedEntry() async throws {
        let cache = SOOMValidatedMemoryCache<String, Int>(maximumCost: 5, maximumCount: 1)
        _ = try await cache.value(for: "one", scope: scope(), authorize: { "v1" }, load: { (1, 5) })
        _ = try await cache.value(for: "two", scope: scope(), authorize: { "v1" }, load: { (2, 5) })
        XCTAssertNil(cache.residentValue(for: "one", scope: scope(), version: "v1"))
        XCTAssertEqual(cache.residentValue(for: "two", scope: scope(), version: "v1"), 2)
        XCTAssertEqual(cache.entryCount, 1); XCTAssertEqual(cache.totalCost, 5)
    }
}
