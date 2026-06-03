import XCTest
@testable import SOOM

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: TrainingSettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "SettingsViewModelTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = TrainingSettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testValidMaxHeartRateIsSaved() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.maxHeartRateText = "187"

        XCTAssertTrue(viewModel.saveMaxHeartRate())
        XCTAssertEqual(viewModel.settings.maxHeartRate, 187)
        XCTAssertEqual(store.loadSettings().maxHeartRate, 187)
    }

    func testInvalidMaxHeartRateIsRejected() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.maxHeartRateText = "260"

        XCTAssertFalse(viewModel.saveMaxHeartRate())
        XCTAssertNil(store.loadSettings().maxHeartRate)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testValidCyclingFTPIsSaved() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.cyclingFTPText = "255"

        XCTAssertTrue(viewModel.saveCyclingFTP())
        XCTAssertEqual(viewModel.settings.cyclingFTP, 255)
        XCTAssertEqual(store.loadSettings().cyclingFTP, 255)
    }

    func testInvalidCyclingFTPIsRejected() {
        let viewModel = SettingsViewModel(store: store)
        viewModel.cyclingFTPText = "20"

        XCTAssertFalse(viewModel.saveCyclingFTP())
        XCTAssertNil(store.loadSettings().cyclingFTP)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testPrivacyDefaultIsSaved() {
        let viewModel = SettingsViewModel(store: store)

        viewModel.updatePrivacyDefault(.followers)

        XCTAssertEqual(viewModel.settings.privacyDefault, .followers)
        XCTAssertEqual(store.loadSettings().privacyDefault, .followers)
    }

    func testViewModelDoesNotUseRecoveryCalculator() {
        let viewModel = SettingsViewModel(store: store)

        viewModel.updatePreferredUnit(.imperial)
        viewModel.updatePrivacyDefault(.privateOnly)

        XCTAssertEqual(viewModel.settings.preferredUnit, .imperial)
        XCTAssertEqual(viewModel.settings.privacyDefault, .privateOnly)
    }

    func testProfileHeroExposesMovementIdentity() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertTrue(ProfileIdentitySystem.heroIdentityPhraseIsPrimary)
        XCTAssertEqual(identity.hero.identityTitle, "리듬을 지키는 라이더")
        XCTAssertTrue(identity.hero.identityTitle.contains("리듬"))
        XCTAssertEqual(identity.hero.representativeSport, "자전거 중심")
        XCTAssertFalse(identity.hero.activeDays.isEmpty)
        XCTAssertFalse(identity.hero.totalDistance.isEmpty)
        XCTAssertFalse(identity.hero.monthlyState.isEmpty)
    }

    func testProfileHeroIncludesOneRepresentativeBadge() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertEqual(ProfileIdentitySystem.heroRepresentativeBadgeCount, 1)
        XCTAssertEqual(identity.hero.representativeBadgeID, "thirty-days")
        XCTAssertEqual(identity.representativeBadge?.title, "30일 리듬")
        XCTAssertEqual(identity.representativeBadge?.subtitle, "꾸준함")
        XCTAssertEqual(identity.representativeBadge?.state, "획득")
    }

    func testProfileHeroStatsAreCompactAndSecondary() {
        let identity = ProfileIdentitySystem.foundation
        let compactStats = identity.compactHeroStats

        XCTAssertTrue(ProfileIdentitySystem.heroStatsAreSecondary)
        XCTAssertEqual(compactStats.count, 3)
        XCTAssertEqual(compactStats.map(\.title), ["움직인 날", "누적 거리", "대표 종목"])
        XCTAssertEqual(compactStats.map(\.value), ["128일 활동", "1,240km", "자전거 중심"])
        XCTAssertFalse(compactStats.contains { $0.value == identity.hero.monthlyState })
    }

    func testProfileDoesNotShowRecentWorkoutList() {
        XCTAssertTrue(ProfileIdentitySystem.profileDoesNotShowRecentWorkoutList)

        let identity = ProfileIdentitySystem.foundation
        let identityText = [
            identity.hero.identityTitle,
            identity.emptyStateCopy
        ] + identity.personalBests.map(\.title) + identity.signatureRoutes.map(\.title)

        XCTAssertFalse(identityText.contains { $0.localizedCaseInsensitiveContains("최근 운동") })
    }

    func testProfilePersonalBestShowcaseIsLimitedToThreeItems() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertLessThanOrEqual(identity.personalBests.count, ProfileIdentitySystem.maxPersonalBestCount)
        XCTAssertEqual(identity.personalBests.count, 3)
        XCTAssertTrue(identity.personalBests.allSatisfy { !$0.value.isEmpty && !$0.context.isEmpty })
    }

    func testProfileBadgeShowcaseAndSignatureRoutesExist() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertGreaterThanOrEqual(identity.badges.count, 3)
        XCTAssertLessThanOrEqual(identity.badges.count, 4)
        XCTAssertTrue(identity.badges.contains { $0.state == "진행중" })
        XCTAssertTrue(identity.badges.contains { $0.isRare })
        XCTAssertEqual(identity.signatureRoutes.map(\.marker), ["대표 코스", "회복 루프", "도전 지점"])
    }

    func testProfileConnectionsAreSupportAreaNotTopHero() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertTrue(ProfileIdentitySystem.connectionsAreSupportArea)
        XCTAssertEqual(identity.connections.first?.id, "healthkit")
        XCTAssertTrue(identity.connections.contains { $0.title == "Strava" && $0.state == .future })
        XCTAssertTrue(identity.connections.contains { $0.title == "Garmin" && $0.state == .future })
    }

    func testProfileEmptyStateCopySupportsNewUsers() {
        let identity = ProfileIdentitySystem.foundation

        XCTAssertTrue(identity.emptyStateCopy.contains("운동 리듬"))
        XCTAssertTrue(identity.emptyStateCopy.contains("첫 운동"))
    }

    func testProfileAggregateTotalsIgnoreNilDistanceButCountDurationAndActiveDays() {
        let aggregator = makeAggregator()
        let workouts = [
            workout(type: .running, daysAgo: 1, hour: 7, duration: 1_800, distance: 5_000),
            workout(type: .running, daysAgo: 1, hour: 18, duration: 1_200, distance: nil),
            workout(type: .walking, daysAgo: 3, hour: 9, duration: 900, distance: 1_000)
        ]

        let aggregate = aggregator.aggregate(workouts)

        XCTAssertEqual(aggregate.totalDistanceMeters, 6_000)
        XCTAssertEqual(aggregate.totalDurationSeconds, 3_900)
        XCTAssertEqual(aggregate.workoutCount, 3)
        XCTAssertEqual(aggregate.activeDays, 2)
    }

    func testProfileAggregateCalculatesPrimarySportRecentStatsAndBests() {
        let aggregator = makeAggregator()
        let workouts = [
            workout(type: .cycling, daysAgo: 1, hour: 7, duration: 3_600, distance: 42_000),
            workout(type: .cycling, daysAgo: 3, hour: 8, duration: 4_200, distance: 58_000),
            workout(type: .running, daysAgo: 2, hour: 18, duration: 2_400, distance: 10_000),
            workout(type: .walking, daysAgo: 120, hour: 10, duration: 1_200, distance: 3_000)
        ]

        let aggregate = aggregator.aggregate(workouts)

        XCTAssertEqual(aggregate.primarySport, .cycling)
        XCTAssertEqual(aggregate.recent90DayWorkoutCount, 3)
        XCTAssertEqual(aggregate.recent90DayDistanceMeters, 110_000)
        XCTAssertEqual(aggregate.longestRideDistance, 58_000)
        XCTAssertEqual(aggregate.longestRunDistance, 10_000)
        XCTAssertEqual(aggregate.longestWalkDistance, 3_000)
        XCTAssertEqual(aggregate.bestWeeklyDistance, 110_000)
    }

    func testProfileIdentityPhraseChangesByDominantSport() {
        let aggregator = makeAggregator()
        let cyclingIdentity = aggregator.profileIdentity(from: (0..<16).map {
            workout(type: .cycling, daysAgo: $0, hour: 7, duration: 3_600, distance: 30_000)
        })
        let runningIdentity = aggregator.profileIdentity(from: (0..<16).map {
            workout(type: .running, daysAgo: $0, hour: 7, duration: 1_800, distance: 8_000)
        })

        XCTAssertEqual(cyclingIdentity.hero.identityTitle, "리듬을 지키는 라이더")
        XCTAssertEqual(cyclingIdentity.hero.representativeSport, "자전거 중심")
        XCTAssertEqual(runningIdentity.hero.identityTitle, "꾸준함을 쌓는 러너")
        XCTAssertEqual(runningIdentity.hero.representativeSport, "러닝 중심")
    }

    func testProfileEmptyAggregateReturnsStarterIdentity() {
        let identity = makeAggregator().profileIdentity(from: [])

        XCTAssertEqual(identity.hero.identityTitle, "아직 나의 운동 리듬을 만드는 중")
        XCTAssertEqual(identity.compactHeroStats.map(\.value), ["0일", "0km", "시작 전"])
        XCTAssertTrue(identity.personalBests.allSatisfy { $0.value == "기록 준비 중" })
        XCTAssertEqual(identity.representativeBadge?.title, "첫 기록")
    }

    func testProfileHeroPersonalBestAndBadgesUseAggregateValues() {
        let identity = makeAggregator().profileIdentity(from: [
            workout(type: .cycling, daysAgo: 0, hour: 7, duration: 3_600, distance: 42_000),
            workout(type: .running, daysAgo: 1, hour: 8, duration: 2_000, distance: 9_200),
            workout(type: .walking, daysAgo: 2, hour: 9, duration: 1_200, distance: 2_400)
        ])

        XCTAssertEqual(identity.compactHeroStats.map(\.title), ["움직인 날", "누적 거리", "대표 종목"])
        XCTAssertEqual(identity.compactHeroStats.map(\.value), ["3일 움직임", "53.6km", "자전거 중심"])
        XCTAssertEqual(identity.personalBests.map(\.value), ["42.0km", "9.2km", "53.6km"])
        XCTAssertEqual(identity.badges.first { $0.id == "first-workout" }?.state, "획득")
        XCTAssertEqual(identity.badges.first { $0.id == "thirty-days" }?.state, "진행중")
    }

    func testProfileAggregationKeepsActivityBoundary() {
        let identity = makeAggregator().profileIdentity(from: [
            workout(type: .cycling, daysAgo: 1, hour: 7, duration: 3_600, distance: 42_000)
        ])
        let identityText = [
            identity.hero.identityTitle,
            identity.emptyStateCopy
        ] + identity.personalBests.map(\.title) + identity.signatureRoutes.map(\.title)

        XCTAssertTrue(ProfileIdentitySystem.profileDoesNotShowRecentWorkoutList)
        XCTAssertFalse(identityText.contains { $0.localizedCaseInsensitiveContains("최근 운동") })
    }

    private func makeAggregator() -> ProfileWorkoutAggregator {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ProfileWorkoutAggregator(
            calendar: calendar,
            referenceDate: date(year: 2026, month: 6, day: 3, hour: 12)
        )
    }

    private func workout(
        type: UnifiedWorkoutType,
        daysAgo: Int,
        hour: Int,
        duration: TimeInterval,
        distance: Double?
    ) -> UnifiedWorkout {
        let start = makeAggregator().calendar.date(
            byAdding: .day,
            value: -daysAgo,
            to: date(year: 2026, month: 6, day: 3, hour: hour)
        )!

        return UnifiedWorkout(
            id: UUID(),
            externalId: nil,
            source: .soomLocal,
            workoutType: type,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            durationSeconds: duration,
            distanceMeters: distance,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            dataQuality: .partial,
            createdAt: start,
            updatedAt: start
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
