import Foundation

struct RecoveryCalculator {
    private let referenceDate: Date

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    func calculateSummary(from activities: [RecoveryActivity]) -> RecoverySummary {
        guard !activities.isEmpty else {
            return emptySummary()
        }

        let sortedActivities = activities.sorted { $0.completedAt < $1.completedAt }
        let recentActivities = activitiesCompleted(sinceDaysAgo: 3, from: sortedActivities)
        let recentLoadAverage = average(recentActivities.map(\.trainingLoad))
        let effortSum = sortedActivities.reduce(0) { $0 + $1.relativeEffort }
        let restDays = estimateRestDays(from: sortedActivities)
        let score = calculateScore(recentLoadAverage: recentLoadAverage, effortSum: effortSum, restDays: restDays)
        let status = statusLabel(for: score)

        return RecoverySummary(
            score: score,
            status: status,
            description: description(score: score, recentLoadAverage: recentLoadAverage, restDays: restDays),
            recommendation: recommendation(score: score, recentLoadAverage: recentLoadAverage),
            trendText: "최근 3일 평균 부하 \(Int(recentLoadAverage))",
            coachMessage: buildCoachMessage(score: score, recentLoadAverage: recentLoadAverage, effortSum: effortSum),
            recommendationCard: buildRecommendation(score: score, recentLoadAverage: recentLoadAverage),
            trends: buildTrends(from: sortedActivities, recentActivities: recentActivities),
            insights: buildInsights(
                from: sortedActivities,
                score: score,
                recentLoadAverage: recentLoadAverage,
                effortSum: effortSum,
                restDays: restDays
            ),
            lastUpdated: referenceDate,
            dataQuality: .estimated
        )
    }

    private func emptySummary() -> RecoverySummary {
        let score = 72

        return RecoverySummary(
            score: score,
            status: "데이터 부족",
            description: "최근 운동 기록이 충분하지 않아 회복 상태를 보수적으로 추정했습니다.",
            recommendation: "오늘은 가벼운 활동으로 시작해보세요.",
            trendText: "최근 7일 운동 기록 부족",
            coachMessage: RecoveryCoachMessage(
                coachName: "SOOM AI 코치",
                subtitle: "운동 기록 부족",
                message: "아직 회복 흐름을 판단할 운동 기록이 부족합니다. 짧은 걷기나 가벼운 유산소로 몸 상태를 확인해보세요."
            ),
            recommendationCard: RecoveryRecommendation(
                title: "오늘의 추천",
                description: "몸 상태를 확인하는 정도의 가벼운 활동부터 시작하는 것이 좋습니다.",
                actionLabel: "가벼운 활동 보기",
                icon: SOOMIcon.recovery
            ),
            trends: [
                RecoveryTrend(
                    title: "운동 부하",
                    currentValue: "-",
                    unit: "TL",
                    changeText: "기록 부족",
                    direction: .flat,
                    values: []
                ),
                RecoveryTrend(
                    title: "피로도",
                    currentValue: "-",
                    unit: "점",
                    changeText: "기록 부족",
                    direction: .flat,
                    values: []
                )
            ],
            insights: [
                RecoveryInsight(
                    title: "운동 기록이 필요해요",
                    message: "최근 7일 운동 기록이 쌓이면 회복 점수와 추천 행동이 더 자연스럽게 바뀝니다.",
                    icon: SOOMIcon.chartLine,
                    tone: .neutral
                )
            ],
            lastUpdated: referenceDate,
            dataQuality: .estimated
        )
    }

    private func buildTrends(from activities: [RecoveryActivity], recentActivities: [RecoveryActivity]) -> [RecoveryTrend] {
        [
            calculateTrainingLoadTrend(from: activities, recentActivities: recentActivities),
            calculateFatigueTrend(from: activities, recentActivities: recentActivities),
            calculateHeartRateTrend(from: activities, recentActivities: recentActivities)
        ]
    }

    private func calculateTrainingLoadTrend(from activities: [RecoveryActivity], recentActivities: [RecoveryActivity]) -> RecoveryTrend {
        let sevenDayLoad = activities.reduce(0) { $0 + $1.trainingLoad }
        let recentLoadAverage = average(recentActivities.map(\.trainingLoad))

        return RecoveryTrend(
            title: "운동 부하",
            currentValue: "\(Int(sevenDayLoad))",
            unit: "TL",
            changeText: "3일 평균 \(Int(recentLoadAverage))",
            direction: recentLoadAverage > 85 ? .up : .flat,
            values: activities.map(\.trainingLoad)
        )
    }

