import Foundation

struct WorkoutDetailSectionGroup: Identifiable, Equatable {
    let id: Kind
    let title: String
    let caption: String
    let priority: Int
    let isCollapsibleReady: Bool

    enum Kind: String, CaseIterable {
        case core
        case growth
        case sensorData
        case recovery
    }

    static let core = WorkoutDetailSectionGroup(
        id: .core,
        title: "오늘 핵심",
        caption: "운동 결과를 먼저 짧게 정리해요.",
        priority: 0,
        isCollapsibleReady: false
    )

    static let growth = WorkoutDetailSectionGroup(
        id: .growth,
        title: "성장 흐름",
        caption: "최근 기록과 오늘 운동의 리듬을 비교해요.",
        priority: 1,
        isCollapsibleReady: false
    )

    static let sensorData = WorkoutDetailSectionGroup(
        id: .sensorData,
        title: "운동 데이터",
        caption: "센서와 zone 데이터를 보조 지표로 확인해요.",
        priority: 2,
        isCollapsibleReady: false
    )

    static let recovery = WorkoutDetailSectionGroup(
        id: .recovery,
        title: "회복 해석",
        caption: "다음 운동을 위한 컨디션 힌트를 정리해요.",
        priority: 3,
        isCollapsibleReady: false
    )

    static let ordered: [WorkoutDetailSectionGroup] = [
        .core,
        .growth,
        .sensorData,
        .recovery
    ]
}
