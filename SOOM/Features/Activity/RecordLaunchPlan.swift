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
}

struct RecordWeatherSnapshot: Equatable {
    let temperatureText: String
    let conditionText: String
    let windText: String?

    static let mockClear = RecordWeatherSnapshot(
        temperatureText: "26°",
        conditionText: "맑음",
        windText: "바람 약함"
    )
}

struct RecordRouteRecommendation: Equatable {
    let title: String
    let distanceText: String
    let durationText: String
    let reason: String
    let coordinates: [RecordMapCoordinate]

    static let mockHanRiver = RecordRouteRecommendation(
        title: "한강 가벼운 코스",
        distanceText: "8.6 km",
        durationText: "45분",
        reason: "회복 흐름에 맞는 코스",
        coordinates: [
            RecordMapCoordinate(latitude: 37.5253, longitude: 126.9148),
            RecordMapCoordinate(latitude: 37.5204, longitude: 126.9238),
            RecordMapCoordinate(latitude: 37.5228, longitude: 126.9362),
            RecordMapCoordinate(latitude: 37.5302, longitude: 126.9448),
            RecordMapCoordinate(latitude: 37.5364, longitude: 126.9360),
            RecordMapCoordinate(latitude: 37.5328, longitude: 126.9220)
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
}

struct RecordLaunchPlan: Equatable {
    let defaultSport: RecordSportMode
    let recommendation: RecordLaunchRecommendation
    let weather: RecordWeatherSnapshot
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
        weather: .mockClear,
        route: .mockHanRiver,
        usesMapboxWhenConfigured: true,
        requiresLocationPermissionOnEntry: false
    )
}
