import XCTest
@testable import SOOM

final class FitnessTrendCalculatorTests: XCTestCase {
    func testChronicLoadSeriesRampsUpFromZeroSeed() {
        let series = FitnessTrendCalculator.chronicLoadSeries(dailyLoads: [42, 42, 42])

        // Each step moves 1/42 of the way from the previous value toward the day's load.
        XCTAssertEqual(series[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(series[1], 1.0 + 41.0 / 42.0, accuracy: 0.001)
        XCTAssertTrue(series[2] > series[1])
    }

    func testChronicLoadSeriesConvergesTowardConstantLoad() {
        let dailyLoads = Array(repeating: 50.0, count: 200)
        let series = FitnessTrendCalculator.chronicLoadSeries(dailyLoads: dailyLoads)

        XCTAssertEqual(series.last ?? 0, 50, accuracy: 0.5)
    }

    func testChronicLoadSeriesDecaysDuringRestDays() {
        var dailyLoads = Array(repeating: 60.0, count: 100)
        dailyLoads.append(contentsOf: Array(repeating: 0.0, count: 14))
        let series = FitnessTrendCalculator.chronicLoadSeries(dailyLoads: dailyLoads)

        XCTAssertTrue(series.last! < series[99])
    }

    func testEmptyInputReturnsEmptySeries() {
        XCTAssertTrue(FitnessTrendCalculator.chronicLoadSeries(dailyLoads: []).isEmpty)
    }
}

final class FitnessTrendBuilderTests: XCTestCase {
    func testTooFewTrainingDaysReturnsNil() {
        XCTAssertNil(FitnessTrendBuilder.build(dailyLoadsAscending: [0, 40]))
        XCTAssertNil(FitnessTrendBuilder.build(dailyLoadsAscending: []))
        XCTAssertNil(FitnessTrendBuilder.build(dailyLoadsAscending: [40]))
    }

    func testBuildsScoreAndPointsDeltaFromRisingLoad() {
        let dailyLoads = Array(repeating: 0.0, count: 40) + [40, 40]
        let trend = FitnessTrendBuilder.build(dailyLoadsAscending: dailyLoads)

        XCTAssertNotNil(trend)
        XCTAssertGreaterThan(trend!.score, 0)
        XCTAssertGreaterThan(trend!.pointsDelta, 0)
    }

    func testNegativePointsDeltaWhenLoadDropsAfterSustainedTraining() {
        let dailyLoads = Array(repeating: 60.0, count: 60) + [0]
        let trend = FitnessTrendBuilder.build(dailyLoadsAscending: dailyLoads)

        XCTAssertNotNil(trend)
        XCTAssertLessThan(trend!.pointsDelta, 0)
    }

    func testSparklineCapsAtConfiguredDayCount() {
        let dailyLoads = Array(repeating: 30.0, count: 100)
        let trend = FitnessTrendBuilder.build(dailyLoadsAscending: dailyLoads)

        XCTAssertEqual(trend?.sparkline.count, FitnessTrendBuilder.sparklineDayCount)
    }
}
