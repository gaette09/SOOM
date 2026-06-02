import CoreLocation
import CoreGraphics
import Foundation

enum RecordSportMode: String, CaseIterable, Identifiable, Equatable {
    case cycling
    case running
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cycling:
            return "라이딩"
        case .running:
            return "러닝"
        case .walking:
            return "걷기"
        }
    }

    var startTitle: String {
        "\(title) 시작"
    }

    var iconName: String {
        switch self {
        case .cycling:
            return SOOMIcon.bike
        case .running:
            return SOOMIcon.run
        case .walking:
            return "figure.walk"
        }
    }

    var workoutType: UnifiedWorkoutType {
        switch self {
        case .cycling:
            return .cycling
        case .running:
            return .running
        case .walking:
            return .walking
        }
    }
}

struct RecordWeatherSnapshot: Equatable {
    let temperatureCelsius: Double?
    let condition: RecordWeatherCondition
    let wind: RecordWeatherWind?
    let observedAt: Date
    let source: String
    let isFallback: Bool

    init(
        temperatureCelsius: Double?,
        condition: RecordWeatherCondition,
        wind: RecordWeatherWind?,
        observedAt: Date,
        source: String,
        isFallback: Bool
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.condition = condition
        self.wind = wind
        self.observedAt = observedAt
        self.source = source
        self.isFallback = isFallback
    }

    var temperatureText: String {
        guard let temperatureCelsius else { return "--°" }
        return "\(Int(temperatureCelsius.rounded()))°"
    }

    var conditionText: String {
        condition.label
    }

    var conditionIconName: String {
        condition.iconName
    }

    var windText: String? {
        wind?.label
    }

    var pillText: String {
        if let windText {
            return "\(temperatureText) · \(conditionText) · \(windText)"
        }
        return "\(temperatureText) · \(conditionText)"
    }

    static let fallbackClear = RecordWeatherSnapshot(
        temperatureCelsius: 26,
        condition: .clear,
        wind: RecordWeatherWind(speedMps: 2.1),
        observedAt: Date(timeIntervalSince1970: 1_750_000_000),
        source: "fallback",
        isFallback: true
    )

    static let mockClear = fallbackClear
}

enum RecordWeatherCondition: String, Equatable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case unknown

    var label: String {
        switch self {
        case .clear:
            return "맑음"
        case .cloudy:
            return "흐림"
        case .rain:
            return "비"
        case .snow:
            return "눈"
        case .storm:
            return "폭풍"
        case .unknown:
            return "날씨"
        }
    }

    var iconName: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .cloudy:
            return "cloud.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "snowflake"
        case .storm:
            return "cloud.bolt.rain.fill"
        case .unknown:
            return "cloud.sun.fill"
        }
    }

    init(openWeatherConditionId: Int) {
        switch openWeatherConditionId {
        case 200..<300:
            self = .storm
        case 300..<600:
            self = .rain
        case 600..<700:
            self = .snow
        case 800:
            self = .clear
        case 801..<900:
            self = .cloudy
        default:
            self = .unknown
        }
    }
}

struct RecordWeatherWind: Equatable {
    let speedMps: Double

    var label: String {
        switch speedMps {
        case ..<2.5:
            return "바람 약함"
        case ..<6:
            return "바람 보통"
        default:
            return "바람 강함"
        }
    }
}

enum RecordAirQualityLevel: String, Equatable {
    case good
    case moderate
    case bad
    case veryBad

    var label: String {
        switch self {
        case .good:
            return "좋음"
        case .moderate:
            return "보통"
        case .bad:
            return "나쁨"
        case .veryBad:
            return "매우 나쁨"
        }
    }

    init(openWeatherAQI: Int) {
        switch openWeatherAQI {
        case 1:
            self = .good
        case 2, 3:
            self = .moderate
        case 4:
            self = .bad
        default:
            self = .veryBad
        }
    }
}

struct RecordAirQualitySnapshot: Equatable {
    let aqi: Int?
    let pm10: Double?
    let pm25: Double?
    let pm10Level: RecordAirQualityLevel
    let pm25Level: RecordAirQualityLevel

    var fineDustText: String {
        guard let pm10 else { return pm10Level.label }
        return "\(Int(pm10.rounded())) · \(pm10Level.label)"
    }

    var ultraFineDustText: String {
        guard let pm25 else { return pm25Level.label }
        return "\(Int(pm25.rounded())) · \(pm25Level.label)"
    }

    static let fallback = RecordAirQualitySnapshot(
        aqi: nil,
        pm10: nil,
        pm25: nil,
        pm10Level: .moderate,
        pm25Level: .moderate
    )
}

struct RecordHourlyWeather: Equatable, Identifiable {
    let id: String
    let timeLabel: String
    let iconName: String
    let temperatureCelsius: Double?

    var temperatureText: String {
        guard let temperatureCelsius else { return "--°" }
        return "\(Int(temperatureCelsius.rounded()))°"
    }
}

struct RecordDailyWeather: Equatable, Identifiable {
    let id: String
    let dayLabel: String
    let iconName: String
    let minTempCelsius: Double?
    let maxTempCelsius: Double?
    let conditionLabel: String

    var rangeText: String {
        let minText = minTempCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
        let maxText = maxTempCelsius.map { "\(Int($0.rounded()))°" } ?? "--°"
        return "\(minText) / \(maxText)"
    }
}

