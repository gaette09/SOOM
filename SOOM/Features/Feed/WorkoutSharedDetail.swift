import Foundation
import Supabase
import SwiftData

/// Versioned, single-workout measurements only. No AI, recovery, history,
/// user identifiers, device payloads, coaching text or original timestamps.
struct WorkoutSharedDetailInput: Codable, Equatable {
    var version = 1
    var durationSeconds: Double
    var distanceMeters: Double?
    var route: [RoutePoint] = []
    var samples: [Sample] = []
    struct RoutePoint: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var seconds: Double?
        var altitude: Double?
        var segment: Int
    }
    struct Sample: Codable, Equatable {
        var seconds: Double
        var distanceMeters: Double?
        var heartRateBPM: Double?
        var cadencePerMinute: Double?
        var powerWatts: Double?
        var speedMetersPerSecond: Double?
        var elevationMeters: Double?
        var cadenceUnit: WorkoutTelemetryCadenceUnit?
    }
    static func build(workout: UnifiedWorkout, route: WorkoutRoute?, telemetry: WorkoutTelemetry?) -> Self {
        let duration = min(604_800, max(0, workout.durationSeconds.isFinite ? workout.durationSeconds : 0))
        var input = Self(durationSeconds: duration, distanceMeters: valid(workout.distanceMeters, 0...10_000_000))
        if let route, route.workoutId == workout.id {
            let points = route.coordinates.filter { $0.latitude.isFinite && $0.longitude.isFinite
                && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }
            // Preserve the true endpoints before server masking. This input is
            // owner-only transport; only `masked()` output can be rendered/stored.
            input.route = bounded(points, maximum: 4096).map {
                RoutePoint(latitude: $0.latitude, longitude: $0.longitude,
                    seconds: valid($0.timestamp.map { $0.timeIntervalSince(workout.startDate) }, 0...duration),
                    altitude: valid($0.altitude, -1000...12000), segment: max(0, $0.segmentIndex))
            }
        }
        if let telemetry, telemetry.workoutID == workout.id {
            let readings = telemetry.validated(for: workout).coalescingSamples().samples
            var byTime: [Double: Sample] = [:]
            for reading in readings {
                let seconds = reading.timestamp.timeIntervalSince(workout.startDate)
                guard seconds >= 0, seconds <= duration else { continue }
                var sample = byTime[seconds] ?? Sample(seconds: seconds)
                sample.distanceMeters = reading.distanceMeters ?? sample.distanceMeters
                sample.heartRateBPM = reading.heartRateBPM ?? sample.heartRateBPM
                sample.cadencePerMinute = reading.cadencePerMinute ?? sample.cadencePerMinute
                sample.powerWatts = reading.powerWatts ?? sample.powerWatts
                sample.speedMetersPerSecond = reading.speedMetersPerSecond ?? sample.speedMetersPerSecond
                sample.elevationMeters = reading.elevationMeters ?? sample.elevationMeters
                sample.cadenceUnit = reading.cadenceUnit ?? sample.cadenceUnit
                byTime[seconds] = sample
            }
            let sorted = byTime.values.sorted { $0.seconds < $1.seconds }
            if sorted.count <= 4096 { input.samples = sorted }
            else {
                // First/last and every channel's extrema per bucket. Raw personal
                // telemetry is unchanged; the explicitly shared snapshot is bounded.
                var chosen = Set<Int>()
                let size = Int(ceil(Double(sorted.count) / 256))
                let channels: [(Sample) -> Double?] = [ { $0.distanceMeters }, { $0.heartRateBPM },
                    { $0.cadencePerMinute }, { $0.powerWatts }, { $0.speedMetersPerSecond }, { $0.elevationMeters } ]
                for first in stride(from: 0, to: sorted.count, by: size) {
                    let indices = Array(first..<min(first + size, sorted.count))
                    chosen.insert(indices.first!); chosen.insert(indices.last!)
                    for channel in channels {
                        let measured = indices.filter { channel(sorted[$0]) != nil }
                        if let low = measured.min(by: { channel(sorted[$0])! < channel(sorted[$1])! }) { chosen.insert(low) }
                        if let high = measured.max(by: { channel(sorted[$0])! < channel(sorted[$1])! }) { chosen.insert(high) }
                    }
                }
                input.samples = chosen.sorted().map { sorted[$0] }
            }
        }
        return input
    }
    static func valid(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
        value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }
    private static func bounded<T>(_ values: [T], maximum: Int) -> [T] {
        guard values.count > maximum else { return values }
        return (0..<maximum).map { values[Int(Double($0) * Double(values.count - 1) / Double(maximum - 1))] }
    }
    /// Same 200m radial fence as the server. Removes loop re-entries too and
    /// breaks segments across removed areas; no line crosses a private endpoint.
    func masked() -> Self {
        var result = self
        guard let first = route.first, let last = route.last, route.count > 1 else { result.route = []; return result }
        var output: [RoutePoint] = []; var segment = -1; var previous: RoutePoint?
        for var point in route {
            guard Self.distance(first, point) >= 200, Self.distance(last, point) >= 200 else {
                previous = nil; continue
            }
            if previous == nil || previous!.segment != point.segment
                || Self.distance(previous!, point) > 1000
                || !Self.edgeClear(previous!, point, origin: first)
                || !Self.edgeClear(previous!, point, origin: last) { segment += 1 }
            previous = point
            point.segment = segment
            output.append(point)
        }
        let groups = Dictionary(grouping: output, by: \.segment)
        result.route = output.filter { (groups[$0.segment]?.count ?? 0) >= 2 }
        return result
    }
    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dlat = lat2 - lat1, dlon = (b.longitude - a.longitude) * .pi / 180
        let h = min(1, max(0, pow(sin(dlat / 2),2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2),2)))
        return 6_371_000 * 2 * atan2(sqrt(h),sqrt(1-h))
    }
    static func edgeClear(_ a: RoutePoint, _ b: RoutePoint, origin: RoutePoint) -> Bool {
        func xy(_ p: RoutePoint) -> (Double,Double) {
            var delta = p.longitude - origin.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return (delta * .pi / 180 * 6_371_000 * cos(origin.latitude * .pi / 180),
                    (p.latitude-origin.latitude) * .pi / 180 * 6_371_000)
        }
        let p = xy(a), q = xy(b), dx = q.0-p.0, dy = q.1-p.1
        let norm = dx*dx+dy*dy
        let t = norm > 0 ? min(1,max(0,-(p.0*dx+p.1*dy)/norm)) : 0
        return hypot(p.0+t*dx,p.1+t*dy) >= 202 // conservative projection margin
    }
}

