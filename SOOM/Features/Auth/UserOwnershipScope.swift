import Foundation

enum UserOwnershipScope: String, Codable, Equatable, CaseIterable {
    case localOnly
    case remoteAccountLinked
    case migrationEligible
    case migratedFuture
    case conflictFuture

    var title: String {
        switch self {
        case .localOnly:
            return "로컬 기록"
        case .remoteAccountLinked:
            return "계정 연결됨"
        case .migrationEligible:
            return "연결 검토 가능"
        case .migratedFuture:
            return "이전 완료 예정"
        case .conflictFuture:
            return "충돌 확인 예정"
        }
    }

    var summary: String {
        switch self {
        case .localOnly:
            return "이 기기의 기록은 로컬에만 머물러 있어요."
        case .remoteAccountLinked:
            return "계정은 연결됐지만 기록 소유권은 아직 로컬 기준이에요."
        case .migrationEligible:
            return "기록을 계정에 연결하려면 별도 확인이 필요해요."
        case .migratedFuture:
            return "명시적 동의 후 기록 연결이 완료되는 미래 상태예요."
        case .conflictFuture:
            return "여러 기기 기록이 겹칠 때 확인이 필요한 미래 상태예요."
        }
    }
}