struct RecordWeatherDetailSnapshot: Equatable {
    let locationName: String
    let temperatureText: String
    let conditionText: String
    let conditionIconName: String
    let feelsLikeText: String
    let windText: String
    let airQuality: RecordAirQualitySnapshot
    let hourlyForecasts: [RecordHourlyWeather]
    let dailyForecasts: [RecordDailyWeather]
    let updatedAt: Date
    let isFallback: Bool

    var fineDustText: String {
        airQuality.fineDustText
    }

    var ultraFineDustText: String {
        airQuality.ultraFineDustText
    }

    static func make(from snapshot: RecordWeatherSnapshot) -> RecordWeatherDetailSnapshot {
        let temperature = snapshot.temperatureText
        let hourlyForecasts = [
            RecordHourlyWeather(id: "now", timeLabel: "지금", iconName: snapshot.conditionIconName, temperatureCelsius: snapshot.temperatureCelsius),
            RecordHourlyWeather(id: "plus-1", timeLabel: "1시간", iconName: snapshot.conditionIconName, temperatureCelsius: snapshot.temperatureCelsius),
            RecordHourlyWeather(id: "plus-2", timeLabel: "2시간", iconName: snapshot.conditionIconName, temperatureCelsius: snapshot.temperatureCelsius),
            RecordHourlyWeather(id: "plus-3", timeLabel: "3시간", iconName: snapshot.conditionIconName, temperatureCelsius: snapshot.temperatureCelsius)
        ]
        let dailyForecasts = [
            RecordDailyWeather(id: "today", dayLabel: "오늘", iconName: snapshot.conditionIconName, minTempCelsius: snapshot.temperatureCelsius.map { $0 - 2 }, maxTempCelsius: snapshot.temperatureCelsius.map { $0 + 2 }, conditionLabel: snapshot.conditionText),
            RecordDailyWeather(id: "tomorrow", dayLabel: "내일", iconName: RecordWeatherCondition.cloudy.iconName, minTempCelsius: snapshot.temperatureCelsius.map { $0 - 3 }, maxTempCelsius: snapshot.temperatureCelsius.map { $0 + 1 }, conditionLabel: "가벼운 흐림"),
            RecordDailyWeather(id: "plus-2", dayLabel: "모레", iconName: RecordWeatherCondition.clear.iconName, minTempCelsius: snapshot.temperatureCelsius.map { $0 - 1 }, maxTempCelsius: snapshot.temperatureCelsius.map { $0 + 3 }, conditionLabel: "맑음")
        ]

        return RecordWeatherDetailSnapshot(
            locationName: "현재 위치 근처",
            temperatureText: temperature,
            conditionText: snapshot.conditionText,
            conditionIconName: snapshot.conditionIconName,
            feelsLikeText: temperature,
            windText: snapshot.windText ?? "바람 정보 없음",
            airQuality: .fallback,
            hourlyForecasts: hourlyForecasts,
            dailyForecasts: dailyForecasts,
            updatedAt: snapshot.observedAt,
            isFallback: snapshot.isFallback
        )
    }
}

protocol RecordWeatherService {
    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot
    func fetchWeatherDetail(latitude: Double, longitude: Double) async throws -> RecordWeatherDetailSnapshot
}

extension RecordWeatherService {
    func fetchWeatherDetail(latitude: Double, longitude: Double) async throws -> RecordWeatherDetailSnapshot {
        let snapshot = try await fetchWeather(latitude: latitude, longitude: longitude)
        return RecordWeatherDetailSnapshot.make(from: snapshot)
    }
}

struct FallbackRecordWeatherService: RecordWeatherService {
    let snapshot: RecordWeatherSnapshot

    init(snapshot: RecordWeatherSnapshot = .fallbackClear) {
        self.snapshot = snapshot
    }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        snapshot
    }

    func fetchWeatherDetail(latitude: Double, longitude: Double) async throws -> RecordWeatherDetailSnapshot {
        RecordWeatherDetailSnapshot.make(from: snapshot)
    }
}

