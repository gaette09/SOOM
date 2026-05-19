import Foundation

struct RecoverySummaryComposer {
    private let coachMessagePersonalizer: RecoveryCoachMessagePersonalizer
    private let insightPersonalizer: RecoveryInsightPersonalizer

    init(
        coachMessagePersonalizer: RecoveryCoachMessagePersonalizer = RecoveryCoachMessagePersonalizer(),
        insightPersonalizer: RecoveryInsightPersonalizer = RecoveryInsightPersonalizer()
    ) {
        self.coachMessagePersonalizer = coachMessagePersonalizer
        self.insightPersonalizer = insightPersonalizer
    }

    func compose(
        baseSummary: RecoverySummary,
        latestCheckIn: RecoveryCheckIn?
    ) -> RecoverySummary {
        let coachPersonalizedSummary = coachMessagePersonalizer.personalize(
            summary: baseSummary,
            latestCheckIn: latestCheckIn
        )

        return insightPersonalizer.personalize(
            summary: coachPersonalizedSummary,
            latestCheckIn: latestCheckIn
        )
    }
}
