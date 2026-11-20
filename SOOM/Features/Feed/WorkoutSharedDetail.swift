import Foundation
import Supabase
import SwiftData

/// Versioned, single-workout measurements only. No AI, recovery, history,
/// user identifiers, device payloads, coaching text or original timestamps.
struct WorkoutSharedDetailInput: Codable, Equatable {
    var version = 1
    var durationSeconds: Double
    /// Stored server result only. Older payloads have no marker and remain 200m.
    var routePrivacyRadiusMeters: Int? = nil
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
            input.samples = sharedPointSamples(workout: workout, telemetry: telemetry, duration: duration)
        }
        return input
    }
    static func sharedPointSamples(workout: UnifiedWorkout, telemetry: WorkoutTelemetry, duration: Double) -> [Sample] {
        guard telemetry.workoutID == workout.id else { return [] }
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
        if sorted.count <= 4096 { return sorted }
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
            return chosen.sorted().map { sorted[$0] }
        }
    }

    static func validPoint(_ sample: Sample, duration: Double) -> Bool {
        sample.seconds.isFinite && (0...duration).contains(sample.seconds)
            && valid(sample.distanceMeters,0...10_000_000) == sample.distanceMeters
            && valid(sample.heartRateBPM,1...300) == sample.heartRateBPM
            && valid(sample.cadencePerMinute,0...400) == sample.cadencePerMinute
            && valid(sample.powerWatts,0...5000) == sample.powerWatts
            && valid(sample.speedMetersPerSecond,0...150) == sample.speedMetersPerSecond
            && valid(sample.elevationMeters,-1000...12000) == sample.elevationMeters
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
    /// Loopback fixture preview matches the language-neutral server sanitizer:
    /// exact original endpoints, 20cm coordinate and 2m segment margins,
    /// preserved breaks, and no added chords at dateline or near a pole.
    func maskedFor50mPreview() -> Self {
        var masked = self
        masked.routePrivacyRadiusMeters = 50
        masked.route = []
        guard let first = route.first, let last = route.last, route.count > 1,
              abs(first.latitude) < 85, abs(last.latitude) < 85 else { return masked }
        var previous: RoutePoint?, segment = -1
        for var point in route {
            guard Self.distance(first, point) >= 50.2, Self.distance(last, point) >= 50.2 else {
                previous = nil; continue
            }
            if previous == nil || previous?.segment != point.segment
                || (previous.map { Self.distance($0, point) > 1000
                    || abs($0.longitude - point.longitude) > 180
                    || !Self.edgeClear($0, point, origin: first, minimumDistance: 52)
                    || !Self.edgeClear($0, point, origin: last, minimumDistance: 52) } ?? false) {
                segment += 1
            }
            previous = point
            point.segment = segment
            masked.route.append(point)
        }
        let groups = Dictionary(grouping: masked.route, by: \.segment)
        masked.route = masked.route.filter { (groups[$0.segment]?.count ?? 0) > 1 }
        return masked
    }

    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dlat = lat2 - lat1, dlon = (b.longitude - a.longitude) * .pi / 180
        let h = min(1, max(0, pow(sin(dlat / 2),2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2),2)))
        return 6_371_000 * 2 * atan2(sqrt(h),sqrt(1-h))
    }
    static func edgeClear(_ a: RoutePoint, _ b: RoutePoint, origin: RoutePoint, minimumDistance: Double = 202) -> Bool {
        func xy(_ p: RoutePoint) -> (Double,Double) {
            var delta = p.longitude - origin.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return (delta * .pi / 180 * 6_371_000 * cos(origin.latitude * .pi / 180),
                    (p.latitude-origin.latitude) * .pi / 180 * 6_371_000)
        }
        let p = xy(a), q = xy(b), dx = q.0-p.0, dy = q.1-p.1
        let norm = dx*dx+dy*dy
        let t = norm > 0 ? min(1,max(0,-(p.0*dx+p.1*dy)/norm)) : 0
        return hypot(p.0+t*dx,p.1+t*dy) >= minimumDistance // conservative projection margin
    }
}

struct WorkoutSharedDetailSnapshot: Codable, Equatable {
    let postID: UUID
    let revision: Int64
    let payload: WorkoutSharedDetailInput
    enum CodingKeys: String, CodingKey { case postID = "post_id", revision, payload }
    func isValid(for post: FeedPostDTO) -> Bool {
        postID == post.id && revision == post.sharedDetailRevision && hasValidPayload
    }

