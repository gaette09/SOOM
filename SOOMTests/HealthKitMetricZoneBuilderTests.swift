import XCTest
@testable import SOOM

final class HealthKitMetricZoneBuilderTests: XCTestCase {
    private let builder = HealthKitMetricZoneBuilder()

    func testBuildsHeartRateZoneSummary() {
        let samples = [
            makeSample(.heartRate, value: 110, start: 0, end: 60),
            makeSample(.heartRate, value: 130, start: 60, end: 180),
            makeSample(.heartRate, value: 170, start: 180, end: 240)
        ]

        let summary = builder.buildHeartRateSummary(from: samples, maxHeartRate: 190)

        XCTAssertEqual(summary.type, .heartRate)
        XCTAssertEqual(summary.zones.count, 3)
        XCTAssertEqual(summary.dominantZone?.zoneIndex, 2)
        XCTAssertTrue(summary.insightText?.contains("Zone 2") == true)
        XCTAssertEqual(summary.dataSource.sourceType, .healthKitStream)
        XCTAssertFalse(summary.isPersonalized)
        XCTAssertNil(summary.baselineDescription)
    }

    func testPersonalizedHeartRateZoneUsesMaxHeartRateBaseline() {
        let samples = [
            makeSample(.heartRate, value: 118, start: 0, end: 60),
            makeSample(.heartRate, value: 130, start: 60, end: 180),
            makeSample(.heartRate, value: 185, start: 180, end: 240)
        ]
        let baseline = PersonalizedZoneBaseline(maxHeartRate: 200)

        let summary = builder.buildHeartRateSummary(from: samples, baseline: baseline)

        XCTAssertEqual(summary.zones.map(\.zoneIndex), [1, 2, 5])
        XCTAssertEqual(summary.dominantZone?.zoneIndex, 2)
        XCTAssertTrue(summary.isPersonalized)
        XCTAssertEqual(summary.baselineDescription, "최대심박 기준")
    }

    func testFallbackHeartRateZoneUsesGenericBaselineWithoutPersonalizedBadge() {
        let samples = [makeSample(.heartRate, value: 130, start: 0, end: 120)]

        let summary = builder.buildHeartRateSummary(from: samples)

        XCTAssertEqual(summary.dominantZone?.zoneIndex, 2)
        XCTAssertFalse(summary.isPersonalized)
        XCTAssertNil(summary.baselineDescription)
    }

    func testBuildsCadenceZoneSummary() {
        let samples = [
            makeSample(.cyclingCadence, value: 65, start: 0, end: 30),
            makeSample(.cyclingCadence, value: 88, start: 30, end: 150),
            makeSample(.cyclingCadence, value: 102, start: 150, end: 210)
        ]

        let summary = builder.buildCyclingCadenceSummary(from: samples)

        XCTAssertEqual(summary.type, .cadence)
        XCTAssertEqual(summary.zones.count, 3)
        XCTAssertEqual(summary.dominantZone?.zoneIndex, 2)
        XCTAssertTrue(summary.insightText?.contains("안정적인 케이던스") == true)
        XCTAssertEqual(summary.dataSource.sourceType, .healthKitStream)
    }

    func testPowerWithoutFTPReturnsUnavailableSummary() {
        let samples = [makeSample(.cyclingPower, value: 240, start: 0, end: 120)]

        let summary = builder.buildCyclingPowerSummary(from: samples, ftp: nil)

        XCTAssertEqual(summary.type, .power)
        XCTAssertFalse(summary.isAvailable)
        XCTAssertTrue(summary.zones.isEmpty)
        XCTAssertTrue(summary.insightText?.contains("FTP") == true)
        XCTAssertEqual(summary.dataSource.sourceType, .unavailable)
        XCTAssertFalse(summary.isPersonalized)
    }

    func testPowerWithFTPBuildsFutureReadySummary() {
        let samples = [
            makeSample(.cyclingPower, value: 120, start: 0, end: 60),
            makeSample(.cyclingPower, value: 240, start: 60, end: 180),
            makeSample(.cyclingPower, value: 330, start: 180, end: 240)
        ]

        let summary = builder.buildCyclingPowerSummary(from: samples, ftp: 250)

        XCTAssertEqual(summary.type, .power)
        XCTAssertTrue(summary.isAvailable)
        XCTAssertEqual(summary.dominantZone?.zoneIndex, 4)
        XCTAssertEqual(summary.dataSource.sourceType, .healthKitStream)
        XCTAssertFalse(summary.isPersonalized)
    }

    func testPersonalizedPowerZoneUsesFTPBaseline() {
        let samples = [
            makeSample(.cyclingPower, value: 120, start: 0, end: 60),
            makeSample(.cyclingPower, value: 240, start: 60, end: 180),
            makeSample(.cyclingPower, value: 330, start: 180, end: 240)
        ]
        let baseline = PersonalizedZoneBaseline(cyclingFTP: 250)

        let summary = builder.buildCyclingPowerSummary(from: samples, baseline: baseline)

        XCTAssertEqual(summary.zones.map(\.zoneIndex), [1, 4, 6])
        XCTAssertEqual(summary.dominantZone?.zoneIndex, 4)
        XCTAssertTrue(summary.isPersonalized)
        XCTAssertEqual(summary.baselineDescription, "FTP 기준")
        XCTAssertEqual(summary.zones[1].percentage, 50, accuracy: 0.001)
    }

    func testEmptySamplesReturnUnavailableSafely() {
        let heartRate = builder.buildHeartRateSummary(from: [])
        let cadence = builder.buildCyclingCadenceSummary(from: [])
        let power = builder.buildCyclingPowerSummary(from: [])

        XCTAssertFalse(heartRate.isAvailable)
        XCTAssertFalse(cadence.isAvailable)
        XCTAssertFalse(power.isAvailable)
        XCTAssertEqual(heartRate.dataSource.sourceType, .unavailable)
        XCTAssertEqual(cadence.dataSource.sourceType, .unavailable)
        XCTAssertEqual(power.dataSource.sourceType, .unavailable)
    }

    func testZoneCopyAvoidsNegativeTone() {
        let summaries = [
            builder.buildHeartRateSummary(from: [makeSample(.heartRate, value: 140, start: 0, end: 60)]),
            builder.buildCyclingCadenceSummary(from: [makeSample(.cyclingCadence, value: 88, start: 0, end: 60)]),
            builder.buildCyclingPowerSummary(from: [makeSample(.cyclingPower, value: 200, start: 0, end: 60)], ftp: nil)
        ]
        let copy = summaries.compactMap(\.insightText).joined(separator: " ")

        ["못", "나쁨", "실패", "위험", "부족"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Unexpected negative wording: \(word)")
        }
    }

    func testSourceIndicatorCopyAvoidsAlarmTone() {
        let sources: [WorkoutZoneDataSource] = [.healthKitStream, .fallbackEstimate, .unavailable]
        let copy = sources.map { "\($0.label) \($0.description)" }.joined(separator: " ")

        ["위험", "오류", "실패", "문제"].forEach { word in
            XCTAssertFalse(copy.contains(word), "Unexpected source wording: \(word)")
        }
    }

    private func makeSample(
        _ type: HealthKitWorkoutMetricSampleType,
        value: Double,
        start: TimeInterval,
        end: TimeInterval
    ) -> HealthKitWorkoutMetricSample {
        HealthKitWorkoutMetricSample(
            sampleType: type,
            value: value,
            unit: type == .cyclingPower ? "watt" : "count/min",
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: end)
        )
    }
}
