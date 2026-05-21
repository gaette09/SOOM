import Foundation

struct RecoveryComparisonSummary {
    enum DifferenceLevel {
        case similar
        case moderate
        case large
    }

    let officialScore: Int
    let previewScore: Int
    let difference: Int
    let differenceLevel: DifferenceLevel
    let comparisonMessage: String
    let recommendation: String
    let confidenceNote: String
}