    var hasValidPayload: Bool {
        guard revision > 0, payload.version == 1, payload.durationSeconds.isFinite,
              (0...604_800).contains(payload.durationSeconds), payload.route.count <= 4096,
              payload.samples.count <= 4096, (payload.routePrivacyRadiusMeters.map { [50, 200].contains($0) } ?? true),
              WorkoutSharedDetailInput.valid(payload.distanceMeters,0...10_000_000) == payload.distanceMeters else { return false }
        return payload.route.allSatisfy { point in
            point.latitude.isFinite && point.longitude.isFinite && (-90...90).contains(point.latitude)
                && (-180...180).contains(point.longitude) && point.segment >= 0
                && (point.seconds.map { $0.isFinite && (0...payload.durationSeconds).contains($0) } ?? true)
                && (point.altitude.map { $0.isFinite && (-1000...12000).contains($0) } ?? true)
        } && payload.samples.allSatisfy { WorkoutSharedDetailInput.validPoint($0, duration: payload.durationSeconds) }
    }
    func route(start: Date) -> WorkoutRoute? {
        guard payload.route.count > 1 else { return nil }
        let coords = payload.route.map { WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude,
            altitude: $0.altitude, timestamp: $0.seconds.map { start.addingTimeInterval($0) }, segmentIndex: $0.segment) }
        let distance = zip(payload.route,payload.route.dropFirst()).reduce(0.0) {
            $0 + ($1.0.segment == $1.1.segment ? WorkoutSharedDetailInput.distance($1.0,$1.1) : 0)
        }
        return WorkoutRoute(id: postID, workoutId: postID, source: .unknown, coordinates: coords, totalDistanceMeters: distance, createdAt: start, privacyMaskApplied: true,
            privacyMaskRadiusMeters: payload.routePrivacyRadiusMeters.map(Double.init), hasAuthoritativeShareMask: true)
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
    var route: WorkoutRoute? { nativeMaskedRoute ?? item.permittedSharedDetail?.route(start: item.activityDate ?? item.createdAt) }
    var telemetry: WorkoutTelemetry? {
        let start = item.activityDate ?? item.createdAt
        if let nativeTelemetry { return nativeTelemetry }
        guard let detail = item.permittedSharedDetail else { return nil }
        return detail.telemetry(start: start) ?? WorkoutTelemetry(workoutID: item.id, source: .unknown, samples: [], fetchedAt: start)
    }
    var measurementWorkout: UnifiedWorkout {
        let start = item.activityDate ?? item.createdAt
        let duration = item.permittedSharedDetail?.payload.durationSeconds ?? item.workoutDurationSeconds ?? 0
        return UnifiedWorkout(id: item.id, externalId: nil, source: .unknown, workoutType: item.recordWorkoutType,
            startDate: start, endDate: start.addingTimeInterval(max(duration, nativeTimelineElapsed ?? duration)), durationSeconds: duration,
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

/// Owner-authored share supplement candidate. Payload never includes personal
/// thresholds, exact timestamps, location, device data or private analytics.
/// Separate notice acknowledgement is required even when v1 measurement
/// sharing is already available.
struct NativeWorkoutSharedAggregateInput: Codable, Equatable {
    struct Lap: Codable, Equatable {
        let offsetSeconds: Int
        let endOffsetSeconds: Int
        let distanceMeters: Int?
    }
    struct MeasuredInterval: Codable, Equatable {
        let kind: WorkoutTelemetryInterval.Kind
        let offsetSeconds: Double
        let endOffsetSeconds: Double
        let value: Double

        func isValid(elapsed: Double) -> Bool {
            let bounds: ClosedRange<Double>
            switch kind {
            case .distanceMeters: bounds = 0...10_000_000
            case .steps, .swimStrokeCount: bounds = 0...1_000_000
            case .energyKcal: bounds = 0...40_000
            case .elevationGainMeters: bounds = -20_000...20_000
            case .activeZoneMinutes: return false
            }
            return offsetSeconds.isFinite && endOffsetSeconds.isFinite && value.isFinite
                && offsetSeconds >= 0 && endOffsetSeconds > offsetSeconds
                && endOffsetSeconds <= elapsed && bounds.contains(value)
        }
    }
    struct Timeline: Codable, Equatable {
        struct Pause: Codable, Equatable {
            let start: Double
            let end: Double
        }
        let endOffsetSeconds: Double
        let samples: [WorkoutSharedDetailInput.Sample]
        let pauses: [Pause]

        func isValid(active: Double) -> Bool {
            guard endOffsetSeconds.isFinite, endOffsetSeconds > active, endOffsetSeconds <= 604_800,
                  samples.count <= 4096, pauses.count <= 128,
                  samples.allSatisfy({ WorkoutSharedDetailInput.validPoint($0, duration: endOffsetSeconds) }),
                  zip(samples, samples.dropFirst()).allSatisfy({ $0.seconds < $1.seconds }) else { return false }
            var previous = 0.0
            for pause in pauses {
                guard pause.start.isFinite && pause.end.isFinite && pause.start >= previous
                    && pause.end > pause.start && pause.end <= endOffsetSeconds else { return false }
                previous = pause.end
            }
            return true
        }
    }

    static let legacyNoticeVersion = "shared-workout-laps-zones-v1"
    static let intervalNoticeVersion = "shared-workout-laps-zones-intervals-v2"
    static let noticeVersion = "shared-workout-charts-elapsed-v3"
    let lapIntervals: [Lap]
    let zoneSeconds: [Int]?
    let measuredIntervals: [MeasuredInterval]?
    let elapsedTimeline: Timeline?

    func isValid(elapsed active: Double) -> Bool {
        guard active.isFinite, (1...604_800).contains(active),
              elapsedTimeline.map({ $0.isValid(active: active) }) ?? true else { return false }
        let elapsed = elapsedTimeline?.endOffsetSeconds ?? active
        guard elapsed.isFinite, (1...604_800).contains(elapsed), lapIntervals.count <= 512 else { return false }
        var previous = 0
        for lap in lapIntervals {
            guard lap.offsetSeconds >= previous, lap.endOffsetSeconds > lap.offsetSeconds,
                  lap.endOffsetSeconds <= Int(elapsed),
                  lap.distanceMeters.map({ (0...10_000_000).contains($0) }) ?? true else { return false }
            previous = lap.endOffsetSeconds
        }
        if let measuredIntervals {
            guard measuredIntervals.count <= 512 else { return false }
            var last: [WorkoutTelemetryInterval.Kind: Double] = [:]
            for interval in measuredIntervals {
                guard interval.isValid(elapsed: elapsed), interval.offsetSeconds >= (last[interval.kind] ?? 0) else { return false }
                last[interval.kind] = interval.endOffsetSeconds
            }
        }
        guard let zoneSeconds else { return !lapIntervals.isEmpty || !(measuredIntervals?.isEmpty ?? true) || !(elapsedTimeline?.samples.isEmpty ?? true) }
        guard zoneSeconds.count == 5, zoneSeconds.allSatisfy({ (0...Int(elapsed)).contains($0) }) else { return false }
        return (1...Int(elapsed)).contains(zoneSeconds.reduce(0, +))
    }

    static func build(workout: UnifiedWorkout, telemetry: WorkoutTelemetry,
                      explicitAcknowledgement: String?) -> Self? {
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard [noticeVersion, intervalNoticeVersion, legacyNoticeVersion].contains(explicitAcknowledgement ?? ""),
              telemetry.workoutID == workout.id,
              elapsed.isFinite, (1...604_800).contains(elapsed) else { return nil }
        let validated = telemetry.validated(for: workout).coalescingSamples()
        var previousEnd = 0
        var laps: [Lap] = []
        for lap in validated.splits.sorted(by: { $0.startDate < $1.startDate }) {
            switch lap.provenance {
            case .healthKitLapEvent, .healthKitSegmentEvent, .tcxLapElement: break
            default: continue
            }
            let start = lap.startDate.timeIntervalSince(workout.startDate)
            let end = lap.endDate.timeIntervalSince(workout.startDate)
            guard start.isFinite, end.isFinite, start >= 0, start < end, end <= elapsed else { continue }
            let startSeconds = Int(start.rounded(.up)), endSeconds = Int(end.rounded(.down))
            guard startSeconds >= previousEnd, endSeconds > startSeconds else { continue }
            previousEnd = endSeconds
            laps.append(.init(offsetSeconds: startSeconds, endOffsetSeconds: endSeconds,
                distanceMeters: WorkoutSharedDetailInput.valid(lap.distanceMeters, 0...10_000_000).map { Int($0.rounded()) }))
            if laps.count == 512 { break }
        }
        let provider = validated.heartRateZones
        let computed: [WorkoutTelemetryZone]
        if provider.isEmpty, let maximum = telemetry.recordedHeartRateZoneBasis?.maximum(for: workout) {
            computed = WorkoutTelemetryChartBuilder.heartRateZones(telemetry, workout: workout, maximumHeartRate: maximum)
        } else { computed = provider }
        var mapped: [Int: Int] = [:], invalidZones = false
        for zone in computed {
            guard let index = WorkoutHeartRateZoneDisplay.index(for: zone.name), (1...5).contains(index),
                  mapped[index] == nil, zone.durationSeconds.isFinite,
                  (0...elapsed).contains(zone.durationSeconds)
            else { invalidZones = true; break }
            mapped[index] = Int(zone.durationSeconds.rounded(.down))
        }
        let zones = (1...5).compactMap { mapped[$0] }
        let hasValidZones = !invalidZones && zones.count == 5 && (1...Int(elapsed)).contains(zones.reduce(0, +))
        var measurements: [MeasuredInterval] = []
        if explicitAcknowledgement != legacyNoticeVersion {
            // Preserve duration and raw count together; the viewer computes
            // labelled measured averages, never from session-level totals.
            var last: [WorkoutTelemetryInterval.Kind: Double] = [:]
            for interval in validated.intervals.sorted(by: { $0.startDate < $1.startDate }) {
                let measurement = MeasuredInterval(kind: interval.kind,
                    offsetSeconds: interval.startDate.timeIntervalSince(workout.startDate),
                    endOffsetSeconds: interval.endDate.timeIntervalSince(workout.startDate), value: interval.value)
                guard measurement.isValid(elapsed: elapsed), measurement.offsetSeconds >= (last[interval.kind] ?? 0) else { continue }
                last[interval.kind] = measurement.endOffsetSeconds
                measurements.append(measurement)
                if measurements.count == 512 { break }
            }
        }
        var timeline: Timeline?
        if explicitAcknowledgement == noticeVersion, workout.durationSeconds.isFinite,
           workout.durationSeconds >= 1, elapsed > workout.durationSeconds {
            let pauses: [Timeline.Pause] = WorkoutTelemetryChartBuilder.recordedPauses(validated.events).compactMap {
                let start = $0.start.timeIntervalSince(workout.startDate)
                let end = $0.end.timeIntervalSince(workout.startDate)
                guard start.isFinite, end.isFinite, start >= 0, end > start, end <= elapsed else { return nil }
                return .init(start: start, end: end)
            }.prefix(128).map { $0 }
            let all = WorkoutSharedDetailInput.sharedPointSamples(workout: workout, telemetry: validated, duration: elapsed)
            timeline = .init(endOffsetSeconds: elapsed, samples: all, pauses: pauses)
        }
        guard !laps.isEmpty || hasValidZones || !measurements.isEmpty || !(timeline?.samples.isEmpty ?? true) else { return nil }
        return .init(lapIntervals: laps, zoneSeconds: hasValidZones ? zones : nil,
            measuredIntervals: measurements.isEmpty ? nil : measurements, elapsedTimeline: timeline)
    }
}

/// Writer usable only by the explicit, per-workout owner review. Never attached
/// to automatic health import or an account/profile visibility toggle.
@MainActor
enum NativeWorkoutAggregateService {
    struct Acknowledgement {
        let ownerID: UUID
        let cardID: UUID
        let cardRevision: Int64
        let detailRevision: Int64
        let measurementRevision: Int64
        let acceptedNoticeVersion: String
    }
    private struct Params: Encodable {
        let p_card_id: UUID
        let p_source_workout_id: UUID
        let p_expected_card_revision: Int64
        let p_expected_detail_revision: Int64
        let p_expected_measurement_revision: Int64
        let p_notice_version: String
        let p_acknowledged: Bool
        let p_input: NativeWorkoutSharedAggregateInput
    }

    static func upload(workout: UnifiedWorkout, telemetry: WorkoutTelemetry,
                       acknowledgement: Acknowledgement,
                       isCurrent: @MainActor () -> Bool) async throws -> Bool {
        let environment = AuthEnvironmentLoader().load()
        guard NativeSharedWorkoutRuntime.current(environment: environment).allowsOwnerReview,
              isCurrent(), !Task.isCancelled,
              acknowledgement.cardRevision > 0, acknowledgement.detailRevision > 0, acknowledgement.measurementRevision > 0,
              let client = SupabaseClientProvider(environment: environment).makeClient(),
              client.auth.currentSession?.user.id == acknowledgement.ownerID,
              let input = NativeWorkoutSharedAggregateInput.build(workout: workout, telemetry: telemetry,
                explicitAcknowledgement: acknowledgement.acceptedNoticeVersion) else { return false }
        let result: Bool = try await client.rpc("soom_put_native_workout_aggregates_v1", params: Params(
            p_card_id: acknowledgement.cardID, p_source_workout_id: workout.id, p_expected_card_revision: acknowledgement.cardRevision,
            p_expected_detail_revision: acknowledgement.detailRevision,
            p_expected_measurement_revision: acknowledgement.measurementRevision,
            p_notice_version: acknowledgement.acceptedNoticeVersion, p_acknowledged: true, p_input: input)).execute().value
        return isCurrent() && !Task.isCancelled && client.auth.currentSession?.user.id == acknowledgement.ownerID && result
    }
}

/// Separately gated new-route writer. No import/backfill caller. The route is
/// owner-local, and only the reviewed server can apply the source-bound mask.
@MainActor
enum NativeRoute50Upload {
    static let notice = "share-both-endpoints-50m-v2"

    // An owner-confirmed loopback test is the only allowed path that can send
    // original coordinates. No build with Release compilation can enable it.
    static var rawFixtureEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        let env = AuthEnvironmentLoader().load()
        let runtime = NativeSharedWorkoutRuntime.current(environment: env)
        return runtime.target == .localQA && runtime.allows50mRoutes
            && ProcessInfo.processInfo.environment["SOOM_ALLOW_RAW_ROUTE_LOOPBACK_FIXTURE"] == "1"
        #else
        return false
        #endif
    }

    static func maskedPreview(workout: UnifiedWorkout, route: WorkoutRoute) -> WorkoutSharedDetailInput {
        WorkoutSharedDetailInput.build(workout: workout, route: route, telemetry: nil).maskedFor50mPreview()
    }

    struct Params: Encodable {
        let p_post_id: UUID
        let p_source_workout_id: UUID
        let p_expected_revision: Int64
        let p_expected_consent_revision: Int64
        let p_notice_version: String
        let p_acknowledged: Bool
        let p_input: WorkoutSharedDetailInput
    }

    static func upload(workout: UnifiedWorkout, route: WorkoutRoute, ownerID: UUID, postID: UUID,
                       expectedRevision: Int64, consentRevision: Int64, acceptedNotice: String?,
                       isCurrent: @MainActor () -> Bool) async throws -> Bool {
        let environment = AuthEnvironmentLoader().load()
        guard rawFixtureEnabled,
              acceptedNotice == notice, route.workoutId == workout.id,
              expectedRevision >= 0, consentRevision > 0, !route.privacyMaskApplied,
              route.coordinates.count >= 2,
              route.coordinates.allSatisfy({
                  $0.latitude.isFinite && $0.longitude.isFinite
                  && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
              }),
              let client = SupabaseClientProvider(environment: environment).makeClient(),
              client.auth.currentSession?.user.id == ownerID, isCurrent(), !Task.isCancelled
        else { return false }
        let input = WorkoutSharedDetailInput.build(workout: workout, route: route, telemetry: nil)
        let saved: [WorkoutSharedDetailSnapshot] = try await client.rpc("soom_put_new_shared_route_50_v2",
            params: Params(p_post_id: postID, p_source_workout_id: workout.id,
                p_expected_revision: expectedRevision, p_expected_consent_revision: consentRevision,
                p_notice_version: notice, p_acknowledged: true, p_input: input)).execute().value
        return isCurrent() && !Task.isCancelled && client.auth.currentSession?.user.id == ownerID
            && saved.count == 1 && saved.first?.postID == postID && saved.first?.payload.routePrivacyRadiusMeters == 50
            && saved.first?.payload.route == input.maskedFor50mPreview().route
    }
}

extension NativeWorkoutAggregateService {
    struct Review: Decodable {
        let ownerID: UUID
        let cardID: UUID
        let sourceID: UUID
        let cardRevision: Int64
        let detailRevision: Int64?
        let measurementRevision: Int64?
        let canApply: Bool?
        let hasSavedSupplement: Bool
        enum CodingKeys: String, CodingKey {
            case ownerID = "owner_id", cardID = "card_id", sourceID = "source_id"
            case cardRevision = "card_revision", detailRevision = "detail_revision"
            case measurementRevision = "measurement_revision", canApply = "can_apply"
            case hasSavedSupplement = "has_saved_supplement"
        }

        func acknowledgement(affirmed: Bool) -> Acknowledgement? {
            guard affirmed, canApply == true, cardRevision > 0,
                  let detailRevision, detailRevision > 0, let measurementRevision, measurementRevision > 0 else { return nil }
            return .init(ownerID: ownerID, cardID: cardID, cardRevision: cardRevision,
                detailRevision: detailRevision, measurementRevision: measurementRevision,
                acceptedNoticeVersion: NativeWorkoutSharedAggregateInput.noticeVersion)
        }
    }

    static var reviewEnabled: Bool { NativeSharedWorkoutRuntime.current().allowsOwnerReview }

    static func review(sourceID: UUID, ownerID: UUID, isCurrent: @MainActor () -> Bool) async throws -> Review? {
        struct Params: Encodable { let p_source_workout_id: UUID }
        guard reviewEnabled, isCurrent(), !Task.isCancelled,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == ownerID else { return nil }
        let result: Review? = try await client.rpc("soom_review_native_workout_measurements_v1", params: Params(p_source_workout_id: sourceID)).execute().value
        guard isCurrent(), !Task.isCancelled, client.auth.currentSession?.user.id == ownerID,
              result?.ownerID == ownerID, result?.sourceID == sourceID else { return nil }
        return result
    }

    static func withdraw(review: Review, isCurrent: @MainActor () -> Bool) async throws -> Bool {
        struct Params: Encodable { let p_card_id: UUID }
        guard reviewEnabled, isCurrent(), !Task.isCancelled,
              let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
              client.auth.currentSession?.user.id == review.ownerID else { return false }
        let withdrawn: Bool = try await client.rpc("soom_withdraw_native_workout_aggregates_v1", params: Params(p_card_id: review.cardID)).execute().value
        return isCurrent() && !Task.isCancelled && client.auth.currentSession?.user.id == review.ownerID && withdrawn
    }
}

/// The signed app is OFF by default. A server response cannot activate a
/// client built without separate review, and no fallback can switch projects.
struct NativeSharedWorkoutRuntime: Equatable {
    enum Target: Equatable { case disabled, localQA, verifiedRelease }
    let target: Target
    let allowsOwnerReview: Bool
    let allows50mRoutes: Bool
    var allowsViewer: Bool { target != .disabled }

    static let disabled = Self(target: .disabled, allowsOwnerReview: false, allows50mRoutes: false)

    static func verifiedRelease(environment: AuthEnvironment, releaseCodeCompiled: Bool,
                                appExplicitlyEnabled: Bool, pinnedHost: String?,
                                ownerReviewEnabled: Bool, routes50Enabled: Bool) -> Self {
        guard releaseCodeCompiled, appExplicitlyEnabled, environment.environment == .production,
              environment.isSupabaseConfigured, let url = environment.supabaseURL,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), let pinnedHost = pinnedHost?.lowercased(),
              !host.isEmpty, host == pinnedHost, host.hasSuffix(".supabase.co"),
              parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/"
        else { return .disabled }
        return .init(target: .verifiedRelease, allowsOwnerReview: ownerReviewEnabled,
            allows50mRoutes: routes50Enabled)
    }

    static func current(environment: AuthEnvironment = AuthEnvironmentLoader().load()) -> Self {
        #if DEBUG && targetEnvironment(simulator)
        let flags = ProcessInfo.processInfo.environment
        if flags["SOOM_NATIVE_CARD_DETAIL_LOCAL"] == "1" {
            guard let host = environment.supabaseURL?.host,
                  ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) else { return .disabled }
            return .init(target: .localQA, allowsOwnerReview: flags["SOOM_NATIVE_MEASUREMENTS_REVIEW_LOCAL"] == "1",
                         allows50mRoutes: flags["SOOM_NATIVE_ROUTE_50_LOCAL"] == "1")
        }
        #endif
        #if SOOM_NATIVE_SHARED_DETAIL_RELEASE_CAPABLE
        let bundle = Bundle.main
        func enabled(_ key: String) -> Bool {
            (bundle.object(forInfoDictionaryKey: key) as? String) == "YES"
        }
        return verifiedRelease(environment: environment, releaseCodeCompiled: true,
            appExplicitlyEnabled: enabled("SOOMNativeSharedDetailClientEnabled"),
            pinnedHost: bundle.object(forInfoDictionaryKey: "SOOMNativeSharedDetailProjectHost") as? String,
            ownerReviewEnabled: enabled("SOOMNativeMeasurementReviewClientEnabled"),
            routes50Enabled: enabled("SOOMNativeRoute50ClientEnabled"))
        #else
        return .disabled
        #endif
    }

