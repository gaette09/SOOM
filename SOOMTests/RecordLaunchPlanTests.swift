import XCTest
@testable import SOOM

final class RecordLaunchPlanTests: XCTestCase {
    func testMockPlanStartsWithCyclingWithoutRequestingLocationPermission() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.defaultSport, .cycling)
        XCTAssertTrue(plan.usesMapboxWhenConfigured)
        XCTAssertFalse(plan.requiresLocationPermissionOnEntry)
        XCTAssertGreaterThanOrEqual(plan.route.coordinates.count, 2)
    }

    func testSportStartTitlesFollowSelectedSport() {
        XCTAssertEqual(RecordSportMode.cycling.startTitle, "라이딩 시작")
        XCTAssertEqual(RecordSportMode.running.startTitle, "러닝 시작")
        XCTAssertEqual(RecordSportMode.walking.startTitle, "걷기 시작")
    }

    func testRecommendationCopyChangesBySport() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.subtitle(for: .cycling).contains("라이딩"))
        XCTAssertTrue(recommendation.subtitle(for: .running).contains("조깅"))
        XCTAssertTrue(recommendation.subtitle(for: .walking).contains("걷기"))
    }

    func testRecordLaunchPlanDoesNotUseRecoveryCalculator() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.recommendation.recoveryLabel, "회복 82 · 좋음")
        XCTAssertFalse(plan.route.title.isEmpty)
    }
}
