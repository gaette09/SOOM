import Foundation

struct WorkoutGrowthInput: Identifiable, Equatable {
    let id: UUID
    let source: UnifiedDataSource
    let workoutType: UnifiedWorkoutType
    let startDate: Date
    let durationMinutes: Int
    let distanceKm: Double?
    let averagePaceText: String?
    let averageSpeedKmh: Double?
    let averageHeartRate: Double?
    let elevationGainMeters: Double?
    let activeEnergyKcal: Double?
}
