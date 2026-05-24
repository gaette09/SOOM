import HealthKit
import XCTest
@testable import SOOM

final class HealthKitWorkoutMetricMapperTests: XCTestCase {
    private let mapper = HealthKitWorkoutMetricMapper()

    func testMapsHeartRateSample() {
        let sample = makeQuantitySample(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            value: 142,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 130)
        )

        let mapped = mapper.map(sample, sampleType: .heartRate)

        XCTAssertEqual(mapped.sampleType, .heartRate)
        XCTAssertEqual(mapped.value, 142, accuracy: 0.001)
        XCTAssertEqual(mapped.unit, "count/min")
        XCTAssertEqual(mapped.durationSeconds, 30, accuracy: 0.001)
    }

    func testMapsCyclingCadenceSample() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Cycling cadence requires iOS 17+") }
        let sample = makeQuantitySample(
            identifier: .cyclingCadence,
            unit: HKUnit.count().unitDivided(by: .minute()),
            value: 88,
            start: Date(timeIntervalSince1970: 200),
            end: Date(timeIntervalSince1970: 260)
        )

        let mapped = mapper.map(sample, sampleType: .cyclingCadence)

        XCTAssertEqual(mapped.sampleType, .cyclingCadence)
        XCTAssertEqual(mapped.value, 88, accuracy: 0.001)
        XCTAssertEqual(mapped.unit, "rpm")
        XCTAssertEqual(mapped.durationSeconds, 60, accuracy: 0.001)
    }

    func testMapsCyclingPowerSample() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Cycling power requires iOS 17+") }
        let sample = makeQuantitySample(
            identifier: .cyclingPower,
            unit: .watt(),
            value: 230,
            start: Date(timeIntervalSince1970: 300),
            end: Date(timeIntervalSince1970: 315)
        )

        let mapped = mapper.map(sample, sampleType: .cyclingPower)

        XCTAssertEqual(mapped.sampleType, .cyclingPower)
        XCTAssertEqual(mapped.value, 230, accuracy: 0.001)
        XCTAssertEqual(mapped.unit, "watt")
        XCTAssertEqual(mapped.durationSeconds, 15, accuracy: 0.001)
    }

    func testQuantityTypeSafeGuardsOptionalHealthKitTypes() {
        XCTAssertNotNil(mapper.quantityType(for: .heartRate))

        if #available(iOS 17.0, *) {
            XCTAssertNotNil(mapper.quantityType(for: .cyclingCadence))
            XCTAssertNotNil(mapper.quantityType(for: .cyclingPower))
        }
    }

    private func makeQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        start: Date,
        end: Date
    ) -> HKQuantitySample {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            preconditionFailure("Missing quantity type for test fixture")
        }

        return HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: start,
            end: end
        )
    }
}
