import Foundation

enum RoutePrivacyMaskingMode: String, Equatable {
    case none
    case startAndEnd
    case startOnly
    case endOnly
}

struct RoutePrivacyMaskingPolicy: Equatable {
    let mode: RoutePrivacyMaskingMode
    let distanceMeters: Double

    init(
        mode: RoutePrivacyMaskingMode = .startAndEnd,
        distanceMeters: Double = 100
    ) {
        self.mode = mode
        self.distanceMeters = max(0, distanceMeters)
    }

    static let none = RoutePrivacyMaskingPolicy(mode: .none, distanceMeters: 0)
    /// Personal display: radial distance from each original endpoint, not path length.
    static let defaultDisplay = RoutePrivacyMaskingPolicy(distanceMeters: 50)
    /// Existing shared v1 contract remains 200m until a separately reviewed server transition.
    static let defaultShare = RoutePrivacyMaskingPolicy(distanceMeters: 200)

    var shouldMaskStart: Bool {
        mode == .startAndEnd || mode == .startOnly
    }

    var shouldMaskEnd: Bool {
        mode == .startAndEnd || mode == .endOnly
    }
}
