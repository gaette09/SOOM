import Foundation
import SwiftData

@MainActor
enum ReviewDemoData {
    static func workouts(referenceDate: Date = Date()) -> [UnifiedWorkout] {
        (0..<18).map { index in
            let type: UnifiedWorkoutType = [.running, .cycling, .swimming][index % 3]
            // Always show one sample in today's month, including on its first day.
            let dayOffset = index == 0 ? 0 : -(1 + index * 2)
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: referenceDate) ?? referenceDate
            let morning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day
            let start = index == 0 ? min(morning, referenceDate) : morning
            let duration: Double = type == .cycling ? 4_200 : (type == .swimming ? 1_800 : 2_400)
            let distance: Double = type == .cycling ? 28_000 + Double(index * 200) : (type == .swimming ? 1_200 + Double(index * 25) : 6_400 + Double(index * 100))
            let title = type == .cycling ? "DEMO · 강변 라이딩" : (type == .swimming ? "DEMO · 아침 수영" : "DEMO · 공원 러닝")
            return makeWorkout(type: type, start: start, duration: duration, distance: distance, title: title)
        }
    }

    static func seed(in context: ModelContext, referenceDate: Date = Date()) throws {
        for workout in workouts(referenceDate: referenceDate) {
            let record = UnifiedWorkoutPersistenceMapper().makeRecord(from: workout)
            record.telemetryData = try JSONEncoder().encode(telemetry(for: workout))
            context.insert(record)
            if workout.workoutType != .swimming {
                context.insert(WorkoutRouteMapper().makeRecord(from: route(for: workout)))
            }
        }
        // Keep today empty so a reviewer can submit a fresh check-in.
        for dayOffset in 1...14 {
            let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: referenceDate) ?? referenceDate
            let checkIn = RecoveryCheckIn(date: date, fatigueLevel: 2 + dayOffset % 3,
                sleepQuality: 3 + dayOffset % 3, muscleSoreness: 1 + dayOffset % 3,
                moodLevel: 3 + dayOffset % 3, note: "DEMO · 합성 체크인 / Sample check-in")
            context.insert(RecoveryCheckInPersistenceMapper().makeRecord(from: checkIn))
            let snapshot = DailyRecoverySnapshot(date: Calendar.current.startOfDay(for: date),
                score: 65 + dayOffset % 5 * 5, status: "데모 회복 흐름", recommendation: "가볍게 움직이며 몸의 반응을 확인해요.",
                coachMessage: "샘플 운동과 체크인으로 회복 흐름을 살펴보세요.",
                explanation: "DEMO · 합성 데이터로 만든 예시입니다.", dataQuality: .mock,
                activityCount: dayOffset % 2, activityCountKnown: true, checkInId: checkIn.id)
            context.insert(DailyRecoverySnapshotMapper().makeRecord(from: snapshot))
        }
        try context.save()
    }

    static func importSample(in context: ModelContext) async throws {
        guard ReviewDemoMode.isActive,
              HealthCloudJournal.accountID(for: context) == ReviewDemoMode.userID,
              !HealthCloudJournal.isRetired(context) else { throw HealthCloudError.accountChanged }
        let workout = makeWorkout(type: .running, start: Date().addingTimeInterval(-2_000),
            duration: 1_800, distance: 5_000, title: "DEMO · 방금 가져온 샘플 러닝")
        try await SwiftDataUnifiedWorkoutStore(modelContext: context).saveWorkout(workout)
        try await SwiftDataWorkoutRoutePersistenceStore(modelContext: context).saveRoute(route(for: workout))
        try WorkoutTelemetryStore(modelContext: context).save(telemetry(for: workout))
        NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: nil)
    }

    private static func makeWorkout(type: UnifiedWorkoutType, start: Date, duration: Double,
                                    distance: Double, title: String) -> UnifiedWorkout {
        UnifiedWorkout(id: UUID(), externalId: nil, source: .manual, workoutType: type,
            startDate: start, endDate: start.addingTimeInterval(duration), durationSeconds: duration,
            distanceMeters: distance, activeEnergyKcal: duration / 6, averageHeartRate: type == .swimming ? 125 : 142,
            maxHeartRate: 168, averageSpeedMetersPerSecond: distance / duration,
            elevationGainMeters: type == .swimming ? nil : 48,
            averagePowerWatts: type == .cycling ? 175 : nil,
            averageCadence: type == .cycling ? 85 : (type == .running ? 168 : nil),
            routeMissingReason: type == .swimming ? .indoorNoLocationData : .none,
            dataQuality: .estimated, createdAt: start, updatedAt: start,
            companionNames: ["샘플 친구"], userTitle: title,
            userDescription: "체험을 위한 합성 운동입니다. 실제 건강 앱에 저장하거나 서버에 업로드하지 않습니다.",
            sharingVisibilityRaw: FeedPostVisibility.privatePost.rawValue,
            deviceName: "SOOM Demo", locationName: type == .swimming ? "샘플 수영장" : "샘플 강변 코스")
    }

    static func telemetry(for workout: UnifiedWorkout) -> WorkoutTelemetry {
        let samples = (0...120).map { index -> WorkoutTelemetrySample in
            let fraction = Double(index) / 120
            let wave = sin(fraction * .pi * 8)
            return WorkoutTelemetrySample(timestamp: workout.startDate.addingTimeInterval(workout.durationSeconds * fraction),
                distanceMeters: (workout.distanceMeters ?? 0) * fraction, heartRateBPM: 137 + 15 * wave,
                cadencePerMinute: workout.averageCadence.map { $0 + 4 * wave },
                powerWatts: workout.averagePowerWatts.map { $0 + 35 * wave },
                speedMetersPerSecond: (workout.averageSpeedMetersPerSecond ?? 1) * (1 + wave * 0.12),
                elevationMeters: workout.workoutType == .swimming ? nil : 12 + 8 * sin(fraction * .pi * 2),
                cadenceUnit: workout.workoutType == .cycling ? .revolutionsPerMinute : .stepsPerMinute, source: .manual)
        }
        let splits = (0..<5).map { index in
            let interval = workout.durationSeconds / 5
            return WorkoutTelemetrySplit(label: "구간 \(index + 1)",
                startDate: workout.startDate.addingTimeInterval(interval * Double(index)),
                endDate: workout.startDate.addingTimeInterval(interval * Double(index + 1)),
                durationSeconds: interval, distanceMeters: (workout.distanceMeters ?? 0) / 5,
                averageHeartRate: 136 + Double(index * 3), averagePowerWatts: workout.averagePowerWatts,
                averageCadence: workout.averageCadence)
        }
        return WorkoutTelemetry(workoutID: workout.id, source: .manual, samples: samples, splits: splits,
            heartRateZones: [.init(name: "Zone 1", durationSeconds: workout.durationSeconds * 0.2),
                             .init(name: "Zone 2", durationSeconds: workout.durationSeconds * 0.55),
                             .init(name: "Zone 3", durationSeconds: workout.durationSeconds * 0.25)])
    }

    private static func route(for workout: UnifiedWorkout) -> WorkoutRoute {
        let coordinates = (0...120).map { index in
            let fraction = Double(index) / 120
            let angle = fraction * 2 * .pi
            return WorkoutRouteCoordinate(latitude: 37.53 + 0.012 * sin(angle),
                longitude: 126.98 + 0.026 * cos(angle), altitude: 12 + 8 * sin(angle),
                timestamp: workout.startDate.addingTimeInterval(workout.durationSeconds * fraction))
        }
        return WorkoutRoute(workoutId: workout.id, source: .manual, coordinates: coordinates,
            totalDistanceMeters: workout.distanceMeters ?? 0, totalElevationGain: workout.elevationGainMeters)
    }
}
