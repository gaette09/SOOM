import Foundation

enum CourseProgressionDirection: String, Equatable {
    case improving
    case stable
    case fluctuating
    case insufficientData
}

struct CourseProgressionTimeline: Identifiable, Equatable {
    let courseId: String
    let points: [CourseProgressionPoint]
    let summary: String
    let direction: CourseProgressionDirection

    var id: String {
        courseId
    }

    static let insufficientData = CourseProgressionTimeline(
        courseId: "insufficient-data",
        points: [],
        summary: "비슷한 코스 기록이 더 쌓이면 시간에 따른 흐름을 함께 보여줄게요.",
        direction: .insufficientData
    )
}