struct URLSessionRecordWeatherService: RecordWeatherService {
    let apiKey: String
    var session: URLSession = .shared

    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: "kr")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
        let conditionId = payload.weather.first?.id ?? 0
        return RecordWeatherSnapshot(
            temperatureCelsius: payload.main.temp,
            condition: RecordWeatherCondition(openWeatherConditionId: conditionId),
            wind: payload.wind?.speed.map(RecordWeatherWind.init(speedMps:)),
            observedAt: Date(timeIntervalSince1970: TimeInterval(payload.dt)),
            source: "openweather",
            isFallback: false
        )
    }

    func fetchWeatherDetail(latitude: Double, longitude: Double) async throws -> RecordWeatherDetailSnapshot {
        async let oneCallPayload = fetchOneCall(latitude: latitude, longitude: longitude)
        async let airPayload = fetchAirPollution(latitude: latitude, longitude: longitude)

        let payload = try await oneCallPayload
        let airQuality = (try? await airPayload)?.airQuality ?? .fallback
        let currentCondition = RecordWeatherCondition(openWeatherConditionId: payload.current.weather.first?.id ?? 0)
        let snapshot = RecordWeatherSnapshot(
            temperatureCelsius: payload.current.temp,
            condition: currentCondition,
            wind: payload.current.windSpeed.map(RecordWeatherWind.init(speedMps:)),
            observedAt: Date(timeIntervalSince1970: TimeInterval(payload.current.dt)),
            source: "openweather-one-call",
            isFallback: false
        )

        let hourlyForecasts = payload.hourly.prefix(8).enumerated().map { index, hour in
            RecordHourlyWeather(
                id: "hour-\(index)-\(hour.dt)",
                timeLabel: Self.hourLabel(from: hour.dt),
                iconName: RecordWeatherCondition(openWeatherConditionId: hour.weather.first?.id ?? 0).iconName,
                temperatureCelsius: hour.temp
            )
        }

        let dailyForecasts = payload.daily.prefix(5).enumerated().map { index, day in
            let condition = RecordWeatherCondition(openWeatherConditionId: day.weather.first?.id ?? 0)
            return RecordDailyWeather(
                id: "day-\(index)-\(day.dt)",
                dayLabel: Self.dayLabel(from: day.dt, index: index),
                iconName: condition.iconName,
                minTempCelsius: day.temp.min,
                maxTempCelsius: day.temp.max,
                conditionLabel: condition.label
            )
        }

        return RecordWeatherDetailSnapshot(
            locationName: "현재 위치 근처",
            temperatureText: snapshot.temperatureText,
            conditionText: snapshot.conditionText,
            conditionIconName: snapshot.conditionIconName,
            feelsLikeText: payload.current.feelsLike.map { "\(Int($0.rounded()))°" } ?? snapshot.temperatureText,
            windText: snapshot.windText ?? "바람 정보 없음",
            airQuality: airQuality,
            hourlyForecasts: hourlyForecasts.isEmpty ? RecordWeatherDetailSnapshot.make(from: snapshot).hourlyForecasts : hourlyForecasts,
            dailyForecasts: dailyForecasts.isEmpty ? RecordWeatherDetailSnapshot.make(from: snapshot).dailyForecasts : dailyForecasts,
            updatedAt: snapshot.observedAt,
            isFallback: false
        )
    }

    private func fetchOneCall(latitude: Double, longitude: Double) async throws -> OpenWeatherOneCallResponse {
        var components = URLComponents(string: "https://api.openweathermap.org/data/3.0/onecall")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: "kr"),
            URLQueryItem(name: "exclude", value: "minutely,alerts")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(OpenWeatherOneCallResponse.self, from: data)
    }

    private func fetchAirPollution(latitude: Double, longitude: Double) async throws -> OpenWeatherAirPollutionResponse {
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/air_pollution")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "appid", value: apiKey)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(OpenWeatherAirPollutionResponse.self, from: data)
    }

    private static func hourLabel(from timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH시"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func dayLabel(from timestamp: Int, index: Int) -> String {
        if index == 0 { return "오늘" }
        if index == 1 { return "내일" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

private struct OpenWeatherResponse: Decodable {
    struct Weather: Decodable {
        let id: Int
    }

    struct Main: Decodable {
        let temp: Double
    }

    struct Wind: Decodable {
        let speed: Double?
    }

    let weather: [Weather]
    let main: Main
    let wind: Wind?
    let dt: Int
}

private struct OpenWeatherOneCallResponse: Decodable {
    struct Weather: Decodable {
        let id: Int
    }

    struct Current: Decodable {
        let dt: Int
        let temp: Double?
        let feelsLike: Double?
        let windSpeed: Double?
        let weather: [Weather]

        enum CodingKeys: String, CodingKey {
            case dt
            case temp
            case feelsLike = "feels_like"
            case windSpeed = "wind_speed"
            case weather
        }
    }

    struct Hourly: Decodable {
        let dt: Int
        let temp: Double?
        let weather: [Weather]
    }

    struct DailyTemp: Decodable {
        let min: Double?
        let max: Double?
    }

    struct Daily: Decodable {
        let dt: Int
        let temp: DailyTemp
        let weather: [Weather]
    }

    let current: Current
    let hourly: [Hourly]
    let daily: [Daily]
}

private struct OpenWeatherAirPollutionResponse: Decodable {
    struct Main: Decodable {
        let aqi: Int
    }

    struct Components: Decodable {
        let pm10: Double?
        let pm25: Double?

        enum CodingKeys: String, CodingKey {
            case pm10
            case pm25 = "pm2_5"
        }
    }

    struct Item: Decodable {
        let main: Main
        let components: Components
    }

    let list: [Item]

    var airQuality: RecordAirQualitySnapshot {
        guard let item = list.first else { return .fallback }
        let pm10Level = Self.level(forPM10: item.components.pm10, fallbackAQI: item.main.aqi)
        let pm25Level = Self.level(forPM25: item.components.pm25, fallbackAQI: item.main.aqi)
        return RecordAirQualitySnapshot(
            aqi: item.main.aqi,
            pm10: item.components.pm10,
            pm25: item.components.pm25,
            pm10Level: pm10Level,
            pm25Level: pm25Level
        )
    }

    private static func level(forPM10 value: Double?, fallbackAQI: Int) -> RecordAirQualityLevel {
        guard let value else { return RecordAirQualityLevel(openWeatherAQI: fallbackAQI) }
        switch value {
        case ..<31:
            return .good
        case ..<81:
            return .moderate
        case ..<151:
            return .bad
        default:
            return .veryBad
        }
    }

    private static func level(forPM25 value: Double?, fallbackAQI: Int) -> RecordAirQualityLevel {
        guard let value else { return RecordAirQualityLevel(openWeatherAQI: fallbackAQI) }
        switch value {
        case ..<16:
            return .good
        case ..<36:
            return .moderate
        case ..<76:
            return .bad
        default:
            return .veryBad
        }
    }
}

enum RecordWeatherServiceFactory {
    static func make(
        apiKey: String? = configuredAPIKey(),
        fallback: RecordWeatherSnapshot = .fallbackClear
    ) -> RecordWeatherService {
        guard let key = usableAPIKey(apiKey) else {
            return FallbackRecordWeatherService(snapshot: fallback)
        }

        return URLSessionRecordWeatherService(apiKey: key)
    }

    static func configuredAPIKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        return environment["OPENWEATHER_API_KEY"]
            ?? environment["WEATHER_API_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "OPENWEATHER_API_KEY") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "WEATHER_API_KEY") as? String
    }

    static func usableAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        guard !trimmed.hasPrefix("$("),
              !trimmed.hasSuffix(")"),
              !lowercased.contains("placeholder"),
              !lowercased.contains("replace_me"),
              !lowercased.contains("your_") else {
            return nil
        }

        return trimmed
    }
}

enum RecordWeatherFetchPolicy {
    static func shouldAttemptLiveFetch(locationState: RecordLocationState, apiKey: String?) -> Bool {
        locationState.canShowUserLocation && RecordWeatherServiceFactory.usableAPIKey(apiKey) != nil
    }

    static func shouldAttemptLiveFetch(locationState: RecordLocationState) -> Bool {
        locationState.canShowUserLocation && RecordWeatherServiceFactory.usableAPIKey(
            RecordWeatherServiceFactory.configuredAPIKey()
        ) != nil
    }
}

struct RecordWeatherRetryState: Equatable {
    private(set) var lastAttemptCoordinateKey: String?
    private(set) var lastSuccessfulCoordinateKey: String?

    func shouldAttemptFetch(for coordinateKey: String, forceRefresh: Bool = false) -> Bool {
        forceRefresh || coordinateKey != lastSuccessfulCoordinateKey
    }

    mutating func markAttempt(for coordinateKey: String) {
        lastAttemptCoordinateKey = coordinateKey
    }

    mutating func markSuccess(for coordinateKey: String) {
        lastAttemptCoordinateKey = coordinateKey
        lastSuccessfulCoordinateKey = coordinateKey
    }

    mutating func markFailure(for coordinateKey: String) {
        lastAttemptCoordinateKey = coordinateKey
    }
}

enum RecordWeatherResolver {
    static func snapshot(
        for locationState: RecordLocationState,
        service: any RecordWeatherService,
        apiKey: String? = RecordWeatherServiceFactory.configuredAPIKey(),
        fallback: RecordWeatherSnapshot = .fallbackClear
    ) async -> RecordWeatherSnapshot {
        guard RecordWeatherFetchPolicy.shouldAttemptLiveFetch(locationState: locationState, apiKey: apiKey),
              let coordinate = locationState.coordinate else {
            return fallback
        }

        do {
            return try await service.fetchWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            return fallback
        }
    }
}

enum RecordWeatherRecommendationCopy {
    static func prefix(for weather: RecordWeatherSnapshot) -> String? {
        switch weather.condition {
        case .rain, .storm:
            return "비가 오면 짧게, 미끄럼만 조심해요"
        case .snow:
            return "길이 미끄러울 수 있어 짧게 시작해요"
        case .clear:
            if let speed = weather.wind?.speedMps, speed >= 6 {
                return "맑지만 바람이 강해요"
            }
            return "맑고 바람이 약해요"
        case .cloudy:
            if let speed = weather.wind?.speedMps, speed >= 6 {
                return "흐리고 바람이 강해요"
            }
            return "흐려도 리듬은 편해요"
        case .unknown:
            if let speed = weather.wind?.speedMps, speed >= 6 {
                return "바람이 강하면 순환 코스가 좋아요"
            }
            return nil
        }
    }
}

struct RecordRouteRecommendation: Equatable {
    let title: String
    let distanceText: String
    let durationText: String
    let reason: String
    let coordinates: [RecordMapCoordinate]

    static let mockHanRiver = RecordRouteRecommendation(
        title: "한강 가벼운 코스",
        distanceText: "9.2 km",
        durationText: "45분",
        reason: "회복 흐름에 맞는 코스",
        coordinates: [
            RecordMapCoordinate(latitude: 37.5274, longitude: 126.9089),
            RecordMapCoordinate(latitude: 37.5282, longitude: 126.9134),
            RecordMapCoordinate(latitude: 37.5287, longitude: 126.9182),
            RecordMapCoordinate(latitude: 37.5286, longitude: 126.9235),
            RecordMapCoordinate(latitude: 37.5279, longitude: 126.9292),
            RecordMapCoordinate(latitude: 37.5271, longitude: 126.9347),
            RecordMapCoordinate(latitude: 37.5267, longitude: 126.9405),
            RecordMapCoordinate(latitude: 37.5269, longitude: 126.9460),
            RecordMapCoordinate(latitude: 37.5277, longitude: 126.9512),
            RecordMapCoordinate(latitude: 37.5291, longitude: 126.9561)
        ]
    )
}

struct RecordMapCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RecordLaunchRecommendation: Equatable {
    let recoveryLabel: String
    let title: String
    let subtitle: String

    func subtitle(for sport: RecordSportMode) -> String {
        switch sport {
        case .cycling:
            return "Z2 라이딩 40분 또는 강변 가벼운 코스를 추천해요."
        case .running:
            return "가벼운 조깅 25분으로 호흡을 먼저 살펴봐요."
        case .walking:
            return "천천히 걷기 30분으로 오늘 리듬을 열어봐요."
        }
    }

    func compactText(for sport: RecordSportMode, weather: RecordWeatherSnapshot) -> String {
        let sportText: String
        switch sport {
        case .cycling:
            sportText = "Z2 40분"
        case .running:
            sportText = "조깅 25분"
        case .walking:
            sportText = "걷기 30분"
        }

        guard let weatherPrefix = RecordWeatherRecommendationCopy.prefix(for: weather) else {
            return sportText
        }

        return "\(weatherPrefix) · \(sportText)"
    }

    func guidanceText(for sport: RecordSportMode, weather: RecordWeatherSnapshot) -> String {
        let sportText: String
        switch sport {
        case .cycling:
            sportText = "Z2 40분으로 리듬을 이어가요."
        case .running:
            sportText = "30분 조깅으로 호흡을 맞춰요."
        case .walking:
            sportText = "25분 걷기로 몸을 깨워요."
        }

        guard let weatherPrefix = RecordWeatherRecommendationCopy.prefix(for: weather) else {
            return sportText
        }

        return "\(weatherPrefix). \(sportText)"
    }
}

enum RecordLaunchControl: String, CaseIterable, Equatable {
    case weather
    case routeRecommendation
    case currentLocation

    static let rightEdgeOrder: [RecordLaunchControl] = [
        .weather,
        .routeRecommendation,
        .currentLocation
    ]

    var iconName: String {
        switch self {
        case .weather:
            return "sun.max.fill"
        case .routeRecommendation:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .currentLocation:
            return "location.fill"
        }
    }
}

struct RecordMapHeaderFrames: Equatable {
    let bannerFrame: CGRect
    let backButtonCenter: CGPoint
    let rightControlsFrame: CGRect
    let rightControlCenters: [CGPoint]

    var rightControlsTop: CGFloat {
        rightControlsFrame.minY
    }

    var weatherButtonTop: CGFloat {
        rightControlsFrame.minY
    }
}

enum RecordMapHeaderLayout {
    static let usesTopHeaderLayer = true
    static let usesMapOverlayGuidanceCard = false
    static let usesUnifiedFrameSource = true
    static let topHeaderInsetBelowSafeArea: CGFloat = 12
    static let guidanceHorizontalInset: CGFloat = 36
    static let guidanceHeight: CGFloat = 78
    static let guidanceMinHeight: CGFloat = 76
    static let guidanceMaxHeight: CGFloat = 82
    static let guidanceCornerRadius: CGFloat = 22
    static let maxBodyLineCount = 2
    static let showsRouteStripByDefault = false
    static let routeRecommendationUsesRightControlOnly = true
    static let maxVisualTopRatio: CGFloat = 0.12
    static let maxVisualBottomRatio: CGFloat = 0.22
    static let backButtonCenterX: CGFloat = 52
    static let backButtonCenterSpacingBelowGuidance: CGFloat = 30
    static let rightControlCenterTrailingInset: CGFloat = 54
    static let rightControlsTopSpacingBelowGuidance: CGFloat = 12
    static let controlSize: CGFloat = 46
    static let controlSpacing: CGFloat = 10

    static func guidanceTopY(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + topHeaderInsetBelowSafeArea
    }

    static func guidanceBottomY(safeAreaTop: CGFloat) -> CGFloat {
        guidanceTopY(safeAreaTop: safeAreaTop) + guidanceHeight
    }

    static func backButtonCenterY(safeAreaTop: CGFloat) -> CGFloat {
        guidanceBottomY(safeAreaTop: safeAreaTop) + backButtonCenterSpacingBelowGuidance
    }

    static func rightControlsTopY(safeAreaTop: CGFloat) -> CGFloat {
        guidanceBottomY(safeAreaTop: safeAreaTop) + rightControlsTopSpacingBelowGuidance
    }

    static var rightControlsStackHeight: CGFloat {
        controlSize * 3 + controlSpacing * 2
    }

    static func visualTopRatio(safeAreaTop: CGFloat, screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return 0 }
        return guidanceTopY(safeAreaTop: safeAreaTop) / screenHeight
    }

    static func visualBottomRatio(safeAreaTop: CGFloat, screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return 0 }
        return guidanceBottomY(safeAreaTop: safeAreaTop) / screenHeight
    }

    static func frames(containerSize: CGSize, safeAreaTop: CGFloat) -> RecordMapHeaderFrames {
        let bannerWidth = max(0, containerSize.width - guidanceHorizontalInset * 2)
        let bannerFrame = CGRect(
            x: guidanceHorizontalInset,
            y: guidanceTopY(safeAreaTop: safeAreaTop),
            width: bannerWidth,
            height: guidanceHeight
        )
        let backButtonCenter = CGPoint(
            x: backButtonCenterX,
            y: backButtonCenterY(safeAreaTop: safeAreaTop)
        )
        let rightControlsTop = rightControlsTopY(safeAreaTop: safeAreaTop)
        let rightControlsFrame = CGRect(
            x: containerSize.width - rightControlCenterTrailingInset - controlSize / 2,
            y: rightControlsTop,
            width: controlSize,
            height: rightControlsStackHeight
        )
        let rightControlCenters = RecordLaunchControl.rightEdgeOrder.enumerated().map { index, _ in
            CGPoint(
                x: rightControlsFrame.midX,
                y: rightControlsTop + controlSize / 2 + CGFloat(index) * (controlSize + controlSpacing)
            )
        }

        return RecordMapHeaderFrames(
            bannerFrame: bannerFrame,
            backButtonCenter: backButtonCenter,
            rightControlsFrame: rightControlsFrame,
            rightControlCenters: rightControlCenters
        )
    }
}

