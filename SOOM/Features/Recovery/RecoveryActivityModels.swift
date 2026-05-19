import Foundation

enum RecoveryWorkoutType {
    case ride
    case run
    case swim
    case brick

    var title: String {
        switch self {
        case .ride:
            return "라이딩"
        case .run:
            return "러닝"
        case .swim:
            return "수영"
        case .brick:
            return "브릭"
        }
    }

    var iconName: String {
        switch self {
        case .ride:
            return SOOMIcon.bike
        case .run:
            return SOOMIcon.run
        case .swim:
            return SOOMIcon.swim
        case .brick:
            return SOOMIcon.brick
        }
    }
}

struct RecoveryActivity: Identifiable {
    let id = UUID()
    let workoutType: RecoveryWorkoutType
    let durationMinutes: Int
    let distanceKm: Double
    let averageHeartRate: Int
    let relativeEffort: Int
    let trainingLoad: Double
    let completedAt: Date
}

extension RecoveryActivity {
    static func mockWeek(referenceDate: Date = Date()) -> [RecoveryActivity] {
        [
            RecoveryActivity(
                workoutType: .ride,
                durationMinutes: 52,
                distanceKm: 18.4,
                averageHeartRate: 136,
                relativeEffort: 34,
                trainingLoad: 58,
                completedAt: Calendar.current.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate
            ),
            RecoveryActivity(
                workoutType: .run,
                durationMinutes: 42,
                distanceKm: 8.2,
                averageHeartRate: 151,
                relativeEffort: 52,
                trainingLoad: 86,
                completedAt: Calendar.current.date(byAdding: .day, value: -5, to: referenceDate) ?? referenceDate
            ),
            RecoveryActivity(
                workoutType: .swim,
                durationMinutes: 44,
                distanceKm: 2.1,
                averageHeartRate: 128,
                relativeEffort: 28,
                trainingLoad: 46,
                completedAt: Calendar.current.date(byAdding: .day, value: -4, to: referenceDate) ?? referenceDate
            ),
            RecoveryActivity(
                workoutType: .ride,
                durationMinutes: 88,
                distanceKm: 41.7,
                averageHeartRate: 148,
                relativeEffort: 68,
                trainingLoad: 118,
                completedAt: Calendar.current.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate
            ),
            RecoveryActivity(
                workoutType: .run,
                durationMinutes: 30,
                distanceKm: 5.4,
                averageHeartRate: 144,
                relativeEffort: 36,
                trainingLoad: 61,
                completedAt: Calendar.current.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            )
        ]
    }
}
