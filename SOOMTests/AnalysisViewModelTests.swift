import XCTest
@testable import SOOM

@MainActor
final class AnalysisViewModelTests: XCTestCase {
    func testLoadPublishesProviderProgressOnSuccess() async {
        let expected = makeProgress(workoutCount: 3, trendType: .improving)
        let provider = FakeWeeklyWorkoutProgressProvider(result: .success(expected))
        let viewModel = AnalysisViewModel(provider: provider)

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.progress, expected)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(provider.requestedReferenceDate, baseDate)
    }

    func testLoadFallsBackToInsufficientDataWhenProviderFailsWithoutFallbackWorkouts() async {
        let provider = FakeWeeklyWorkoutProgressProvider(result: .failure(TestError.failed))
        let viewModel = AnalysisViewModel(provider: provider)

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.progress.trendType, .insufficientData)
        XCTAssertEqual(viewModel.progress.workoutCount, 0)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadFallsBackToExistingWorkoutDataWhenProviderFails() async {
        let provider = FakeWeeklyWorkoutProgressProvider(result: .failure(TestError.failed))
        let viewModel = AnalysisViewModel(provider: provider)
        let fallbackWorkouts = [
            makeWorkout(daysAgo: 0, distanceMeters: 10_000, duration: 3_000),
            makeWorkout(daysAgo: 2, distanceMeters: 5_000, duration: 1_500)
        ]

        await viewModel.load(fallbackWorkouts: fallbackWorkouts, referenceDate: baseDate)

        XCTAssertEqual(viewModel.progress.workoutCount, 2)
        XCTAssertEqual(viewModel.progress.totalDistanceKm, 15.0, accuracy: 0.01)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testIsLoadingIsTrueWhileProviderIsSuspended() async {
        let provider = SuspendedWeeklyWorkoutProgressProvider()
        let viewModel = AnalysisViewModel(provider: provider)

        let loadTask = Task {
            await viewModel.load(referenceDate: baseDate)
        }

        await provider.waitUntilRequested()
        XCTAssertTrue(viewModel.isLoading)

        provider.succeed(with: makeProgress(workoutCount: 1, trendType: .steady))
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadDoesNotUseRecoveryCalculator() async {
        let provider = FakeWeeklyWorkoutProgressProvider(
            result: .success(makeProgress(workoutCount: 1, trendType: .insufficientData))
        )
        let viewModel = AnalysisViewModel(provider: provider)

        await viewModel.load(referenceDate: baseDate)

        XCTAssertFalse(viewModel.progress.progressSummary.isEmpty)
        XCTAssertEqual(viewModel.progress.trendType, .insufficientData)
    }

    func testLoadPublishesFourWeekTrendFromProvider() async {
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(
            result: .success(makeProgress(workoutCount: 2, trendType: .steady))
        )
        let expectedTrend = makeFourWeekTrend(trendType: .improving)
        let trendProvider = FakeFourWeekWorkoutTrendProvider(result: .success(expectedTrend))
        let viewModel = AnalysisViewModel(
            provider: weeklyProvider,
            fourWeekTrendProvider: trendProvider
        )

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.fourWeekTrend, expectedTrend)
        XCTAssertEqual(trendProvider.requestedReferenceDate, baseDate)
    }

    func testFourWeekTrendFailureDoesNotReplaceWeeklyProgress() async {
        let expectedProgress = makeProgress(workoutCount: 3, trendType: .improving)
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(result: .success(expectedProgress))
        let trendProvider = FakeFourWeekWorkoutTrendProvider(result: .failure(TestError.failed))
        let viewModel = AnalysisViewModel(
            provider: weeklyProvider,
            fourWeekTrendProvider: trendProvider
        )

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.progress, expectedProgress)
        XCTAssertEqual(viewModel.fourWeekTrend.trendType, .insufficientData)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testFallbackWorkoutsBuildFourWeekTrendWhenNoTrendProviderIsInjected() async {
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(
            result: .success(makeProgress(workoutCount: 2, trendType: .steady))
        )
        let viewModel = AnalysisViewModel(provider: weeklyProvider)
        let fallbackWorkouts = [
            makeWorkout(daysAgo: 21, distanceMeters: 4_000, duration: 1_500),
            makeWorkout(daysAgo: 14, distanceMeters: 5_000, duration: 1_800),
            makeWorkout(daysAgo: 7, distanceMeters: 7_000, duration: 2_400),
            makeWorkout(daysAgo: 0, distanceMeters: 9_000, duration: 3_000)
        ]

        await viewModel.load(fallbackWorkouts: fallbackWorkouts, referenceDate: baseDate)

        XCTAssertEqual(viewModel.fourWeekTrend.trendType, .improving)
    }

    func testLoadPublishesPersonalRecordsFromProvider() async {
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(
            result: .success(makeProgress(workoutCount: 2, trendType: .steady))
        )
        let expectedRecords = [makePersonalRecord(metricType: .longestDistance, value: "12.0 km")]
        let recordProvider = FakePersonalRecordProvider(result: .success(expectedRecords))
        let viewModel = AnalysisViewModel(
            provider: weeklyProvider,
            personalRecordProvider: recordProvider
        )

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.personalRecords, expectedRecords)
        XCTAssertEqual(recordProvider.requestedReferenceDate, baseDate)
    }

    func testPersonalRecordFailureDoesNotReplaceWeeklyProgress() async {
        let expectedProgress = makeProgress(workoutCount: 3, trendType: .improving)
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(result: .success(expectedProgress))
        let recordProvider = FakePersonalRecordProvider(result: .failure(TestError.failed))
        let viewModel = AnalysisViewModel(
            provider: weeklyProvider,
            personalRecordProvider: recordProvider
        )

        await viewModel.load(referenceDate: baseDate)

        XCTAssertEqual(viewModel.progress, expectedProgress)
        XCTAssertTrue(viewModel.personalRecords.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testFallbackWorkoutsBuildPersonalRecordsWhenNoRecordProviderIsInjected() async {
        let weeklyProvider = FakeWeeklyWorkoutProgressProvider(
            result: .success(makeProgress(workoutCount: 2, trendType: .steady))
        )
        let viewModel = AnalysisViewModel(provider: weeklyProvider)
        let fallbackWorkouts = [
            makeWorkout(daysAgo: 1, distanceMeters: 4_000, duration: 1_500),
            makeWorkout(daysAgo: 0, distanceMeters: 11_000, duration: 3_600)
        ]

        await viewModel.load(fallbackWorkouts: fallbackWorkouts, referenceDate: baseDate)

        XCTAssertEqual(viewModel.personalRecords.first?.metricType, .longestDistance)
        XCTAssertEqual(viewModel.personalRecords.first?.value, "11.0 km")
    }

    private var baseDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 7)) ?? Date()
    }

    private func makeProgress(
        workoutCount: Int,
        trendType: WeeklyWorkoutTrendType
    ) -> WeeklyWorkoutProgress {
        WeeklyWorkoutProgress(
            weekStartDate: baseDate,
            workoutCount: workoutCount,
            totalDistanceKm: Double(workoutCount) * 5,
            totalDurationMinutes: workoutCount * 30,
            averagePaceOrSpeedText: "평균 6:00/km",
            progressSummary: "주간 흐름 테스트",
            motivationText: "성장 흐름을 확인합니다.",
            trendType: trendType
        )
    }

    private func makeFourWeekTrend(trendType: FourWeekWorkoutTrendType) -> FourWeekWorkoutTrend {
        FourWeekWorkoutTrend(
            weeks: [
                WeeklyWorkoutTrendPoint(weekStartDate: baseDate.addingTimeInterval(-21 * 24 * 60 * 60), workoutCount: 1, totalDistanceKm: 4, totalDurationMinutes: 24),
                WeeklyWorkoutTrendPoint(weekStartDate: baseDate.addingTimeInterval(-14 * 24 * 60 * 60), workoutCount: 1, totalDistanceKm: 5, totalDurationMinutes: 30),
                WeeklyWorkoutTrendPoint(weekStartDate: baseDate.addingTimeInterval(-7 * 24 * 60 * 60), workoutCount: 1, totalDistanceKm: 7, totalDurationMinutes: 38),
                WeeklyWorkoutTrendPoint(weekStartDate: baseDate, workoutCount: 1, totalDistanceKm: 9, totalDurationMinutes: 48)
            ],
            trendType: trendType,
            summaryText: "4주 흐름 테스트",
            motivationText: "장기 성장 흐름을 확인합니다."
        )
    }

    private func makePersonalRecord(
        metricType: PersonalRecordMetricType,
        value: String
    ) -> PersonalRecord {
        PersonalRecord(
            workoutType: .running,
            metricType: metricType,
            value: value,
            achievedAt: baseDate,
            comparisonText: "개인 기록 테스트",
            motivationText: "성장 흐름을 확인합니다."
        )
    }

    private func makeWorkout(
        daysAgo: Int,
        distanceMeters: Double,
        duration: TimeInterval
    ) -> Workout {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: baseDate) ?? baseDate
        return Workout(
            id: UUID(),
            sport: .run,
            title: "테스트 러닝",
            date: date,
            distanceMeters: distanceMeters,
            duration: duration,
            activeCalories: 420,
            avgHeartRate: 148,
            maxHeartRate: 172,
            avgPower: nil,
            elevationGain: 30,
            cadence: 174,
            effort: 6,
            source: "테스트",
            route: [],
            splits: [],
            samples: [],
            zones: [],
            achievements: [],
            aiSummary: "테스트 운동입니다."
        )
    }
}