struct WorkoutSharedDetailSnapshot: Codable, Equatable {
    let postID: UUID
    let revision: Int64
    let payload: WorkoutSharedDetailInput
    enum CodingKeys: String, CodingKey { case postID = "post_id", revision, payload }
    func isValid(for post: FeedPostDTO) -> Bool {
        guard postID == post.id, revision > 0, revision == post.sharedDetailRevision,
              payload.version == 1, payload.durationSeconds.isFinite,
              (0...604_800).contains(payload.durationSeconds), payload.route.count <= 4096,
              payload.samples.count <= 4096,
              WorkoutSharedDetailInput.valid(payload.distanceMeters,0...10_000_000) == payload.distanceMeters else { return false }
        return payload.route.allSatisfy { point in
            point.latitude.isFinite && point.longitude.isFinite && (-90...90).contains(point.latitude)
                && (-180...180).contains(point.longitude) && point.segment >= 0
                && (point.seconds.map { $0.isFinite && (0...payload.durationSeconds).contains($0) } ?? true)
                && (point.altitude.map { $0.isFinite && (-1000...12000).contains($0) } ?? true)
        } && payload.samples.allSatisfy { sample in
            sample.seconds.isFinite && (0...payload.durationSeconds).contains(sample.seconds)
                && [WorkoutSharedDetailInput.valid(sample.distanceMeters,0...10_000_000) == sample.distanceMeters,
                    WorkoutSharedDetailInput.valid(sample.heartRateBPM,1...300) == sample.heartRateBPM,
                    WorkoutSharedDetailInput.valid(sample.cadencePerMinute,0...400) == sample.cadencePerMinute,
                    WorkoutSharedDetailInput.valid(sample.powerWatts,0...5000) == sample.powerWatts,
                    WorkoutSharedDetailInput.valid(sample.speedMetersPerSecond,0...150) == sample.speedMetersPerSecond,
                    WorkoutSharedDetailInput.valid(sample.elevationMeters,-1000...12000) == sample.elevationMeters].allSatisfy { $0 }
        }
    }
    func route(start: Date) -> WorkoutRoute? {
        guard payload.route.count > 1 else { return nil }
        let coords = payload.route.map { WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude,
            altitude: $0.altitude, timestamp: $0.seconds.map { start.addingTimeInterval($0) }, segmentIndex: $0.segment) }
        let distance = zip(payload.route,payload.route.dropFirst()).reduce(0.0) {
            $0 + ($1.0.segment == $1.1.segment ? WorkoutSharedDetailInput.distance($1.0,$1.1) : 0)
        }
        return WorkoutRoute(id: postID, workoutId: postID, source: .unknown, coordinates: coords, totalDistanceMeters: distance, createdAt: start, privacyMaskApplied: true)
    }
    func telemetry(start: Date) -> WorkoutTelemetry? {
        guard !payload.samples.isEmpty else { return nil }
        return WorkoutTelemetry(workoutID: postID, source: .unknown, samples: payload.samples.map {
            WorkoutTelemetrySample(timestamp: start.addingTimeInterval($0.seconds), distanceMeters: $0.distanceMeters,
                heartRateBPM: $0.heartRateBPM, cadencePerMinute: $0.cadencePerMinute, powerWatts: $0.powerWatts,
                speedMetersPerSecond: $0.speedMetersPerSecond, elevationMeters: $0.elevationMeters, cadenceUnit: $0.cadenceUnit,
                source: .unknown)
        }, fetchedAt: start)
    }
}