enum RecordMapOrnamentLayout {
    static let bottomInset: CGFloat = 8
    static let horizontalInset: CGFloat = 12
}

enum RecordCurrentLocationMarkerStyle {
    static let dotRadius: Double = 8
    static let fallbackDotRadius: Double = 6
    static let staticHaloRadius: Double = 14
    static let pulseStartRadius: Double = 20
    static let pulseEndRadius: Double = 25
    static let pulseStartOpacity: Double = 0.13
    static let pulseDurationSeconds: TimeInterval = 1.9
    static let fallbackStaticHaloDiameter: CGFloat = 56
    static let anchorOffset = CGSize(width: 0, height: 0)

    static func pulseRadius(progress: Double) -> Double {
        pulseStartRadius + (pulseEndRadius - pulseStartRadius) * max(0, min(1, progress))
    }

    static func pulseOpacity(progress: Double) -> Double {
        pulseStartOpacity * (1 - max(0, min(1, progress)))
    }

    static func isPulseEnabled(canShowUserLocation: Bool, reduceMotionEnabled: Bool) -> Bool {
        canShowUserLocation && !reduceMotionEnabled
    }
}

enum RecordBreathingBottomWaveLayout {
    static let waveHeight: CGFloat = 360
    static let blobWidthMultiplier: CGFloat = 2.4
    static let blobBaseHeight: CGFloat = 620
    static let blobFrameHeightMultiplier: CGFloat = 1.8
    static let blobCenterYOffset: CGFloat = 270
    static let blobEndRadiusMultiplier: CGFloat = 0.84
    static let blobScaleInhale: CGFloat = 0.98
    static let blobScaleExhale: CGFloat = 1.05
    static let blobInteractionScale: CGFloat = 0.96
    static let radialBlobOpacityStops: [(location: CGFloat, opacity: Double)] = [
        (0.00, 1.0),
        (0.45, 0.95),
        (0.65, 0.55),
        (0.82, 0.18),
        (1.00, 0.0)
    ]
    static let inhaleProgress: CGFloat = 0
    static let exhaleProgress: CGFloat = 1
    static let reducedMotionProgress: CGFloat = 0.5
    static let interactionProgress: CGFloat = 0
    static let inhaleOpacity = 0.82
    static let exhaleOpacity = 1.0
    static let reducedMotionOpacity = 0.91
    static let interactionOpacity = 0.45
    static let previousInhaleYOffset: CGFloat = 22
    static let previousExhaleYOffset: CGFloat = -4
    static let inhaleYOffset: CGFloat = 30
    static let exhaleYOffset: CGFloat = 8
    static let reducedMotionYOffset: CGFloat = 20
    static let interactionYOffset: CGFloat = 42
    static let breathingDuration: TimeInterval = 3.2
    static let transitionDuration: TimeInterval = 0.22
    static let usesLegacyBottomGradient = false
    static let usesReferenceWaveView = false
    static let usesBottomBlobWaveView = false
    static let usesRecordBreathingBottomWaveView = true
    static let usesCustomProgressShape = false
    static let usesCustomBezierWaveShape = false
    static let usesCircleOrEllipseGeometry = false
    static let usesRadialBlobFill = true
    static let usesRadialGradientFill = true
    static let usesEllipticalRadialFade = false
    static let usesAlphaMaskFade = false
    static let alphaMaskUsesSolidPurpleFill = false
    static let usesOversizedRadialBlob = true
    static let usesDirectRadialBlobGradient = true
    static let clipsToCustomWaveShape = false
    static let visibleShapeEdgeCanReachScreen = false
    static let usesLinearGradientFill = false
    static let usesBlurOverlay = false
    static let usesSolidRectangleLayer = false
    static let usesLinearGradientBackground = false
    static let usesRectangularTopEdge = false
    static let usesTopStrokeOrBorder = false
    static let usesTopShadowOrOverlay = false
    static let usesCustomShapeClippingEdge = false
    static let allowsHitTesting = false
    static let waveBottomFullyOpaque = true
    static let waveOutsideTransparent = true
    static let breathingLoopsBetweenTwoStates = true
    static let breathingChangesShape = true
    static let disablesBreathingForReduceMotion = true
    static let repeatForeverAutoreverses = true

