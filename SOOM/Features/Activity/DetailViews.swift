import SwiftUI
import HealthKit

struct WorkoutDetailView: View {
    let workout: Workout
    var comparisonWorkouts: [Workout] = []
    var healthKitWorkout: HKWorkout?
    var zoneDataProvider: WorkoutZoneDataProviding?

    var body: some View {
        SOOMScreen {
            WorkoutDetailContent(
                workout: workout,
                showsHeader: true,
                sessionSummary: sessionSummary,
                growthSummary: growthSummary,
                growthMetrics: growthMetrics,
                weaknessInsight: weaknessInsight,
                recoveryImpact: recoveryImpact,
                shareableCard: shareableCard,
                mapRoute: detailMapRoute,
                healthKitWorkout: healthKitWorkout,
                zoneDataProvider: zoneDataProvider
            )
        }
        .navigationTitle("운동 상세")
        .navigationBarTitleDisplayMode(.inline)
        .hidesSOOMTabBar()
    }


    private var shareableCard: ShareableWorkoutCardModel {
        ShareableWorkoutCardBuilder().build(
            workout: workout,
            sessionSummary: sessionSummary,
            growthSummary: growthSummary,
            recoveryImpact: recoveryImpact
        )
    }

    private var sessionSummary: WorkoutSessionSummary {
        WorkoutSessionSummaryBuilder().build(
            workout: workout,
            growthSummary: growthSummary,
            weaknessInsight: weaknessInsight,
            recoveryImpact: recoveryImpact
        )
    }

    private var growthMetrics: [WorkoutGrowthMetric] {
        let recentInputs = (comparisonWorkouts.isEmpty ? [workout] : comparisonWorkouts).map { WorkoutGrowthInput(detailWorkout: $0) }
        return WorkoutGrowthMetricsBuilder().build(
            current: WorkoutGrowthInput(detailWorkout: workout),
            recent: recentInputs
        )
    }

    private var growthSummary: WorkoutGrowthSummary {
        WorkoutGrowthSummaryBuilder().build(
            current: workout,
            recentWorkouts: comparisonWorkouts.isEmpty ? [workout] : comparisonWorkouts
        )
    }

    private var weaknessInsight: WorkoutWeaknessInsight {
        WorkoutWeaknessInsightBuilder().build(
            current: workout,
            recentWorkouts: comparisonWorkouts.isEmpty ? [workout] : comparisonWorkouts
        )
    }

    private var recoveryImpact: WorkoutRecoveryImpact {
        WorkoutRecoveryImpactBuilder().build(workout: workout)
    }

    private var detailMapRoute: WorkoutRoute? {
        guard !workout.route.isEmpty else { return nil }

        let coordinates = workout.route.map { point in
            WorkoutRouteCoordinate(latitude: point.latitude, longitude: point.longitude)
        }

        return WorkoutRoute(
            workoutId: workout.id,
            source: .soomLocal,
            coordinates: coordinates,
            totalDistanceMeters: workout.distanceMeters,
            totalElevationGain: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil,
            createdAt: workout.date
        )
    }
}

struct ClubDetailView: View {
    let club: Club

    var body: some View {
        SOOMScreen {
            DetailHeader(icon: SOOMIcon.people, title: club.name, subtitle: "\(club.location) · \(club.memberCount)명", tint: SOOMColor.bike)

            SOOMCard {
                SOOMSectionHeader("클럽 소개")
                Text(club.description)
                    .font(SOOMFont.body(17, relativeTo: .body))
                    .foregroundStyle(SOOMColor.secondaryInk)
                HStack {
                    SOOMMetricPill("멤버", "\(club.memberCount)명", tint: SOOMColor.bike)
                    SOOMMetricPill("주간 볼륨", club.weeklyVolume, tint: SOOMColor.swim)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("클럽 소개")
            .accessibilityValue(club.description)

            SOOMCard {
                SOOMSectionHeader("태그")
                FlowTags(tags: club.tags, tint: SOOMColor.bike)
            }
            .accessibilityLabel("클럽 태그")

            SOOMCard {
                SOOMSectionHeader("예정 모임")
                ForEach(club.upcoming, id: \.self) { event in
                    Label(event, systemImage: SOOMIcon.calendar)
                }
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("예정 모임")
        }
        .navigationTitle("클럽 상세")
        .navigationBarTitleDisplayMode(.inline)
        .hidesSOOMTabBar()
    }
}

private extension WorkoutGrowthInput {
    init(detailWorkout workout: Workout) {
        self.init(
            id: workout.id,
            source: .soomLocal,
            workoutType: UnifiedWorkoutType(detailSport: workout.sport),
            startDate: workout.date,
            durationMinutes: Int(workout.duration / 60),
            distanceKm: workout.distanceMeters > 0 ? workout.distanceMeters / 1_000 : nil,
            averagePaceText: workout.sport == .run ? workout.formattedPace : nil,
            averageSpeedKmh: workout.duration > 0 ? (workout.distanceMeters / 1_000) / (workout.duration / 3_600) : nil,
            averageHeartRate: Double(workout.avgHeartRate),
            elevationGainMeters: Double(workout.elevationGain),
            activeEnergyKcal: Double(workout.activeCalories)
        )
    }
}

private extension UnifiedWorkoutType {
    init(detailSport sport: WorkoutSport) {
        switch sport {
        case .swim:
            self = .swimming
        case .bike, .brick:
            self = .cycling
        case .run:
            self = .running
        }
    }
}