    struct Capabilities: Decodable {
        let version: Int
        let detail: Bool
        let charts: Bool
        let route50: Bool
    }

    @MainActor
    func loadCapabilities(client: SupabaseClient, viewerID: UUID, isCurrent: @MainActor () -> Bool) async throws -> Capabilities? {
        guard allowsViewer, !Task.isCancelled, isCurrent(), client.auth.currentSession?.user.id == viewerID else { return nil }
        do {
            let grant: Capabilities = try await client.rpc("soom_native_share_capabilities_v1").execute().value
            guard grant.version == 1, !Task.isCancelled, isCurrent(),
                  client.auth.currentSession?.user.id == viewerID else { return nil }
            return grant
        } catch let error as PostgrestError where error.code == "PGRST202" { return nil }
    }
}

extension NativeRoute50Upload {
    struct Review: Decodable {
        let ownerID: UUID
        let postID: UUID
        let sourceID: UUID
        let expectedRevision: Int64
        let consentRevision: Int64?
        let canApply: Bool
        let hasSavedRoute: Bool
        enum CodingKeys: String, CodingKey {
            case ownerID = "owner_id", postID = "post_id", sourceID = "source_id"
            case expectedRevision = "expected_revision", consentRevision = "consent_revision"
            case canApply = "can_apply", hasSavedRoute = "has_saved_route"
        }