    static func blobScale(progress: CGFloat) -> CGFloat {
        interpolate(from: blobScaleInhale, to: blobScaleExhale, progress: progress)
    }

    static func blobHeight(for screenWidth: CGFloat) -> CGFloat {
        max(blobBaseHeight, screenWidth * 1.32)
    }

    static func blobWidth(for screenWidth: CGFloat) -> CGFloat {
        max(screenWidth * blobWidthMultiplier, blobHeight(for: screenWidth))
    }

    static func blobFrameHeight(for screenWidth: CGFloat) -> CGFloat {
        blobHeight(for: screenWidth) * blobFrameHeightMultiplier
    }

    static func blobEndRadius(for screenWidth: CGFloat) -> CGFloat {
        blobHeight(for: screenWidth) * blobEndRadiusMultiplier
    }

    static func opacity(progress: CGFloat) -> Double {
        Double(interpolate(from: CGFloat(inhaleOpacity), to: CGFloat(exhaleOpacity), progress: progress))
    }

    static func yOffset(progress: CGFloat) -> CGFloat {
        interpolate(from: inhaleYOffset, to: exhaleYOffset, progress: progress)
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        let clampedProgress = max(0, min(1, progress))
        return start + (end - start) * clampedProgress
    }
}

enum RecordReadyWaveInteractionState: CaseIterable, Equatable {
    case idle
    case revealing
    case dragging
    case confirmed
    case cancelled