private enum TestError: Error {
    case failed
}

private final class FakeWeeklyWorkoutProgressProvider: WeeklyWorkoutProgressProviding {
    private let result: Result<WeeklyWorkoutProgress, Error>
    private(set) var requestedReferenceDate: Date?

    init(result: Result<WeeklyWorkoutProgress, Error>) {
        self.result = result
    }

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        requestedReferenceDate = referenceDate
        return try result.get()
    }
}

private final class FakeFourWeekWorkoutTrendProvider: FourWeekWorkoutTrendProviding {
    private let result: Result<FourWeekWorkoutTrend, Error>
    private(set) var requestedReferenceDate: Date?

    init(result: Result<FourWeekWorkoutTrend, Error>) {
        self.result = result
    }

    func fetchFourWeekTrend(referenceDate: Date) async throws -> FourWeekWorkoutTrend {
        requestedReferenceDate = referenceDate
        return try result.get()
    }
}

private final class FakePersonalRecordProvider: PersonalRecordProviding {
    private let result: Result<[PersonalRecord], Error>
    private(set) var requestedReferenceDate: Date?

    init(result: Result<[PersonalRecord], Error>) {
        self.result = result
    }

    func fetchPersonalRecords(referenceDate: Date) async throws -> [PersonalRecord] {
        requestedReferenceDate = referenceDate
        return try result.get()
    }
}

private final class SuspendedWeeklyWorkoutProgressProvider: WeeklyWorkoutProgressProviding {
    private var continuation: CheckedContinuation<WeeklyWorkoutProgress, Error>?
    private var requestedContinuation: CheckedContinuation<Void, Never>?

    func fetchWeeklyProgress(referenceDate: Date) async throws -> WeeklyWorkoutProgress {
        requestedContinuation?.resume()
        requestedContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        if continuation != nil { return }

        await withCheckedContinuation { continuation in
            requestedContinuation = continuation
        }
    }

    func succeed(with progress: WeeklyWorkoutProgress) {
        continuation?.resume(returning: progress)
        continuation = nil
    }
}
