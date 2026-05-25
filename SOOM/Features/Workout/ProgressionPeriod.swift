import Foundation

enum ProgressionPeriod: Equatable {
    case weekly
    case monthly
    case rollingFourWeeks
    case rollingThreeMonths

    var dayCount: Int {
        switch self {
        case .weekly:
            return 7
        case .monthly:
            return 30
        case .rollingFourWeeks:
            return 28
        case .rollingThreeMonths:
            return 90
        }
    }

    var title: String {
        switch self {
        case .weekly:
            return "최근 1주"
        case .monthly:
            return "최근 한 달"
        case .rollingFourWeeks:
            return "최근 4주"
        case .rollingThreeMonths:
            return "최근 3개월"
        }
    }
}
