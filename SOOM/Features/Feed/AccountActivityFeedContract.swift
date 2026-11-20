import Foundation

/// These DTOs describe an isolated server candidate, not deployed authority.
enum AccountActivityFeedReleaseGate { static let productionReady = false }

/// Contract choice is explicit. A v1 receipt can never stand in for mutual v2.
enum AccountActivityReadPolicy: Int, Equatable {
    case approvedFollowersV1 = 1, profileOnlyV2 = 2
    var productionReady: Bool {
        self == .profileOnlyV2 ? ProfileOnlyPrivacyReleaseGate.productionReady : AccountActivityFeedReleaseGate.productionReady
    }
    static var deployed: Self { ProfileOnlyPrivacyReleaseGate.productionReady ? .profileOnlyV2 : .approvedFollowersV1 }
    var interactionsProductionReady: Bool { self == .profileOnlyV2 ? ProfileOnlyPrivacyReleaseGate.productionReady : AccountActivityInteractionReleaseGate.productionReady }
    var inboxProductionReady: Bool { self == .profileOnlyV2 ? ProfileOnlyPrivacyReleaseGate.productionReady : (AccountActivityNativeInboxGate.productionReady && productionReady && interactionsProductionReady) }
    var rankingProductionReady: Bool { self == .profileOnlyV2 ? ProfileOnlyPrivacyReleaseGate.productionReady : AccountActivityRankingReleaseGate.productionReady }
    var rankingScope: String { self == .profileOnlyV2 ? "public_profile_v2_auto" : "public_account_transitioned_auto" }
    var rankingMeasurementVerification: String { self == .profileOnlyV2 ? "profile_v2_summary_grant" : "client_attested_projection" }
    var nativeSourceKind: String { self == .profileOnlyV2 ? "activity_native_v2" : "activity_native_v1" }
    func interactionRPC(_ v1: String) -> String { self == .profileOnlyV2 ? v1.replacingOccurrences(of: "_candidate_v1", with: "_candidate_v2") : v1 }

    func pageRPC(preview: Bool) throws -> String {
        guard !preview || self == .approvedFollowersV1 else { throw AccountActivityContractError.unreleased }
        return preview ? "soom_activity_page_preview_v1" : (self == .profileOnlyV2 ? "soom_activity_page_candidate_v2" : "soom_activity_page_candidate_v1")
    }
    func cardRPC(preview: Bool) throws -> String {
        guard !preview || self == .approvedFollowersV1 else { throw AccountActivityContractError.unreleased }
        return preview ? "soom_activity_card_preview_v1" : (self == .profileOnlyV2 ? "soom_activity_card_candidate_v2" : "soom_activity_card_candidate_v1")
    }
}

enum AccountActivityContractError: Error, Equatable {
    case unreleased, invalidRequest, wrongContext, malformedPage, invalidRow, invalidOrder, invalidLegacyMapping
}

enum AccountActivityScope: String, Codable { case home, profile }

struct AccountActivityCursor: Equatable {
    let activityAt: Date
    let cardID: UUID
}

struct AccountActivityPageRequest {
    let viewerID: UUID
    let scope: AccountActivityScope
    let ownerID: UUID?
    let before: AccountActivityCursor?
    let limit: Int

    func validate() throws {
        guard (1...100).contains(limit),
              (scope == .home ? ownerID == nil : ownerID != nil),
              before?.activityAt.timeIntervalSince1970.isFinite != false else {
            throw AccountActivityContractError.invalidRequest
        }
    }
}

struct AccountActivityFeedRow: Decodable, Equatable {
    let cardID: UUID
    let canonicalID: UUID
    let ownerID: UUID
    let sport: String
    let activityAt: String
    let durationSeconds: Int
    let distanceMeters: Double?
    let revision: Int64
    // Client provenance, set only after validating the envelope version. Not a
    // server row field and never inferred from a legacy visibility value.
    var readPolicy: AccountActivityReadPolicy = .approvedFollowersV1

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id", canonicalID = "canonical_id", ownerID = "owner_id"
        case sport, activityAt = "activity_at", durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters", revision
    }

    var cursor: AccountActivityCursor? {
        AccountActivityContractDate.parse(activityAt).map { AccountActivityCursor(activityAt: $0, cardID: cardID) }
    }
}

