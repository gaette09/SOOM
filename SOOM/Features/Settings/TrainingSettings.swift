import Foundation

enum TrainingPreferredUnit: String, CaseIterable, Identifiable, Equatable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric:
            return "킬로미터"
        case .imperial:
            return "마일"
        }
    }
}

struct TrainingSettings: Equatable {
    var maxHeartRate: Int?
    var cyclingFTP: Int?
    var preferredUnit: TrainingPreferredUnit
    var privacyDefault: ShareableWorkoutVisibility

    init(
        maxHeartRate: Int? = nil,
        cyclingFTP: Int? = nil,
        preferredUnit: TrainingPreferredUnit = .metric,
        privacyDefault: ShareableWorkoutVisibility = .privateOnly
    ) {
        self.maxHeartRate = maxHeartRate
        self.cyclingFTP = cyclingFTP
        self.preferredUnit = preferredUnit
        self.privacyDefault = privacyDefault
    }
}
