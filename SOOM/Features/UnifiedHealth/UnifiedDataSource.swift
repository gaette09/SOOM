import Foundation

enum UnifiedDataSource: String, Equatable, Codable {
    case appleHealthKit
    case garmin
    case samsungHealth
    case healthConnect
    case soomLocal
    case manual
    case unknown
}
