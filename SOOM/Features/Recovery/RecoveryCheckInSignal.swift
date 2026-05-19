import Foundation

enum RecoveryCheckInSignal: Equatable {
    case highFatigue
    case lowSleep
    case highSoreness
    case lowMood
    case stable
}

struct RecoveryCheckInSignalClassifier {
    func classify(_ checkIn: RecoveryCheckIn?) -> RecoveryCheckInSignal {
        guard let checkIn else { return .stable }

        if checkIn.fatigueLevel >= 4 {
            return .highFatigue
        }

        if checkIn.sleepQuality <= 2 {
            return .lowSleep
        }

        if checkIn.muscleSoreness >= 4 {
            return .highSoreness
        }

        if checkIn.moodLevel <= 2 {
            return .lowMood
        }

        return .stable
    }
}
