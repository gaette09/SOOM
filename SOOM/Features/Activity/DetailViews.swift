import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    var comparisonWorkouts: [Workout] = []

    var body: some View {
        Group {
            if workout.route.isEmpty {
                SOOMScreen {
                    WorkoutDetailContent(
                        workout: workout,
                        showsHeader: true,
                        sessionSummary: sessionSummary,
                        growthSummary: growthSummary,
                        weaknessInsight: weaknessInsight,
                        recoveryImpact: recoveryImpact,
                        shareableCard: shareableCard
                    )
                }
                .navigationTitle("운동 상세")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                WorkoutMapSheetScaffold(workout: workout, navigationTitle: "운동 상세") {
                    WorkoutDetailContent(
                        workout: workout,
                        showsHeader: true,
                        sessionSummary: sessionSummary,
                        growthSummary: growthSummary,
                        weaknessInsight: weaknessInsight,
                        recoveryImpact: recoveryImpact,
                        shareableCard: shareableCard
                    )
                }
            }
        }
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
