import CoreLocation
import SwiftUI
import MapboxMaps

struct WorkoutDetailMapView: View {
    let route: WorkoutRoute?
    let fallbackStyle: StaticRouteFallbackStyle
    let tint: Color

    private var coordinates: [CLLocationCoordinate2D] {
        route?.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? []
    }

    var body: some View {
        ZStack {
            if hasRenderableMap {
                MapboxRouteMap(
                    coordinates: coordinates,
                    bounds: route?.bounds,
                    tint: UIColor(tint)
                )
                .accessibilityHidden(true)
            } else {
                WorkoutDetailMapFallback(style: fallbackStyle, tint: tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

    private var hasRenderableMap: Bool {
        coordinates.count >= 2 && MapboxAccessTokenAvailability.hasUsableToken
    }
}

private struct MapboxRouteMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let bounds: WorkoutRouteBounds?
    let tint: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        mapView.ornaments.options.logo.margins = CGPoint(x: 10, y: 10)
        mapView.ornaments.options.attributionButton.margins = CGPoint(x: 10, y: 10)
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        context.coordinator.configure(mapView: mapView, coordinates: coordinates, bounds: bounds, tint: tint)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.configure(mapView: mapView, coordinates: coordinates, bounds: bounds, tint: tint)
    }

    final class Coordinator {
        private var annotationManager: PolylineAnnotationManager?
        private var lastSignature: String?

        func configure(
            mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?,
            tint: UIColor
        ) {
            let signature = coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
            guard signature != lastSignature else { return }
            lastSignature = signature

            if annotationManager == nil {
                annotationManager = mapView.annotations.makePolylineAnnotationManager()
            }

            var annotation = PolylineAnnotation(lineCoordinates: coordinates)
            annotation.lineColor = StyleColor(tint)
            annotation.lineWidth = 4
            annotation.lineOpacity = 0.9
            annotationManager?.annotations = [annotation]

            setCamera(on: mapView, coordinates: coordinates, bounds: bounds)
        }

        private func setCamera(
            on mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?
        ) {
            guard let center = centerCoordinate(from: coordinates, bounds: bounds) else { return }

            let camera = CameraOptions(
                center: center,
                padding: UIEdgeInsets(top: 36, left: 28, bottom: 72, right: 28),
                zoom: zoomEstimate(for: bounds),
                bearing: 0,
                pitch: 0
            )
            mapView.mapboxMap.setCamera(to: camera)
        }

        private func centerCoordinate(
            from coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?
        ) -> CLLocationCoordinate2D? {
            if let bounds {
                return CLLocationCoordinate2D(
                    latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                    longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
                )
            }

            guard !coordinates.isEmpty else { return nil }
            let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
            let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        private func zoomEstimate(for bounds: WorkoutRouteBounds?) -> CGFloat {
            guard let bounds else { return 12 }
            let latitudeDelta = max(bounds.maxLatitude - bounds.minLatitude, 0.001)
            let longitudeDelta = max(bounds.maxLongitude - bounds.minLongitude, 0.001)
            let span = max(latitudeDelta, longitudeDelta)

            switch span {
            case ..<0.01: return 14.5
            case ..<0.03: return 13.5
            case ..<0.08: return 12.5
            case ..<0.16: return 11.5
            default: return 10.5
            }
        }
    }
}

private struct WorkoutDetailMapFallback: View {
    let style: StaticRouteFallbackStyle
    let tint: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.18), SOOMColor.surface, SOOMColor.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: SOOMLayout.Metrics.tagSpacing) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                Text(fallbackText)
                    .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fallbackText)
    }

    private var iconName: String {
        switch style {
        case .running: return SOOMIcon.run
        case .cycling: return SOOMIcon.bike
        case .swimming: return SOOMIcon.swim
        case .walking: return "figure.walk"
        case .generic: return SOOMIcon.chartLine
        }
    }

    private var fallbackText: String {
        switch style {
        case .running: return "러닝 경로를 불러올 수 없어요"
        case .cycling: return "라이딩 경로를 불러올 수 없어요"
        case .swimming: return "수영 기록은 경로 없이 표시해요"
        case .walking: return "걷기 경로를 불러올 수 없어요"
        case .generic: return "운동 경로가 아직 없어요"
        }
    }
}

enum MapboxAccessTokenAvailability {
    static var hasUsableToken: Bool {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else {
            return false
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("$(") else { return false }
        guard !trimmed.localizedCaseInsensitiveContains("placeholder") else { return false }
        return true
    }
}
