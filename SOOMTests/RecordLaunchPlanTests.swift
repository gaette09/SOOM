import XCTest
@testable import SOOM

final class RecordLaunchPlanTests: XCTestCase {
    func testMockPlanStartsWithCyclingWithoutRequestingLocationPermission() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.defaultSport, .cycling)
        XCTAssertTrue(plan.usesMapboxWhenConfigured)
        XCTAssertFalse(plan.requiresLocationPermissionOnEntry)
        XCTAssertGreaterThanOrEqual(plan.route.coordinates.count, 2)
    }

    func testSportStartTitlesFollowSelectedSport() {
        XCTAssertEqual(RecordSportMode.cycling.startTitle, "라이딩 시작")
        XCTAssertEqual(RecordSportMode.running.startTitle, "러닝 시작")
        XCTAssertEqual(RecordSportMode.walking.startTitle, "걷기 시작")
    }

    func testRecommendationCopyChangesBySport() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.subtitle(for: .cycling).contains("라이딩"))
        XCTAssertTrue(recommendation.subtitle(for: .running).contains("조깅"))
        XCTAssertTrue(recommendation.subtitle(for: .walking).contains("걷기"))
    }

    func testRecordLaunchPlanDoesNotUseRecoveryCalculator() {
        let plan = RecordLaunchPlan.mockToday

        XCTAssertEqual(plan.recommendation.recoveryLabel, "회복 82 · 좋음")
        XCTAssertFalse(plan.route.title.isEmpty)
    }

    func testFallbackWeatherIsUsedWithoutCoordinate() async {
        let state = RecordLocationState(
            authorization: .authorized,
            coordinate: nil,
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: "valid-weather-key"
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.source, "fallback")
    }

    func testFallbackWeatherIsUsedWithoutAPIKey() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: nil
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.source, "fallback")
    }

    func testLiveWeatherCanBeFetchedAfterUserLocationExists() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: StubRecordWeatherService(snapshot: .liveClear),
            apiKey: "valid-weather-key"
        )

        XCTAssertFalse(snapshot.isFallback)
        XCTAssertEqual(snapshot.temperatureText, "23°")
        XCTAssertEqual(snapshot.conditionText, "맑음")
    }

    func testNetworkFailureFallsBackSafely() async {
        let state = authorizedLocationState()

        let snapshot = await RecordWeatherResolver.snapshot(
            for: state,
            service: FailingRecordWeatherService(),
            apiKey: "valid-weather-key"
        )

        XCTAssertTrue(snapshot.isFallback)
        XCTAssertEqual(snapshot.pillText, "26° · 맑음 · 바람 약함")
    }

    func testWeatherAPIKeyValidationRejectsPlaceholders() {
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey(nil))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey(""))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("$(WEATHER_API_KEY)"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("placeholder"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("replace_me"))
        XCTAssertNil(RecordWeatherServiceFactory.usableAPIKey("your_openweather_key"))
        XCTAssertEqual(RecordWeatherServiceFactory.usableAPIKey("live-key"), "live-key")
    }

    func testWeatherRecommendationCopyChangesWithConditions() {
        let recommendation = RecordLaunchPlan.mockToday.recommendation

        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .liveClear).contains("맑고 바람이 약해요"))
        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .rainy).contains("비가 오면"))
        XCTAssertTrue(recommendation.compactText(for: .cycling, weather: .windy).contains("바람이 강해요"))
    }

    func testWeatherPolicyDoesNotAttemptLiveFetchOnEntryWithoutCoordinate() {
        let state = RecordLocationState.mockCurrent

        XCTAssertFalse(state.shouldRequestPermissionOnEntry)
        XCTAssertFalse(RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: state, apiKey: "valid-weather-key"))
    }

    private func authorizedLocationState() -> RecordLocationState {
        RecordLocationState(
            authorization: .authorized,
            coordinate: RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
            fallbackCoordinate: RecordLocationState.fallbackCoordinate
        )
    }
}

private struct StubRecordWeatherService: RecordWeatherService {
    let snapshot: RecordWeatherSnapshot

    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        snapshot
    }
}

private struct FailingRecordWeatherService: RecordWeatherService {
    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        throw URLError(.cannotConnectToHost)
    }
}

private extension RecordWeatherSnapshot {
    static let liveClear = RecordWeatherSnapshot(
        temperatureCelsius: 23,
        condition: .clear,
        wind: RecordWeatherWind(speedMps: 1.8),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )

    static let rainy = RecordWeatherSnapshot(
        temperatureCelsius: 18,
        condition: .rain,
        wind: RecordWeatherWind(speedMps: 3.2),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )

    static let windy = RecordWeatherSnapshot(
        temperatureCelsius: 21,
        condition: .clear,
        wind: RecordWeatherWind(speedMps: 7.2),
        observedAt: Date(timeIntervalSince1970: 1_750_001_000),
        source: "test-live",
        isFallback: false
    )
}
