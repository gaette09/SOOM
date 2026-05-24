import Foundation
import HealthKit

struct HealthKitWorkoutMetricMapper {
    func map(
        _ sample: HKQuantitySample,
        sampleType: HealthKitWorkoutMetricSampleType
    ) -> HealthKitWorkoutMetricSample {
        let unit = unit(for: sampleType)
        return HealthKitWorkoutMetricSample(
            sampleType: sampleType,
            value: sample.quantity.doubleValue(for: unit),
            unit: unitLabel(for: sampleType),
            startDate: sample.startDate,
            endDate: sample.endDate
        )
    }

    func quantityType(for sampleType: HealthKitWorkoutMetricSampleType) -> HKQuantityType? {
        switch sampleType {
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .cyclingCadence:
            if #available(iOS 17.0, *) {
                return HKQuantityType.quantityType(forIdentifier: .cyclingCadence)
            }
            return nil
        case .cyclingPower:
            if #available(iOS 17.0, *) {
                return HKQuantityType.quantityType(forIdentifier: .cyclingPower)
            }
            return nil
        }
    }

    func unit(for sampleType: HealthKitWorkoutMetricSampleType) -> HKUnit {
        switch sampleType {
        case .heartRate, .cyclingCadence:
            return HKUnit.count().unitDivided(by: .minute())
        case .cyclingPower:
            return .watt()
        }
    }

    func unitLabel(for sampleType: HealthKitWorkoutMetricSampleType) -> String {
        switch sampleType {
        case .heartRate:
            return "count/min"
        case .cyclingCadence:
            return "rpm"
        case .cyclingPower:
            return "watt"
        }
    }
}