extension FeedItem {
    var permittedSharedDetail: WorkoutSharedDetailSnapshot? {
        guard sharedDetailContractEnabled, let sharedDetail, let post = serverPostSnapshot,
              sharedDetail.isValid(for: post) else { return nil }
        return sharedDetail
    }
}

extension WorkoutDetailSharedRecord {
    var route: WorkoutRoute? { item.permittedSharedDetail?.route(start: item.activityDate ?? item.createdAt) }
    var telemetry: WorkoutTelemetry? {
        guard let detail = item.permittedSharedDetail else { return nil }
        let start = item.activityDate ?? item.createdAt
        return detail.telemetry(start: start) ?? WorkoutTelemetry(workoutID: item.id, source: .unknown, samples: [], fetchedAt: start)
    }
    var measurementWorkout: UnifiedWorkout {
        let start = item.activityDate ?? item.createdAt
        let duration = item.permittedSharedDetail?.payload.durationSeconds ?? item.workoutDurationSeconds ?? 0
        return UnifiedWorkout(id: item.id, externalId: nil, source: .unknown, workoutType: item.recordWorkoutType,
            startDate: start, endDate: start.addingTimeInterval(duration), durationSeconds: duration,
            distanceMeters: item.workoutDistanceMeters, activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .partial, createdAt: start, updatedAt: start)
    }
}

