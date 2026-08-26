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
        // 2026-08-26: workouts upload automatically on completion now
        // (opt-out via "공유 안 함", not opt-in "공유하기") — public is
        // the correct default for that model. Users who want private-by-
        // default can still flip this in Settings.
        privacyDefault: ShareableWorkoutVisibility = .publicFeed
    ) {
        self.maxHeartRate = maxHeartRate
        self.cyclingFTP = cyclingFTP
        self.preferredUnit = preferredUnit
        self.privacyDefault = privacyDefault
    }
}
