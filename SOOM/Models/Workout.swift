import Foundation
import SwiftUI

enum WorkoutSport: String, CaseIterable, Identifiable {
    case swim
    case bike
    case run
    case brick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swim: "수영"
        case .bike: "사이클"
        case .run: "러닝"
        case .brick: "브릭"
        }
    }

    var iconName: String {
        switch self {
        case .swim: SOOMIcon.swim
        case .bike: SOOMIcon.bike
        case .run: SOOMIcon.run
        case .brick: SOOMIcon.brick
        }
    }

    var tint: Color {
        switch self {
        case .swim: SOOMColor.swim
        case .bike: SOOMColor.bike
        case .run: SOOMColor.run
        case .brick: SOOMColor.recovery
        }
    }
}

struct Workout: Identifiable {
    let id: UUID
    let sport: WorkoutSport
    let title: String
    let date: Date
    let distanceMeters: Double
    let duration: TimeInterval
    let activeCalories: Int
    let avgHeartRate: Int
    let maxHeartRate: Int
    let avgPower: Int?
    let elevationGain: Int
    let cadence: Int?
    let effort: Int
    let source: String
    let route: [RoutePoint]
    let splits: [WorkoutSplit]
    let samples: [WorkoutSample]
    let zones: [HeartRateZone]
    let achievements: [String]
    let aiSummary: String

    var formattedDistance: String {
        if sport == .swim && distanceMeters < 10_000 {
            return "\(Int(distanceMeters)) m"
        }
        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }
        return "\(minutes)분"
    }

    var formattedPace: String {
        guard distanceMeters > 0 else { return "-" }
        let pace = duration / (distanceMeters / 1_000)
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return "\(minutes):\(String(format: "%02d", seconds))/km"
    }
}

struct RoutePoint: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

struct WorkoutSplit: Identifiable {
    let id = UUID()
    let label: String
    let distance: String
    let time: String
    let pace: String
    let heartRate: Int
    let power: Int?
}

struct WorkoutSample: Identifiable {
    let id = UUID()
    let minute: Double
    let heartRate: Int
    let paceSeconds: Double
    let power: Int?
}

struct HeartRateZone: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Int
    let tint: Color
}

struct MonthlySportSummary: Identifiable {
    let id = UUID()
    let sport: WorkoutSport
    let change: Int
    let volume: String
    let sessions: Int
    let progress: Double
}

struct MonthlySnapshot {
    let workoutCount: Int
    let trainingHours: Double
    let restDays: Int
    let highIntensityRatio: Int
    let conditionScore: Int
    let fatigueScore: Int
    let riskScore: Int
    let summaries: [MonthlySportSummary]
    let insights: [AIInsight]
    let recommendations: [AIRecommendation]
}
