import CoreLocation
import SwiftUI
import MapboxMaps

/// Cache exact geometry identity without formatting every GPS point on each playback tick.
/// Segment boundaries are part of the identity: no simplification or gap bridging occurs.
struct WorkoutRouteGeometryRevision {
    private var coordinates: [CLLocationCoordinate2D] = []
    private var segments: [[CLLocationCoordinate2D]] = []
    private(set) var revision = 0

    mutating func update(coordinates next: [CLLocationCoordinate2D],
                         segments nextSegments: [[CLLocationCoordinate2D]] = []) -> Int {
        let unchanged = Self.equal(coordinates, next) && segments.count == nextSegments.count
            && zip(segments, nextSegments).allSatisfy { Self.equal($0.0, $0.1) }
        if !unchanged {
            coordinates = next; segments = nextSegments; revision += 1
        }
        return revision
    }

    private static func equal(_ a: [CLLocationCoordinate2D], _ b: [CLLocationCoordinate2D]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
        }
    }
}

/// Per-mounted-map cache. Exact source equality includes privacy flags and segment
/// boundaries; nil/revoked input clears immediately. No cross-account or disk state.
@MainActor final class WorkoutRouteRenderCache {
    struct Snapshot {
        let route: WorkoutRoute?
        let coordinates: [CLLocationCoordinate2D]
        let segments: [[CLLocationCoordinate2D]]
    }
    private var source: WorkoutRoute?
    private var value: Snapshot?
    private(set) var preparations = 0
    func resolve(_ next: WorkoutRoute?) -> Snapshot {
        if let value, source == next { return value }
        source = next
        let route = next.map { RoutePrivacyMasker().mask(route: $0) }
        let result = Snapshot(route: route,
            coordinates: route?.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? [],
            segments: route?.coordinateSegments.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } } ?? [])
        preparations += 1; value = result
        return result
    }
}

struct WorkoutDetailMapView: View {
    let route: WorkoutRoute?
    let fallbackStyle: StaticRouteFallbackStyle
    let tint: Color
    var routeLineWidth: Double = SOOMRouteRenderingStyle.detailLineWidth
    var compactRouteOnly = false
    var feedCardPresentation = false
    var achievements: [WorkoutAchievement] = []
    var playbackProgress: Double? = nil

    @State private var renderCache = WorkoutRouteRenderCache()

