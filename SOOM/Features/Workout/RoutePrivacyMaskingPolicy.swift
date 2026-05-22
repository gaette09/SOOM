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
        distanceMeters: Double = 200
    ) {
        self.mode = mode
        self.distanceMeters = max(0, distanceMeters)
    }

    static let none = RoutePrivacyMaskingPolicy(mode: .none, distanceMeters: 0)
    static let defaultShare = RoutePrivacyMaskingPolicy()

    var shouldMaskStart: Bool {
        mode == .startAndEnd || mode == .startOnly
    }

    var shouldMaskEnd: Bool {
        mode == .startAndEnd || mode == .endOnly
    }
}
