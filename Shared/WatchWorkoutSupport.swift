import Combine
import Foundation
import HealthKit

/// A pool length is required for pool swimming; open-water workouts use GPS.
struct WatchWorkoutPlan: Hashable, Sendable {
    var sport: WorkoutLiveState.Sport
    var indoor = false
    var poolLengthMeters: Double? = nil
    var isPoolSwimming: Bool { sport == .swimming && poolLengthMeters != nil }
    var recordsRoute: Bool { !indoor && !isPoolSwimming }

    var isValid: Bool {
        if sport == .swimming {
            return poolLengthMeters.map { $0.isFinite && (10...150).contains($0) } ?? !indoor
        }
        return poolLengthMeters == nil
    }
    var title: String {
        if sport == .swimming { return isPoolSwimming ? "수영장 수영" : "오픈워터 수영" }
        return (indoor ? "실내 " : "실외 ") + sport.title
    }
    var configuration: HKWorkoutConfiguration {
        let result = HKWorkoutConfiguration()
        result.activityType = sport.healthKitType
        result.locationType = indoor ? .indoor : .outdoor
        if sport == .swimming {
            result.swimmingLocationType = isPoolSwimming ? .pool : .openWater
            if let poolLengthMeters, isValid {
                result.lapLength = HKQuantity(unit: .meter(), doubleValue: poolLengthMeters)
            }
        }
        return result
    }
    init(sport: WorkoutLiveState.Sport, indoor: Bool = false, poolLengthMeters: Double? = nil) {
        self.sport = sport; self.indoor = indoor; self.poolLengthMeters = poolLengthMeters
    }
    init?(configuration: HKWorkoutConfiguration) {
        guard let sport = WorkoutLiveState.Sport(healthKitType: configuration.activityType) else { return nil }
        self.sport = sport
        indoor = configuration.locationType == .indoor
        if sport == .swimming && configuration.swimmingLocationType == .pool {
            guard let length = configuration.lapLength else { return nil }
            poolLengthMeters = length.doubleValue(for: .meter())
        } else {
            guard sport != .swimming || configuration.swimmingLocationType == .openWater else { return nil }
            poolLengthMeters = nil
        }
        guard isValid else { return nil }
    }
}

extension WorkoutLiveState.Sport {
    var healthKitType: HKWorkoutActivityType {
        switch self { case .running: .running; case .walking: .walking; case .cycling: .cycling; case .swimming: .swimming }
    }
    init?(healthKitType: HKWorkoutActivityType) {
        switch healthKitType {
        case .running: self = .running
        case .walking: self = .walking
        case .cycling: self = .cycling
        case .swimming: self = .swimming
        default: return nil
        }
    }
    var distanceQuantity: HKQuantityTypeIdentifier {
        switch self { case .cycling: .distanceCycling; case .swimming: .distanceSwimming; default: .distanceWalkingRunning }
    }
    var additionalQuantities: [HKQuantityTypeIdentifier] {
        switch self {
        case .running: [.runningPower, .runningSpeed, .stepCount]
        case .walking: [.walkingSpeed, .stepCount]
        case .cycling: [.cyclingPower, .cyclingCadence, .cyclingSpeed]
        case .swimming: [.distanceSwimming, .swimmingStrokeCount]
        }
    }
}

struct WatchWorkoutHistoryItem: Identifiable, Hashable {
    let id: UUID
    let sport: WorkoutLiveState.Sport
    let startedAt: Date
    let duration: TimeInterval
    let distance: Double?
    let energy: Double?
    let averageHeartRate: Double?
    let strokes: Double?
    let poolLengthMeters: Double?
    let indoor: Bool

    init?(workout: HKWorkout) {
        guard let sport = WorkoutLiveState.Sport(healthKitType: workout.workoutActivityType) else { return nil }
        self.id = workout.uuid; self.sport = sport; self.startedAt = workout.startDate
        duration = workout.duration
        func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
            workout.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: unit)
        }
        distance = Self.measured(sum(sport.distanceQuantity, unit: .meter()) ?? workout.totalDistance?.doubleValue(for: .meter()))
        energy = Self.measured(sum(.activeEnergyBurned, unit: .kilocalorie()))
        averageHeartRate = Self.measured(workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        strokes = sport == .swimming ? Self.measured(sum(.swimmingStrokeCount, unit: .count())) : nil
        poolLengthMeters = (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter())
        indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
    }
    private static func measured(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    var distanceText: String {
        guard let distance else { return "–" }
        return sport == .swimming ? String(format: "%.0f", distance) : String(format: "%.2f", distance / 1000)
    }
    var effortText: String {
        guard let distance else { return "–" }
        let state = WorkoutLiveState(id: id, scope: "local-history", sport: sport, phase: .finished,
            startedAt: startedAt, updatedAt: startedAt.addingTimeInterval(duration), elapsed: duration,
            distance: distance, isWatch: true)
        return state.effortText(at: state.updatedAt)
    }
}

/// Reads saved SOOM workouts directly from HealthKit. No duplicate local health database.
@MainActor
final class WatchWorkoutHistoryStore: ObservableObject {
    @Published private(set) var workouts: [WatchWorkoutHistoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private let healthStore = HKHealthStore()

    func load() async {
        guard !isLoading else { return }
        isLoading = true; message = nil
        defer { isLoading = false }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "이 워치에서 건강 기록을 사용할 수 없어요."; return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(),
                HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceSwimming),
                HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.swimmingStrokeCount)])
            let samples: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: .workoutType(),
                    predicate: HKQuery.predicateForObjects(withMetadataKey: "SOOMWorkoutID"), limit: 30,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
                }
                healthStore.execute(query)
            }
            workouts = samples.compactMap(WatchWorkoutHistoryItem.init)
            // HealthKit does not reveal whether read permission was denied.
            if workouts.isEmpty { message = "표시할 SOOM 운동이 없어요. 기록이 있다면 건강의 읽기 권한을 확인해 주세요." }
        } catch {
            workouts = []
            message = "기록을 불러오지 못했어요. 워치를 잠금 해제하고 다시 시도해 주세요."
        }
    }
}