        func approvedConsentRevision(affirmed: Bool, sourceID: UUID, ownerID: UUID) -> Int64? {
            guard affirmed, canApply, !hasSavedRoute, expectedRevision >= 0,
                  self.sourceID == sourceID, self.ownerID == ownerID,
                  let consentRevision, consentRevision > 0 else { return nil }
            return consentRevision
        }
    }

    static func review(sourceID: UUID, ownerID: UUID, isCurrent: @MainActor () -> Bool) async throws -> Review? {
        struct Params: Encodable { let p_source_workout_id: UUID }
        let environment = AuthEnvironmentLoader().load()
        guard rawFixtureEnabled,
              isCurrent(), !Task.isCancelled,
              let client = SupabaseClientProvider(environment: environment).makeClient(),
              client.auth.currentSession?.user.id == ownerID else { return nil }
        let reply: Review? = try await client.rpc("soom_review_new_shared_route_50_v2",
            params: Params(p_source_workout_id: sourceID)).execute().value
        guard isCurrent(), !Task.isCancelled, client.auth.currentSession?.user.id == ownerID,
              reply?.ownerID == ownerID, reply?.sourceID == sourceID else { return nil }
        return reply
    }

    static func withdraw(review: Review, isCurrent: @MainActor () -> Bool) async throws -> Bool {
        struct Params: Encodable { let p_post_id: UUID }
        let environment = AuthEnvironmentLoader().load()
        guard rawFixtureEnabled,
              review.hasSavedRoute, isCurrent(), !Task.isCancelled,
              let client = SupabaseClientProvider(environment: environment).makeClient(),
              client.auth.currentSession?.user.id == review.ownerID else { return false }
        let result: Bool = try await client.rpc("soom_withdraw_new_shared_route_50_v2",
            params: Params(p_post_id: review.postID)).execute().value
        return isCurrent() && !Task.isCancelled && client.auth.currentSession?.user.id == review.ownerID && result
    }
}

