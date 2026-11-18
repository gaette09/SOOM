import Foundation
import SwiftData

/// Durable outbox and server-version shadow, stored in the same account database
/// and transaction as the health models. Never contains authentication secrets.
@Model
final class HealthCloudOutboxRecord {
    var key: String
    var kind: String
    var recordKey: String
    var payload: Data?
    var serverVersion: Int64
    var mutationID: UUID
    var pending: Bool
    // Avoid PersistentModel.isDeleted: that name belongs to SwiftData itself.
    var isTombstone: Bool = false
    var conflicted: Bool
    var conflictPayload: Data?
    var conflictVersion: Int64
    var conflictDeleted: Bool

    init(kind: String, recordKey: String, payload: Data?, isDeleted: Bool = false) {
        self.key = kind + ":" + recordKey
        self.kind = kind
        self.recordKey = recordKey
        self.payload = payload
        self.serverVersion = 0
        self.mutationID = UUID()
        self.pending = true
        self.isTombstone = isDeleted
        self.conflicted = false
        self.conflictPayload = nil
        self.conflictVersion = 0
        self.conflictDeleted = false
    }
}

enum HealthCloudKind: String, Codable, CaseIterable {
    case workout, route, checkIn, recoverySnapshot
}

enum HealthCloudError: Error, LocalizedError {
    case accountChanged, unavailable, invalidPayload, conflict, guestImportClaimed
    var errorDescription: String? {
        switch self {
        case .accountChanged: return "계정이 변경되어 동기화를 중단했어요."
        case .unavailable: return "서버에 연결하지 못했어요. 변경 사항은 이 기기에 보관됩니다."
        case .invalidPayload: return "저장된 기록 형식을 확인하지 못했어요."
        case .conflict: return "다른 기기의 변경과 충돌했어요. 유지할 기록을 선택해 주세요."
        case .guestImportClaimed: return "이 기기의 기존 기록은 다른 계정으로 이관 중이거나 이관되었습니다."
        }
    }
}

/// Versioned transport format. DTOs use persistence values so restoring never
/// fabricates health metrics or calls calculators. Dates use Codable's stable
/// reference-date representation inside JSON, independent of PostgREST dates.
struct HealthCloudPayload: Codable {
    var formatVersion = 1
    var workout: UnifiedWorkout?
    var route: Route?
    var checkIn: CheckIn?
    var snapshot: Snapshot?
    var telemetry: WorkoutTelemetry? = nil

    struct Route: Codable {
        var id: UUID; var workoutId: UUID; var sourceRaw: String
        var encodedCoordinates: String?; var coordinateCount: Int
        var totalDistanceMeters: Double; var totalElevationGain: Double?
        var createdAt: Date; var updatedAt: Date; var courseIdentity: String?
        @MainActor init(_ value: PersistedWorkoutRoute) {
            id = value.id; workoutId = value.workoutId; sourceRaw = value.sourceRaw
            encodedCoordinates = value.encodedCoordinates; coordinateCount = value.coordinateCount
            totalDistanceMeters = value.totalDistanceMeters; totalElevationGain = value.totalElevationGain
            createdAt = value.createdAt; updatedAt = value.updatedAt; courseIdentity = value.courseIdentity
        }
        @MainActor func makeRecord() -> PersistedWorkoutRoute {
            PersistedWorkoutRoute(id: id, workoutId: workoutId, sourceRaw: sourceRaw,
                encodedCoordinates: encodedCoordinates, coordinateCount: coordinateCount,
                totalDistanceMeters: totalDistanceMeters, totalElevationGain: totalElevationGain,
                createdAt: createdAt, updatedAt: updatedAt, courseIdentity: courseIdentity)
        }
    }
    struct CheckIn: Codable {
        var id: UUID; var date: Date; var fatigueLevel: Int; var sleepQuality: Int
        var muscleSoreness: Int; var moodLevel: Int; var note: String?
        var createdAt: Date; var updatedAt: Date
        @MainActor init(_ value: CheckInRecord) {
            id = value.id; date = value.date; fatigueLevel = value.fatigueLevel
            sleepQuality = value.sleepQuality; muscleSoreness = value.muscleSoreness
            moodLevel = value.moodLevel; note = value.note
            createdAt = value.createdAt; updatedAt = value.updatedAt
        }
        @MainActor func makeRecord() -> CheckInRecord {
            CheckInRecord(id: id, date: date, fatigueLevel: fatigueLevel,
                sleepQuality: sleepQuality, muscleSoreness: muscleSoreness,
                moodLevel: moodLevel, note: note, createdAt: createdAt, updatedAt: updatedAt)
        }
    }
    struct Snapshot: Codable {
        var id: UUID; var date: Date; var score: Int; var status: String
        var recommendation: String; var coachMessage: String; var explanation: String?
        var dataQuality: String; var activityCount: Int; var activityCountKnown: Bool?
        var checkInId: UUID?; var createdAt: Date; var updatedAt: Date
        @MainActor init(_ value: DailyRecoverySnapshotRecord) {
            id = value.id; date = value.date; score = value.score; status = value.status
            recommendation = value.recommendation; coachMessage = value.coachMessage
            explanation = value.explanation; dataQuality = value.dataQuality
            activityCount = value.activityCount; activityCountKnown = value.activityCountKnown
            checkInId = value.checkInId; createdAt = value.createdAt; updatedAt = value.updatedAt
        }
        @MainActor func makeRecord() -> DailyRecoverySnapshotRecord {
            DailyRecoverySnapshotRecord(id: id, date: date, score: score, status: status,
                recommendation: recommendation, coachMessage: coachMessage,
                explanation: explanation, dataQuality: dataQuality, activityCount: activityCount,
                activityCountKnown: activityCountKnown ?? false, checkInId: checkInId,
                createdAt: createdAt, updatedAt: updatedAt)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    static func equivalent(_ lhs: Data?, _ rhs: Data?) -> Bool {
        if lhs == rhs { return true }
        guard let lhs, let rhs,
              let left = try? JSONSerialization.jsonObject(with: lhs) as? NSDictionary,
              let right = try? JSONSerialization.jsonObject(with: rhs) as? NSDictionary else { return false }
        return left.isEqual(right)
    }
    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.formatVersion == 1 else { throw HealthCloudError.invalidPayload }
        return value
    }
}
