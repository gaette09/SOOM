import Foundation

struct ProfileWorkoutAggregate: Equatable {
    let totalDistanceMeters: Double
    let totalDurationSeconds: TimeInterval
    let activeDays: Int
    let workoutCount: Int
    let primarySport: UnifiedWorkoutType?
    let sportDistribution: [UnifiedWorkoutType: Int]
    let recent90DayWorkoutCount: Int
    let recent90DayDistanceMeters: Double
    let longestRideDistance: Double?
    let longestRunDistance: Double?
    let longestWalkDistance: Double?
    let bestWeeklyDistance: Double?
    let consistencyScore: Double
    let morningWorkoutRatio: Double
    let weekendLongRatio: Double
    let recoveryFriendlyRatio: Double?

    static let empty = ProfileWorkoutAggregate(
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        activeDays: 0,
        workoutCount: 0,
        primarySport: nil,
        sportDistribution: [:],
        recent90DayWorkoutCount: 0,
        recent90DayDistanceMeters: 0,
        longestRideDistance: nil,
        longestRunDistance: nil,
        longestWalkDistance: nil,
        bestWeeklyDistance: nil,
        consistencyScore: 0,
        morningWorkoutRatio: 0,
        weekendLongRatio: 0,
        recoveryFriendlyRatio: nil
    )
}

struct ProfileMovementIdentity: Equatable {
    let phrase: String
    let representativeSportText: String
}

struct ProfilePersonalBest: Equatable {
    let title: String
    let value: String
    let context: String
    let icon: String
}

struct ProfileMovementPattern: Equatable {
    let title: String
    let subtitle: String
    let icon: String
    let isPrimary: Bool
}

struct ProfileWorkoutAggregator {
    var calendar: Calendar = .current
    var referenceDate: Date = Date()

    func aggregate(_ workouts: [UnifiedWorkout]) -> ProfileWorkoutAggregate {
        let includedWorkouts = workouts.filter { !$0.isExcludedFromAnalysis }
        guard !includedWorkouts.isEmpty else {
            return .empty
        }

        let totalDistance = includedWorkouts.compactMap(\.distanceMeters).reduce(0, +)
        let totalDuration = includedWorkouts.map(\.durationSeconds).reduce(0, +)
        let activeDayStarts = Set(includedWorkouts.map { calendar.startOfDay(for: $0.startDate) })
        let sportDistribution = Dictionary(grouping: includedWorkouts, by: \.workoutType)
            .mapValues(\.count)
        let distanceBySport = includedWorkouts.reduce(into: [UnifiedWorkoutType: Double]()) { result, workout in
            result[workout.workoutType, default: 0] += workout.distanceMeters ?? 0
        }
        let primarySport = primarySport(
            sportDistribution: sportDistribution,
            distanceBySport: distanceBySport,
            totalDistance: totalDistance
        )
        let recentThreshold = calendar.date(byAdding: .day, value: -90, to: referenceDate) ?? referenceDate
        let recentWorkouts = includedWorkouts.filter { $0.startDate >= recentThreshold }

        return ProfileWorkoutAggregate(
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: totalDuration,
            activeDays: activeDayStarts.count,
            workoutCount: includedWorkouts.count,
            primarySport: primarySport,
            sportDistribution: sportDistribution,
            recent90DayWorkoutCount: recentWorkouts.count,
            recent90DayDistanceMeters: recentWorkouts.compactMap(\.distanceMeters).reduce(0, +),
            longestRideDistance: longestDistance(in: includedWorkouts, type: .cycling),
            longestRunDistance: longestDistance(in: includedWorkouts, type: .running),
            longestWalkDistance: longestDistance(in: includedWorkouts, type: .walking),
            bestWeeklyDistance: bestWeeklyDistance(in: includedWorkouts),
            consistencyScore: min(1, Double(activeDayStarts.count) / 30),
            morningWorkoutRatio: ratio(in: includedWorkouts) { workout in
                let hour = calendar.component(.hour, from: workout.startDate)
                return (5..<12).contains(hour)
            },
            weekendLongRatio: ratio(in: includedWorkouts) { workout in
                let isWeekend = calendar.isDateInWeekend(workout.startDate)
                let isLong = (workout.distanceMeters ?? 0) >= 20_000 || workout.durationSeconds >= 3_600
                return isWeekend && isLong
            },
            recoveryFriendlyRatio: nil
        )
    }

