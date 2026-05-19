import Foundation

struct AIInsight: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let priority: InsightPriority
}

enum InsightPriority: String {
    case positive = "좋음"
    case caution = "주의"
    case action = "실행"
}

struct AIRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let targetDay: String
}
