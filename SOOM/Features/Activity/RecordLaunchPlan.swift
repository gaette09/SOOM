import Foundation
import CoreLocation

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

protocol RecordWeatherService {
    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot
}

struct FallbackRecordWeatherService: RecordWeatherService {
    let snapshot: RecordWeatherSnapshot

    init(snapshot: RecordWeatherSnapshot = .fallbackClear) {
        self.snapshot = snapshot
    }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> RecordWeatherSnapshot {
        snapshot
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