    func identity(from aggregate: ProfileWorkoutAggregate) -> ProfileMovementIdentity {
        guard aggregate.workoutCount > 0, let primarySport = aggregate.primarySport else {
            return ProfileMovementIdentity(
                phrase: "아직 나의 운동 리듬을 만드는 중",
                representativeSportText: "시작 전"
            )
        }

        if isMixedSportIdentity(aggregate) {
            return ProfileMovementIdentity(
                phrase: "여러 리듬을 이어가는 무버",
                representativeSportText: "멀티 스포츠"
            )
        }

        switch primarySport {
        case .cycling:
            return ProfileMovementIdentity(
                phrase: aggregate.consistencyScore >= 0.5 ? "리듬을 지키는 라이더" : "리듬을 찾아가는 라이더",
                representativeSportText: "자전거 중심"
            )
        case .running:
            return ProfileMovementIdentity(
                phrase: aggregate.consistencyScore >= 0.5 ? "꾸준함을 쌓는 러너" : "호흡을 맞추는 러너",
                representativeSportText: "러닝 중심"
            )
        case .walking:
            return ProfileMovementIdentity(
                phrase: "몸의 리듬을 만드는 워커",
                representativeSportText: "걷기 중심"
            )
        default:
            return ProfileMovementIdentity(
                phrase: "나만의 기준을 쌓는 무버",
                representativeSportText: primarySport.profileTitle
            )
        }
    }

    func movementPatterns(from aggregate: ProfileWorkoutAggregate) -> [ProfileMovementPattern] {
        guard aggregate.workoutCount > 0 else {
            return [
                ProfileMovementPattern(title: "리듬 준비 중", subtitle: "첫 기록을 쌓으면 성향이 생겨요", icon: SOOMIcon.sparkles, isPrimary: true),
                ProfileMovementPattern(title: "기록 시작 전", subtitle: "Activity는 기록, Profile은 정체성을 보여줘요", icon: SOOMIcon.profile, isPrimary: false)
            ]
        }

        var patterns: [ProfileMovementPattern] = []
        if aggregate.morningWorkoutRatio >= 0.5 {
            patterns.append(ProfileMovementPattern(title: "아침형", subtitle: "하루를 먼저 깨우는 편", icon: "sunrise.fill", isPrimary: true))
        }
        if aggregate.consistencyScore >= 0.5 {
            patterns.append(ProfileMovementPattern(title: "꾸준함 중심", subtitle: "긴 공백보다 유지에 가까움", icon: SOOMIcon.calendarClock, isPrimary: true))
        }
        if aggregate.weekendLongRatio >= 0.25 {
            patterns.append(ProfileMovementPattern(title: "주말 장거리형", subtitle: "주말에 길게 리듬을 쌓음", icon: SOOMIcon.map, isPrimary: patterns.isEmpty))
        }
        if aggregate.primarySport == .cycling {
            patterns.append(ProfileMovementPattern(title: "라이딩 중심", subtitle: "거리 위에서 기준을 쌓음", icon: SOOMIcon.bike, isPrimary: patterns.isEmpty))
        } else if aggregate.primarySport == .running {
            patterns.append(ProfileMovementPattern(title: "러닝 중심", subtitle: "호흡과 페이스를 이어감", icon: SOOMIcon.run, isPrimary: patterns.isEmpty))
        } else if aggregate.primarySport == .walking {
            patterns.append(ProfileMovementPattern(title: "걷기 중심", subtitle: "몸의 리듬을 부드럽게 만듦", icon: "figure.walk", isPrimary: patterns.isEmpty))
        }

        patterns.append(ProfileMovementPattern(title: "회복 친화형", subtitle: "무리보다 지속을 먼저 둠", icon: "leaf.fill", isPrimary: patterns.isEmpty))
        return Array(patterns.prefix(4))
    }