/// Modern native projection does not manufacture a legacy post ID.
struct ModernSourceChartInput: Codable, Equatable {
    let elapsedSeconds: Double
    let samples: [WorkoutSharedDetailInput.Sample]
    let pauses: [NativeWorkoutSharedAggregateInput.Timeline.Pause]
    let supplement: NativeWorkoutSharedAggregateInput?

    static func build(workout: UnifiedWorkout, telemetry: WorkoutTelemetry) -> Self? {
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard telemetry.workoutID == workout.id, workout.durationSeconds.isFinite, elapsed.isFinite,
              (1...604_800).contains(workout.durationSeconds),
              (workout.durationSeconds...604_800).contains(elapsed) else { return nil }
        let sanitized = telemetry.validated(for: workout)
        let points = WorkoutSharedDetailInput.sharedPointSamples(workout: workout, telemetry: sanitized, duration: elapsed)
        let full = NativeWorkoutSharedAggregateInput.build(workout: workout, telemetry: telemetry,
            explicitAcknowledgement: NativeWorkoutSharedAggregateInput.noticeVersion)
        let supplemental = full.flatMap { value -> NativeWorkoutSharedAggregateInput? in
            let result = NativeWorkoutSharedAggregateInput(lapIntervals: value.lapIntervals, zoneSeconds: value.zoneSeconds,
                measuredIntervals: value.measuredIntervals, elapsedTimeline: nil)
            return result.isValid(elapsed: elapsed) ? result : nil
        }
        let value = Self(elapsedSeconds: elapsed, samples: points, pauses: full?.elapsedTimeline?.pauses ?? [], supplement: supplemental)
        return value.valid(active: workout.durationSeconds) ? value : nil
    }

