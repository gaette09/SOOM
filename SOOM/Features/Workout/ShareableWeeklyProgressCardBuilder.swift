import Foundation

struct ShareableWeeklyProgressCardBuilder {
    func build(
        progress: WeeklyWorkoutProgress,
        trend: FourWeekWorkoutTrend? = nil,
        visibility: ShareableWorkoutVisibility = .privateOnly
    ) -> ShareableWeeklyProgressCardModel {
        ShareableWeeklyProgressCardModel(
            weekLabel: weekLabel(from: progress.weekStartDate),
            totalDistanceText: distanceText(progress.totalDistanceKm),
            totalDurationText: durationText(progress.totalDurationMinutes),
            workoutCountText: "\(progress.workoutCount)회",
            progressMessage: progressMessage(from: progress, trend: trend),
            motivationText: motivationText(from: progress, trend: trend),
            footerText: footerText(for: visibility),
            visibility: visibility
        )
    }

    private func weekLabel(from weekStartDate: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStartDate)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start

        return "\(monthDayText(start)) - \(monthDayText(end))"
    }

    private func monthDayText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0).\(components.day ?? 0)"
    }

    private func distanceText(_ distanceKm: Double) -> String {
        guard distanceKm > 0 else { return "거리 준비 중" }
        return String(format: "%.1f km", distanceKm)
    }

    private func durationText(_ durationMinutes: Int) -> String {
        let minutes = max(durationMinutes, 0)
        guard minutes > 0 else { return "시간 준비 중" }

        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)시간 \(remainingMinutes)분" : "\(hours)시간"
        }

        return "\(minutes)분"
    }

    private func progressMessage(
        from progress: WeeklyWorkoutProgress,
        trend: FourWeekWorkoutTrend?
    ) -> String {
        if trend?.trendType == .improving, progress.trendType == .improving {
            return "최근 흐름 안에서도 이번 주 리듬이 잘 이어졌어요."
        }

        switch progress.trendType {
        case .improving:
            return "이번 주는 꾸준함이 좋아지고 있어요."
        case .steady:
            return "리듬을 잘 이어간 한 주였어요."
        case .lighterWeek:
            return "이번 주는 몸 상태에 맞춰 가볍게 이어갔어요."
        case .insufficientData:
            return "기록이 쌓이면 주간 흐름을 더 잘 보여드릴게요."
        }
    }

    private func motivationText(
        from progress: WeeklyWorkoutProgress,
        trend: FourWeekWorkoutTrend?
    ) -> String {
        if progress.trendType == .insufficientData {
            return "이번 기록은 다음 주 성장 흐름을 만들기 위한 좋은 기준점이에요."
        }

        if trend?.trendType == .lighter {
            return "가벼운 주간도 다음 리듬을 준비하는 과정이 될 수 있어요."
        }

        return progress.motivationText
    }

    private func footerText(for visibility: ShareableWorkoutVisibility) -> String {
        switch visibility {
        case .privateOnly:
            return "SOOM · 주간 성장 미리보기"
        case .followers:
            return "SOOM · 팔로워 주간 공유 예정"
        case .publicFeed:
            return "SOOM · 공개 주간 공유 예정"
        }
    }
}