    var weakensWave: Bool {
        switch self {
        case .revealing, .dragging:
            return true
        case .idle, .confirmed, .cancelled:
            return false
        }
    }

    var restoresBreathing: Bool {
        switch self {
        case .idle, .confirmed, .cancelled:
            return true
        case .revealing, .dragging:
            return false
        }
    }

    var isIdleBreathingActive: Bool {
        self == .idle
    }
}

enum RecordReadyLaunchVisualLayout {
    static let coordinateSpaceName = "record-ready-launch-control"
    static let containerHeight: CGFloat = 214
    static let buttonDiameter: CGFloat = 104
    static let interactiveHitDiameter: CGFloat = buttonDiameter
    static let maxInteractiveHitDiameter: CGFloat = 112
    static let usesCircleContentShape = true
    static let attachesGestureToButtonOnly = true
    static let containerUsesRectangularContentShape = false
    static let decorativeLayersAllowHitTesting = false
    static let buttonCenterBottomOffset: CGFloat = 80
    static let previousButtonCenterBottomOffset: CGFloat = 54
    static let bottomPaddingExtra: CGFloat = 10
    static let primaryIconName = "play.fill"
    static let primaryLabel = ""
    static let playIconSize: CGFloat = 34
    static let usesBlackSurface = true
    static let hidesSportIconInButton = true
    static let hidesReadyText = true
    static let hidesStartHintInButton = true
    static let defaultShadowOpacity = 0.18
    static let focusedShadowOpacity = 0.08
    static let defaultShadowRadius: CGFloat = 12
    static let focusedShadowRadius: CGFloat = 7
    static let shadowYOffset: CGFloat = 8
    static let hasBreathingRing = true
    static let ringMinScale: CGFloat = 1.0
    static let ringMaxScale: CGFloat = 1.06
    static let ringMinOpacity = 0.22
    static let ringMaxOpacity = 0.38
    static let focusedRingOpacity = 0.12
    static let ringLineWidth: CGFloat = 1.35
    static let ringDuration: TimeInterval = 3.25
    static let disablesRingBreathingForReduceMotion = true
}

