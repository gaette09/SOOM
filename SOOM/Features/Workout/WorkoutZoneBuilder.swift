import Foundation

struct WorkoutZoneBuilder {
    func buildSummary(
        type: WorkoutZoneType,
        durations: [WorkoutZoneDurationInput],
        dataSource: WorkoutZoneDataSource = .fallbackEstimate
    ) -> WorkoutZoneSummary {
        let validDurations = durations.filter { $0.durationSeconds > 0 }
        let totalDuration = validDurations.reduce(0) { $0 + $1.durationSeconds }

        guard totalDuration > 0 else {
            return unavailableSummary(type: type)
        }

        let zones = validDurations
            .sorted { $0.zoneIndex < $1.zoneIndex }
            .map { input in
                WorkoutZone(
                    zoneType: type,
                    zoneIndex: input.zoneIndex,
                    durationSeconds: input.durationSeconds,
                    percentage: input.durationSeconds / totalDuration * 100,
                    rangeDescription: input.rangeDescription
                )
            }

        let dominantZone = zones.max { $0.durationSeconds < $1.durationSeconds }

        return WorkoutZoneSummary(
            type: type,
            zones: zones,
            dominantZone: dominantZone,
            insightText: insightText(type: type, dominantZone: dominantZone),
            dataSource: dataSource
        )
    }

    func unavailableSummary(type: WorkoutZoneType) -> WorkoutZoneSummary {
        WorkoutZoneSummary(
            type: type,
            zones: [],
            dominantZone: nil,
            insightText: unavailableText(type: type),
            dataSource: .unavailable
        )
    }

    private func insightText(
        type: WorkoutZoneType,
        dominantZone: WorkoutZone?
    ) -> String? {
        guard let dominantZone else {
            return unavailableText(type: type)
        }

        switch type {
        case .heartRate:
            return "오늘은 Zone \(dominantZone.zoneIndex) 유지 시간이 길었어요."
        case .cadence:
            return cadenceInsight(for: dominantZone)
        case .power:
            return "파워 Zone \(dominantZone.zoneIndex)에 머문 시간이 가장 길었어요."
        }
    }

    private func cadenceInsight(for zone: WorkoutZone) -> String {
        switch zone.zoneIndex {
        case 1:
            return "오늘은 낮은 케이던스 리듬이 길었어요."
        case 2:
            return "오늘은 안정적인 케이던스 리듬을 오래 유지했어요."
        default:
            return "오늘은 높은 케이던스 리듬이 비교적 길었어요."
        }
    }

    private func unavailableText(type: WorkoutZoneType) -> String {
        switch type {
        case .heartRate:
            return "심박 기록이 쌓이면 강도 흐름을 보여드릴게요."
        case .cadence:
            return "케이던스 기록이 있으면 리듬 변화를 보여드릴게요."
        case .power:
            return "파워존은 FTP와 파워 기록이 있으면 보여드릴게요."
        }
    }
}