/// Existing authenticated client only. Feature-off and missing migration are
/// compatible fallbacks; permission/network/validation failures are not ignored.
struct SupabaseWorkoutSharedDetailService {
    let client: SupabaseClient
    static let header = "x-soom-workout-contract"
    static let contract = "detail-v1"
    func enabled() async throws -> Bool {
        do {
            let active: Bool = try await client.rpc("soom_shared_detail_enabled_v1")
                .setHeader(name: Self.header, value: Self.contract).execute().value
            guard active else { return false }
            return try await client.rpc("soom_full_detail_consent_ready_v1")
                .setHeader(name: Self.header, value: Self.contract).execute().value
        } catch let error as PostgrestError where error.code == "PGRST202" { return false }
    }
    func fetch(posts: [FeedPostDTO]) async throws -> (enabled: Bool, snapshots: [WorkoutSharedDetailSnapshot]) {
        let active = try await enabled()
        guard active, !posts.isEmpty else { return (active,[]) }
        struct Params: Encodable { let p_post_ids: [UUID] }
        let snapshots: [WorkoutSharedDetailSnapshot] = try await client.rpc("soom_shared_workout_details_v1",
            params: Params(p_post_ids: posts.map(\.id)))
            .setHeader(name: Self.header, value: Self.contract).execute().value
        let byID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id,$0) })
        guard Set(snapshots.map(\.postID)).count == snapshots.count,
              snapshots.allSatisfy({ snapshot in byID[snapshot.postID].map { snapshot.isValid(for: $0) } == true }) else {
            throw FeedPostManagementError.changeNotConfirmed
        }
        return (active,snapshots)
    }
    func authorizedPosts(_ posts: [FeedPostDTO]) async throws -> Set<UUID> {
        guard try await enabled(), !posts.isEmpty else { return [] }
        struct Params: Encodable { let p_post_ids: [UUID] }
        struct Row: Decodable { let post_id: UUID; let revision: Int64 }
        let rows: [Row] = try await client.rpc("soom_shared_detail_access_v1", params: Params(p_post_ids: posts.map(\.id)))
            .setHeader(name: Self.header, value: Self.contract).execute().value
        let byID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id,$0) })
        guard rows.allSatisfy({ byID[$0.post_id]?.sharedDetailRevision == $0.revision }) else { throw FeedPostManagementError.changeNotConfirmed }
        return Set(rows.map(\.post_id))
    }
    @MainActor
    func prepare(workout: UnifiedWorkout, route: WorkoutRoute?, telemetry: WorkoutTelemetry?, ownerID: UUID,
                 expectedConsentRevision: Int64? = nil, onlyPostIDs: Set<UUID>? = nil) async throws {
        func check() throws { guard client.auth.currentSession?.user.id == ownerID else { throw CommunitySafetyError.accountChanged } }
        try check()
        guard try await enabled() else { throw CommunitySafetyError.unavailable }
        try check()
        let privacy = try await SupabaseAccountPrivacyService(client: client).fetch()
        try check()
        guard privacy.isSelected, privacy.shareMeasurements == true else { throw CommunitySafetyError.socialUnverified }
        if let expectedConsentRevision, privacy.revision != expectedConsentRevision { throw FeedPostManagementError.changeNotConfirmed }
        let remote = SupabaseWorkoutRecordRemote(client: client)
        var posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        try check()
        if let onlyPostIDs {
            posts = posts.filter { onlyPostIDs.contains($0.id) }
            if posts.isEmpty { return }
        }
        if posts.isEmpty {
            try await remote.update(workout: workout, ownerID: ownerID, visibility: .privatePost, createIfMissing: true)
            posts = try await remote.linkedPosts(workoutID: workout.id, ownerID: ownerID)
        }
        guard !posts.isEmpty else { throw FeedPostManagementError.changeNotConfirmed }
        let input = WorkoutSharedDetailInput.build(workout: workout, route: route, telemetry: telemetry)
        struct Params: Encodable {
            let p_post_id: UUID; let p_owner_id: UUID; let p_expected_revision: Int64; let p_input: WorkoutSharedDetailInput
        }
        for post in posts {
            try check()
            let rows: [WorkoutSharedDetailSnapshot] = try await client.rpc("put_shared_workout_detail_v1",
                params: Params(p_post_id: post.id,p_owner_id: ownerID,p_expected_revision: post.sharedDetailRevision ?? 0,p_input: input))
                .setHeader(name: Self.header, value: Self.contract)
                .setHeader(name: "x-soom-detail-consent-revision", value: String(privacy.revision)).execute().value
            try check()
            guard rows.count == 1, rows.first?.postID == post.id else { throw FeedPostManagementError.changeNotConfirmed }
        }
    }
}