    func personalBests(from aggregate: ProfileWorkoutAggregate) -> [ProfilePersonalBest] {
        guard aggregate.workoutCount > 0 else {
            return [
                ProfilePersonalBest(title: "최장 라이딩", value: "기록 준비 중", context: "첫 라이딩을 기록해보세요", icon: SOOMIcon.bike),
                ProfilePersonalBest(title: "최장 러닝", value: "기록 준비 중", context: "첫 러닝을 기록해보세요", icon: SOOMIcon.run),
                ProfilePersonalBest(title: "최고 주간 거리", value: "기록 준비 중", context: "한 주의 리듬을 기다리는 중", icon: SOOMIcon.trend)
            ]
        }

        return [
            ProfilePersonalBest(title: "최장 라이딩", value: distanceText(aggregate.longestRideDistance), context: aggregate.longestRideDistance == nil ? "첫 라이딩을 기록해보세요" : "한 번에 이어간 거리", icon: SOOMIcon.bike),
            ProfilePersonalBest(title: "최장 러닝", value: distanceText(aggregate.longestRunDistance), context: aggregate.longestRunDistance == nil ? "첫 러닝을 기록해보세요" : "호흡을 이어간 거리", icon: SOOMIcon.run),
            ProfilePersonalBest(title: "최고 주간 거리", value: distanceText(aggregate.bestWeeklyDistance), context: aggregate.bestWeeklyDistance == nil ? "거리 기록을 기다리는 중" : "가장 길게 쌓은 한 주", icon: SOOMIcon.trend)
        ]
    }

    func profileIdentity(from workouts: [UnifiedWorkout]) -> ProfileIdentitySystem {
        let aggregate = aggregate(workouts)
        let movementIdentity = identity(from: aggregate)
        let personalBests = personalBests(from: aggregate)
        let patterns = movementPatterns(from: aggregate)

        return ProfileIdentitySystem(
            hero: ProfileIdentitySystem.Hero(
                identityTitle: movementIdentity.phrase,
                representativeBadgeID: representativeBadgeID(for: aggregate),
                representativeSport: representativeSportStatText(for: aggregate),
                activeDays: aggregate.activeDays > 0 ? "\(aggregate.activeDays)일 움직임" : "0일",
                totalDistance: distanceText(aggregate.totalDistanceMeters),
                monthlyState: aggregate.recent90DayWorkoutCount > 0 ? "최근 90일 \(aggregate.recent90DayWorkoutCount)회" : "리듬 준비 중"
            ),
            patterns: patterns.enumerated().map { index, pattern in
                ProfileIdentitySystem.MovementPattern(
                    id: "aggregate-pattern-\(index)",
                    title: pattern.title,
                    subtitle: pattern.subtitle,
                    icon: pattern.icon,
                    isPrimary: pattern.isPrimary
                )
            },
            personalBests: personalBests.prefix(ProfileIdentitySystem.maxPersonalBestCount).enumerated().map { index, best in
                ProfileIdentitySystem.PersonalBest(
                    id: "aggregate-pb-\(index)",
                    title: best.title,
                    value: best.value,
                    context: best.context,
                    icon: best.icon
                )
            },
            badges: badges(from: aggregate),
            signatureRoutes: ProfileIdentitySystem.foundation.signatureRoutes,
            connections: ProfileIdentitySystem.foundation.connections,
            emptyStateCopy: "아직 나의 운동 리듬을 만드는 중입니다. 첫 운동을 기록하면 대표 종목과 성향이 생겨요."
        )
    }

    private func representativeBadgeID(for aggregate: ProfileWorkoutAggregate) -> String {
        if aggregate.activeDays >= 30 { return "thirty-days" }
        if aggregate.totalDistanceMeters >= 1_000_000 { return "thousand-km" }
        if aggregate.workoutCount >= 1 { return "first-workout" }
        return "first-workout"
    }

    private func representativeSportStatText(for aggregate: ProfileWorkoutAggregate) -> String {
        guard let primarySport = aggregate.primarySport else { return "시작 전" }

        switch primarySport {
        case .cycling:
            return "자전거 중심"
        case .running:
            return "러닝 중심"
        case .walking:
            return "걷기 중심"
        default:
            return primarySport.profileTitle
        }
    }

