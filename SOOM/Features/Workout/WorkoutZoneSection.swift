import SwiftUI

struct WorkoutZoneSection: View {
    let sport: WorkoutSport
    let summaries: [WorkoutZoneSummary]

    init(workout: Workout) {
        self.sport = workout.sport
        self.summaries = Self.makeSummaries(for: workout)
    }

    init(sport: WorkoutSport, summaries: [WorkoutZoneSummary]) {
        self.sport = sport
        self.summaries = summaries
    }

    var body: some View {
        if !visibleSummaries.isEmpty {
            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                SOOMSectionHeader("존 분석", caption: "강도와 리듬을 가볍게 확인해요")

                VStack(spacing: SOOMLayout.stackSpacing) {
                    ForEach(visibleSummaries, id: \.type.rawValue) { summary in
                        WorkoutZoneCard(summary: summary, tint: sport.tint)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    var visibleSummaries: [WorkoutZoneSummary] {
        summaries.filter { summary in
            summary.isAvailable || Self.shouldShowUnavailable(summary.type, for: sport)
        }
    }

    static func makeSummaries(for workout: Workout) -> [WorkoutZoneSummary] {
        let builder = WorkoutZoneBuilder()
        var summaries: [WorkoutZoneSummary] = []

        summaries.append(makeHeartRateSummary(for: workout, builder: builder))

        switch workout.sport {
        case .run:
            if let cadence = workout.cadence {
                summaries.append(makeCadenceSummary(cadence: cadence, duration: workout.duration, sport: workout.sport, builder: builder))
            }
        case .bike, .brick:
            if let cadence = workout.cadence {
                summaries.append(makeCadenceSummary(cadence: cadence, duration: workout.duration, sport: workout.sport, builder: builder))
            }
            summaries.append(makePowerSummary(power: workout.avgPower, duration: workout.duration, builder: builder))
        case .swim:
            break
        }

        return summaries
    }

    static func shouldShowUnavailable(_ type: WorkoutZoneType, for sport: WorkoutSport) -> Bool {
        switch (sport, type) {
        case (.bike, .power), (.brick, .power):
            return true
        case (.swim, .heartRate), (.run, .heartRate), (.bike, .heartRate), (.brick, .heartRate):
            return true
        default:
            return false
        }
    }

    private static func makeHeartRateSummary(for workout: Workout, builder: WorkoutZoneBuilder) -> WorkoutZoneSummary {
        let durations = workout.zones.enumerated().map { index, zone in
            WorkoutZoneDurationInput(
                zoneIndex: zoneIndex(from: zone.name) ?? index + 1,
                durationSeconds: TimeInterval(zone.minutes * 60),
                rangeDescription: zone.name
            )
        }
        return builder.buildSummary(type: .heartRate, durations: durations)
    }

    private static func makeCadenceSummary(
        cadence: Int,
        duration: TimeInterval,
        sport: WorkoutSport,
        builder: WorkoutZoneBuilder
    ) -> WorkoutZoneSummary {
        let zoneIndex: Int
        let rangeDescription: String

        switch sport {
        case .bike, .brick:
            if cadence < 75 {
                zoneIndex = 1
                rangeDescription = "낮은 리듬"
            } else if cadence <= 95 {
                zoneIndex = 2
                rangeDescription = "안정 리듬"
            } else {
                zoneIndex = 3
                rangeDescription = "빠른 리듬"
            }
        case .run:
            if cadence < 165 {
                zoneIndex = 1
                rangeDescription = "낮은 보폭 리듬"
            } else if cadence <= 185 {
                zoneIndex = 2
                rangeDescription = "안정 러닝 리듬"
            } else {
                zoneIndex = 3
                rangeDescription = "빠른 러닝 리듬"
            }
        case .swim:
            zoneIndex = 2
            rangeDescription = "기술 리듬"
        }

        return builder.buildSummary(
            type: .cadence,
            durations: [WorkoutZoneDurationInput(zoneIndex: zoneIndex, durationSeconds: duration, rangeDescription: rangeDescription)]
        )
    }

    private static func makePowerSummary(
        power: Int?,
        duration: TimeInterval,
        builder: WorkoutZoneBuilder
    ) -> WorkoutZoneSummary {
        guard let power else {
            return builder.unavailableSummary(type: .power)
        }

        let zoneIndex: Int
        let rangeDescription: String

        switch power {
        case ..<150:
            zoneIndex = 1
            rangeDescription = "가벼운 파워"
        case 150..<200:
            zoneIndex = 2
            rangeDescription = "지속 파워"
        case 200..<250:
            zoneIndex = 3
            rangeDescription = "템포 파워"
        case 250..<300:
            zoneIndex = 4
            rangeDescription = "높은 파워"
        default:
            zoneIndex = 5
            rangeDescription = "고강도 파워"
        }

        return builder.buildSummary(
            type: .power,
            durations: [WorkoutZoneDurationInput(zoneIndex: zoneIndex, durationSeconds: duration, rangeDescription: rangeDescription)]
        )
    }

    private static func zoneIndex(from name: String) -> Int? {
        let digits = name.compactMap { $0.isNumber ? $0 : nil }
        guard !digits.isEmpty else { return nil }
        return Int(String(digits))
    }
}

#Preview("WorkoutZoneSection") {
    let workout = MockWorkoutHarness().loadWorkouts()[2]

    SOOMScreen {
        WorkoutZoneSection(workout: workout)
    }
}
