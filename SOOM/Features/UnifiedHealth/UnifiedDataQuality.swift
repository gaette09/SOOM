import Foundation

enum UnifiedDataQuality: String, Equatable, Codable {
    case complete
    case partial
    case estimated
    case missing
    case unknown
}
