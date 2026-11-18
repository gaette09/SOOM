import SwiftUI
import UIKit
import Combine

/// Display-only result of the independently authorized legacy read. This is
/// never a detail/photo/social grant and cannot be reused in another return.
struct FeedLinkedCardPresentation: Equatable {
    let title: String
    let caption: String?
    let device: String?
    let location: String?
    let route: WorkoutRoute?

    init(item: FeedItem, date: Date) {
        title = item.recordTitle; caption = item.caption; device = item.deviceName
        location = item.locationHint
        route = item.permittedSharedDetail?.route(start: date)
    }
    init(title: String, caption: String? = nil, device: String? = nil,
         location: String? = nil, route: WorkoutRoute? = nil) {
        self.title = title; self.caption = caption; self.device = device
        self.location = location; self.route = route
    }
    var memoryCost: Int {
        256 + title.utf8.count + (caption?.utf8.count ?? 0) +
        (device?.utf8.count ?? 0) + (location?.utf8.count ?? 0) + (route?.coordinates.count ?? 0) * 128
    }
}

struct FeedLinkedCardAuthority: Equatable {
    let context: FeedReturnBatchContext
    let batchID: UUID
    let grantID: UUID
    let row: AccountActivityFeedRow
}

/// A page-owned, bounded completion receipt survives lazy row destruction, but
/// not a permission epoch. Successful `nil` is distinct from an error/retry.
@MainActor final class FeedLinkedCardStore {
    struct Completion { let presentation: FeedLinkedCardPresentation? }
    private struct Entry {
        let authority: FeedLinkedCardAuthority
        let completion: Completion
        let order: Int
        var cost: Int { completion.presentation?.memoryCost ?? 128 }
    }
    private struct Flight {
        let id: UUID
        let authority: FeedLinkedCardAuthority
        let task: Task<Completion, Error>
        let order: Int
    }
    private var entries: [UUID: Entry] = [:]
    private var flights: [UUID: Flight] = [:]
    private var sequence = 0
    private(set) var startedReads = 0
    private(set) var joinedReads = 0
    private(set) var hits = 0
    private(set) var cancelledForCapacity = 0
    private(set) var activeOperations = 0
    private(set) var maximumObservedOperations = 0
    var inFlightCount: Int { flights.count }
    let maximumFlights: Int
    let maximumCount: Int
    let maximumCost: Int
    var count: Int { entries.count }
    var cost: Int { entries.values.reduce(0) { $0 + $1.cost } }

