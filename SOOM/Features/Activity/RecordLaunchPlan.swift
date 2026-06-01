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

struct RecordWeatherDetailSnapshot: Equatable {
    let locationName: String
    let temperatureText: String
    let conditionText: String
    let feelsLikeText: String
    let windText: String
    let fineDustText: String
    let ultraFineDustText: String
    let hourlyForecast: [String]
    let dailyForecast: [String]
    let isFallback: Bool

    static func make(from snapshot: RecordWeatherSnapshot) -> RecordWeatherDetailSnapshot {
        let temperature = snapshot.temperatureText
        return RecordWeatherDetailSnapshot(
            locationName: "현재 위치 근처",
            temperatureText: temperature,
            conditionText: snapshot.conditionText,
            feelsLikeText: temperature,
            windText: snapshot.windText ?? "바람 정보 없음",
            fineDustText: "보통",
            ultraFineDustText: "보통",
            hourlyForecast: ["지금 \(temperature)", "1시간 뒤 \(temperature)", "2시간 뒤 \(temperature)", "3시간 뒤 \(temperature)"],
            dailyForecast: ["오늘 \(snapshot.conditionText)", "내일 가벼운 흐림", "모레 맑음"],
            isFallback: snapshot.isFallback
        )
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
    static let pulseEndRadius: Double = 26
    static let pulseStartOpacity: Double = 0.14
    static let pulseDurationSeconds: TimeInterval = 1.9

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

enum RecordMapBottomFocusGradientLayout {
    static let defaultHeight: CGFloat = 120
    static let focusedHeight: CGFloat = 240
    static let defaultMiddleOpacity = 0.045
    static let defaultBottomOpacity = 0.09
    static let focusedMiddleOpacity = 0.18
    static let focusedBottomOpacity = 0.30
}

enum RecordReadyLaunchVisualLayout {
    static let containerHeight: CGFloat = 214
    static let buttonDiameter: CGFloat = 80
    static let buttonCenterBottomOffset: CGFloat = 54
    static let bottomPaddingExtra: CGFloat = 10
    static let iconSize: CGFloat = 18
    static let readyFontSize: CGFloat = 13
    static let hintFontSize: CGFloat = 7
    static let defaultShadowOpacity = 0.10
    static let focusedShadowOpacity = 0.16
    static let defaultShadowRadius: CGFloat = 8
    static let focusedShadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 7
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

    static let sportAngles: [RecordSportMode: Double] = [
        .cycling: 150,
        .running: 90,
        .walking: 30
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
}

enum RecordReadyRadialInteraction {
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
