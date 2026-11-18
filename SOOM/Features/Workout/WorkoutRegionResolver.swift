import CoreLocation
import Foundation
import SwiftData

/// A coarse point from the already masked route interior. This pure helper
/// does not send coordinates anywhere or retain a full route in the cache.
struct WorkoutRegionQueryPoint: Hashable {
    let latitudeHundredths: Int
    let longitudeHundredths: Int
    var latitude: Double { Double(latitudeHundredths) / 100 }
    var longitude: Double { Double(longitudeHundredths) / 100 }

    static func make(route: WorkoutRoute) -> Self? {
        guard route.coordinates.count >= 2,
              route.coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite
                  && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else { return nil }
        let interior = RoutePrivacyMasker().mask(route: route).coordinates
        guard interior.count >= 2 else { return nil }
        let middle = interior[interior.count / 2]
        return Self(latitudeHundredths: Int((middle.latitude * 100).rounded()),
                    longitudeHundredths: Int((middle.longitude * 100).rounded()))
    }
}

/// Address lines and points of interest are intentionally absent from this type.
struct WorkoutRegionPlacemark {
    var locality: String? = nil
    var subAdministrativeArea: String? = nil
    var administrativeArea: String? = nil
    var subLocality: String? = nil
    var country: String? = nil

    var displayName: String? {
        func clean(_ text: String?) -> String? {
            guard let text else { return nil }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : String(value.prefix(100))
        }
        let city = clean(locality) ?? clean(subAdministrativeArea)
        // Korean providers sometimes put a district here. Neighborhood names
        // (dong), street addresses, and points of interest are not displayed.
        let district = clean(subLocality).flatMap { $0.hasSuffix("구") || $0.hasSuffix("군") ? $0 : nil }
        var parts: [String] = []
        for part in [clean(administrativeArea), city, district].compactMap({ $0 }) where !parts.contains(part) {
            parts.append(part)
        }
        if parts.isEmpty, let country = clean(country) { parts.append(country) }
        return parts.isEmpty ? nil : String(parts.joined(separator: " ").prefix(100))
    }
}

@MainActor
protocol WorkoutRegionGeocoding: AnyObject {
    func placemark(for point: WorkoutRegionQueryPoint) async throws -> WorkoutRegionPlacemark?
    func cancel()
}

/// Only the coarse, route-interior point reaches Apple's geocoding service.
/// Core Location remains available on the app's iOS 18 deployment target.
@MainActor
final class AppleWorkoutRegionGeocoder: WorkoutRegionGeocoding {
    private let geocoder = CLGeocoder()

    func placemark(for point: WorkoutRegionQueryPoint) async throws -> WorkoutRegionPlacemark? {
        if ReviewDemoMode.isActive { return WorkoutRegionPlacemark(locality: "데모 운동 지역") }
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let value = try await geocoder.reverseGeocodeLocation(location,
            preferredLocale: Locale(identifier: "ko_KR")).first else { return nil }
        return WorkoutRegionPlacemark(locality: value.locality,
            subAdministrativeArea: value.subAdministrativeArea,
            administrativeArea: value.administrativeArea,
            subLocality: value.subLocality, country: value.country)
    }

    func cancel() { geocoder.cancelGeocode() }
}

@MainActor
final class WorkoutRegionResolver {
    static let shared = WorkoutRegionResolver(geocoder: AppleWorkoutRegionGeocoder(), minimumInterval: 60)

    private struct Key: Hashable { let scopeID: String; let point: WorkoutRegionQueryPoint }
    private struct CacheEntry { let name: String?; let expiresAt: Date }
    private struct Waiter {
        let continuation: CheckedContinuation<String?, Never>
        let isCurrent: @MainActor () -> Bool
    }
    private final class Request {
        let key: Key
        var waiters: [UUID: Waiter] = [:]
        init(key: Key) { self.key = key }
    }
    private let geocoder: any WorkoutRegionGeocoding
    private let now: () -> Date
    private let minimumInterval: TimeInterval
    private let failureBackoff: TimeInterval
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var cache: [Key: CacheEntry] = [:]
    private var queue: [Request] = []
    private var active: Request?
    private var worker: Task<Void, Never>?
    private var lastRequestAt: Date?

