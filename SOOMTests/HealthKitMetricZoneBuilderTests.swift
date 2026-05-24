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
    }

    func testPowerWithoutFTPReturnsUnavailableSummary() {
        let samples = [makeSample(.cyclingPower, value: 240, start: 0, end: 120)]

        let summary = builder.buildCyclingPowerSummary(from: samples, ftp: nil)

        XCTAssertEqual(summary.type, .power)
        XCTAssertFalse(summary.isAvailable)
        XCTAssertTrue(summary.zones.isEmpty)
        XCTAssertTrue(summary.insightText?.contains("FTP") == true)
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
    }

    func testEmptySamplesReturnUnavailableSafely() {
        let heartRate = builder.buildHeartRateSummary(from: [])
        let cadence = builder.buildCyclingCadenceSummary(from: [])
        let power = builder.buildCyclingPowerSummary(from: [])

        XCTAssertFalse(heartRate.isAvailable)
        XCTAssertFalse(cadence.isAvailable)
        XCTAssertFalse(power.isAvailable)
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
