import Foundation

enum WorkoutZoneDataSourceType: String, Equatable, Codable {
    case healthKitStream
    case fallbackEstimate
    case unavailable
    case manualFuture
}

struct WorkoutZoneDataSource: Equatable {
    let sourceType: WorkoutZoneDataSourceType
    let label: String
    let description: String

    init(
        sourceType: WorkoutZoneDataSourceType,
        label: String? = nil,
        description: String? = nil
    ) {
        self.sourceType = sourceType
        self.label = label ?? Self.defaultLabel(for: sourceType)
        self.description = description ?? Self.defaultDescription(for: sourceType)
    }

    static let healthKitStream = WorkoutZoneDataSource(sourceType: .healthKitStream)
    static let fallbackEstimate = WorkoutZoneDataSource(sourceType: .fallbackEstimate)
    static let unavailable = WorkoutZoneDataSource(sourceType: .unavailable)
    static let manualFuture = WorkoutZoneDataSource(sourceType: .manualFuture)

    private static func defaultLabel(for sourceType: WorkoutZoneDataSourceType) -> String {
        switch sourceType {
        case .healthKitStream:
            return "HealthKit 데이터"
        case .fallbackEstimate:
            return "기본 추정"
        case .unavailable:
            return "데이터 없음"
        case .manualFuture:
            return "직접 기록 후보"
        }
    }

    private static func defaultDescription(for sourceType: WorkoutZoneDataSourceType) -> String {
        switch sourceType {
        case .healthKitStream:
            return "운동 중 기록된 센서 데이터를 기준으로 계산했어요."
        case .fallbackEstimate:
            return "센서 데이터가 부족해 기본 흐름으로 보여줘요."
        case .unavailable:
            return "이 운동에는 해당 센서 기록이 없어요."
        case .manualFuture:
            return "직접 기록한 데이터를 바탕으로 보여줄 예정이에요."
        }
    }
}
