enum MorningCheckInState: Equatable {
    case notCheckedInToday
    case checkedInToday
    case skippedToday
    case insufficientData
    case healthKitNotConnected
}