    func valid(active: Double) -> Bool {
        guard active.isFinite, (1...604_800).contains(active), elapsedSeconds.isFinite,
              (active...604_800).contains(elapsedSeconds), samples.count <= 4096, pauses.count <= 128,
              !samples.isEmpty || supplement != nil,
              supplement.map({ $0.elapsedTimeline == nil && $0.isValid(elapsed: elapsedSeconds) }) ?? true
        else { return false }
        if elapsedSeconds > active {
            return NativeWorkoutSharedAggregateInput.Timeline(endOffsetSeconds: elapsedSeconds, samples: samples,
                pauses: pauses).isValid(active: active)
        }
        return pauses.isEmpty && samples.allSatisfy { WorkoutSharedDetailInput.validPoint($0, duration: elapsedSeconds) }
            && zip(samples, samples.dropFirst()).allSatisfy { $0.seconds < $1.seconds }
    }

    func render(cardID: UUID, start: Date) -> WorkoutTelemetry {
        .init(workoutID: cardID, source: .unknown,
            samples: samples.map {
                .init(timestamp: start.addingTimeInterval($0.seconds), distanceMeters: $0.distanceMeters,
                    heartRateBPM: $0.heartRateBPM, cadencePerMinute: $0.cadencePerMinute, powerWatts: $0.powerWatts,
                    speedMetersPerSecond: $0.speedMetersPerSecond, elevationMeters: $0.elevationMeters,
                    cadenceUnit: $0.cadenceUnit, source: .unknown)
            },
            intervals: (supplement?.measuredIntervals ?? []).map {
                .init(kind: $0.kind, startDate: start.addingTimeInterval($0.offsetSeconds),
                    endDate: start.addingTimeInterval($0.endOffsetSeconds), value: $0.value)
            },
            splits: (supplement?.lapIntervals ?? []).enumerated().map { i, lap in
                .init(label: "랩 \(i + 1)", startDate: start.addingTimeInterval(Double(lap.offsetSeconds)),
                    endDate: start.addingTimeInterval(Double(lap.endOffsetSeconds)), durationSeconds: Double(lap.endOffsetSeconds-lap.offsetSeconds),
                    distanceMeters: lap.distanceMeters.map(Double.init))
            },
            heartRateZones: (supplement?.zoneSeconds ?? []).enumerated().map {
                .init(name: "Z\($0.offset+1)", durationSeconds: Double($0.element))
            }, fetchedAt: start,
            events: pauses.flatMap {
                [.init(timestamp: start.addingTimeInterval($0.start), type: "pause"),
                 .init(timestamp: start.addingTimeInterval($0.end), type: $0.end == elapsedSeconds ? "stop" : "resume")]
            })
    }
}

/// Independent modern native chart lane. No URL override from runtime input.
struct ModernChartRuntime: Equatable {
    enum Target: Equatable { case disabled, localQA, verifiedRelease }
    let target: Target
    let ownerReviewEnabled: Bool
    var viewerEnabled: Bool { target != .disabled }
    static let disabled = Self(target: .disabled, ownerReviewEnabled: false)

    static func verifiedRelease(environment: AuthEnvironment, compiled: Bool, signedAppOptIn: Bool,
        exactPinnedHost: String?, ownerReview: Bool) -> Self {
        let decision = NativeSharedWorkoutRuntime.verifiedRelease(environment: environment,
            releaseCodeCompiled: compiled, appExplicitlyEnabled: signedAppOptIn, pinnedHost: exactPinnedHost,
            ownerReviewEnabled: ownerReview, routes50Enabled: false)
        guard decision.target == .verifiedRelease else { return .disabled }
        return .init(target: .verifiedRelease, ownerReviewEnabled: decision.allowsOwnerReview)
    }

    static func current(environment: AuthEnvironment = AuthEnvironmentLoader().load()) -> Self {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["SOOM_MODERN_CHART_LOCAL"] == "1" {
            guard NativeSharedWorkoutRuntime.current(environment: environment).target == .localQA else { return .disabled }
            return .init(target: .localQA, ownerReviewEnabled: true)
        }
        #endif
        #if SOOM_MODERN_CHART_RELEASE_CAPABLE
        let bundle = Bundle.main
        return verifiedRelease(environment: environment, compiled: true,
            signedAppOptIn: (bundle.object(forInfoDictionaryKey: "SOOMModernChartClientEnabled") as? String) == "YES",
            exactPinnedHost: bundle.object(forInfoDictionaryKey: "SOOMModernChartProjectHost") as? String,
            ownerReview: (bundle.object(forInfoDictionaryKey: "SOOMModernChartOwnerReviewEnabled") as? String) == "YES")
        #else
        return .disabled
        #endif
    }
}

@MainActor
struct ModernSourceChartAdapter {
    struct Review: Decodable {
        let version: Int
        let ownerID: UUID
        let sourceID: UUID
        let cardID: UUID
        let projectionRevision: Int64
        let profileRevision: Int64
        let measurementRevision: Int64
        let needsAffirmativeNotice: Bool
        let canApply: Bool
        let hasSaved: Bool
        enum CodingKeys: String, CodingKey {
            case version, ownerID = "owner_id", sourceID = "source_id", cardID = "card_id", projectionRevision = "projection_revision"
            case profileRevision = "profile_revision", measurementRevision = "measurement_revision"
            case needsAffirmativeNotice = "needs_affirmative_notice", canApply = "can_apply", hasSaved = "has_saved"
        }
    }
    struct Reply: Decodable {
        let contractVersion: Int
        let cardID: UUID
        let canonicalID: UUID
        let ownerID: UUID
        let viewerID: UUID
        let projectionRevision: Int64
        let activeSeconds: Double
        let measurements: ModernSourceChartInput
    }
    struct Write: Encodable {
        let p_card_id: UUID
        let p_source_id: UUID
        let p_projection_revision: Int64
        let p_profile_revision: Int64
        let p_measurement_revision: Int64
        let p_notice: String
        let p_acknowledged: Bool
        let p_measures: ModernSourceChartInput
    }