// MARK: Existing-authorized detail refresh (profile-only v2)
struct WorkoutExistingDetailLookup:Codable {
    struct Row:Codable {let post_id:UUID;let canonical_id:UUID;let detail_revision:Int64}
    let version:Int;let owner_id:UUID;let source_id:UUID;let profile_revision:Int64
    let measurement_revision:Int64;let rows:[Row];let release_ready:Bool
}
struct WorkoutExistingDetailRefreshParameters:Encodable {
    let p_post_id:UUID;let p_source_id:UUID;let p_expected_profile_revision:Int64
    let p_expected_measurement_revision:Int64;let p_expected_detail_revision:Int64;let p_input:WorkoutSharedDetailInput
}
struct WorkoutExistingDetailRefreshReceipt:Codable {
    let version:Int;let owner_id:UUID;let post_id:UUID;let source_id:UUID;let detail_revision:Int64
    let profile_revision:Int64;let measurement_revision:Int64;let refreshed:Bool;let release_ready:Bool
}
@MainActor protocol WorkoutExistingDetailRefreshTransport {
    var ownerID:UUID? {get}
    func lookup(sourceID:UUID) async throws -> WorkoutExistingDetailLookup
    func refresh(_ parameters:WorkoutExistingDetailRefreshParameters) async throws -> WorkoutExistingDetailRefreshReceipt
}
@MainActor protocol WorkoutExistingDetailRefreshing {
    /// Returns the number of existing snapshots refreshed; zero never means a new grant.
    func refresh(sourceID:UUID,ownerID:UUID,validate:@escaping () throws -> Void,
                 loadInput:@escaping () async throws -> WorkoutSharedDetailInput) async throws -> Int
}
@MainActor struct WorkoutExistingDetailRefreshService:WorkoutExistingDetailRefreshing {
    let transport:any WorkoutExistingDetailRefreshTransport
    func refresh(sourceID:UUID,ownerID:UUID,validate:@escaping () throws -> Void,
                 loadInput:@escaping () async throws -> WorkoutSharedDetailInput) async throws -> Int {
        func check() throws {
            try Task.checkCancellation();try validate()
            guard transport.ownerID==ownerID else {throw CommunitySafetyError.accountChanged}
        }
        try check()
        let lookup=try await transport.lookup(sourceID:sourceID)
        try check()
        guard lookup.version==2,lookup.release_ready,lookup.owner_id==ownerID,lookup.source_id==sourceID,
              lookup.profile_revision>0,lookup.profile_revision<Int64.max,lookup.measurement_revision>=0,lookup.measurement_revision<Int64.max,lookup.rows.count<=1,
              Set(lookup.rows.map(\.post_id)).count==lookup.rows.count,
              lookup.rows.allSatisfy({$0.detail_revision>=0 && $0.detail_revision<Int64.max}) else {throw FeedPostManagementError.changeNotConfirmed}
        guard !lookup.rows.isEmpty else{return 0} // No GPS/measurement read for a missing grant.
        guard lookup.measurement_revision>0 else {throw FeedPostManagementError.changeNotConfirmed}
        let input=try await loadInput()
        try check()
        for row in lookup.rows {
            let receipt=try await transport.refresh(.init(p_post_id:row.post_id,p_source_id:sourceID,
                p_expected_profile_revision:lookup.profile_revision,p_expected_measurement_revision:lookup.measurement_revision,
                p_expected_detail_revision:row.detail_revision,p_input:input))
            try check()
            guard receipt.version==2,receipt.release_ready,receipt.refreshed,receipt.owner_id==ownerID,
                  receipt.post_id==row.post_id,receipt.source_id==sourceID,
                  receipt.profile_revision==lookup.profile_revision,receipt.measurement_revision==lookup.measurement_revision,receipt.detail_revision>=0,receipt.detail_revision<Int64.max,
                  receipt.detail_revision==row.detail_revision || receipt.detail_revision==row.detail_revision+1
            else {throw FeedPostManagementError.changeNotConfirmed}
        }
        return lookup.rows.count
    }
}
@MainActor struct SupabaseWorkoutExistingDetailRefreshTransport:WorkoutExistingDetailRefreshTransport {
    let client:SupabaseClient
    var ownerID:UUID? {client.auth.currentSession?.user.id}
    private func check() throws {
        guard ProfileOnlyPrivacyReleaseGate.productionReady,ownerID != nil else {throw CommunitySafetyError.socialUnverified}
    }
    func lookup(sourceID:UUID) async throws -> WorkoutExistingDetailLookup {
        try check()
        struct Params:Encodable {let p_source_id:UUID}
        return try await client.rpc("soom_existing_detail_refresh_lookup_v2",params:Params(p_source_id:sourceID))
            .setHeader(name:SupabaseWorkoutSharedDetailService.header,value:SupabaseWorkoutSharedDetailService.contract).execute().value
    }
    func refresh(_ parameters:WorkoutExistingDetailRefreshParameters) async throws -> WorkoutExistingDetailRefreshReceipt {
        try check()
        return try await client.rpc("soom_refresh_existing_detail_candidate_v2",params:parameters)
            .setHeader(name:SupabaseWorkoutSharedDetailService.header,value:SupabaseWorkoutSharedDetailService.contract).execute().value
    }
}


@MainActor enum WorkoutExistingDetailRefreshPending {
    static let didChange=Notification.Name("SOOM.existingDetailRefreshPending.changed")
    private static func key(_ owner:UUID)->String {"SOOM.existingDetailRefreshPending.v2."+owner.uuidString.lowercased()}
    static func entries(ownerID:UUID)->[UUID:UUID] {
        let raw=UserDefaults.standard.dictionary(forKey:key(ownerID)) as? [String:String] ?? [:]
        return Dictionary(uniqueKeysWithValues:raw.compactMap {k,v in guard let id=UUID(uuidString:k),let token=UUID(uuidString:v) else{return nil};return (id,token)})
    }
    static func count(ownerID:UUID)->Int {entries(ownerID:ownerID).count}
    static func nextBatch(ownerID:UUID,limit:Int=100)->[(key:UUID,value:UUID)] {
        let values=entries(ownerID:ownerID).sorted{$0.key.uuidString<$1.key.uuidString}
        guard !values.isEmpty else{return []}
        let cursor=UserDefaults.standard.string(forKey:key(ownerID)+".cursor")
        let start=cursor.flatMap{last in values.firstIndex{$0.key.uuidString>last}} ?? 0
        return Array((Array(values[start...])+Array(values[..<start])).prefix(max(0,min(limit,100))))
    }
    static func recordAttempt(ownerID:UUID,workoutID:UUID) {
        UserDefaults.standard.set(workoutID.uuidString,forKey:key(ownerID)+".cursor")
    }