    private func calculateFatigueTrend(from activities: [RecoveryActivity], recentActivities: [RecoveryActivity]) -> RecoveryTrend {
        let recentLoadAverage = average(recentActivities.map(\.trainingLoad))
        let effortSum = activities.reduce(0) { $0 + $1.relativeEffort }
        let restDays = estimateRestDays(from: activities)
        let fatigueScore = calculateFatigueScore(recentLoadAverage: recentLoadAverage, effortSum: effortSum, restDays: restDays)

        return RecoveryTrend(
            title: "피로도",
            currentValue: "\(fatigueScore)",
            unit: "점",
            changeText: fatigueScore >= 70 ? "높음" : "관리 가능",
            direction: fatigueScore >= 70 ? .up : .flat,
            values: fatigueValues(from: activities)
        )
    }

    private func calculateHeartRateTrend(from activities: [RecoveryActivity], recentActivities: [RecoveryActivity]) -> RecoveryTrend {
        let heartRateAverage = average(activities.map { Double($0.averageHeartRate) })
        let recentHeartRateAverage = average(recentActivities.map { Double($0.averageHeartRate) })

        return RecoveryTrend(
            title: "평균 심박",
            currentValue: "\(Int(heartRateAverage.rounded()))",
            unit: "bpm",
            changeText: heartRateChangeText(weekly: heartRateAverage, recent: recentHeartRateAverage),
            direction: recentHeartRateAverage > heartRateAverage + 4 ? .up : .flat,
            values: activities.map { Double($0.averageHeartRate) }
        )
    }

    private func buildRecommendation(score: Int, recentLoadAverage: Double) -> RecoveryRecommendation {
        RecoveryRecommendation(
            title: "오늘의 추천",
            description: recommendationDescription(score: score, recentLoadAverage: recentLoadAverage),
            actionLabel: actionLabel(score: score),
            icon: score >= 78 ? SOOMIcon.bike : SOOMIcon.recovery
        )
    }

    private func buildCoachMessage(score: Int, recentLoadAverage: Double, effortSum: Int) -> RecoveryCoachMessage {
        RecoveryCoachMessage(
            coachName: "SOOM AI 코치",
            subtitle: "운동 기록 기반 추정",
            message: coachMessage(score: score, recentLoadAverage: recentLoadAverage, effortSum: effortSum)
        )
    }

    private func buildInsights(
        from activities: [RecoveryActivity],
        score: Int,
        recentLoadAverage: Double,
        effortSum: Int,
        restDays: Int
    ) -> [RecoveryInsight] {
        var output: [RecoveryInsight] = []
        let latestActivity = activities.last

        output.append(
            RecoveryInsight(
                title: "운동 기록 기반 추정",
                message: "최근 7일 운동 부하와 체감 강도를 기준으로 회복 상태를 계산했습니다.",
                icon: SOOMIcon.chartLine,
                tone: .neutral
            )
        )

        if recentLoadAverage > 85 || effortSum > 220 {
            output.append(
                RecoveryInsight(
                    title: "부하 누적 주의",
                    message: "최근 운동 부하가 높습니다. 다음 고강도 세션 전 회복 시간을 확보하세요.",
                    icon: SOOMIcon.bolt,
                    tone: .warning
                )
            )
        } else {
            output.append(
                RecoveryInsight(
                    title: "훈련 부하 안정",
                    message: "최근 부하는 관리 가능한 수준입니다. 가벼운 유산소로 흐름을 이어가기 좋습니다.",
                    icon: SOOMIcon.checkCircle,
                    tone: .positive
                )
            )
        }

        if let latestActivity {
            output.append(
                RecoveryInsight(
                    title: "최근 운동",
                    message: "마지막 세션은 \(latestActivity.workoutType.title) \(latestActivity.durationMinutes)분, 부하 \(Int(latestActivity.trainingLoad))TL입니다.",
                    icon: latestActivity.workoutType.iconName,
                    tone: score >= 78 ? .positive : .neutral
                )
            )
        }

        if restDays <= 1 {
            output.append(
                RecoveryInsight(
                    title: "휴식일 부족",
                    message: "최근 7일 중 휴식일이 적습니다. 다음 성장에는 쉬는 날의 질도 중요합니다.",
                    icon: SOOMIcon.moon,
                    tone: .warning
                )
            )
        }

        // TODO: Replace these rule-based estimates with a validated recovery model
        // that can merge TRIMP, HRV, sleep, resting heart rate, and long-term baselines.
        return output
    }

