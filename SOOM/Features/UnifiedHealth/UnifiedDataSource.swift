import Foundation

enum UnifiedDataSource: String, Equatable, Codable {
    case appleHealthKit
    case garmin
    case strava
    case samsungHealth
    case healthConnect
    case soomLocal
    case manual
    case unknown

    /// A workout pulled in from an external device/service, as opposed to
    /// one entered directly in SOOM (soomLocal via Record, or manual entry).
    /// Matches the split RootTabView.destination(for:) already uses to
    /// route direct-Record workouts away from the imported-workout library.
    var isImported: Bool {
        switch self {
        case .appleHealthKit, .garmin, .strava, .samsungHealth, .healthConnect, .unknown:
            return true
        case .soomLocal, .manual:
            return false
        }
    }
}