    @discardableResult static func mark(ownerID:UUID,workoutID:UUID)->UUID {
        var values=entries(ownerID:ownerID);let token=UUID();values[workoutID]=token;save(values,ownerID:ownerID);return token
    }
    static func acknowledge(ownerID:UUID,workoutID:UUID,token:UUID) {
        var values=entries(ownerID:ownerID)
        guard values[workoutID]==token else{return};values.removeValue(forKey:workoutID);save(values,ownerID:ownerID)
    }
    private static func save(_ values:[UUID:UUID],ownerID:UUID) {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues:values.map{($0.key.uuidString.lowercased(),$0.value.uuidString)}),forKey:key(ownerID))
        NotificationCenter.default.post(name:didChange,object:ownerID)
    }
}
@MainActor enum WorkoutExistingDetailRefreshRetry {
    private static var running=Set<UUID>()
    /// At most 100 pending IDs per foreground run; no raw payload is persisted.
    /// Errors stay pending, and one failed card does not block later cards.
    static func run(storage:HealthAccountStorageController,makeRefresher:((UUID)->any WorkoutExistingDetailRefreshing)? = nil) async {
        guard ProfileOnlyPrivacyReleaseGate.productionReady,!ReviewDemoMode.isActive,
              let owner=storage.userID else{return}
        let container=storage.container,scope=storage.scopeID,context=ModelContext(storage.container)
        func current()->Bool {storage.userID==owner && storage.scopeID==scope && storage.container === container &&
            HealthCloudJournal.accountID(for:context)==owner && !HealthCloudJournal.isRetired(context) && !Task.isCancelled}
        // A new foreground must not lose its retry while the cancelled prior
        // request is still retiring. Waiting is local and cancellation-aware.
        while running.contains(owner) {
            guard current() else{return}
            do {try await Task.sleep(for:.milliseconds(25))} catch {return}
        }
        guard current() else{return}
        running.insert(owner);defer{running.remove(owner)}
        let captured=WorkoutExistingDetailRefreshPending.nextBatch(ownerID:owner)
        for (id,token) in captured {
            guard current() else{return}
            WorkoutExistingDetailRefreshPending.recordAttempt(ownerID:owner,workoutID:id)
            do {
                let store=SwiftDataUnifiedWorkoutStore(modelContext:context)
                guard let value=try await store.fetchWorkout(id:id) else {
                    guard current() else{return}
                    WorkoutExistingDetailRefreshPending.acknowledge(ownerID:owner,workoutID:id,token:token);continue
                }
                guard current() else{return}
                let model=WorkoutRecordManagement(workout:value);model.configure(context:context,storage:storage,existingDetailRefresher:makeRefresher?(owner))
                _=await model.refreshProviderMeasurements()
            } catch {continue}
        }
    }
}

// MARK: - Card-only legacy preview (never a full-detail fallback)

struct FeedCardPreviewRead {
    let postID: UUID
    let ownerID: UUID
    let presentation: FeedLinkedCardPresentation
}

enum FeedCardPreviewReadError: Error {
    case changedContext, invalidMetadata, invalidGeometry, changedMetadata
}

/// The exact RLS-protected metadata fields required by a card. No measurement
/// samples, reactions, comments, profiles or photo contents belong to this read.
struct FeedCardPreviewMetadata: Decodable, Equatable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let body: String?
    let routeSummary: FeedRouteSummaryDTO?
    let updatedAt: Date?
    let detailRevision: Int64?
    enum CodingKeys: String, CodingKey {
        case id, title, body
        case ownerID = "user_id", routeSummary = "route_summary"
        case updatedAt = "updated_at", detailRevision = "shared_detail_revision"
    }
}

/// Geometry is already masked by the server. This DTO deliberately has no
/// timestamp, altitude, distance series or physiological sample fields.
struct FeedCardPreviewGeometry: Decodable, Equatable {
    struct Point: Decodable, Equatable {
        let latitude: Double
        let longitude: Double
        let segment: Int
    }
    let postID: UUID
    let ownerID: UUID
    let revision: Int64
    let points: [Point]
    enum CodingKeys: String, CodingKey {
        case postID = "post_id", ownerID = "owner_id", revision
        case points = "authorized_route_geometry"
    }
}

@MainActor
struct SupabaseFeedCardPreviewReader {
    let client: SupabaseClient
    static let metadataColumns = "id,user_id,title,body,route_summary,updated_at,shared_detail_revision"