struct AccountActivityFeedPage: Decodable {
    let version: Int
    let rows: [AccountActivityFeedRow]
    let releaseReady: Bool
    let scope: AccountActivityScope
    let viewerID: UUID

    enum CodingKeys: String, CodingKey {
        case version, rows, scope, releaseReady = "release_ready", viewerID = "viewer_id"
    }

    /// Structural validation for local candidate tests. This does NOT authorize
    /// display or replace RLS. Pass current approved owner IDs for home scope;
    /// absence is not inferred from cached follows/pending requests.
    func validateCandidate(request: AccountActivityPageRequest, currentViewerID: UUID?,
                           allowedHomeOwners: Set<UUID>, latestPermittedDate: Date,
                           seenCardIDs: Set<UUID> = [], seenOwnerCanonicalKeys: Set<String> = [],
                           expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws {
        try request.validate()
        guard currentViewerID == request.viewerID, viewerID == request.viewerID,
              scope == request.scope else { throw AccountActivityContractError.wrongContext }
        guard version == expectedPolicy.rawValue, rows.count <= request.limit, latestPermittedDate.timeIntervalSince1970.isFinite else {
            throw AccountActivityContractError.malformedPage
        }
        var cards = seenCardIDs
        var identities = seenOwnerCanonicalKeys
        var previous = request.before
        for row in rows {
            guard ["running", "cycling", "walking", "swimming", "hiking", "strength", "yoga", "other"].contains(row.sport), row.revision > 0,
                  (0...604800).contains(row.durationSeconds), row.distanceMeters.map({ $0.isFinite && (0...10_000_000).contains($0) }) ?? true, let cursor = row.cursor,
                  cursor.activityAt <= latestPermittedDate,
                  cards.insert(row.cardID).inserted,
                  identities.insert(Self.identityKey(ownerID: row.ownerID, canonicalID: row.canonicalID)).inserted else {
                throw AccountActivityContractError.invalidRow
            }
            if request.scope == .profile {
                guard row.ownerID == request.ownerID else { throw AccountActivityContractError.wrongContext }
            } else {
                guard row.ownerID == request.viewerID || allowedHomeOwners.contains(row.ownerID) else {
                    throw AccountActivityContractError.wrongContext
                }
            }
            if let previous {
                guard Self.isStrictlyBefore(cursor, previous) else { throw AccountActivityContractError.invalidOrder }
            }
            previous = cursor
        }
    }

    func validateForProduction(request: AccountActivityPageRequest, currentViewerID: UUID?,
                               allowedHomeOwners: Set<UUID>, latestPermittedDate: Date,
                               expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws {
        guard expectedPolicy.productionReady, releaseReady else {
            throw AccountActivityContractError.unreleased
        }
        try validateCandidate(request: request, currentViewerID: currentViewerID,
                              allowedHomeOwners: allowedHomeOwners, latestPermittedDate: latestPermittedDate, expectedPolicy: expectedPolicy)
    }

    /// A full page may have more rows. The contract does not promise has_more.
    var nextCursor: AccountActivityCursor? { rows.last?.cursor }
    static func identityKey(ownerID: UUID, canonicalID: UUID) -> String {
        ownerID.uuidString.lowercased() + ":" + canonicalID.uuidString.lowercased()
    }
    private static func isStrictlyBefore(_ a: AccountActivityCursor, _ b: AccountActivityCursor) -> Bool {
        a.activityAt == b.activityAt ? a.cardID.uuidString.lowercased() < b.cardID.uuidString.lowercased() : a.activityAt < b.activityAt
    }
}

/// Permission-rechecked single-card response. A nil row means unavailable;
/// it does not authorize fallback to a cached legacy card or local sample.
struct AccountActivityCardEnvelope: Decodable {
    let version: Int
    let viewerID: UUID
    let row: AccountActivityFeedRow?
    let releaseReady: Bool
    enum CodingKeys: String, CodingKey {
        case version, viewerID = "viewer_id", row, releaseReady = "release_ready"
    }

    func validateCandidate(expectedCardID: UUID, requestViewerID: UUID,
                           currentViewerID: UUID?, requestGeneration: Int,
                           currentGeneration: Int, latestPermittedDate: Date,
                           expectedOwnerID: UUID? = nil,
                           expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws -> AccountActivityFeedRow? {
        guard version == expectedPolicy.rawValue else { throw AccountActivityContractError.malformedPage }
        guard viewerID == requestViewerID, currentViewerID == requestViewerID,
              requestGeneration >= 0, requestGeneration == currentGeneration else {
            throw AccountActivityContractError.wrongContext
        }
        guard var row else { return nil }
        guard row.cardID == expectedCardID,
              expectedOwnerID == nil || row.ownerID == expectedOwnerID else {
            throw AccountActivityContractError.wrongContext
        }
        // Reuse row shape validation, without claiming home membership or
        // allowing this independent detail to be inserted into the home feed.
        let request = AccountActivityPageRequest(viewerID: requestViewerID, scope: .profile,
            ownerID: row.ownerID, before: nil, limit: 1)
        try AccountActivityFeedPage(version: version, rows: [row], releaseReady: releaseReady,
            scope: .profile, viewerID: viewerID).validateCandidate(request: request,
            currentViewerID: currentViewerID, allowedHomeOwners: [], latestPermittedDate: latestPermittedDate, expectedPolicy: expectedPolicy)
        row.readPolicy = expectedPolicy
        return row
    }

    func validateForProduction(expectedCardID: UUID, requestViewerID: UUID,
                               currentViewerID: UUID?, requestGeneration: Int,
                               currentGeneration: Int, latestPermittedDate: Date,
                               expectedOwnerID: UUID? = nil,
                               expectedPolicy: AccountActivityReadPolicy = .approvedFollowersV1) throws -> AccountActivityFeedRow? {
        guard expectedPolicy.productionReady, releaseReady else {
            throw AccountActivityContractError.unreleased
        }
        return try validateCandidate(expectedCardID: expectedCardID, requestViewerID: requestViewerID,
            currentViewerID: currentViewerID, requestGeneration: requestGeneration,
            currentGeneration: currentGeneration, latestPermittedDate: latestPermittedDate,
            expectedOwnerID: expectedOwnerID, expectedPolicy: expectedPolicy)
    }
}

struct AccountActivityLegacyDetailReceipt: Decodable, Equatable {
    let version: Int
    let cardID: UUID
    let legacyPostID: UUID
    let releaseReady: Bool
    enum CodingKeys: String, CodingKey {
        case version, cardID = "card_id", legacyPostID = "legacy_post_id", releaseReady = "release_ready"
    }

    /// Only consume a result from soom_activity_legacy_detail_candidate_v1,
    /// whose SQL intersects projection can_read AND legacy can_view_post.
    /// Its payload lacks viewer/owner/revision, so the caller MUST retain the
    /// request account generation and recheck it. This mapping is not permission
    /// to reuse cached old content: fetch the returned legacy ID with current RLS.
    func validateCandidate(expectedCardID: UUID, requestViewerID: UUID,
                           currentViewerID: UUID?, requestGeneration: Int,
                           currentGeneration: Int) throws {
        guard version == 1, cardID == expectedCardID else { throw AccountActivityContractError.invalidLegacyMapping }
        guard requestViewerID == currentViewerID, requestGeneration == currentGeneration else {
            throw AccountActivityContractError.wrongContext
        }
        // cardID and legacyPostID are deliberately independent identities.
    }

    func validateForProduction(expectedCardID: UUID, requestViewerID: UUID,
                               currentViewerID: UUID?, requestGeneration: Int,
                               currentGeneration: Int) throws {
        guard AccountActivityFeedReleaseGate.productionReady, releaseReady else {
            throw AccountActivityContractError.unreleased
        }
        try validateCandidate(expectedCardID: expectedCardID, requestViewerID: requestViewerID,
                              currentViewerID: currentViewerID, requestGeneration: requestGeneration,
                              currentGeneration: currentGeneration)
    }
}

private enum AccountActivityContractDate {
    static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }()
        guard let date, date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }
}


/// Local native detail envelope. The base card proves profile authorization;
/// absent or unsupported measurement data never invalidates its basic fields.
struct AccountActivityNativeDetailEnvelope: Decodable {
    struct Params: Encodable {
        let p_card_id: UUID
        let p_expected_revision: Int64
    }
    let contractVersion: Int
    let card: AccountActivityCardEnvelope
    private let snapshot: WorkoutSharedDetailSnapshot?
    private let aggregates: NativeWorkoutSharedAggregateInput?
    var isSupported: Bool { (1...3).contains(contractVersion) }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version", card, snapshot, aggregates
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decode(Int.self, forKey: .contractVersion)
        card = try container.decode(AccountActivityCardEnvelope.self, forKey: .card)
        snapshot = try? container.decodeIfPresent(WorkoutSharedDetailSnapshot.self, forKey: .snapshot)
        aggregates = try? container.decodeIfPresent(NativeWorkoutSharedAggregateInput.self, forKey: .aggregates)
    }