enum RecordFixedSheetLayout {
    static let weatherHeight: CGFloat = 600
    static let routeRecommendationHeight: CGFloat = 500
    static let coachDetailHeight: CGFloat = 420
    static let usesSingleFixedDetent = true
    static let usesInternalScrollOnly = true
}

struct RecordReadyRadialItem: Equatable {
    let sport: RecordSportMode
    let angleDegrees: Double
    let center: CGPoint
}

enum RecordReadyRadialHapticEvent: Equatable {
    case longPressStarted
    case menuRevealed
    case hoverChanged
    case releaseConfirmed
    case releaseCancelled
}

enum RecordReadyRadialLayout {
    static let radius: CGFloat = 106
    static let hitRadius: CGFloat = 42
    static let touchRevealMinimumDistance: CGFloat = 0
    static let sportIconInitialScale: CGFloat = 0.30
    static let sportIconFinalScale: CGFloat = 1.0
    static let hoveredScale: CGFloat = 1.14

    static let sportAngles: [RecordSportMode: Double] = [
        .cycling: 150,
        .running: 90,
        .walking: 30
    ]

    static let revealDelays: [RecordSportMode: Double] = [
        .cycling: 0.00,
        .running: 0.05,
        .walking: 0.10
    ]

    static func items(center: CGPoint, radius: CGFloat = Self.radius) -> [RecordReadyRadialItem] {
        RecordSportMode.allCases.compactMap { sport in
            guard let angle = sportAngles[sport] else { return nil }
            return RecordReadyRadialItem(
                sport: sport,
                angleDegrees: angle,
                center: point(center: center, radius: radius, angleDegrees: angle)
            )
        }
    }

