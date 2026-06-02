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
}