    var body: some View {
        let geometry = renderCache.resolve(route)
        let displayRoute = geometry.route
        let coordinates = geometry.coordinates
        let hasRenderableMap = coordinates.count >= 2 && MapboxAccessTokenAvailability.hasUsableToken
        ZStack {
            if hasRenderableMap, compactRouteOnly, let route = displayRoute {
                WorkoutRecordRoutePreview(route: route)
                SOOMMapboxRouteThumbnail(route: route)
                    .accessibilityHidden(true)
            } else if hasRenderableMap {
                SOOMMapboxRouteMap(
                    coordinates: coordinates,
                    coordinateSegments: geometry.segments,
                    bounds: displayRoute?.bounds,
                    tint: SOOMRouteRenderingStyle.accentUIColor,
                    lineWidth: routeLineWidth,
                    cameraPadding: compactRouteOnly ? UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) : (feedCardPresentation ? UIEdgeInsets(top: 24, left: 24, bottom: 36, right: 24) : UIEdgeInsets(top: 36, left: 28, bottom: 72, right: 28)),
                    showsScaleBar: !feedCardPresentation,
                    routeFitInset: feedCardPresentation ? 8 : WorkoutRouteCameraPadding.visibleRouteInset,
                    cameraZoomOutset: feedCardPresentation ? 0 : 0.15,
                    compactRouteOnly: compactRouteOnly,
                    achievements: compactRouteOnly ? [] : achievements,
                    playbackProgress: playbackProgress
                )
                .accessibilityHidden(true)
            } else if compactRouteOnly, let route = displayRoute {
                WorkoutRecordRoutePreview(route: route)
            } else {
                WorkoutDetailMapFallback(style: fallbackStyle, tint: tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
    }

}

/// The small photo inset has no room for map ornaments. Attribution is shown
/// alongside the photo by its parent; the full-size map retains native ornaments.
private struct SOOMMapboxRouteThumbnail: UIViewRepresentable {
    let route: WorkoutRoute

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SOOMRouteThumbnailImageView {
        let view = SOOMRouteThumbnailImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.onLayoutSizeChange = { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            coordinator?.renderIfNeeded(in: view)
        }
        context.coordinator.route = route
        return view
    }

    func updateUIView(_ view: SOOMRouteThumbnailImageView, context: Context) {
        context.coordinator.route = route
        context.coordinator.renderIfNeeded(in: view)
    }

    static func dismantleUIView(_ view: SOOMRouteThumbnailImageView, coordinator: Coordinator) {
        view.onLayoutSizeChange = nil
        coordinator.cancel()
    }

    final class Coordinator {
        var route: WorkoutRoute?
        private var snapshotter: Snapshotter?
        private var styleObserver: AnyCancelable?
        private var signature: String?
        private var generation = UUID()

        func cancel() {
            generation = UUID()
            styleObserver?.cancel()
            styleObserver = nil
            snapshotter?.cancel()
            snapshotter = nil
        }

        func renderIfNeeded(in imageView: UIImageView) {
            let size = imageView.bounds.size
            guard size.width > 0, size.height > 0, let route else { return }
            let segments = route.coordinateSegments.filter { $0.count >= 2 }.map { segment in
                segment.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            }
            let coordinates = segments.flatMap { $0 }
            guard coordinates.count >= 2 else { return }
            let nextSignature = coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
                + "|\(segments.map(\.count))|\(size.width),\(size.height)"
            guard nextSignature != signature else { return }
            signature = nextSignature
            cancel()
            let request = generation
            MapboxAccessTokenAvailability.configureMapboxOptionsIfNeeded()
            let snapshotter = Snapshotter(options: MapSnapshotOptions(
                size: size, pixelRatio: imageView.traitCollection.displayScale,
                showsLogo: false, showsAttribution: false
            ))
            self.snapshotter = snapshotter
            styleObserver = snapshotter.onStyleLoaded.observeNext { [weak self, weak imageView, weak snapshotter] _ in
                guard let self, self.generation == request, let snapshotter else { return }
                let camera = snapshotter.camera(for: coordinates,
                    padding: UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7), bearing: 0, pitch: 0)
                snapshotter.setCamera(to: camera)
                snapshotter.start(overlayHandler: { overlay in
                    let path = CGMutablePath()
                    for segment in segments {
                        guard let first = segment.first else { continue }
                        path.move(to: overlay.pointForCoordinate(first))
                        for point in segment.dropFirst() { path.addLine(to: overlay.pointForCoordinate(point)) }
                    }
                    overlay.context.setLineCap(.round)
                    overlay.context.setLineJoin(.round)
                    overlay.context.addPath(path)
                    overlay.context.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                    overlay.context.setLineWidth(4)
                    overlay.context.strokePath()
                    overlay.context.addPath(path)
                    overlay.context.setStrokeColor(SOOMRouteRenderingStyle.accentUIColor.cgColor)
                    overlay.context.setLineWidth(2.4)
                    overlay.context.strokePath()
                }) { [weak self, weak imageView] result in
                    DispatchQueue.main.async {
                        guard self?.generation == request, case .success(let image) = result else { return }
                        imageView?.image = image
                    }
                }
            }
            snapshotter.styleURI = SOOMMapboxConfiguration.styleURI
        }
    }
}

private final class SOOMRouteThumbnailImageView: UIImageView {
    var onLayoutSizeChange: (() -> Void)?
    private var previousSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        onLayoutSizeChange?()
    }
}

/// Mapbox rebuilds ornament images even when callers assign identical options.
/// Keep configuration updates independent of route playback progress.
struct WorkoutRouteOrnamentRevision {
    private var last: State?
    private struct State: Equatable {
        let top: CGFloat
        let compact: Bool
        let scale: Bool
    }
    mutating func needsUpdate(topMargin: CGFloat, compact: Bool, scale: Bool) -> Bool {
        let next = State(top: topMargin, compact: compact, scale: scale)
        guard next != last else { return false }
        last = next
        return true
    }
}

