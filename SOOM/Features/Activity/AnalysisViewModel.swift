import Combine
import Foundation

protocol WeeklyWorkoutProgressProviding {
    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress
}

extension UnifiedWorkoutWeeklyProgressProvider: WeeklyWorkoutProgressProviding {}

protocol FourWeekWorkoutTrendProviding {
    func fetchFourWeekTrend(referenceDate: Date) async throws -> FourWeekWorkoutTrend
}

extension UnifiedWorkoutGrowthTrendProvider: FourWeekWorkoutTrendProviding {}

protocol PersonalRecordProviding {
    func fetchPersonalRecords(referenceDate: Date) async throws -> [PersonalRecord]
}

extension UnifiedWorkoutPersonalRecordProvider: PersonalRecordProviding {}

protocol ProgressionIntelligenceProviding {
    func fetchProgressionIntelligence(referenceDate: Date) async throws -> ProgressionIntelligence
}

extension UnifiedWorkoutProgressionIntelligenceProvider: ProgressionIntelligenceProviding {}

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var progress: WeeklyWorkoutProgress
    @Published private(set) var fourWeekTrend: FourWeekWorkoutTrend
    @Published private(set) var personalRecords: [PersonalRecord]
    @Published private(set) var progressionIntelligence: ProgressionIntelligence
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let provider: WeeklyWorkoutProgressProviding
    private let fourWeekTrendProvider: FourWeekWorkoutTrendProviding?
    private let personalRecordProvider: PersonalRecordProviding?
    private let progressionIntelligenceProvider: ProgressionIntelligenceProviding?
    private let builder: WeeklyWorkoutProgressBuilder
    private let fourWeekTrendBuilder: FourWeekWorkoutTrendBuilder
    private let personalRecordBuilder: PersonalRecordBuilder
    private let progressionIntelligenceBuilder: ProgressionIntelligenceBuilder

    init(
        provider: WeeklyWorkoutProgressProviding,
        fourWeekTrendProvider: FourWeekWorkoutTrendProviding? = nil,
        personalRecordProvider: PersonalRecordProviding? = nil,
        progressionIntelligenceProvider: ProgressionIntelligenceProviding? = nil,
        builder: WeeklyWorkoutProgressBuilder = WeeklyWorkoutProgressBuilder(),
        fourWeekTrendBuilder: FourWeekWorkoutTrendBuilder = FourWeekWorkoutTrendBuilder(),
        personalRecordBuilder: PersonalRecordBuilder = PersonalRecordBuilder(),
        progressionIntelligenceBuilder: ProgressionIntelligenceBuilder = ProgressionIntelligenceBuilder()
    ) {
        self.provider = provider
        self.fourWeekTrendProvider = fourWeekTrendProvider
        self.personalRecordProvider = personalRecordProvider
        self.progressionIntelligenceProvider = progressionIntelligenceProvider
        self.builder = builder
        self.fourWeekTrendBuilder = fourWeekTrendBuilder
        self.personalRecordBuilder = personalRecordBuilder
        self.progressionIntelligenceBuilder = progressionIntelligenceBuilder
        self.progress = builder.build(inputs: [])
        self.fourWeekTrend = fourWeekTrendBuilder.build(inputs: [])
        self.personalRecords = []
        self.progressionIntelligence = ProgressionIntelligence.insufficientData(period: .rollingFourWeeks)
    }

    func load(
        fallbackWorkouts: [Workout] = [],
        referenceDate: Date = Date()
    ) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            progress = try await provider.fetchWeeklyProgress(referenceDate: referenceDate)
        } catch {
            guard !Task.isCancelled else { return }
            if !hasLoaded { progress = builder.build(workouts: fallbackWorkouts, referenceDate: referenceDate) }
            if progress.trendType != .insufficientData || !fallbackWorkouts.isEmpty {
                errorMessage = "가져온 운동 기록을 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            } else {
                errorMessage = "가져온 운동 기록을 불러오지 못했어요."
            }
        }

        guard !Task.isCancelled else { return }
        await loadFourWeekTrend(fallbackWorkouts: fallbackWorkouts, referenceDate: referenceDate)
        guard !Task.isCancelled else { return }
        await loadProgressionIntelligence(fallbackWorkouts: fallbackWorkouts, referenceDate: referenceDate)
        guard !Task.isCancelled else { return }
        await loadPersonalRecords(fallbackWorkouts: fallbackWorkouts, referenceDate: referenceDate)
        if !Task.isCancelled { hasLoaded = true }

    }

    private func loadProgressionIntelligence(
        fallbackWorkouts: [Workout],
        referenceDate: Date
    ) async {
        guard let progressionIntelligenceProvider else {
            progressionIntelligence = progressionIntelligenceBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
            return
        }

        do {
            progressionIntelligence = try await progressionIntelligenceProvider.fetchProgressionIntelligence(referenceDate: referenceDate)
        } catch {
            guard !Task.isCancelled else { return }
            if !hasLoaded { progressionIntelligence = progressionIntelligenceBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate) }
            if errorMessage == nil {
                errorMessage = "장기 운동 흐름을 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            }
        }
    }

    private func loadPersonalRecords(
        fallbackWorkouts: [Workout],
        referenceDate: Date
    ) async {
        guard let personalRecordProvider else {
            personalRecords = personalRecordBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
            return
        }

        do {
            personalRecords = try await personalRecordProvider.fetchPersonalRecords(referenceDate: referenceDate)
        } catch {
            guard !Task.isCancelled else { return }
            if !hasLoaded { personalRecords = personalRecordBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate) }
            if errorMessage == nil {
                errorMessage = "개인 기록을 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            }
        }
    }

    private func loadFourWeekTrend(
        fallbackWorkouts: [Workout],
        referenceDate: Date
    ) async {
        guard let fourWeekTrendProvider else {
            fourWeekTrend = fourWeekTrendBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
            return
        }

        do {
            fourWeekTrend = try await fourWeekTrendProvider.fetchFourWeekTrend(referenceDate: referenceDate)
        } catch {
            guard !Task.isCancelled else { return }
            if !hasLoaded { fourWeekTrend = fourWeekTrendBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate) }
            if errorMessage == nil {
                errorMessage = "4주 성장 추세를 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            }
        }
    }
}
