import Foundation

enum UserOwnershipEligibleDataType: String, Codable, Equatable, CaseIterable {
    case trainingSettings
    case workouts
    case workoutRoutes
    case courseIdentities
    case progressionSummaries
    case futureFeedPosts

    var title: String {
        switch self {
        case .trainingSettings:
            return "운동 기준값"
        case .workouts:
            return "운동 기록"
        case .workoutRoutes:
            return "route 데이터"
        case .courseIdentities:
            return "코스 식별"
        case .progressionSummaries:
            return "성장 흐름"
        case .futureFeedPosts:
            return "향후 피드 게시물"
        }
    }

    static let localFirstDefaults: [UserOwnershipEligibleDataType] = [
        .trainingSettings,
        .workouts,
        .workoutRoutes,
        .courseIdentities,
        .progressionSummaries
    ]
}

enum UserOwnershipMigrationStatus: String, Codable, Equatable, CaseIterable {
    case notLinked
    case readyForReview
    case awaitingConsent
    case deferred
    case migratedFuture
    case conflictFuture

    var title: String {
        switch self {
        case .notLinked:
            return "계정 미연결"
        case .readyForReview:
            return "검토 가능"
        case .awaitingConsent:
            return "동의 필요"
        case .deferred:
            return "보류"
        case .migratedFuture:
            return "이전 완료 예정"
        case .conflictFuture:
            return "충돌 확인 예정"
        }
    }
}

struct UserOwnershipMigrationPlan: Codable, Equatable {
    let localUserId: UUID?
    let remoteUserId: UUID?
    let ownershipScope: UserOwnershipScope
    let eligibleDataTypes: [UserOwnershipEligibleDataType]
    let requiresUserConsent: Bool
    let migrationStatus: UserOwnershipMigrationStatus

    var hasEligibleLocalData: Bool {
        !eligibleDataTypes.isEmpty
    }

    var userFacingSummary: String {
        switch migrationStatus {
        case .notLinked:
            return "계정을 연결하면 기록 연결 여부를 나중에 직접 선택할 수 있어요."
        case .readyForReview, .awaitingConsent:
            return "이 기기의 기록은 아직 로컬에 있어요. 계정에 연결하려면 다음 단계에서 확인이 필요해요."
        case .deferred:
            return "계정은 연결됐지만 옮길 로컬 기록은 아직 확인되지 않았어요."
        case .migratedFuture:
            return "명시적 동의 후 기록이 계정 기준으로 연결되는 미래 상태예요."
        case .conflictFuture:
            return "겹치는 기록은 사용자 확인 후 정리하는 미래 상태예요."
        }
    }
}