    let viewer: () -> UUID?
    let reviewCall: (UUID) async throws -> Review?
    let detailCall: (UUID, Int64) async throws -> Reply?
    let writeCall: (Write) async throws -> Bool
    let withdrawalCall: (UUID) async throws -> Bool
    var capabilityCall: ((UUID?, UUID?) async throws -> Capability?)? = nil

    struct Capability: Decodable {
        let version: Int
        let canView: Bool
        let canReview: Bool
        let canApply: Bool
        let canWithdraw: Bool
        enum CodingKeys: String, CodingKey {
            case version, canView = "can_view", canReview = "can_review", canApply = "can_apply", canWithdraw = "can_withdraw"
        }
    }

    static var localEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return NativeSharedWorkoutRuntime.current().target == .localQA
            && ProcessInfo.processInfo.environment["SOOM_MODERN_CHART_LOCAL"] == "1"
        #else
        return false
        #endif
    }

    /// Use only the existing signed app's authenticated registry client. A
    /// different client/URL can't borrow this project's signed configuration.
    static func active(expectedClient: SupabaseClient? = nil, ownerReview: Bool = false) -> Self? {
        let environment = AuthEnvironmentLoader().load()
        let mode = ModernChartRuntime.current(environment: environment)
        guard mode.viewerEnabled, !ownerReview || mode.ownerReviewEnabled,
              let registered = SupabaseClientProvider(environment: environment).makeClient(),
              expectedClient.map({ $0 === registered }) ?? true,
              registered.auth.currentSession != nil else { return nil }
        return rpcTransport(client: registered)
    }

    #if DEBUG && targetEnvironment(simulator)
    static func loopbackTestClient(url: URL, storage: any AuthLocalStorage) -> (SupabaseClient, Self)? {
        guard let allowedPort = ProcessInfo.processInfo.environment["SOOM_MODERN_HTTP_FIXTURE_PORT"].flatMap(Int.init),
              url.scheme == "http", url.host == "127.0.0.1", url.port == allowedPort,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty else { return nil }
        let options = SupabaseClientOptions(
            auth: .init(storage: storage, storageKey: "modern-http-" + UUID().uuidString,
                autoRefreshToken: false, emitLocalSessionAsInitialSession: true),
            global: .init(session: URLSession(configuration: .ephemeral)))
        let client = SupabaseClient(supabaseURL: url, supabaseKey: "anonymous-fixture-config", options: options)
        return (client, rpcTransport(client: client))
    }
    #endif

    private static func rpcTransport(client: SupabaseClient) -> Self {
        struct SourceParams: Encodable { let p_source_id: UUID }
        struct DetailParams: Encodable { let p_card_id: UUID; let p_projection_revision: Int64 }
        struct CardParams: Encodable { let p_card_id: UUID }
        struct CapabilityParams: Encodable { let p_card_id: UUID?; let p_source_id: UUID? }
        return .init(viewer: { client.auth.currentSession?.user.id },
            reviewCall: { id in
                do { return try await client.rpc("soom_review_modern_workout_chart_v1",
                    params: SourceParams(p_source_id: id)).execute().value }
                catch let error as PostgrestError where error.code == "PGRST202" { return nil }
            }, detailCall: { id, revision in
                do { return try await client.rpc("soom_get_modern_workout_chart_v1",
                    params: DetailParams(p_card_id: id, p_projection_revision: revision)).execute().value }
                catch let error as PostgrestError where error.code == "PGRST202" { return nil }
            }, writeCall: { try await client.rpc("soom_put_modern_workout_chart_v1",params: $0).execute().value },
            withdrawalCall: { try await client.rpc("soom_withdraw_modern_workout_chart_v1",
                params: CardParams(p_card_id: $0)).execute().value },
            capabilityCall: { card, source in
                do { return try await client.rpc("soom_modern_chart_capabilities_v1",
                    params: CapabilityParams(p_card_id: card, p_source_id: source)).execute().value }
                catch let error as PostgrestError where error.code == "PGRST202" { return nil }
            })
    }

    private func can(_ key: KeyPath<Capability, Bool>, card: UUID? = nil, source: UUID? = nil,
        actor: UUID, current: () -> Bool) async throws -> Bool {
        // Injected unit fixtures without an HTTP transport are isolated. All
        // real SDK transports above include the exact per-resource check.
        guard current(), viewer() == actor, !Task.isCancelled else { return false }
        guard let capabilityCall else { return true }
        let snapshot = try await capabilityCall(card, source)
        return current() && viewer() == actor && !Task.isCancelled && snapshot?.version == 1 && snapshot?[keyPath: key] == true
    }

    func review(source: UUID, owner: UUID, current: () -> Bool) async throws -> Review? {
        guard try await can(\.canReview, source: source, actor: owner, current: current) else { return nil }
        let reply = try await reviewCall(source)
        guard current(), viewer() == owner, !Task.isCancelled, let reply, reply.version == 1,
              reply.ownerID == owner, reply.sourceID == source, reply.needsAffirmativeNotice,
              reply.projectionRevision > 0, reply.profileRevision > 0, reply.measurementRevision > 0 else { return nil }
        return reply
    }

    func apply(workout: UnifiedWorkout, telemetry: WorkoutTelemetry, review: Review,
               affirmed: Bool, current: () -> Bool) async throws -> Bool {
        guard affirmed, review.canApply, viewer() == review.ownerID, current(), !Task.isCancelled,
              workout.id == review.sourceID, let payload = ModernSourceChartInput.build(workout: workout, telemetry: telemetry)
        else { return false }
        guard try await can(\.canApply, source: review.sourceID, actor: review.ownerID, current: current) else { return false }
        let applied = try await writeCall(.init(p_card_id: review.cardID, p_source_id: review.sourceID,
            p_projection_revision: review.projectionRevision, p_profile_revision: review.profileRevision,
            p_measurement_revision: review.measurementRevision, p_notice: "modern-workout-chart-v1",
            p_acknowledged: true, p_measures: payload))
        return current() && viewer() == review.ownerID && !Task.isCancelled && applied
    }

    func withdraw(review: Review, current: () -> Bool) async throws -> Bool {
        guard current(), viewer() == review.ownerID, !Task.isCancelled, review.hasSaved else { return false }
        guard try await can(\.canWithdraw, source: review.sourceID, actor: review.ownerID, current: current) else { return false }
        let result = try await withdrawalCall(review.cardID)
        return current() && viewer() == review.ownerID && !Task.isCancelled && result
    }

    func mayView(row: AccountActivityFeedRow, expectedViewer: UUID, current: () -> Bool) async throws -> Bool {
        try await can(\.canView, card: row.cardID, actor: expectedViewer, current: current)
    }

    func detail(row: AccountActivityFeedRow, expectedViewer: UUID, current: () -> Bool) async throws
        -> (telemetry: WorkoutTelemetry, elapsed: Double)? {
        guard current(), viewer() == expectedViewer, !Task.isCancelled, let start = row.cursor?.activityAt else { return nil }
        guard try await can(\.canView, card: row.cardID, actor: expectedViewer, current: current) else { return nil }
        let reply = try await detailCall(row.cardID, row.revision)
        guard current(), viewer() == expectedViewer, !Task.isCancelled, let reply,
              reply.contractVersion == 1, reply.cardID == row.cardID, reply.canonicalID == row.canonicalID, reply.ownerID == row.ownerID,
              reply.viewerID == expectedViewer, reply.projectionRevision == row.revision,
              reply.activeSeconds == Double(row.durationSeconds), reply.measurements.valid(active: reply.activeSeconds)
        else { return nil }
        return (reply.measurements.render(cardID: row.cardID, start: start), reply.measurements.elapsedSeconds)
    }
}