    init(geocoder: any WorkoutRegionGeocoding, minimumInterval: TimeInterval = 60,
         failureBackoff: TimeInterval = 15 * 60, now: @escaping () -> Date = Date.init,
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000))
         }) {
        self.geocoder = geocoder
        self.minimumInterval = max(0, minimumInterval)
        self.failureBackoff = max(0, failureBackoff)
        self.now = now
        self.sleep = sleep
    }

    func resolve(route: WorkoutRoute, scopeID: String,
                 isCurrent: @escaping @MainActor () -> Bool) async -> String? {
        guard !Task.isCancelled, isCurrent(), let point = WorkoutRegionQueryPoint.make(route: route) else { return nil }
        let key = Key(scopeID: scopeID.lowercased(), point: point)
        if let entry = cache[key], entry.expiresAt > now() { return entry.name }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, isCurrent() else { continuation.resume(returning: nil); return }
                let request: Request
                if let existing = active, existing.key == key, !existing.waiters.isEmpty { request = existing }
                else if let existing = queue.first(where: { $0.key == key }) { request = existing }
                else { request = Request(key: key); queue.append(request) }
                request.waiters[waiterID] = Waiter(continuation: continuation, isCurrent: isCurrent)
                if worker == nil { worker = Task { await self.drain() } }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(waiterID) }
        }
    }

    private func cancel(_ waiterID: UUID) {
        if let waiter = active?.waiters.removeValue(forKey: waiterID) {
            waiter.continuation.resume(returning: nil)
            if active?.waiters.isEmpty == true { geocoder.cancel() }
            return
        }
        for request in queue {
            if let waiter = request.waiters.removeValue(forKey: waiterID) {
                waiter.continuation.resume(returning: nil)
                return
            }
        }
    }

    private func prune(_ request: Request) {
        for (id, waiter) in request.waiters where !waiter.isCurrent() {
            request.waiters.removeValue(forKey: id)?.continuation.resume(returning: nil)
        }
    }

    private func drain() async {
        defer { active = nil; worker = nil }
        while !queue.isEmpty {
            let request = queue.removeFirst()
            active = request
            prune(request)
            guard !request.waiters.isEmpty else { continue }
            if let lastRequestAt {
                let delay = minimumInterval - now().timeIntervalSince(lastRequestAt)
                if delay > 0 { try? await sleep(delay) }
            }
            prune(request)
            guard !request.waiters.isEmpty else { continue }
            lastRequestAt = now()
            let name: String?
            do { name = try await geocoder.placemark(for: request.key.point)?.displayName }
            catch { name = nil }
            prune(request)
            if !request.waiters.isEmpty {
                cache = cache.filter { $0.value.expiresAt > now() }
                if cache.count >= 128, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
                    cache.removeValue(forKey: oldest.key)
                }
                cache[request.key] = CacheEntry(name: name, expiresAt: now().addingTimeInterval(name == nil ? failureBackoff : 30 * 86_400))
            }
            let waiters = Array(request.waiters.values)
            request.waiters.removeAll()
            for waiter in waiters { waiter.continuation.resume(returning: waiter.isCurrent() ? name : nil) }
            active = nil
        }
    }
}

@MainActor
enum WorkoutRegionEnricher {
    /// Writes only the missing region on the still-existing record, then uses
    /// the account's normal consent-gated cloud outbox. It cannot publish a post.
    static func resolveAndPersist(workoutID: UUID, context: ModelContext, scopeID: String,
                                  isCurrent: @escaping @MainActor () -> Bool,
                                  resolver: WorkoutRegionResolver? = nil) async -> String? {
        let regionResolver = resolver ?? .shared
        func valid() -> Bool {
            !Task.isCancelled && isCurrent() && !HealthCloudJournal.isRetired(context)
                && (HealthCloudJournal.accountID(for: context)?.uuidString.lowercased() ?? "guest") == scopeID.lowercased()
        }
        func workoutRecord() throws -> UnifiedWorkoutRecord? {
            var query = FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.id == workoutID })
            query.fetchLimit = 1
            return try context.fetch(query).first
        }
        func routeRecord() throws -> PersistedWorkoutRoute? {
            var query = FetchDescriptor<PersistedWorkoutRoute>(predicate: #Predicate { $0.workoutId == workoutID })
            query.fetchLimit = 1
            return try context.fetch(query).first
        }
        func existingName(_ record: UnifiedWorkoutRecord) -> String? {
            let value = record.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        do {
            guard valid(), let record = try workoutRecord() else { return nil }
            if let name = existingName(record) { return name }
            guard let storedRoute = try routeRecord() else { return nil }
            let expectedRouteID = storedRoute.id
            let expectedRouteUpdatedAt = storedRoute.updatedAt
            let expectedRouteCoordinates = storedRoute.encodedCoordinates
            let route = WorkoutRouteMapper().makeRoute(from: storedRoute)
            guard let expectedPoint = WorkoutRegionQueryPoint.make(route: route),
                  let name = await regionResolver.resolve(route: route, scopeID: scopeID, isCurrent: { isCurrent() && !HealthCloudJournal.isRetired(context) }),
                  valid(), let current = try workoutRecord() else { return nil }
            // A user edit or refreshed cloud value wins over a delayed lookup.
            if let existing = existingName(current) { return existing }
            guard let latestRoute = try routeRecord(),
                  latestRoute.id == expectedRouteID,
                  latestRoute.updatedAt == expectedRouteUpdatedAt,
                  latestRoute.encodedCoordinates == expectedRouteCoordinates,
                  WorkoutRegionQueryPoint.make(route: WorkoutRouteMapper().makeRoute(from: latestRoute)) == expectedPoint else { return nil }
            current.locationName = name
            current.updatedAt = Date()
            try HealthCloudJournal.workout(current, context: context)
            try HealthCloudJournal.commit(context)
            return name
        } catch { return nil }
    }
}