    func load(postID: UUID, ownerID: UUID, date: Date,
              isCurrent: @escaping @MainActor () -> Bool) async throws -> FeedCardPreviewRead? {
        guard let viewer = client.auth.currentSession?.user.id else { throw FeedCardPreviewReadError.changedContext }
        func check() throws {
            guard !Task.isCancelled, isCurrent(), client.auth.currentSession?.user.id == viewer,
                  !AccountDeletionWriteFence.shared.isRetired(viewer) else { throw FeedCardPreviewReadError.changedContext }
        }
        func metadata() async throws -> FeedCardPreviewMetadata? {
            try check()
            let rows: [FeedCardPreviewMetadata] = try await client.from("feed_posts")
                .select(Self.metadataColumns).eq("id", value: postID).limit(2).execute().value
            try check()
            guard rows.count <= 1 else { throw FeedCardPreviewReadError.invalidMetadata }
            guard let row = rows.first else { return nil }
            guard row.id == postID, row.ownerID == ownerID else { throw FeedCardPreviewReadError.invalidMetadata }
            return row
        }
        try check()
        guard let first = try await metadata() else { return nil }
        struct Parameters: Encodable { let p_post_ids: [UUID] }
        try check()
        let geometry: [FeedCardPreviewGeometry] = try await client.rpc("soom_shared_workout_card_preview_v1",
            params: Parameters(p_post_ids: [postID]))
            .setHeader(name: SupabaseWorkoutSharedDetailService.header, value: SupabaseWorkoutSharedDetailService.contract)
            .execute().value
        try check()
        // Endpoint absence/errors throw. A full-detail reader is never invoked.
        guard let confirmed = try await metadata(), confirmed == first else { throw FeedCardPreviewReadError.changedMetadata }
        try check()
        return try Self.validated(metadata: first, geometry: geometry, postID: postID, ownerID: ownerID, date: date)
    }

    static func validated(metadata: FeedCardPreviewMetadata, geometry: [FeedCardPreviewGeometry],
                          postID: UUID, ownerID: UUID, date: Date) throws -> FeedCardPreviewRead {
        guard metadata.id == postID, metadata.ownerID == ownerID, date.timeIntervalSince1970.isFinite,
              metadata.detailRevision.map({ $0 >= 0 }) ?? true else { throw FeedCardPreviewReadError.invalidMetadata }
        guard geometry.count <= 1 else { throw FeedCardPreviewReadError.invalidGeometry }
        var route: WorkoutRoute?
        if let value = geometry.first {
            guard value.postID == postID, value.ownerID == ownerID,
                  let revision = metadata.detailRevision, revision > 0, value.revision == revision,
                  value.points.count <= 4096,
                  value.points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite &&
                      (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && $0.segment >= 0 }) else {
                throw FeedCardPreviewReadError.invalidGeometry
            }
            if value.points.count > 1 {
                let points = value.points.map { WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, segmentIndex: $0.segment) }
                let distance = zip(value.points, value.points.dropFirst()).reduce(0.0) { sum, pair in
                    guard pair.0.segment == pair.1.segment else { return sum }
                    let a = WorkoutSharedDetailInput.RoutePoint(latitude: pair.0.latitude, longitude: pair.0.longitude, seconds: nil, altitude: nil, segment: pair.0.segment)
                    let b = WorkoutSharedDetailInput.RoutePoint(latitude: pair.1.latitude, longitude: pair.1.longitude, seconds: nil, altitude: nil, segment: pair.1.segment)
                    return sum + WorkoutSharedDetailInput.distance(a, b)
                }
                route = WorkoutRoute(id: postID, workoutId: postID, source: .unknown, coordinates: points,
                    totalDistanceMeters: distance, createdAt: date, privacyMaskApplied: true)
            }
        }
        // No geometry means denied/unavailable route, not a reason to discard
        // independently RLS-authorized title, caption, device and location.
        return FeedCardPreviewRead(postID: postID, ownerID: ownerID,
            presentation: .init(title: metadata.title, caption: metadata.body,
                device: metadata.routeSummary?.deviceName, location: metadata.routeSummary?.locationName, route: route))
    }
}


// MARK: - Strict visible-batch v3 card projection (no transport or detail fallback)

