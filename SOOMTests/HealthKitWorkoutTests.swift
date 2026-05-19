import HealthKit
import XCTest
@testable import SOOM

final class HealthKitWorkoutTests: XCTestCase {
    func testWorkoutTypeMappingForTriathlonCoreSports() {
        XCTAssertEqual(HealthKitWorkoutType(activityType: .running), .running)
        XCTAssertEqual(HealthKitWorkoutType(activityType: .cycling), .cycling)
        XCTAssertEqual(HealthKitWorkoutType(activityType: .swimming), .swimming)
    }

    func testWorkoutTypeMappingFallsBackToOther() {
        XCTAssertEqual(HealthKitWorkoutType(activityType: .mindAndBody), .other)
    }

    func testHealthKitManagerReadTypesAreReadOnlyCandidates() {
        let readTypes = HealthKitManager.readTypes

        XCTAssertTrue(readTypes.contains(HKWorkoutType.workoutType()))
        XCTAssertTrue(readTypes.contains(HKQuantityType.quantityType(forIdentifier: .heartRate)!))
        XCTAssertTrue(readTypes.contains(HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!))
        XCTAssertTrue(readTypes.contains(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!))
        XCTAssertTrue(readTypes.contains(HKQuantityType.quantityType(forIdentifier: .distanceCycling)!))
    }
}