/// Read-only, short-lived addition to an already independently allowed detail.
struct HistoricalRecordedZoneOverlay {
    let rowID, ownerID: UUID
    let postID: UUID?
    let expiresAt, start: Date
    let zones: [WorkoutTelemetryZone]

    private struct Params: Encodable { let p_card_id: UUID; let p_projection_revision: Int64 }
    private struct Grant: Decodable {
        let version: Int
        let scope, pairContract, issuedAt, expiresAt, historyCutoff: String
        let cardID, canonicalID, ownerID, viewerID: UUID
        let projectionRevision, rosterRevision, policyRevision, consentRevision, measurementRevision, relationshipRevision: Int64
        let activeSeconds, elapsedSeconds: Double
        let recordedZones: [Int]
    }

    @MainActor static func fetch(client: SupabaseClient, row: AccountActivityFeedRow, viewer: UUID, postID: UUID?,
                                 current: () -> Bool) async throws -> Self? {
        guard row.readPolicy == .profileOnlyV2, row.ownerID != viewer, current(), !Task.isCancelled,
              client.auth.currentSession?.user.id == viewer else { return nil }
        let request = try client.rpc("soom_get_historical_mutual_workout_detail_v1",
            params: Params(p_card_id: row.cardID, p_projection_revision: row.revision))
        let data = try await request.setHeader(name: "Cache-Control", value: "no-cache, no-store").execute().data
        guard current(), !Task.isCancelled, client.auth.currentSession?.user.id == viewer else { return nil }
        return decode(data, row: row, viewer: viewer, postID: postID, now: Date())
    }

    static func decode(_ data: Data, row: AccountActivityFeedRow, viewer: UUID, postID: UUID?, now: Date) -> Self? {
        let required: Set<String> = ["version", "scope", "pairContract", "issuedAt", "expiresAt", "historyCutoff",
            "cardID", "canonicalID", "ownerID", "viewerID", "projectionRevision", "rosterRevision", "policyRevision",
            "consentRevision", "measurementRevision", "relationshipRevision", "activeSeconds", "elapsedSeconds",
            "recordedZones", "heartRate", "laps"]
        func parse(_ value: String) -> Date? {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = parser.date(from: value) { return date }
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: value)
        }
        guard data.count <= 65_536, row.readPolicy == .profileOnlyV2, row.ownerID != viewer,
              let wire = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? [String: Any],
              Set(wire.keys) == required, (wire["heartRate"] as? [Any])?.isEmpty == true,
              (wire["laps"] as? [Any])?.isEmpty == true,
              let g = try? JSONDecoder().decode(Grant.self, from: data),
              g.version == 1, g.scope == "historical_mutual_roster_v1", g.pairContract == "frozen_pair_r4_v1",
              g.cardID == row.cardID, g.canonicalID == row.canonicalID, g.ownerID == row.ownerID, g.viewerID == viewer,
              g.projectionRevision == row.revision, [g.projectionRevision, g.rosterRevision, g.policyRevision,
                g.consentRevision, g.measurementRevision, g.relationshipRevision].allSatisfy({ $0 > 0 }),
              let start = parse(row.activityAt), let issued = parse(g.issuedAt),
              let expires = parse(g.expiresAt), let cutoff = parse(g.historyCutoff), start < cutoff, cutoff <= issued,
              issued <= now, now.timeIntervalSince(issued) <= 10, expires > now, expires.timeIntervalSince(issued) <= 60,
              (1...604_800).contains(row.durationSeconds), g.activeSeconds == Double(row.durationSeconds),
              (g.activeSeconds...604_800).contains(g.elapsedSeconds), g.recordedZones.count == 5,
              g.recordedZones.allSatisfy({ (0...row.durationSeconds).contains($0) }),
              (1...row.durationSeconds).contains(g.recordedZones.reduce(0, +)) else { return nil }
        return .init(rowID: row.cardID, ownerID: row.ownerID, postID: postID,
            expiresAt: expires, start: start, zones: g.recordedZones.enumerated().map {
                .init(name: "Z\($0.offset + 1)", durationSeconds: Double($0.element))
            })
    }

    func applying(to base: WorkoutTelemetry?, id: UUID, authorID: UUID, now: Date = Date()) -> WorkoutTelemetry? {
        guard expiresAt > now, authorID == ownerID, id == rowID || id == postID,
              base?.heartRateZones.isEmpty ?? true else { return base }
        var result = base ?? WorkoutTelemetry(workoutID: id, source: .unknown, fetchedAt: start)
        result.heartRateZones = zones
        result.historicalFrozenOriginalZones = true
        return result
    }
}