struct SOOMMapboxRouteMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    var coordinateSegments: [[CLLocationCoordinate2D]]? = nil
    let bounds: WorkoutRouteBounds?
    let tint: UIColor
    var lineWidth = SOOMRouteRenderingStyle.detailLineWidth
    var cameraPadding = UIEdgeInsets(top: 36, left: 28, bottom: 72, right: 28)
    var scaleBarTopMargin: CGFloat? = nil
    var showsScaleBar = true
    var routeFitInset: CGFloat = 8
    var cameraZoomOutset: CGFloat = 0.15
    var compactRouteOnly = false
    var achievements: [WorkoutAchievement] = []
    var playbackProgress: Double? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SOOMRouteMapView {
        MapboxAccessTokenAvailability.configureMapboxOptionsIfNeeded()

        let mapView = SOOMRouteMapView(
            frame: .zero,
            mapInitOptions: MapInitOptions(styleURI: SOOMMapboxConfiguration.styleURI)
        )
        context.coordinator.updateOrnaments(mapView, topMargin: scaleBarTopMargin ?? cameraPadding.top,
            compact: compactRouteOnly, scale: showsScaleBar)
        context.coordinator.compactRouteOnly = compactRouteOnly
        context.coordinator.routeFitInset = routeFitInset
        context.coordinator.cameraZoomOutset = cameraZoomOutset
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        context.coordinator.configure(mapView: mapView, coordinates: coordinates, coordinateSegments: coordinateSegments, bounds: bounds, tint: tint, lineWidth: lineWidth, cameraPadding: cameraPadding, achievements: achievements, playbackProgress: playbackProgress)
        mapView.onLayoutSizeChange = { [weak coordinator = context.coordinator] in
            coordinator?.updateCameraForLayout()
        }
        return mapView
    }

    func updateUIView(_ mapView: SOOMRouteMapView, context: Context) {
        context.coordinator.updateOrnaments(mapView, topMargin: scaleBarTopMargin ?? cameraPadding.top,
            compact: compactRouteOnly, scale: showsScaleBar)
        context.coordinator.compactRouteOnly = compactRouteOnly
        context.coordinator.routeFitInset = routeFitInset
        context.coordinator.cameraZoomOutset = cameraZoomOutset
        context.coordinator.configure(mapView: mapView, coordinates: coordinates, coordinateSegments: coordinateSegments, bounds: bounds, tint: tint, lineWidth: lineWidth, cameraPadding: cameraPadding, achievements: achievements, playbackProgress: playbackProgress)
    }

    final class Coordinator {
        private var ornamentRevision = WorkoutRouteOrnamentRevision()
        func updateOrnaments(_ mapView: MapView, topMargin: CGFloat, compact: Bool, scale: Bool) {
            guard ornamentRevision.needsUpdate(topMargin: topMargin, compact: compact, scale: scale) else { return }
            var options = mapView.ornaments.options
            options.logo.margins = CGPoint(x: 10, y: 10)
            options.attributionButton.margins = CGPoint(x: 10, y: 10)
            options.scaleBar.margins = CGPoint(x: 10, y: topMargin)
            options.scaleBar.visibility = compact || !scale ? .hidden : .adaptive
            options.compass.visibility = compact ? .hidden : .adaptive
            mapView.ornaments.options = options
        }
        private var annotationManager: PolylineAnnotationManager?
        private var achievementAnnotationManager: PointAnnotationManager?
        private var endpointAnnotationManager: PointAnnotationManager?
        private var playbackLineManager: PolylineAnnotationManager?
        private var playbackPositionManager: PointAnnotationManager?
        private var preparedPlayback: WorkoutRoutePlayback.Prepared?
        private var lastSignature: String?
        private var routeGeometry = WorkoutRouteGeometryRevision()
        private var cameraGeometry = WorkoutRouteGeometryRevision()
        private var lastPlaybackSignature: String?
        private var lastCameraSignature: String?
        private var cameraLayoutUpdate: (() -> Void)?
        var routeFitInset: CGFloat = 8
        var cameraZoomOutset: CGFloat = 0.15
        private var hasAppliedCamera = false
        private var styleLoadToken = 0
        var compactRouteOnly = false

        func configure(
            mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            coordinateSegments: [[CLLocationCoordinate2D]]?,
            bounds: WorkoutRouteBounds?,
            tint: UIColor,
            lineWidth: Double,
            cameraPadding: UIEdgeInsets,
            achievements: [WorkoutAchievement],
            playbackProgress: Double?
        ) {
            cameraLayoutUpdate = { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.fitCameraIfNeeded(on: mapView, coordinates: coordinates, bounds: bounds, cameraPadding: cameraPadding)
            }
            guard ensureSOOMStyle(on: mapView, coordinates: coordinates, coordinateSegments: coordinateSegments, bounds: bounds, tint: tint, lineWidth: lineWidth, cameraPadding: cameraPadding, achievements: achievements, playbackProgress: playbackProgress) else {
                return
            }
            applyRoute(mapView: mapView, coordinates: coordinates, coordinateSegments: coordinateSegments, bounds: bounds, tint: tint, lineWidth: lineWidth, cameraPadding: cameraPadding, achievements: achievements, playbackProgress: playbackProgress)
        }

        func updateCameraForLayout() {
            cameraLayoutUpdate?()
        }

        private func ensureSOOMStyle(
            on mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            coordinateSegments: [[CLLocationCoordinate2D]]?,
            bounds: WorkoutRouteBounds?,
            tint: UIColor,
            lineWidth: Double,
            cameraPadding: UIEdgeInsets,
            achievements: [WorkoutAchievement],
            playbackProgress: Double?
        ) -> Bool {
            let expectedStyle = SOOMMapboxConfiguration.styleURI
            guard mapView.mapboxMap.styleURI != expectedStyle else { return true }

            styleLoadToken += 1
            let currentToken = styleLoadToken
            lastSignature = nil
            lastPlaybackSignature = nil
            annotationManager = nil
            achievementAnnotationManager = nil
            endpointAnnotationManager = nil
            playbackLineManager = nil
            playbackPositionManager = nil

            mapView.mapboxMap.loadStyle(expectedStyle) { [weak self, weak mapView] error in
                guard let self, currentToken == self.styleLoadToken, error == nil, let mapView else { return }
                self.applyRoute(mapView: mapView, coordinates: coordinates, coordinateSegments: coordinateSegments, bounds: bounds, tint: tint, lineWidth: lineWidth, cameraPadding: cameraPadding, achievements: achievements, playbackProgress: playbackProgress)
            }

            return false
        }

        private func applyRoute(
            mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            coordinateSegments: [[CLLocationCoordinate2D]]?,
            bounds: WorkoutRouteBounds?,
            tint: UIColor,
            lineWidth: Double,
            cameraPadding: UIEdgeInsets,
            achievements: [WorkoutAchievement],
            playbackProgress: Double?
        ) {
            let segments = coordinateSegments ?? [coordinates]
            let achievementSignature = achievements.map { "\($0.id)" }.joined(separator: "|")
            let geometryRevision = routeGeometry.update(coordinates: coordinates, segments: segments)
            let signature = "\(geometryRevision)" + "|\(tint.description)|\(lineWidth)|\(achievementSignature)|\(playbackProgress == nil ? "static" : "playback")|\(WorkoutRoutePlayback.showsFinishMarker(progress: playbackProgress))|\(compactRouteOnly)"
            // Playback redraws annotations, never the fitted camera. Layout changes
            // are handled separately, including the first non-zero map size.
            fitCameraIfNeeded(on: mapView, coordinates: coordinates, bounds: bounds, cameraPadding: cameraPadding)
            guard signature != lastSignature else {
                applyPlayback(mapView: mapView, segments: segments, tint: tint, lineWidth: lineWidth,
                    progress: compactRouteOnly ? nil : playbackProgress)
                return
            }
            lastSignature = signature
            lastPlaybackSignature = nil
            preparedPlayback = WorkoutRoutePlayback.Prepared(segments)

            if annotationManager == nil {
                annotationManager = mapView.annotations.makePolylineAnnotationManager()
            }

            annotationManager?.annotations = segments.filter { $0.count >= 2 }.map { segment in
                var annotation = PolylineAnnotation(lineCoordinates: segment)
                annotation.lineColor = StyleColor(playbackProgress == nil ? tint : UIColor.systemGray3)
                annotation.lineWidth = lineWidth
                annotation.lineOpacity = 0.9
                return annotation
            }

            applyAchievements(mapView: mapView, tint: tint, achievements: compactRouteOnly ? [] : achievements)
            if compactRouteOnly {
                endpointAnnotationManager?.annotations = []
            } else {
                applyEndpoints(mapView: mapView, segments: segments, playbackProgress: playbackProgress)
            }
            applyPlayback(mapView: mapView, segments: segments, tint: tint, lineWidth: lineWidth,
                progress: compactRouteOnly ? nil : playbackProgress)
        }

        private func applyPlayback(mapView: MapView, segments: [[CLLocationCoordinate2D]], tint: UIColor,
                                   lineWidth: Double, progress: Double?) {
            // SwiftUI layout/scroll updates can repeat an unchanged frame. Avoid
            // scheduling Mapbox annotation work when no visual input changed.
            let signature = "\(routeGeometry.revision)|\(progress.map { String($0) } ?? "static")|\(lineWidth)|\(tint.description)"
            guard signature != lastPlaybackSignature else { return }
            lastPlaybackSignature = signature
            guard let progress else {
                playbackLineManager?.annotations = []
                playbackPositionManager?.annotations = []
                return
            }
            if playbackLineManager == nil { playbackLineManager = mapView.annotations.makePolylineAnnotationManager() }
            if playbackPositionManager == nil { playbackPositionManager = mapView.annotations.makePointAnnotationManager() }
            let prepared = preparedPlayback ?? WorkoutRoutePlayback.Prepared(segments)
            let frame = WorkoutRoutePlayback.frame(prepared: prepared, progress: progress)
            playbackLineManager?.annotations = frame.segments.map { segment in
                var annotation = PolylineAnnotation(lineCoordinates: segment)
                annotation.lineColor = StyleColor(tint)
                annotation.lineWidth = lineWidth + 0.8
                return annotation
            }
            if let position = frame.position, progress < 1 {
                var marker = PointAnnotation(coordinate: position)
                marker.image = PointAnnotation.Image(image: Self.playbackPositionImage, name: "soom-route-playback-position")
                playbackPositionManager?.annotations = [marker]
            } else {
                playbackPositionManager?.annotations = []
            }
        }

        private static let playbackPositionImage = UIGraphicsImageRenderer(size: CGSize(width: 15, height: 15)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 15, height: 15)).fill()
            SOOMRouteRenderingStyle.accentUIColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2.5, y: 2.5, width: 10, height: 10)).fill()
        }

        private func applyEndpoints(mapView: MapView, segments: [[CLLocationCoordinate2D]], playbackProgress: Double?) {
            let visible = segments.filter { !$0.isEmpty }
            guard let start = visible.first?.first, let finish = visible.last?.last else {
                endpointAnnotationManager?.annotations = []
                return
            }
            if endpointAnnotationManager == nil {
                endpointAnnotationManager = mapView.annotations.makePointAnnotationManager()
            }
            let endpoints = WorkoutRoutePlayback.showsFinishMarker(progress: playbackProgress)
                ? [(start, false), (finish, true)] : [(start, false)]
            endpointAnnotationManager?.annotations = endpoints.map { coordinate, isFinish in
                var annotation = PointAnnotation(coordinate: coordinate)
                annotation.image = PointAnnotation.Image(
                    image: Self.endpointImage(isFinish: isFinish),
                    name: isFinish ? "soom-route-finish" : "soom-route-start"
                )
                return annotation
            }
        }

        private static func endpointImage(isFinish: Bool) -> UIImage {
            let diameter: CGFloat = isFinish ? 26 : 20
            let size = CGSize(width: diameter, height: diameter)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let circle = CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: circle).fill()
                let center = circle.insetBy(dx: 2, dy: 2)
                (isFinish ? UIColor.black : SOOMRouteRenderingStyle.accentUIColor).setFill()
                UIBezierPath(ovalIn: center).fill()
                if isFinish {
                    let symbol = UIImage(systemName: "flag.checkered", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))?
                        .withTintColor(.white, renderingMode: .alwaysOriginal)
                    symbol?.draw(at: CGPoint(x: (size.width - (symbol?.size.width ?? 0)) / 2,
                                             y: (size.height - (symbol?.size.height ?? 0)) / 2))
                }
            }
        }

        private func applyAchievements(mapView: MapView, tint: UIColor, achievements: [WorkoutAchievement]) {
            guard !achievements.isEmpty else {
                achievementAnnotationManager?.annotations = []
                return
            }

            if achievementAnnotationManager == nil {
                achievementAnnotationManager = mapView.annotations.makePointAnnotationManager()
            }

            let markerImage = Self.markerImage(tint: tint)

            achievementAnnotationManager?.annotations = achievements.map { achievement in
                var annotation = PointAnnotation(
                    id: achievement.id.uuidString,
                    coordinate: CLLocationCoordinate2D(
                        latitude: achievement.coordinate.latitude,
                        longitude: achievement.coordinate.longitude
                    )
                )
                annotation.image = PointAnnotation.Image(image: markerImage, name: "workout-achievement-marker")
                annotation.textField = achievement.pinLabel
                annotation.textSize = 11
                annotation.textColor = StyleColor(UIColor.label)
                annotation.textHaloColor = StyleColor(UIColor.systemBackground)
                annotation.textHaloWidth = 1.5
                annotation.textOffset = [0, 1.4]
                annotation.textAnchor = .top
                return annotation
            }
        }

        private static func markerImage(tint: UIColor) -> UIImage {
            let diameter: CGFloat = 30
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
            return renderer.image { _ in
                let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: rect).fill()

                let strokeRect = rect.insetBy(dx: 1.5, dy: 1.5)
                tint.setStroke()
                let strokePath = UIBezierPath(ovalIn: strokeRect)
                strokePath.lineWidth = 2
                strokePath.stroke()

                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                if let symbol = UIImage(soom: SOOMIcon.medal, withConfiguration: symbolConfig)?
                    .withTintColor(tint, renderingMode: .alwaysOriginal) {
                    let origin = CGPoint(x: (diameter - symbol.size.width) / 2, y: (diameter - symbol.size.height) / 2)
                    symbol.draw(at: origin)
                }
            }
        }

        private func fitCameraIfNeeded(
            on mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?,
            cameraPadding: UIEdgeInsets
        ) {
            guard mapView.bounds.width > 0, mapView.bounds.height > 0, !coordinates.isEmpty else { return }
            let geometryRevision = cameraGeometry.update(coordinates: coordinates)
            let signature = "\(geometryRevision)|\(String(describing: bounds))"
                + "|\(mapView.bounds.width),\(mapView.bounds.height)"
                + "|\(cameraPadding.top),\(cameraPadding.left),\(cameraPadding.bottom),\(cameraPadding.right)"
                + "|\(routeFitInset)|\(cameraZoomOutset)|\(compactRouteOnly)"
            guard signature != lastCameraSignature else { return }
            lastCameraSignature = signature
            setCamera(on: mapView, coordinates: coordinates, bounds: bounds, cameraPadding: cameraPadding)
        }

        private func setCamera(
            on mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?,
            cameraPadding: UIEdgeInsets
        ) {
            guard !coordinates.isEmpty else { return }

            let initialCamera = CameraOptions(
                padding: cameraPadding,
                bearing: 0,
                pitch: 0
            )

            let camera = routeFitCamera(
                on: mapView,
                coordinates: coordinates,
                bounds: bounds,
                initialCamera: initialCamera
            )

            if hasAppliedCamera {
                mapView.camera.ease(
                    to: camera,
                    duration: SOOMLayout.DetailSheet.mapAnimationDuration,
                    curve: .easeInOut
                )
            } else {
                mapView.mapboxMap.setCamera(to: camera)
                hasAppliedCamera = true
            }
        }

        private func routeFitCamera(
            on mapView: MapView,
            coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?,
            initialCamera: CameraOptions
        ) -> CameraOptions {
            do {
                let routeInset = compactRouteOnly ? 2 : routeFitInset
                var camera = try mapView.mapboxMap.camera(
                    for: coordinates,
                    camera: initialCamera,
                    coordinatesPadding: UIEdgeInsets(
                        top: routeInset,
                        left: routeInset,
                        bottom: routeInset,
                        right: routeInset
                    ),
                    maxZoom: 15,
                    offset: nil
                )
                camera.zoom = max(0, (camera.zoom ?? 12) - (compactRouteOnly ? 0.15 : cameraZoomOutset))
                return camera
            } catch {
                return fallbackCamera(for: coordinates, bounds: bounds, initialCamera: initialCamera)
            }
        }

        private func fallbackCamera(
            for coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?,
            initialCamera: CameraOptions
        ) -> CameraOptions {
            CameraOptions(
                center: centerCoordinate(from: coordinates, bounds: bounds),
                padding: initialCamera.padding,
                zoom: max(0, zoomEstimate(for: bounds) - (compactRouteOnly ? 0.15 : cameraZoomOutset)),
                bearing: 0,
                pitch: 0
            )
        }

        private func centerCoordinate(
            from coordinates: [CLLocationCoordinate2D],
            bounds: WorkoutRouteBounds?
        ) -> CLLocationCoordinate2D {
            if let bounds {
                return CLLocationCoordinate2D(
                    latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                    longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
                )
            }

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

/// Fitting after layout avoids a second, different camera fit at the first playback frame.
final class SOOMRouteMapView: MapView {
    var onLayoutSizeChange: (() -> Void)?
    private var previousSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != previousSize else { return }
        previousSize = bounds.size
        onLayoutSizeChange?()
    }
}