    init(maximumCount: Int = 64, maximumCost: Int = 4 * 1_024 * 1_024, maximumFlights: Int = 6) {
        self.maximumCount = max(0, maximumCount); self.maximumCost = max(0, maximumCost)
        self.maximumFlights = max(1, maximumFlights)
    }
    /// Pure lookup for SwiftUI body. The caller must supply a live store fence,
    /// not merely a captured Environment copy of an earlier ready batch.
    func resident(_ authority: FeedLinkedCardAuthority, isCurrent: () -> Bool) -> Completion? {
        guard isCurrent(), let entry = entries[authority.row.cardID], entry.authority == authority else { return nil }
        return entry.completion
    }
    func load(_ authority: FeedLinkedCardAuthority,
              isCurrent: @escaping @MainActor () -> Bool,
              operation: @escaping @MainActor () async throws -> FeedLinkedCardPresentation?) async throws -> Completion {
        guard isCurrent() else { throw FeedReturnBatchError.changed }
        if let value = resident(authority, isCurrent: isCurrent) { hits += 1; return value }
        let flight: Flight
        if let existing = flights[authority.row.cardID], existing.authority == authority {
            joinedReads += 1; flight = existing
        } else {
            flights.removeValue(forKey: authority.row.cardID)?.task.cancel()
            if flights.count >= maximumFlights, let oldest = flights.min(by: { $0.value.order < $1.value.order })?.key {
                flights.removeValue(forKey: oldest)?.task.cancel(); cancelledForCapacity += 1
            }
            sequence += 1
            let id = UUID()
            // View disappearance cancels its waiter, not the authorized page
            // operation. Epoch invalidation below cancels the operation itself.
            let task = Task { @MainActor [weak self] () throws -> Completion in
                guard let self else { throw FeedReturnBatchError.changed }
                // Cancelled transports may unwind cooperatively. Count them
                // until they actually return, so replacement tasks cannot push
                // network concurrency beyond the bound.
                while self.activeOperations >= self.maximumFlights {
                    guard isCurrent(), !Task.isCancelled else { throw FeedReturnBatchError.changed }
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard isCurrent(), !Task.isCancelled else { throw FeedReturnBatchError.changed }
                self.activeOperations += 1
                self.maximumObservedOperations = max(self.maximumObservedOperations, self.activeOperations)
                defer { self.activeOperations -= 1 }
                let value = Completion(presentation: try await operation())
                guard isCurrent(), !Task.isCancelled,
                      self.flights[authority.row.cardID]?.id == id else { throw FeedReturnBatchError.changed }
                self.insert(value, authority: authority)
                return value
            }
            flight = Flight(id: id, authority: authority, task: task, order: sequence)
            flights[authority.row.cardID] = flight; startedReads += 1
        }
        defer { if flights[authority.row.cardID]?.id == flight.id { flights[authority.row.cardID] = nil } }
        let result = try await flight.task.value
        guard isCurrent() else { throw FeedReturnBatchError.changed }
        return result
    }
    private func insert(_ value: Completion, authority: FeedLinkedCardAuthority) {
        sequence += 1
        let entry = Entry(authority: authority, completion: value, order: sequence)
        guard maximumCount > 0, entry.cost <= maximumCost else { return }
        entries[authority.row.cardID] = entry
        while count > maximumCount || cost > maximumCost {
            guard let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key else { break }
            entries[oldest] = nil
        }
    }
    func retain(using batch: FeedReturnBatchPresentation) {
        func matches(_ authority: FeedLinkedCardAuthority) -> Bool {
            guard batch.phase == .ready, batch.id == authority.batchID, batch.context == authority.context,
                  let grant = batch.grants[authority.row.cardID], !batch.denied.contains(authority.row.cardID) else { return false }
            return grant.id == authority.grantID && grant.row == authority.row
        }
        entries = entries.filter { matches($0.value.authority) }
        for (id, flight) in flights where !matches(flight.authority) {
            flight.task.cancel(); flights[id] = nil
        }
    }
    func clear() {
        entries.removeAll(); flights.values.forEach { $0.task.cancel() }; flights.removeAll()
    }
}

private struct FeedLinkedCardStoreKey: EnvironmentKey {
    static let defaultValue: FeedLinkedCardStore? = nil
}
extension EnvironmentValues {
    var soomFeedLinkedCardStore: FeedLinkedCardStore? {
        get { self[FeedLinkedCardStoreKey.self] }
        set { self[FeedLinkedCardStoreKey.self] = newValue }
    }
}

private struct FeedCurrentCardGrantKey: EnvironmentKey {
    static let defaultValue: ((FeedLinkedCardAuthority) -> Bool)? = nil
}
extension EnvironmentValues {
    var soomFeedCardGrantIsCurrent: ((FeedLinkedCardAuthority) -> Bool)? {
        get { self[FeedCurrentCardGrantKey.self] }
        set { self[FeedCurrentCardGrantKey.self] = newValue }
    }
}

// A display-only cache. It never creates a FeedReturnCardGrant, enables an
// interaction, or supplies data to a detail/profile/photo network reader.
struct FeedStaleSummaryLayout: Codable, Equatable, Sendable {
    let width: Double
    let height: Double
    let dynamicType: String
    let environment: String
    let contentRevision: String
    init?(width: Double, height: Double, dynamicType: String, environment: String, contentRevision: String) {
        guard width.isFinite, width > 0, height.isFinite, height >= 44, height <= 20_000,
              !dynamicType.isEmpty, !environment.isEmpty, !contentRevision.isEmpty else { return nil }
        self.width = (width * 64).rounded() / 64; self.height = height
        self.dynamicType = dynamicType; self.environment = environment; self.contentRevision = contentRevision
    }
    func height(width: Double, dynamicType: String, environment: String, contentRevision: String) -> Double? {
        guard width.isFinite, self.width == (width * 64).rounded() / 64,
              self.dynamicType == dynamicType, self.environment == environment,
              self.contentRevision == contentRevision else { return nil }
        return height
    }
    static func environment(locale: String, direction: String, weight: String) -> String {
        "cache-layout-v1|\(locale)|\(direction)|\(weight)"
    }
}

/// Non-sensitive geometry only. Never stores overview values or grants.
struct FeedChromeLayout: Codable, Equatable, Sendable {
    let width: Double
    let dynamicType: String
    let environment: String
    let height: Double
    let version: Int
    init?(width: Double, dynamicType: String, environment: String, height: Double) {
        guard width.isFinite, width > 0, height.isFinite, height >= 1, height <= 10_000 else { return nil }
        self.width = width; self.dynamicType = dynamicType; self.environment = environment
        self.height = height; version = 1
    }
    func matches(width: Double, dynamicType: String, environment: String) -> Bool {
        version == 1 && self.width.isFinite && self.width > 0 && height.isFinite && height >= 1 && height <= 10_000 &&
            self.width == width && self.dynamicType == dynamicType && self.environment == environment
    }
}
struct FeedStaleSummarySnapshot: Codable, Equatable, Identifiable, Sendable {
    struct Metric: Codable, Equatable, Sendable { let label: String; let value: String }
    let id: UUID
    let ownerID: UUID
    let canonicalID: UUID
    let sport: String
    let activityAt: String
    let durationSeconds: Int
    let distanceMeters: Double?
    let projectionRevision: Int64
    let title: String
    let author: String
    let metrics: [Metric]
    let validatedAt: Date
    let validatedUptime: TimeInterval
    let photoVersions: [String: String]
    let photoOrder: [String]
    var photos: [String: Data]
    var layout: FeedStaleSummaryLayout? = nil
    var chromeLayout: FeedChromeLayout? = nil
    var layoutRevision: String { "\(projectionRevision)|\(photoOrder.joined(separator: ","))" }
    var row: AccountActivityFeedRow {
        .init(cardID: id, canonicalID: canonicalID, ownerID: ownerID, sport: sport,
              activityAt: activityAt, durationSeconds: durationSeconds, distanceMeters: distanceMeters,
              revision: projectionRevision, readPolicy: .profileOnlyV2)
    }
}
struct FeedStaleSummaryScope: Codable, Equatable, Hashable, Sendable {
    let viewerID: UUID
    let generation: Int
    let safetyRevision: Int
    let policyVersion: Int
}

@MainActor final class FeedStaleSummaryCache: ObservableObject {
    static let shared: FeedStaleSummaryCache = {
        guard let age = configuredMaximumAge,
              let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return FeedStaleSummaryCache() }
        return FeedStaleSummaryCache(maximumAge: age, displayGrace: configuredDisplayGrace, disk: FeedEncryptedDiskCache(
            directory: base.appendingPathComponent("BoundedFeedSummary", isDirectory: true),
            keys: FeedDiskCacheKeychain(), policy: .init(maximumAge: age,
                maximumFileBytes: 24 * 1_024 * 1_024, maximumTotalBytes: 24 * 1_024 * 1_024)))
    }()
    // Candidate policy is explicit and injectable; shipping stays off until its
    // exposure interval is reviewed. Synthetic tests may select their own cap.
    nonisolated static var configuredMaximumAge: TimeInterval? {
        #if DEBUG && targetEnvironment(simulator)
        if let storage = ProcessInfo.processInfo.environment["SOOM_STALE_STORAGE_SECONDS"].flatMap(Double.init),
           configuredDisplayGrace != nil, storage > 0, storage <= 7 * 86_400 { return storage }
        if let text = ProcessInfo.processInfo.environment["SOOM_STALE_CACHE_SECONDS"],
           let value = Double(text), value > 0, value <= 60 { return value }
        #endif
        if Bundle.main.object(forInfoDictionaryKey: "SOOMFeedStaleCacheEnabled") as? Bool == true,
           configuredDisplayGrace != nil,
           let storage = Bundle.main.object(forInfoDictionaryKey: "SOOMFeedCacheStorageSeconds") as? Double,
           storage > 0, storage <= 7 * 86_400 { return storage }
        guard Bundle.main.object(forInfoDictionaryKey: "SOOMFeedStaleCacheEnabled") as? Bool == true,
              let seconds = Bundle.main.object(forInfoDictionaryKey: "SOOMFeedStaleCacheSeconds") as? Double,
              seconds > 0, seconds <= 60 else { return nil }
        return seconds
    }
    // Storage lifetime and one pending-presentation exposure are independent.
    // No release values are selected here; all shipping activation is explicit.
    nonisolated static var configuredDisplayGrace: TimeInterval? {
        #if DEBUG && targetEnvironment(simulator)
        if let seconds = ProcessInfo.processInfo.environment["SOOM_STALE_DISPLAY_SECONDS"].flatMap(Double.init),
           seconds > 0, seconds <= 30 { return seconds }
        #endif
        guard Bundle.main.object(forInfoDictionaryKey: "SOOMFeedStaleCacheEnabled") as? Bool == true,
              let seconds = Bundle.main.object(forInfoDictionaryKey: "SOOMFeedCacheDisplaySeconds") as? Double,
              seconds > 0, seconds <= 30 else { return nil }
        return seconds
    }
    private struct DisplayWindow {
        let scope: FeedStaleSummaryScope
        let returnEpoch: Int
        let startedAt: Date
        let startedUptime: TimeInterval
    }
    private var earlyDeadlineLocked = false
    private var displayWindow: DisplayWindow?
    private var expiryTask: Task<Void, Never>?
    private let displayGrace: TimeInterval?
    @Published private(set) var revision = 0
    @Published private(set) var diskDiagnostic = "idle"
    private(set) var scope: FeedStaleSummaryScope?
    private var entries: [UUID: FeedStaleSummarySnapshot] = [:]
    private var epoch = UUID()
    private struct PhotoCaptureKey: Hashable {
        let epoch: UUID
        let scope: FeedStaleSummaryScope
        let cardID: UUID
        let resource: String
        let version: String
        let validatedAt: Date
    }
    private var photoCapturesInFlight = Set<PhotoCaptureKey>()
    // Non-published work counters: inspecting these must not invalidate feed UI.
    private(set) var photoEncodingStarts = 0
    private(set) var photoCaptureCommits = 0
    private(set) var photoCaptureReuseHits = 0
    private(set) var photoCaptureCoalesced = 0
    private let maximumAge: TimeInterval?
    private let maximumBytes: Int
    private let maximumCount: Int
    private let disk: FeedEncryptedDiskCache?
    private var diskTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    var totalBytes: Int { entries.values.reduce(0) { $0 + $1.photos.values.reduce(0) { $0 + $1.count } } }
    var count: Int { entries.count }
    var layoutCount: Int { entries.values.filter { $0.layout != nil }.count }
    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var presentedCachedHeights: [UUID: Double] = [:]
    var firstVerifiedHeight: Double { entries.values.compactMap { $0.layout?.height }.first ?? -1 }
    var firstPresentedHeight: Double { presentedCachedHeights.values.first ?? -1 }
    func recordPresentedHeight(cardID: UUID, height: Double) {
        guard height.isFinite, height > 0, presentedCachedHeights[cardID] != height else { return }
        presentedCachedHeights[cardID] = height
    }
    #endif
    var enabled: Bool { maximumAge != nil }
    init(maximumAge: TimeInterval? = FeedStaleSummaryCache.configuredMaximumAge, displayGrace: TimeInterval? = nil,
         maximumBytes: Int = 8 * 1_024 * 1_024, maximumCount: Int = 32, observeSafety: Bool = true, disk: FeedEncryptedDiskCache? = nil) {
        self.disk = disk
        self.displayGrace = displayGrace.flatMap { $0.isFinite && $0 > 0 && $0 <= 30 ? $0 : nil }
        let maximumStorageAge: TimeInterval = self.displayGrace == nil ? 60 : 7 * 86_400
        self.maximumAge = maximumAge.flatMap { $0.isFinite && $0 > 0 && $0 <= maximumStorageAge ? $0 : nil }
        self.maximumBytes = max(0, maximumBytes); self.maximumCount = max(0, maximumCount)
        if observeSafety {
            CommunitySafetyStore.shared.$revision.dropFirst().sink { [weak self] nextRevision in
                let safety = CommunitySafetyStore.shared
                if safety.preservesPendingDisplayCache, let viewer = safety.viewerID {
                    self?.rebindPendingDisplay(viewerID: viewer, generation: safety.accountGeneration, safetyRevision: nextRevision)
                } else { self?.clear() }
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
                .sink { [weak self] _ in self?.clear() }.store(in: &subscriptions)
            WorkoutPhotoImageCache.shared.resourceInvalidations.sink { [weak self] key in self?.revokePhoto(key) }.store(in: &subscriptions)
            WorkoutPhotoImageCache.shared.resourceVersionChanges.sink { [weak self] change in self?.revokePhoto(change.resource) }.store(in: &subscriptions)
        }
    }
    static func scope(_ context: FeedReturnBatchContext) -> FeedStaleSummaryScope {
        .init(viewerID: context.viewerID, generation: context.accountGeneration,
              safetyRevision: context.safetyRevision, policyVersion: 1)
    }
    func accept(_ batch: FeedReturnBatchPresentation, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard enabled, batch.phase == .ready, now.timeIntervalSince1970.isFinite, uptime.isFinite else { return }
        let current = Self.scope(batch.context)
        if scope != current { clear(); scope = current }
        revoke(batch.denied)
        for (id, grant) in batch.grants where grant.row.readPolicy == .profileOnlyV2 {
            let card = AccountActivityWorkoutCardPresentation(row: grant.row)
            let versions = grant.photosAvailable ? grant.photoObjects.compactMapValues(\.cacheVersionToken) : [:]
            let order = grant.photos.filter { versions[$0.cacheKey] != nil }.prefix(4).map(\.cacheKey)
            let previous = entries[id]
            var retained: [String: Data] = [:]
            for key in order where previous?.photoVersions[key] == versions[key] { retained[key] = previous?.photos[key] }
            // No caption, location, route, HR, AI, recovery or personal comparison.
            entries[id] = .init(id: id, ownerID: grant.row.ownerID, canonicalID: grant.row.canonicalID,
                sport: grant.row.sport, activityAt: grant.row.activityAt, durationSeconds: grant.row.durationSeconds,
                distanceMeters: grant.row.distanceMeters, projectionRevision: grant.row.revision,
                title: card.title, author: grant.author?.displayName ?? "작성자", metrics: card.metrics.map { .init(label: $0.label, value: $0.value) },
                validatedAt: now, validatedUptime: uptime, photoVersions: versions, photoOrder: order, photos: retained)
            entries[id]?.chromeLayout = previous?.chromeLayout
            if previous?.layoutRevision == entries[id]?.layoutRevision { entries[id]?.layout = previous?.layout }
        }
        trim(); revision += 1; scheduleVisibilityExpiry(); persist()
    }
    func snapshot(cardID: UUID, scope expected: FeedStaleSummaryScope, now: Date = Date(),
                  uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> FeedStaleSummarySnapshot? {
        guard enabled, expected == scope, displayWindowAllows(expected, now: now, uptime: uptime),
              let entry = entries[cardID], valid(entry, now: now, uptime: uptime) else { return nil }
        return entry
    }
    /// This rebind changes only display bookkeeping, never a current grant.
    private func rebindPendingDisplay(viewerID: UUID, generation: Int, safetyRevision: Int) {
        guard let old = scope, old.viewerID == viewerID, old.generation == generation else { return }
        let next = FeedStaleSummaryScope(viewerID: viewerID, generation: generation, safetyRevision: safetyRevision, policyVersion: old.policyVersion)
        scope = next
        if let window = displayWindow {
            displayWindow = .init(scope: next, returnEpoch: window.returnEpoch,
                startedAt: window.startedAt, startedUptime: window.startedUptime)
        }
        revision += 1
    }
    func beginEarlyDisplay(scope expected: FeedStaleSummaryScope) {
        guard enabled, displayGrace != nil else { return }
        if earlyDeadlineLocked { return }
        beginDisplayWindow(scope: expected, returnEpoch: 0)
        earlyDeadlineLocked = true
    }
    func beginDisplayWindow(scope expected: FeedStaleSummaryScope, returnEpoch: Int,
                            now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard enabled, displayGrace != nil else { return }
        if earlyDeadlineLocked, let old = displayWindow,
           old.scope.viewerID == expected.viewerID, old.scope.generation == expected.generation {
            displayWindow = .init(scope: expected, returnEpoch: returnEpoch,
                startedAt: old.startedAt, startedUptime: old.startedUptime)
            return
        }
        // Duplicate onAppear/refresh callbacks cannot prolong an offline view.
        if let old = displayWindow, old.scope == expected, old.returnEpoch == returnEpoch { return }
        displayWindow = .init(scope: expected, returnEpoch: returnEpoch, startedAt: now, startedUptime: uptime)
        revision += 1
        scheduleVisibilityExpiry()
    }
    private func scheduleVisibilityExpiry() {
        expiryTask?.cancel(); expiryTask = nil
        let now = Date()
        let deadline: Date?
        if let displayGrace {
            deadline = displayWindow.map { $0.startedAt.addingTimeInterval(displayGrace) }
        } else if let maximumAge {
            deadline = entries.values.map { $0.validatedAt.addingTimeInterval(maximumAge) }.filter { $0 > now }.min()
        } else { deadline = nil }
        guard let deadline, deadline > now else { return }
        let identity = epoch, interval = deadline.timeIntervalSince(now)
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            guard let self, self.epoch == identity else { return }
            self.revision += 1
            if self.displayGrace == nil { self.scheduleVisibilityExpiry() }
        }
    }
    private func displayWindowAllows(_ expected: FeedStaleSummaryScope, now: Date, uptime: TimeInterval) -> Bool {
        guard let displayGrace else { return true } // Legacy bounded-age test policy.
        guard let window = displayWindow, window.scope == expected else { return false }
        let wall = now.timeIntervalSince(window.startedAt), monotonic = uptime - window.startedUptime
        return wall.isFinite && monotonic.isFinite && wall >= 0 && monotonic >= 0 &&
            wall < displayGrace && monotonic < displayGrace && abs(wall - monotonic) < 2
    }
    private func valid(_ entry: FeedStaleSummarySnapshot, now: Date, uptime: TimeInterval) -> Bool {
        guard let maximumAge else { return false }
        let wallAge = now.timeIntervalSince(entry.validatedAt), monotonicAge = uptime - entry.validatedUptime
        return wallAge.isFinite && monotonicAge.isFinite && wallAge >= 0 && monotonicAge >= 0 &&
            wallAge < maximumAge && monotonicAge < maximumAge && abs(wallAge - monotonicAge) < 2
    }
    func chromeReservation(viewerID: UUID?, width: Double, dynamicType: String, environment: String) -> FeedChromeLayout? {
        guard earlyDeadlineLocked, scope?.viewerID == viewerID, viewerID != nil else { return nil }
        return entries.values.compactMap(\.chromeLayout).first { $0.matches(width: width, dynamicType: dynamicType, environment: environment) }
    }
    func captureChrome(_ layout: FeedChromeLayout, viewerID: UUID?) {
        guard enabled, let viewerID, scope?.viewerID == viewerID else { return }
        // An older cache without this layout key must still learn its first
        // verified chrome measurement. Never replace an active matching lease.
        if earlyDeadlineLocked && entries.values.compactMap(\.chromeLayout).contains(where: {
            $0.matches(width: layout.width, dynamicType: layout.dynamicType, environment: layout.environment)
        }) { return }
        var changed = false
        for id in entries.keys where entries[id]?.chromeLayout != layout {
            entries[id]?.chromeLayout = layout; changed = true
        }
        if changed { revision += 1; persist() }
    }
    func captureLayout(cardID: UUID, scope expected: FeedStaleSummaryScope,
                       width: Double, height: Double, dynamicType: String, environment: String) {
        guard enabled, scope == expected, var entry = entries[cardID],
              let layout = FeedStaleSummaryLayout(width: width, height: height, dynamicType: dynamicType,
                environment: environment, contentRevision: entry.layoutRevision), entry.layout != layout else { return }
        entry.layout = layout; entries[cardID] = entry; revision += 1; persist()
    }
    func capture(photo: WorkoutPhotoReference, object: FeedReturnStorageObject, image: UIImage, scope expected: FeedStaleSummaryScope) {
        guard enabled, expected == scope, let card = photo.profileAuthority?.cardID,
              let entry = entries[card], let version = object.cacheVersionToken,
              entry.photoVersions[photo.cacheKey] == version, entry.photoOrder.contains(photo.cacheKey),
              valid(entry, now: Date(), uptime: ProcessInfo.processInfo.systemUptime) else { return }
        // A repeated onAppear is not new data. Existing bytes have already been
        // bound to this exact object version by accept()/revokePhoto().
        guard entry.photos[photo.cacheKey] == nil else { photoCaptureReuseHits += 1; return }
        let key = PhotoCaptureKey(epoch: epoch, scope: expected, cardID: card,
            resource: photo.cacheKey, version: version, validatedAt: entry.validatedAt)
        guard !photoCapturesInFlight.contains(key) else { photoCaptureCoalesced += 1; return }
        guard let pixels = image.cgImage else { return }
        photoCapturesInFlight.insert(key); photoEncodingStarts += 1
        Task { @MainActor [weak self] in
            let bytes = await Task.detached(priority: .utility) { UIImage(cgImage: pixels).jpegData(compressionQuality: 0.82) }.value
            guard let self else { return }
            defer { self.photoCapturesInFlight.remove(key) }
            guard self.epoch == key.epoch, self.scope == expected,
                  let bytes, bytes.count <= 2 * 1_024 * 1_024, var current = self.entries[card],
                  current.validatedAt == key.validatedAt, current.photoVersions[photo.cacheKey] == version,
                  current.photos[photo.cacheKey] == nil,
                  self.valid(current, now: Date(), uptime: ProcessInfo.processInfo.systemUptime) else { return }
            current.photos[photo.cacheKey] = bytes; self.entries[card] = current
            self.photoCaptureCommits += 1
            self.trim(); self.revision += 1; self.persist()
        }
    }
    func revoke(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { entries[id] = nil }
        fenceDiskBoundary()
        epoch = UUID(); revision += 1; scheduleVisibilityExpiry(); persist(invalidateFirst: true)
    }
    func revokePhoto(_ key: String) {
        for (id, var entry) in entries where entry.photos[key] != nil { entry.photos[key] = nil; entries[id] = entry }
        fenceDiskBoundary()
        epoch = UUID(); revision += 1; scheduleVisibilityExpiry(); persist(invalidateFirst: true)
    }
    private func fenceDiskBoundary() {
        guard enabled, let disk, let scope else { return }
        if !disk.revokeBoundarySynchronously(viewerID: scope.viewerID) {
            diskDiagnostic = "durable-revocation-failed-cache-disabled"
        }
    }
    func revokeAccountBoundary(viewerID: UUID) {
        guard enabled else { return }
        if let disk, !disk.revokeBoundarySynchronously(viewerID: viewerID) {
            diskDiagnostic = "durable-revocation-failed-cache-disabled"
        }
        if scope == nil || scope?.viewerID == viewerID { clear() }
    }
    func clear() {
        fenceDiskBoundary()
        expiryTask?.cancel(); expiryTask = nil
        epoch = UUID(); entries.removeAll(); scope = nil; displayWindow = nil; earlyDeadlineLocked = false; revision += 1
        guard let disk else { return }
        let previous = diskTask
        diskTask = Task { await previous?.value; try? await disk.logout() }
    }
    /// Auth must already have resolved to viewerID. Restored bytes remain display-only.
    func restore(viewerID: UUID, generation: Int, safetyRevision: Int) async {
        guard enabled, let disk, entries.isEmpty else { return }
        diskDiagnostic = "restore-start"
        let expected = FeedStaleSummaryScope(viewerID: viewerID, generation: generation,
                                             safetyRevision: safetyRevision, policyVersion: 1)
        if let scope, scope != expected { clear() }
        scope = expected
        if displayWindow == nil { beginDisplayWindow(scope: expected, returnEpoch: 0) }
        let identity = epoch
        await diskTask?.value
        guard epoch == identity, scope == expected, entries.isEmpty else { return }
        do {
            _ = try await disk.activate(diskScope(expected), authenticatedViewerID: viewerID)
            guard let bytes = try await disk.load(diskScope(expected), authenticatedViewerID: viewerID),
                  epoch == identity, scope == expected, entries.isEmpty else { diskDiagnostic = "restore-\(await disk.loadDiagnostic)"; return }
            let decoded = try await Task.detached(priority: .utility) {
                try JSONDecoder().decode([FeedStaleSummarySnapshot].self, from: bytes)
            }.value
            guard epoch == identity, scope == expected, entries.isEmpty, !Task.isCancelled else { return }
            let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
            for item in decoded.prefix(maximumCount) where valid(item, now: now, uptime: uptime) {
                entries[item.id] = item
            }
            trim(); revision += 1; scheduleVisibilityExpiry(); diskDiagnostic = "restored-\(entries.count)"
        } catch { diskDiagnostic = "restore-error-\((error as NSError).code)" }
    }
    func allSnapshots(scope expected: FeedStaleSummaryScope, now: Date = Date(),
                      uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [FeedStaleSummarySnapshot] {
        guard enabled, scope == expected, displayWindowAllows(expected, now: now, uptime: uptime) else { return [] }
        return entries.values.filter { valid($0, now: now, uptime: uptime) }
            .sorted { $0.activityAt > $1.activityAt }
    }
    private func diskScope(_ scope: FeedStaleSummaryScope) -> FeedDiskCacheScope {
        .init(viewerID: scope.viewerID, generation: 0,
              policyVersion: scope.policyVersion, safetyRevision: 0)
    }
    private func persist(invalidateFirst: Bool = false) {
        guard enabled, let disk, let scope else { return }
        let previous = diskTask, identity = epoch, diskScope = diskScope(scope)
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        let snapshots = entries.values.filter { valid($0, now: now, uptime: uptime) }
        let boot = FeedDiskCacheClock.current().bootID
        diskTask = Task { [weak self] in
            await previous?.value
            // Even superseded invalidations must run before any following save.
            if invalidateFirst {
                _ = try? await disk.activate(diskScope, authenticatedViewerID: scope.viewerID)
                try? await disk.invalidate(diskScope)
            }
            guard let self, self.epoch == identity, self.scope == scope else { return }
            do {
                let token = try await disk.activate(diskScope, authenticatedViewerID: scope.viewerID)
                guard self.epoch == identity, self.scope == scope else { return }
                guard let oldest = snapshots.min(by: { $0.validatedAt < $1.validatedAt }) else {
                    try await disk.invalidate(diskScope); return
                }
                let bytes = try await Task.detached(priority: .utility) {
                    try JSONEncoder().encode(snapshots)
                }.value
                guard self.epoch == identity, self.scope == scope, !Task.isCancelled else { return }
                // Photo completion must never renew the original server validation.
                let original = FeedDiskCacheClock(wallDate: oldest.validatedAt,
                                                  uptime: oldest.validatedUptime, bootID: boot)
                try await disk.save(payload: bytes, token: token, verifiedAt: original)
                self.diskDiagnostic = "saved-\(snapshots.count)"
            } catch { self.diskDiagnostic = "save-error-\((error as NSError).code)" }
        }
    }
    private func trim() {
        while entries.count > maximumCount || totalBytes > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.validatedAt < $1.value.validatedAt })?.key else { break }
            entries[oldest] = nil
        }
    }
}