    func maskedRoute(for row: AccountActivityFeedRow) -> WorkoutRoute? {
        guard isSupported, card.releaseReady, let issued = card.row,
              issued.cardID == row.cardID, issued.canonicalID == row.canonicalID,
              issued.ownerID == row.ownerID, issued.revision == row.revision,
              let snapshot, snapshot.hasValidPayload,
              let start = row.cursor?.activityAt else { return nil }
        // RPC copies only the already-masked persisted v1 route. Its init marks
        // it masked; do not apply a second endpoint cut.
        return snapshot.route(start: start)
    }

    func elapsedTimeline(for row: AccountActivityFeedRow) -> Double? {
        guard contractVersion >= 2, card.releaseReady, let issued = card.row,
              issued.cardID == row.cardID, issued.canonicalID == row.canonicalID, issued.ownerID == row.ownerID,
              issued.revision == row.revision, let snapshot, snapshot.hasValidPayload,
              let aggregates, aggregates.isValid(elapsed: snapshot.payload.durationSeconds)
        else { return nil }
        return aggregates.elapsedTimeline?.endOffsetSeconds
    }

    func telemetry(for row: AccountActivityFeedRow) -> WorkoutTelemetry? {
        guard isSupported, card.releaseReady, let issued = card.row,
              issued.cardID == row.cardID, issued.canonicalID == row.canonicalID,
              issued.ownerID == row.ownerID, issued.revision == row.revision,
              let snapshot, snapshot.hasValidPayload,
              let start = row.cursor?.activityAt else { return nil }
        var result = snapshot.telemetry(start: start) ?? .init(workoutID: row.cardID, source: .unknown, fetchedAt: start)
        result.workoutID = row.cardID
        if contractVersion >= 2, let aggregates, aggregates.isValid(elapsed: snapshot.payload.durationSeconds) {
            if let timeline = aggregates.elapsedTimeline {
                if !timeline.samples.isEmpty {
                    result.samples = timeline.samples.map {
                        .init(timestamp: start.addingTimeInterval($0.seconds), distanceMeters: $0.distanceMeters,
                            heartRateBPM: $0.heartRateBPM, cadencePerMinute: $0.cadencePerMinute, powerWatts: $0.powerWatts,
                            speedMetersPerSecond: $0.speedMetersPerSecond, elevationMeters: $0.elevationMeters,
                            cadenceUnit: $0.cadenceUnit, source: .unknown)
                    }
                }
                result.events = timeline.pauses.flatMap {
                    [.init(timestamp: start.addingTimeInterval($0.start), type: "pause"),
                     .init(timestamp: start.addingTimeInterval($0.end), type: $0.end == timeline.endOffsetSeconds ? "stop" : "resume")]
                }
            }
            result.splits = aggregates.lapIntervals.enumerated().map { index, lap in
                .init(label: "랩 \(index + 1)", startDate: start.addingTimeInterval(Double(lap.offsetSeconds)),
                    endDate: start.addingTimeInterval(Double(lap.endOffsetSeconds)),
                    durationSeconds: Double(lap.endOffsetSeconds - lap.offsetSeconds),
                    distanceMeters: lap.distanceMeters.map(Double.init))
            }
            result.intervals = (aggregates.measuredIntervals ?? []).map {
                .init(kind: $0.kind, startDate: start.addingTimeInterval($0.offsetSeconds),
                    endDate: start.addingTimeInterval($0.endOffsetSeconds), value: $0.value)
            }
            result.heartRateZones = (aggregates.zoneSeconds ?? []).enumerated().map {
                .init(name: "Z\($0.offset + 1)", durationSeconds: Double($0.element))
            }
        }
        return result.isEmpty ? nil : result
    }
}
