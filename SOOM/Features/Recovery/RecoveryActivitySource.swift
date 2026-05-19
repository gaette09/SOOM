enum RecoveryActivitySource {
    case mock
    case local
    case healthKit

    static let defaultSource: RecoveryActivitySource = .mock
}
