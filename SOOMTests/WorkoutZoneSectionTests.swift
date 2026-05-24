import XCTest
import SwiftUI
@testable import SOOM

final class WorkoutZoneSectionTests: XCTestCase {
    func testRunningZoneConfigurationPrioritizesHeartRateAndCadence() {
        let workout = harnessWorkout(.run)

        let summaries = WorkoutZoneSection.makeSummaries(for: workout)

        XCTAssertEqual(summaries.map(\.type), [.heartRate, .cadence])
        XCTAssertTrue(summaries.first(where: { $0.type == .heartRate })?.isAvailable == true)
        XCTAssertTrue(summaries.first(where: { $0.type == .cadence })?.isAvailable == true)
        XCTAssertTrue(summaries.allSatisfy { $0.dataSource.sourceType == .fallbackEstimate })
        XCTAssertFalse(summaries.contains { $0.type == .power })
    }

    func testCyclingZoneConfigurationIncludesHeartRateCadenceAndPower() {
        let workout = harnessWorkout(.bike)

        let summaries = WorkoutZoneSection.makeSummaries(for: workout)

        XCTAssertEqual(summaries.map(\.type), [.heartRate, .cadence, .power])
        XCTAssertTrue(summaries.allSatisfy { $0.isAvailable })
        XCTAssertEqual(summaries.first(where: { $0.type == .power })?.dominantZone?.zoneIndex, 3)
    }

    func testCyclingPowerUnavailableFallbackIsVisible() {
        let workout = makeWorkout(sport: .bike, cadence: 86, avgPower: nil)

        let summaries = WorkoutZoneSection.makeSummaries(for: workout)
        let visible = WorkoutZoneSection(sport: .bike, summaries: summaries).visibleSummaries
        let power = visible.first { $0.type == .power }

        XCTAssertNotNil(power)
        XCTAssertFalse(power?.isAvailable == true)
        XCTAssertEqual(power?.dataSource.sourceType, .unavailable)
        XCTAssertTrue(power?.insightText?.contains("파워존") == true || power?.insightText?.contains("FTP") == true)
    }

    func testFallbackSummaryUsesFallbackEstimateSource() {
        let workout = harnessWorkout(.run)

        let summaries = WorkoutZoneSection.makeSummaries(for: workout)

        XCTAssertTrue(summaries.filter(\.isAvailable).allSatisfy { $0.dataSource.sourceType == .fallbackEstimate })
    }

    func testSwimmingUsesHeartRateOnlyWhenAvailable() {
        let workout = harnessWorkout(.swim)

        let summaries = WorkoutZoneSection.makeSummaries(for: workout)

        XCTAssertEqual(summaries.map(\.type), [.heartRate])
        XCTAssertTrue(summaries[0].isAvailable)
    }

    func testDominantZoneIsPreservedForDisplay() {
        let workout = harnessWorkout(.run)

        let heartRate = WorkoutZoneSection.makeSummaries(for: workout).first { $0.type == .heartRate }

        XCTAssertEqual(heartRate?.dominantZone?.zoneIndex, 2)
        XCTAssertTrue(heartRate?.insightText?.contains("Zone 2") == true)
    }

    func testZoneCopyAvoidsNegativeTone() {
        let workout = harnessWorkout(.bike)
        let summaries = WorkoutZoneSection.makeSummaries(for: workout)
        let copy = summaries.compactMap(\.insightText).joined(separator: " ")

        ["못", "나쁨", "실패", "위험", "부족"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Unexpected negative wording: \(word)")
        }
    }

    private func harnessWorkout(_ sport: WorkoutSport) -> Workout {
        MockWorkoutHarness().loadWorkouts().first { $0.sport == sport }!
    }

    private func makeWorkout(
        sport: WorkoutSport,
        cadence: Int?,
        avgPower: Int?
    ) -> Workout {
        Workout(
            id: UUID(),
            sport: sport,
            title: "Zone Test",
            date: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: 24_000,
            duration: 3_600,
            activeCalories: 500,
            avgHeartRate: 140,
            maxHeartRate: 166,
            avgPower: avgPower,
            elevationGain: 120,
            cadence: cadence,
            effort: 5,
            source: "Test",
            route: [],
            splits: [],
            samples: [],
            zones: [
                HeartRateZone(name: "Z1 회복", minutes: 10, tint: SOOMColor.recovery),
                HeartRateZone(name: "Z2 유산소", minutes: 35, tint: SOOMColor.bike),
                HeartRateZone(name: "Z3 템포", minutes: 15, tint: SOOMColor.warning)
            ],
            achievements: [],
            aiSummary: "테스트 운동"
        )
    }
}
