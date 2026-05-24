import Foundation

struct PersonalizedZoneBaseline: Equatable {
    var maxHeartRate: Int?
    var cyclingFTP: Int?

    init(maxHeartRate: Int? = nil, cyclingFTP: Int? = nil) {
        self.maxHeartRate = maxHeartRate
        self.cyclingFTP = cyclingFTP
    }

    static let empty = PersonalizedZoneBaseline()

    var hasPersonalizedHeartRate: Bool {
        maxHeartRate != nil
    }

    var hasPersonalizedPower: Bool {
        cyclingFTP != nil
    }
}