enum WorkoutRoutePlayback {
    static func showsFinishMarker(progress: Double?) -> Bool {
        progress.map { $0 >= 1 } ?? true
    }

    struct Frame {
        let segments: [[CLLocationCoordinate2D]]
        let position: CLLocationCoordinate2D?
    }

    struct Prepared {
        let segments: [[CLLocationCoordinate2D]]
        let lengths: [[Double]]
        let total: Double
        init(_ input: [[CLLocationCoordinate2D]]) {
            segments = input.filter { $0.count >= 2 }
            lengths = segments.map { segment in zip(segment, segment.dropFirst()).map { distance($0, $1) } }
            total = lengths.flatMap { $0 }.reduce(0, +)
        }
    }
    /// Retained for callers without a persistent renderer. Playback renderers prepare once.
    static func frame(segments: [[CLLocationCoordinate2D]], progress: Double) -> Frame {
        frame(prepared: Prepared(segments), progress: progress)
    }
    /// Reveals the route by distance, preserving GPS pause gaps between segments.
    static func frame(prepared: Prepared, progress: Double) -> Frame {
        let segments = prepared.segments
        guard let first = segments.first?.first else { return Frame(segments: [], position: nil) }
        let lengths = prepared.lengths
        let total = prepared.total
        guard total > 0 else { return Frame(segments: [], position: first) }
        var remaining = total * min(max(progress, 0), 1)
        var drawn: [[CLLocationCoordinate2D]] = []
        var position = first

        for (segment, legLengths) in zip(segments, lengths) {
            var revealed = [segment[0]]
            position = segment[0]
            for (index, legLength) in legLengths.enumerated() {
                if remaining >= legLength {
                    revealed.append(segment[index + 1])
                    position = segment[index + 1]
                    remaining -= legLength
                } else {
                    if remaining > 0, legLength > 0 {
                        let fraction = remaining / legLength
                        let end = segment[index + 1]
                        position = CLLocationCoordinate2D(
                            latitude: position.latitude + (end.latitude - position.latitude) * fraction,
                            longitude: position.longitude + (end.longitude - position.longitude) * fraction
                        )
                        revealed.append(position)
                    }
                    remaining = 0
                    break
                }
            }
            if revealed.count >= 2 { drawn.append(revealed) }
            if remaining <= 0 { break }
        }
        return Frame(segments: drawn, position: position)
    }

