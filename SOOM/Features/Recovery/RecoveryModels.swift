import Foundation

struct RecoverySummary {
    let score: Int
    let status: String
    let description: String
    let recommendation: String
    let trendText: String
    let coachMessage: RecoveryCoachMessage
    let recommendationCard: RecoveryRecommendation
    let trends: [RecoveryTrend]
    let insights: [RecoveryInsight]
    let lastUpdated: Date
    let dataQuality: RecoveryDataQuality
    /// False when the score is only the calculator's empty-input fallback.
    let hasCalculatedScore: Bool
    /// Count for lastUpdated's calendar day; nil means the provider did not establish it.
    let activityCountToday: Int?

    var statusLabel: String {
        hasCalculatedScore ? "회복 \(score) · \(status)" : "회복 · 데이터 부족"
    }

    init(
        score: Int,
        status: String,
        description: String,
        recommendation: String,
        trendText: String,
        coachMessage: RecoveryCoachMessage,
        recommendationCard: RecoveryRecommendation,
        trends: [RecoveryTrend],
        insights: [RecoveryInsight],
        lastUpdated: Date,
        dataQuality: RecoveryDataQuality,
        hasCalculatedScore: Bool = true,
        activityCountToday: Int? = nil
    ) {
        self.score = score
        self.status = status
        self.description = description
        self.recommendation = recommendation
        self.trendText = trendText
        self.coachMessage = coachMessage
        self.recommendationCard = recommendationCard
        self.trends = trends
        self.insights = insights
        self.lastUpdated = lastUpdated
        self.dataQuality = dataQuality
        self.hasCalculatedScore = hasCalculatedScore
        self.activityCountToday = activityCountToday
    }
}

struct RecoveryCoachMessage {
    let coachName: String
    let subtitle: String
    let message: String
}

struct RecoveryRecommendation {
    let title: String
    let description: String
    let actionLabel: String
    let icon: String
}

struct RecoveryTrend: Identifiable {
    let id = UUID()
    let title: String
    let currentValue: String
    let unit: String
    let changeText: String
    let direction: RecoveryTrendDirection
    let values: [Double]
}

enum RecoveryTrendDirection {
    case up
    case down
    case flat

    var cardDirection: TrendDirection {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        case .flat:
            return .flat
        }
    }
}

struct RecoveryInsight: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let tone: RecoveryInsightTone
}

enum RecoveryInsightTone {
    case neutral
    case positive
    case warning

    var cardTone: InsightTone {
        switch self {
        case .neutral:
            return .neutral
        case .positive:
            return .positive
        case .warning:
            return .warning
        }
    }
}

enum RecoveryDataQuality {
    case mock
    case estimated
    case highConfidence

    var label: String {
        switch self {
        case .mock:
            return "더미 데이터"
        case .estimated:
            return "운동 기록 기반 추정"
        case .highConfidence:
            return "높은 신뢰도"
        }
    }
}
