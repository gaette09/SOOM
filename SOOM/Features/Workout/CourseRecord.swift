import Foundation

enum CourseRecordComparisonType: String, Equatable {
    case bestPace
    case bestSpeed
    case longestDistance
    case fastestCompletion
    case stableRhythm
    case recentImprovement
    case insufficientData
}

struct CourseRecordMetric: Equatable {
    let title: String
    let valueText: String
    let detailText: String
}

struct CourseRecord: Identifiable, Equatable {
    let courseId: String
    let workoutId: UUID
    let comparisonType: CourseRecordComparisonType
    let bestMetric: CourseRecordMetric
    let previousMetric: CourseRecordMetric?
    let improvementValue: String?
    let achievedAt: Date

    var id: String {
        "\(courseId)-\(workoutId.uuidString)-\(comparisonType.rawValue)"
    }

    static let insufficientData = CourseRecord(
        courseId: "insufficient-data",
        workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID(),
        comparisonType: .insufficientData,
        bestMetric: CourseRecordMetric(
            title: "비슷한 코스 기록",
            valueText: "기록 대기",
            detailText: "비슷한 기록이 더 쌓이면 이 코스에서의 변화를 비교해볼게요."
        ),
        previousMetric: nil,
        improvementValue: nil,
        achievedAt: Date(timeIntervalSince1970: 0)
    )
}
