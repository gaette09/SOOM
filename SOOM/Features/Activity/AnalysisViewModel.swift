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

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var progress: WeeklyWorkoutProgress
    @Published private(set) var fourWeekTrend: FourWeekWorkoutTrend
    @Published private(set) var personalRecords: [PersonalRecord]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let provider: WeeklyWorkoutProgressProviding
    private let fourWeekTrendProvider: FourWeekWorkoutTrendProviding?
    private let personalRecordProvider: PersonalRecordProviding?
    private let builder: WeeklyWorkoutProgressBuilder
    private let fourWeekTrendBuilder: FourWeekWorkoutTrendBuilder
    private let personalRecordBuilder: PersonalRecordBuilder

    init(
        provider: WeeklyWorkoutProgressProviding,
        fourWeekTrendProvider: FourWeekWorkoutTrendProviding? = nil,
        personalRecordProvider: PersonalRecordProviding? = nil,
        builder: WeeklyWorkoutProgressBuilder = WeeklyWorkoutProgressBuilder(),
        fourWeekTrendBuilder: FourWeekWorkoutTrendBuilder = FourWeekWorkoutTrendBuilder(),
        personalRecordBuilder: PersonalRecordBuilder = PersonalRecordBuilder()
    ) {
        self.provider = provider
        self.fourWeekTrendProvider = fourWeekTrendProvider
        self.personalRecordProvider = personalRecordProvider
        self.builder = builder
        self.fourWeekTrendBuilder = fourWeekTrendBuilder
        self.personalRecordBuilder = personalRecordBuilder
        self.progress = builder.build(inputs: [])
        self.fourWeekTrend = fourWeekTrendBuilder.build(inputs: [])
        self.personalRecords = []
    }

    func load(
        fallbackWorkouts: [Workout] = [],
        referenceDate: Date = Date()
    ) async {
        isLoading = true
        errorMessage = nil

        do {
            progress = try await provider.fetchWeeklyProgress(referenceDate: referenceDate)
        } catch {
            progress = builder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
            if progress.trendType != .insufficientData || !fallbackWorkouts.isEmpty {
                errorMessage = "가져온 운동 기록을 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            } else {
                errorMessage = "가져온 운동 기록을 불러오지 못했어요."
            }
        }

        await loadFourWeekTrend(fallbackWorkouts: fallbackWorkouts, referenceDate: referenceDate)
        await loadPersonalRecords(fallbackWorkouts: fallbackWorkouts, referenceDate: referenceDate)

        isLoading = false
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
            personalRecords = personalRecordBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
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
            fourWeekTrend = fourWeekTrendBuilder.build(workouts: fallbackWorkouts, referenceDate: referenceDate)
            if errorMessage == nil {
                errorMessage = "4주 성장 추세를 불러오지 못해 기존 운동 데이터로 표시하고 있어요."
            }
        }
    }
}