    private func badges(from aggregate: ProfileWorkoutAggregate) -> [ProfileIdentitySystem.Badge] {
        let firstWorkoutEarned = aggregate.workoutCount >= 1
        let thirtyDaysProgress = min(1, Double(aggregate.activeDays) / 30)
        let thousandKmProgress = min(1, aggregate.totalDistanceMeters / 1_000_000)

        return [
            ProfileIdentitySystem.Badge(
                id: "first-workout",
                title: "첫 기록",
                subtitle: firstWorkoutEarned ? "리듬 시작" : "첫 기록을 기다리는 중",
                state: firstWorkoutEarned ? "획득" : "대기",
                progress: firstWorkoutEarned ? 1 : 0,
                isRare: false
            ),
            ProfileIdentitySystem.Badge(
                id: "thirty-days",
                title: "30일 리듬",
                subtitle: "\(aggregate.activeDays)/30일",
                state: aggregate.activeDays >= 30 ? "획득" : "진행중",
                progress: thirtyDaysProgress,
                isRare: false
            ),
            ProfileIdentitySystem.Badge(
                id: "thousand-km",
                title: "1000km",
                subtitle: "누적 거리",
                state: aggregate.totalDistanceMeters >= 1_000_000 ? "획득" : "진행중",
                progress: thousandKmProgress,
                isRare: false
            ),
            ProfileIdentitySystem.Badge(
                id: "club-contribution",
                title: "첫 클럽 기여",
                subtitle: "Club 연결 예정",
                state: aggregate.workoutCount > 0 ? "준비됨" : "대기",
                progress: aggregate.workoutCount > 0 ? 0.35 : 0,
                isRare: true
            )
        ]
    }

    private func primarySport(
        sportDistribution: [UnifiedWorkoutType: Int],
        distanceBySport: [UnifiedWorkoutType: Double],
        totalDistance: Double
    ) -> UnifiedWorkoutType? {
        if totalDistance > 0,
           let distanceWinner = distanceBySport.max(by: { $0.value < $1.value })?.key {
            return distanceWinner
        }

        return sportDistribution.max(by: { $0.value < $1.value })?.key
    }

    private func longestDistance(in workouts: [UnifiedWorkout], type: UnifiedWorkoutType) -> Double? {
        workouts
            .filter { $0.workoutType == type }
            .compactMap(\.distanceMeters)
            .max()
    }

    private func bestWeeklyDistance(in workouts: [UnifiedWorkout]) -> Double? {
        let distancesByWeek = workouts.reduce(into: [Date: Double]()) { result, workout in
            guard let distance = workout.distanceMeters,
                  let week = calendar.dateInterval(of: .weekOfYear, for: workout.startDate)?.start else {
                return
            }
            result[week, default: 0] += distance
        }

        return distancesByWeek.values.max()
    }

    private func ratio(in workouts: [UnifiedWorkout], matching predicate: (UnifiedWorkout) -> Bool) -> Double {
        guard !workouts.isEmpty else { return 0 }
        return Double(workouts.filter(predicate).count) / Double(workouts.count)
    }

    private func isMixedSportIdentity(_ aggregate: ProfileWorkoutAggregate) -> Bool {
        guard aggregate.workoutCount >= 3,
              let maxCount = aggregate.sportDistribution.values.max() else {
            return false
        }

        return Double(maxCount) / Double(aggregate.workoutCount) < 0.5
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters, meters > 0 else {
            return "기록 준비 중"
        }

        return distanceText(meters)
    }

    private func distanceText(_ meters: Double) -> String {
        guard meters > 0 else { return "0km" }
        let km = meters / 1_000
        if km >= 100 {
            return "\(Int(km.rounded()))km"
        }
        return String(format: "%.1fkm", km)
    }
}

extension UnifiedWorkoutType {
    fileprivate var profileTitle: String {
        switch self {
        case .running:
            return "러닝 중심"
        case .cycling:
            return "자전거 중심"
        case .walking:
            return "걷기 중심"
        case .swimming:
            return "수영 중심"
        case .hiking:
            return "하이킹 중심"
        case .strength:
            return "근력 중심"
        case .yoga:
            return "요가 중심"
        case .other:
            return "움직임 중심"
        }
    }
}