struct FeedBatchCardPreviewWire: Decodable {
    enum ValidationError: Error { case invalidContract }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    struct Point: Decodable {
        let latitude: Double
        let longitude: Double
        let segment: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            guard Set(c.allKeys.map(\.stringValue)) == Set(["latitude", "longitude", "segment"]) else { throw ValidationError.invalidContract }
            latitude = try c.decode(Double.self, forKey: Key("latitude"))
            longitude = try c.decode(Double.self, forKey: Key("longitude"))
            segment = try c.decode(Int.self, forKey: Key("segment"))
        }
    }
    let state: String
    let postID: UUID?
    let ownerID: UUID?
    let postRevision: String?
    let snapshotRevision: Int64?
    let consentRevision: Int64?
    let title: String?
    let caption: String?
    let deviceName: String?
    let locationName: String?
    let routeState: String?
    let points: [Point]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard try c.decode(Int.self, forKey: Key("version")) == 1 else { throw ValidationError.invalidContract }
        state = try c.decode(String.self, forKey: Key("state"))
        let keys = Set(c.allKeys.map(\.stringValue))
        if state == "unavailable" {
            guard keys == Set(["version", "state"]) else { throw ValidationError.invalidContract }
            postID = nil; ownerID = nil; postRevision = nil
            snapshotRevision = nil; consentRevision = nil
            title = nil; caption = nil; deviceName = nil; locationName = nil
            routeState = nil; points = []
            return
        }
        guard state == "ready", keys == Set(["version", "state", "post_id", "owner_id", "post_revision", "snapshot_revision", "consent_revision", "serializer_version", "title", "caption", "device_name", "location_name", "route_state", "authorized_route_geometry"]),
              try c.decode(Int.self, forKey: Key("serializer_version")) == 1 else { throw ValidationError.invalidContract }
        postID = try c.decode(UUID.self, forKey: Key("post_id"))
        ownerID = try c.decode(UUID.self, forKey: Key("owner_id"))
        postRevision = try c.decode(String.self, forKey: Key("post_revision"))
        snapshotRevision = try c.decodeIfPresent(Int64.self, forKey: Key("snapshot_revision"))
        consentRevision = try c.decodeIfPresent(Int64.self, forKey: Key("consent_revision"))
        title = try c.decodeIfPresent(String.self, forKey: Key("title"))
        caption = try c.decodeIfPresent(String.self, forKey: Key("caption"))
        deviceName = try c.decodeIfPresent(String.self, forKey: Key("device_name"))
        locationName = try c.decodeIfPresent(String.self, forKey: Key("location_name"))
        routeState = try c.decode(String.self, forKey: Key("route_state"))
        points = try c.decode([Point].self, forKey: Key("authorized_route_geometry"))
    }

    /// The caller separately verifies the batch social receipt and current
    /// account/generation. This projection is not itself a detail permission.
    func validated(postID expectedPostID: UUID, ownerID expectedOwnerID: UUID,
                   date: Date) throws -> FeedLinkedCardPresentation? {
        guard state == "ready" else { return nil }
        guard postID == expectedPostID, ownerID == expectedOwnerID,
              date.timeIntervalSince1970.isFinite,
              snapshotRevision.map({ $0 > 0 }) ?? true,
              consentRevision.map({ $0 > 0 }) ?? true,
              routeState != "ready" || (snapshotRevision != nil && consentRevision != nil),
              let postRevision, postRevision.utf8.count <= 64,
              Self.validISO8601(postRevision),
              routeState == "ready" || routeState == "unavailable",
              points.count <= 4096,
              points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite &&
                  (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && $0.segment >= 0 }),
              zip(points, points.dropFirst()).allSatisfy({ pair in pair.0.segment <= pair.1.segment }),
              routeState != "unavailable" || (points.isEmpty && snapshotRevision == nil && consentRevision == nil),
              routeState != "ready" || points.count >= 2 else { throw ValidationError.invalidContract }
        var route: WorkoutRoute?
        if routeState == "ready" {
            let distance = zip(points, points.dropFirst()).reduce(0.0) { sum, pair in
                guard pair.0.segment == pair.1.segment else { return sum }
                let a = WorkoutSharedDetailInput.RoutePoint(latitude: pair.0.latitude, longitude: pair.0.longitude, seconds: nil, altitude: nil, segment: pair.0.segment)
                let b = WorkoutSharedDetailInput.RoutePoint(latitude: pair.1.latitude, longitude: pair.1.longitude, seconds: nil, altitude: nil, segment: pair.1.segment)
                return sum + WorkoutSharedDetailInput.distance(a, b)
            }
            route = WorkoutRoute(id: expectedPostID, workoutId: expectedPostID, source: .unknown,
                coordinates: points.map { WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, segmentIndex: $0.segment) },
                totalDistanceMeters: distance, createdAt: date, privacyMaskApplied: true)
        }
        return FeedLinkedCardPresentation(title: title ?? "", caption: caption,
            device: deviceName, location: locationName, route: route)
    }

    private static func validISO8601(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
}