    private static func distance(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
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
                SOOMSportIconView(name: iconName, size: 30)
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
        case .indoor: return "house.fill"
        }
    }

    private var fallbackText: String {
        switch style {
        case .running: return "러닝 경로를 불러올 수 없어요"
        case .cycling: return "라이딩 경로를 불러올 수 없어요"
        case .swimming: return "수영 기록은 경로 없이 표시해요"
        case .walking: return "걷기 경로를 불러올 수 없어요"
        case .generic: return "운동 경로가 아직 없어요"
        case .indoor: return "실내 운동은 경로 없이 표시해요"
        }
    }
}

enum MapboxAccessTokenAvailability {
    static var hasUsableToken: Bool {
        #if DEBUG
        if WorkoutCardPerformanceProbe.enabled { return false } // Local fixture excludes remote map rendering.
        #endif
        return resolvedUsableToken != nil
    }

    static var resolvedUsableToken: String? {
        [
            Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
            ProcessInfo.processInfo.environment["MBX_ACCESS_TOKEN"],
            ProcessInfo.processInfo.environment["MAPBOX_ACCESS_TOKEN"]
        ]
        .compactMap { $0 }
        .first(where: isUsableToken)
    }

    static func isUsableToken(_ token: String?) -> Bool {
        guard let token else { return false }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowered = trimmed.lowercased()
        guard !trimmed.contains("$(") else { return false }
        guard !lowered.contains("placeholder") else { return false }
        guard !lowered.contains("replace_me") else { return false }
        guard !lowered.contains("your_") else { return false }
        guard !lowered.contains("your-") else { return false }
        return true
    }

    static func configureMapboxOptionsIfNeeded() {
        guard let token = resolvedUsableToken else { return }
        MapboxOptions.accessToken = token
    }
}