    private func activitiesCompleted(sinceDaysAgo days: Int, from activities: [RecoveryActivity]) -> [RecoveryActivity] {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return activities.filter { $0.completedAt >= threshold }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func estimateRestDays(from activities: [RecoveryActivity]) -> Int {
        let activeDays = Set(activities.map { Calendar.current.startOfDay(for: $0.completedAt) })
        return max(0, 7 - activeDays.count)
    }

    private func calculateScore(recentLoadAverage: Double, effortSum: Int, restDays: Int) -> Int {
        var score = 88
        score -= Int(recentLoadAverage / 12)
        score -= Int(Double(effortSum) / 55)
        score += min(restDays, 3) * 4
        return min(max(score, 45), 95)
    }

    private func calculateFatigueScore(recentLoadAverage: Double, effortSum: Int, restDays: Int) -> Int {
        var score = Int(recentLoadAverage * 0.45) + Int(Double(effortSum) * 0.12)
        score -= min(restDays, 3) * 4
        return min(max(score, 20), 92)
    }

    private func fatigueValues(from activities: [RecoveryActivity]) -> [Double] {
        activities.map { activity in
            min(92, max(20, activity.trainingLoad * 0.42 + Double(activity.relativeEffort) * 0.20))
        }
    }

    private func statusLabel(for score: Int) -> String {
        switch score {
        case 82...:
            return "좋음"
        case 68..<82:
            return "보통"
        default:
            return "주의"
        }
    }

    private func description(score: Int, recentLoadAverage: Double, restDays: Int) -> String {
        if score >= 82 {
            return "최근 훈련량은 관리 가능한 범위입니다. 휴식일 \(restDays)일이 회복 흐름을 받쳐주고 있어요."
        }

        if recentLoadAverage > 85 {
            return "최근 3일 운동 부하가 높습니다. 강도를 더 올리기보다 회복 리듬을 먼저 확인하세요."
        }

        return "회복은 나쁘지 않지만 피로가 조금 남아 있습니다. 오늘은 강도보다 안정적인 움직임이 좋습니다."
    }

    private func recommendation(score: Int, recentLoadAverage: Double) -> String {
        if score >= 82 {
            return "오늘은 Z2 라이딩 40분 또는 가벼운 조깅을 추천해요."
        }

        if recentLoadAverage > 85 {
            return "오늘은 완전 휴식 또는 30분 회복 라이딩을 추천해요."
        }

        return "오늘은 가벼운 유산소와 스트레칭으로 회복을 우선하세요."
    }

    private func recommendationDescription(score: Int, recentLoadAverage: Double) -> String {
        if score >= 82 {
            return "운동 부하가 안정적이라 짧고 편한 유산소로 리듬을 이어가기 좋습니다."
        }

        if recentLoadAverage > 85 {
            return "최근 부하가 올라와 있습니다. 다음 고강도 전 피로를 먼저 낮추는 편이 좋습니다."
        }

        return "몸은 움직이되, 페이스나 파워 목표는 낮게 잡는 것이 좋습니다."
    }

    private func actionLabel(score: Int) -> String {
        score >= 82 ? "40분 Z2 라이딩 보기" : "회복 세션 보기"
    }

    private func coachMessage(score: Int, recentLoadAverage: Double, effortSum: Int) -> String {
        if score >= 82 {
            return "최근 훈련 흐름은 좋습니다. 오늘은 무리해서 성과를 만들기보다 편안한 강도로 리듬을 이어가세요."
        }

        if recentLoadAverage > 85 || effortSum > 220 {
            return "최근 부하와 체감 강도가 함께 올라갔습니다. 이번 세션은 회복을 우선하는 편이 다음 훈련 품질에 도움이 됩니다."
        }

        return "회복은 중간 수준입니다. 짧은 유산소는 괜찮지만 긴 인터벌은 하루 미루는 편이 좋습니다."
    }

    private func heartRateChangeText(weekly: Double, recent: Double) -> String {
        let diff = Int((recent - weekly).rounded())

        if diff > 0 {
            return "\(diff) 높음"
        }

        if diff < 0 {
            return "\(abs(diff)) 낮음"
        }

        return "안정"
    }
}