    static func point(center: CGPoint, radius: CGFloat, angleDegrees: Double) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y - sin(radians) * radius
        )
    }

    static func hoveredSport(
        at location: CGPoint,
        readyCenter: CGPoint,
        radius: CGFloat = Self.radius,
        hitRadius: CGFloat = Self.hitRadius
    ) -> RecordSportMode? {
        let candidates = items(center: readyCenter, radius: radius)
            .map { item -> (sport: RecordSportMode, distance: CGFloat) in
                let dx = item.center.x - location.x
                let dy = item.center.y - location.y
                return (item.sport, sqrt(dx * dx + dy * dy))
            }
            .sorted { $0.distance < $1.distance }

        guard let closest = candidates.first, closest.distance <= hitRadius else {
            return nil
        }

        return closest.sport
    }

    static func isUpperSemicircle(angleDegrees: Double) -> Bool {
        (0...180).contains(angleDegrees)
    }

    static func isAboveReadyCenter(item: RecordReadyRadialItem, readyCenter: CGPoint) -> Bool {
        item.center.y < readyCenter.y
    }

    static func displayCenter(for item: RecordReadyRadialItem, readyCenter: CGPoint, isRevealed: Bool) -> CGPoint {
        isRevealed ? item.center : readyCenter
    }
}

enum RecordReadyRadialInteraction {
    static func isTouchInsideReadyButton(
        location: CGPoint,
        readyCenter: CGPoint,
        hitDiameter: CGFloat = RecordReadyLaunchVisualLayout.interactiveHitDiameter
    ) -> Bool {
        let dx = location.x - readyCenter.x
        let dy = location.y - readyCenter.y
        let distance = hypot(dx, dy)
        return distance <= hitDiameter / 2
    }

    static func begin() -> [RecordReadyRadialHapticEvent] {
        [.longPressStarted, .menuRevealed]
    }

    static func hoverEvents(previous: RecordSportMode?, next: RecordSportMode?) -> [RecordReadyRadialHapticEvent] {
        previous != next ? [.hoverChanged] : []
    }

    static func release(hoveredSport: RecordSportMode?) -> [RecordReadyRadialHapticEvent] {
        hoveredSport == nil ? [.releaseCancelled] : [.releaseConfirmed]
    }

    static func shouldStartWorkout(isRadialSelectionActive: Bool, hoveredSport: RecordSportMode?) -> Bool {
        isRadialSelectionActive && hoveredSport != nil
    }
}

struct RecordRouteCatalogOption: Identifiable, Equatable {
    let id: String
    let route: RecordRouteRecommendation
    let tag: String

    static func mockOptions(for sport: RecordSportMode) -> [RecordRouteCatalogOption] {
        [
            RecordRouteCatalogOption(
                id: "han-river-recovery",
                route: .mockHanRiver,
                tag: "Z2 추천"
            ),
            RecordRouteCatalogOption(
                id: "tancheon-light-loop",
                route: RecordRouteRecommendation(
                    title: "탄천 가벼운 루프",
                    distanceText: "12.4 km",
                    durationText: sport == .running ? "65분" : "52분",
                    reason: "바람 약한 날 추천",
                    coordinates: [
                        RecordMapCoordinate(latitude: 37.4950, longitude: 127.0810),
                        RecordMapCoordinate(latitude: 37.4984, longitude: 127.0840),
                        RecordMapCoordinate(latitude: 37.5022, longitude: 127.0878),
                        RecordMapCoordinate(latitude: 37.5070, longitude: 127.0916),
                        RecordMapCoordinate(latitude: 37.5128, longitude: 127.0945)
                    ]
                ),
                tag: "가벼운 루프"
            ),
            RecordRouteCatalogOption(
                id: "neighborhood-short",
                route: RecordRouteRecommendation(
                    title: "동네 짧은 코스",
                    distanceText: "4.8 km",
                    durationText: sport == .walking ? "55분" : "28분",
                    reason: "회복 흐름에 맞는 짧은 코스",
                    coordinates: [
                        RecordMapCoordinate(latitude: 37.5266, longitude: 126.9271),
                        RecordMapCoordinate(latitude: 37.5272, longitude: 126.9300),
                        RecordMapCoordinate(latitude: 37.5264, longitude: 126.9327),
                        RecordMapCoordinate(latitude: 37.5251, longitude: 126.9341)
                    ]
                ),
                tag: "회복 추천"
            ),
            RecordRouteCatalogOption(
                id: "long-rhythm",
                route: RecordRouteRecommendation(
                    title: "장거리 리듬 코스",
                    distanceText: "32 km",
                    durationText: "1시간 45분",
                    reason: "컨디션 좋을 때 이어가기",
                    coordinates: [
                        RecordMapCoordinate(latitude: 37.5291, longitude: 126.9561),
                        RecordMapCoordinate(latitude: 37.5318, longitude: 126.9650),
                        RecordMapCoordinate(latitude: 37.5342, longitude: 126.9758),
                        RecordMapCoordinate(latitude: 37.5360, longitude: 126.9884),
                        RecordMapCoordinate(latitude: 37.5384, longitude: 127.0015)
                    ]
                ),
                tag: "컨디션 좋을 때"
            )
        ]
    }
}

struct RecordLaunchPlan: Equatable {
    let defaultSport: RecordSportMode
    let recommendation: RecordLaunchRecommendation
    let route: RecordRouteRecommendation
    let usesMapboxWhenConfigured: Bool
    let requiresLocationPermissionOnEntry: Bool

    static let mockToday = RecordLaunchPlan(
        defaultSport: .cycling,
        recommendation: RecordLaunchRecommendation(
            recoveryLabel: "회복 82 · 좋음",
            title: "오늘은 가볍게 이어가도 좋아요",
            subtitle: "Z2 라이딩 40분 또는 가벼운 조깅을 추천해요"
        ),
        route: .mockHanRiver,
        usesMapboxWhenConfigured: true,
        requiresLocationPermissionOnEntry: false
    )
}
