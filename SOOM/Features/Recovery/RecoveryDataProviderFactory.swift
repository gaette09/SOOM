struct RecoveryDataProviderFactory {
    static func makeProvider(
        source: RecoveryActivitySource = .defaultSource,
        healthKitWorkoutFetcher: (any HealthKitWorkoutFetching)? = nil
    ) -> any RecoveryDataProvider {
        ActivityRecoveryDataProvider(
            store: makeActivityStore(
                source: source,
                healthKitWorkoutFetcher: healthKitWorkoutFetcher
            )
        )
    }

    private static func makeActivityStore(
        source: RecoveryActivitySource,
        healthKitWorkoutFetcher: (any HealthKitWorkoutFetching)?
    ) -> any RecoveryActivityStore {
        switch source {
        case .mock:
            return MockRecoveryActivityStore()
        case .local:
            return LocalActivityStore()
        case .healthKit:
            if let healthKitWorkoutFetcher {
                return HealthKitActivityStore(workoutFetcher: healthKitWorkoutFetcher)
            }
            return HealthKitActivityStore()
        }
    }
}