struct FeedStaleSummaryView: View {
    let snapshot: FeedStaleSummarySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle").resizable().frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.author).font(.subheadline.weight(.bold)).foregroundStyle(SOOMColor.ink)
                    if let date = snapshot.row.cursor?.activityAt {
                        Text(WorkoutCardDateFormatter.label(date)).font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("지역 정보 미표시").font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.top, 24)
            Text(snapshot.title).font(.title2.weight(.bold)).foregroundStyle(SOOMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 27)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 16) {
                ForEach(Array(snapshot.metrics.enumerated()), id: \.offset) { _, metric in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.label).font(.caption2).foregroundStyle(SOOMColor.secondaryInk)
                        Text(metric.value).font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                            .foregroundStyle(SOOMColor.ink).minimumScaleFactor(0.8)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
            if !snapshot.photos.isEmpty {
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(snapshot.photoOrder, id: \.self) { key in
                                if let data = snapshot.photos[key] {
                                    FeedStalePhotoView(data: data,
                                        maximumWidth: WorkoutPhotoMediaLayout.availableWidth(in: geometry.size.width))
                                }
                            }
                        }.padding(.horizontal, 16)
                    }
                }.frame(height: 260).accessibilityIdentifier("feed.stale.photos")
            }
            Text("최신 내용 확인 중").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 16)
        }.frame(maxWidth: .infinity, alignment: .leading).background(SOOMColor.surface)
            .allowsHitTesting(false).accessibilityIdentifier("feed.stale.summary.\(snapshot.id)")
    }
}

private struct FeedStalePhotoView: View {
    let data: Data
    let maximumWidth: CGFloat
    @State private var decoded: UIImage?
    private var width: CGFloat {
        let ratio = decoded.flatMap { $0.size.height > 0 ? $0.size.width / $0.size.height : nil }
        return WorkoutPhotoMediaLayout.tileWidth(aspectRatio: ratio, maxWidth: maximumWidth)
    }
    var body: some View {
        Group {
            if let decoded { Image(uiImage: decoded).resizable().scaledToFill() }
            else { Color.clear }
        }.frame(width: width, height: 260).clipped().accessibilityLabel("저장된 운동 사진")
            .task(id: data) {
                let bytes = data
                let pixels = await Task.detached(priority: .utility) {
                    UIImage(data: bytes)?.preparingForDisplay()?.cgImage
                }.value
                guard !Task.isCancelled else { return }
                decoded = pixels.map { UIImage(cgImage: $0) }
            }
    }
}
