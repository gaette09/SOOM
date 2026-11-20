import MapKit
import SwiftUI

struct WorkoutMapSheetScaffold<SheetContent: View>: View {
    let workout: Workout
    let routeOverride: WorkoutRoute?
    let navigationTitle: String
    let achievements: [WorkoutAchievement]
    let photos: [WorkoutPhotoReference]
    let sharedPostManagement: FeedPostManagement?
    let sheetContent: SheetContent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.workoutDetailPresentationStore) private var presentationStore
    @State private var renderCache = WorkoutRouteRenderCache()
    @State private var playbackProgress: Double?
    @State private var playbackTask: Task<Void, Never>?
    @State private var sheetPosition: WorkoutSheetPosition = .standard
    @State private var mapPosition: MapCameraPosition
    @State private var sheetScrollOffset: CGFloat = 0
    @State private var resetScrollRevision = 0
    @GestureState private var sheetGestureActive = false
    @State private var sheetDrag: CGFloat = 0
    @State private var sheetDragCanMove: Bool?
    @State private var sheetDragActivationTranslation: CGFloat = 0
    @State private var showsPhotoHero = false
    @State private var selectedPhotoID = UUID()
    @State private var galleryPhoto: WorkoutPhotoReference?

    private var route: WorkoutRoute? {
        WorkoutMapSheetRouteContext.route(for: workout, override: routeOverride)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        renderCache.resolve(route).coordinates
    }

    init(
        workout: Workout,
        routeOverride: WorkoutRoute? = nil,
        navigationTitle: String,
        achievements: [WorkoutAchievement] = [],
        photos: [WorkoutPhotoReference] = [],
        sharedPostManagement: FeedPostManagement? = nil,
        @ViewBuilder sheetContent: () -> SheetContent
    ) {
        self.workout = workout
        self.routeOverride = routeOverride
        self.navigationTitle = navigationTitle
        self.achievements = achievements
        self.photos = photos
        self.sharedPostManagement = sharedPostManagement
        self.sheetContent = sheetContent()
        let coordinates = WorkoutMapSheetRouteContext.coordinates(for: workout, override: routeOverride)
        self._showsPhotoHero = State(initialValue: coordinates.count < 2 && !photos.isEmpty)
        self._mapPosition = State(initialValue: .region(routeRegion(
            for: coordinates,
            scale: WorkoutSheetPosition.standard.mapScale,
            latitudeOffset: WorkoutSheetPosition.standard.mapLatitudeOffset
        )))
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WorkoutSheetMetrics(proxy: proxy, position: sheetPosition, drag: sheetDrag)
            // The photo is centered in the area above the sheet, including the
            // status-bar region, rather than behind the entire detail screen.
            let photoViewportHeight = max(1, proxy.size.height - metrics.sheetHeight + proxy.safeAreaInsets.top)

            ZStack(alignment: .bottom) {
                SOOMColor.background
                    .ignoresSafeArea()

                if coordinates.count > 1 {
                WorkoutMapBackground(
                    workout: workout,
                    routeOverride: route,
                    position: $mapPosition,
                    sheetPosition: sheetPosition,
                    cameraPadding: WorkoutRouteCameraPadding.padding(
                        for: sheetPosition,
                        sheetHeight: metrics.sheetHeight,
                        safeAreaInsets: proxy.safeAreaInsets
                    ),
                    achievements: achievements,
                    sharedMeasurementDescription: sharedPostManagement?.item.recordMetrics.map(\.value).joined(separator: ", "),
                    playbackProgress: playbackProgress
                )
                    .ignoresSafeArea()
                }

                if showsPhotoHero && !photos.isEmpty {
                    TabView(selection: $selectedPhotoID) {
                        ForEach(photos) { photo in
                            GeometryReader { photoGeometry in
                                WorkoutPhotoImage(photo: photo, heroStyle: true)
                                    .frame(width: photoGeometry.size.width, height: photoGeometry.size.height)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .onTapGesture { galleryPhoto = photo }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("두 번 탭하여 사진 확대 화면을 엽니다")
                                    .accessibilityIdentifier("workout.detail.heroPhoto." + photo.id.uuidString)
                            }
                            .ignoresSafeArea(.container, edges: .top)
                            .tag(photo.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    // UIPageViewController otherwise insets its pages below the
                    // status bar even though the hero frame extends above it.
                    // Only media ignores safe areas; controls and sheet retain them.
                    .ignoresSafeArea(.container, edges: .top)
                    .background(Color.black)
                    .frame(width: proxy.size.width, height: photoViewportHeight)
                    .clipped()
                    .position(
                        x: proxy.size.width / 2,
                        y: photoViewportHeight / 2 - proxy.safeAreaInsets.top
                    )
                    .allowsHitTesting(!metrics.isExpanded)
                    .zIndex(0.5)
                    .accessibilityLabel("운동 사진. 좌우로 넘겨 다른 사진을 보세요")
                    .accessibilityIdentifier("workout.detail.photoHero")
                }

                SOOMColor.background
                    .ignoresSafeArea()
                    .opacity(metrics.isExpanded ? 1 : 0)
                    .allowsHitTesting(false)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .zIndex(1)

                if !metrics.isExpanded, coordinates.count > 1, let firstPhoto = photos.first {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if showsPhotoHero {
                                        showsPhotoHero = false
                                    } else {
                                        if !photos.contains(where: { $0.id == selectedPhotoID }) {
                                            selectedPhotoID = firstPhoto.id
                                        }
                                        showsPhotoHero = true
                                    }
                                }
                            } label: {
                                Group {
                                    if showsPhotoHero, let route {
                                        WorkoutDetailMapView(
                                            route: route,
                                            fallbackStyle: StaticRouteFallbackStyle(workoutType: workout.comparisonWorkoutType),
                                            tint: SOOMColor.accent,
                                            routeLineWidth: SOOMRouteRenderingStyle.detailLineWidth,
                                            compactRouteOnly: true
                                        )
                                        .allowsHitTesting(false)
                                    } else {
                                        WorkoutPhotoImage(photo: firstPhoto)
                                    }
                                }
                                .frame(width: 76, height: 76)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 3)
                                }
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showsPhotoHero ? "지도로 전환" : "운동 사진 보기")
                            .accessibilityHint(showsPhotoHero ? "지도 화면으로 돌아갑니다" : "사진을 크게 보고 좌우로 넘길 수 있습니다")
                            .accessibilityIdentifier("workout.detail.heroMediaToggle")
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, metrics.sheetHeight + 16)
                    }
                    .zIndex(1.5)
                }

                if !metrics.isExpanded && showsPhotoHero && photos.count > 1 {
                    VStack {
                        Spacer(minLength: 0)
                        WorkoutPhotoPageDots(photos: photos, selectedID: $selectedPhotoID)
                            .padding(.bottom, metrics.sheetHeight + 22)
                    }
                    .zIndex(1.6)
                }

                if !metrics.isExpanded, !reduceMotion, !showsPhotoHero,
                   let route, route.coordinates.count > 1, MapboxAccessTokenAvailability.hasUsableToken {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            Button(action: togglePlayback) {
                                Image(systemName: playbackTask == nil ? "play.fill" : "pause.fill")
                                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 44, height: 44).background(.black.opacity(0.72), in: Circle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(playbackTask == nil ? "경로 재생" : "경로 일시정지")
                                .accessibilityIdentifier("workout.detail.routePlayback")
                        }.padding(.horizontal, 16).padding(.bottom, metrics.sheetHeight + 16)
                    }.zIndex(1.7)
                }

                if !metrics.isExpanded {
                    WorkoutMapControls(onDismiss: { dismiss() }, sharedPostManagement: sharedPostManagement)
                        .zIndex(2)
                }

                WorkoutBottomSheet(
                    metrics: metrics,
                    // Keep the native pan alive during an expanded top-edge drag.
                    // Disabling it mid-recognition cancels the parent sheet pan too.
                    isScrollDisabled: sheetPosition != .expanded,
                    sheetGesture: sheetGesture(metrics: metrics),
                    onScrollOffsetChange: { offset in
                        sheetScrollOffset = offset
                    },
                    restoredScrollOffset: presentationStore?.value(workout.id).scroll ?? 0,
                    resetScrollRevision: resetScrollRevision,
                    onUserScrollOffsetChange: { offset in
                        presentationStore?.update(workout.id) { $0.scroll = max(0, offset) }
                    },
                    header: {
                        if metrics.isExpanded {
                            WorkoutSheetHeader(
                                workout: workout,
                                title: workout.sport.title,
                                onCollapse: {
                                    collapseToPreview()
                                }, sharedPostManagement:sharedPostManagement
                            )
                            .contentShape(Rectangle())
                            .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            WorkoutSheetHandleButton(sheetPosition: $sheetPosition)
                                .overlay(alignment: .trailing) {
                                    if showsPhotoHero && route != nil && MapboxAccessTokenAvailability.hasUsableToken {
                                        compactMapCredits
                                            .padding(.trailing, 12)
                                    }
                                }
                                .transition(.opacity)
                        }
                    },
                    content: {
                        sheetContent
                    }
                )
                .zIndex(3)
            }
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottom) {
                if ProcessInfo.processInfo.environment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] == "1" {
                    Text("sheet=\(String(describing: sheetPosition)) y=\(Int(proxy.frame(in: .global).minY)) safe=\(Int(proxy.safeAreaInsets.top)) scroll=\(Int(sheetScrollOffset)) saved=\(Int(presentationStore?.value(workout.id).scroll ?? 0))")
                        .font(.system(size: 9)).padding(2).background(.white.opacity(0.9))
                        .allowsHitTesting(false).accessibilityIdentifier("detail.sheet.geometry")
                }
            }
            #endif
            .onAppear {
                if let state = presentationStore?.value(workout.id) { sheetPosition = state.sheet }
                if coordinates.count < 2, !photos.isEmpty { showsPhotoHero = true }
                if let first = photos.first, !photos.contains(where: { $0.id == selectedPhotoID }) {
                    selectedPhotoID = first.id
                }
            }
            .onChange(of: sheetGestureActive) { _, active in
                if !active { sheetDragCanMove = nil; resetSheetDrag() }
            }
            .onChange(of: sheetPosition) { _, newPosition in
                presentationStore?.update(workout.id) { $0.sheet = newPosition }
                withAnimation(.easeInOut(duration: SOOMLayout.DetailSheet.mapAnimationDuration)) {
                    mapPosition = .region(routeRegion(
                        for: coordinates,
                        scale: newPosition.mapScale,
                        latitudeOffset: newPosition.mapLatitudeOffset
                    ))
                }
            }
            .onChange(of: photos) { _, newPhotos in
                if let first = newPhotos.first {
                    if coordinates.count < 2 { showsPhotoHero = true }
                    if !newPhotos.contains(where: { $0.id == selectedPhotoID }) {
                        selectedPhotoID = first.id
                    }
                } else {
                    showsPhotoHero = false
                }
            }
        }
        .preference(key: WorkoutMapTopOverflowPreference.self, value: true)
        .workoutPhotoGallery(photos: photos, selection: $galleryPhoto)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { stopPlayback() }
        .onChange(of: route?.id) { _, _ in stopPlayback() }
        .onChange(of: reduceMotion) { _, enabled in if enabled { stopPlayback() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                stopPlayback()
                // Native photo presentations are separate from the masked
                // navigation hierarchy; shared pixels must close before recheck.
                if sharedPostManagement != nil { galleryPhoto = nil }
            }
        }
    }

    // Keep the inset itself limited to the map and route. The adjacent sheet
    // carries the snapshot attribution even while the main map is covered.
    private var compactMapCredits: some View {
        Text("[© Mapbox](https://www.mapbox.com/about/maps/) · [© OpenStreetMap](https://www.openstreetmap.org/copyright)")
            .font(.system(size: 8))
            .tint(.secondary)
            .lineLimit(1)
            .accessibilityLabel("지도 제공 Mapbox, OpenStreetMap")
    }

    private func collapseToPreview() {
        // Explicit collapse button returns the preview to its identity/header.
        // Other presentations retain their existing scroll restoration policy.
        resetScrollRevision += 1
        sheetScrollOffset = 0
        presentationStore?.update(workout.id) { $0.scroll = 0 }
        sheetDragCanMove = nil
        resetSheetDrag()

        withAnimation(.spring(response: SOOMLayout.DetailSheet.sheetSpringResponse, dampingFraction: SOOMLayout.DetailSheet.sheetSpringDamping)) {
            sheetPosition = .standard
        }
    }

    private func sheetGesture(metrics: WorkoutSheetMetrics) -> some Gesture {
        DragGesture(minimumDistance: SOOMLayout.DetailSheet.dragMinimumDistance, coordinateSpace: .global)
            .updating($sheetGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                let shouldBeginMoving = canMoveSheet(value, metrics: metrics)
                if sheetDragCanMove == nil {
                    sheetDragActivationTranslation = 0
                    sheetDragCanMove = shouldBeginMoving
                }

                if sheetDragCanMove == true {
                    sheetDrag = value.translation.height - sheetDragActivationTranslation
                } else {
                    sheetDrag = 0
                }
            }
            .onEnded { value in
                finishSheetDrag(value, metrics: metrics)
            }
    }

    private func canMoveSheet(_ value: DragGesture.Value, metrics: WorkoutSheetMetrics) -> Bool {
        guard abs(value.translation.height) > abs(value.translation.width) else { return false }
        if metrics.isExpanded {
            return sheetScrollOffset <= SOOMLayout.DetailSheet.scrollTopThreshold
                && value.translation.height > 0
        }

        return true
    }

    private func finishSheetDrag(_ value: DragGesture.Value, metrics: WorkoutSheetMetrics) {
        let shouldMoveSheet = sheetDragCanMove == true
        sheetDragCanMove = nil

        guard shouldMoveSheet else {
            resetSheetDrag()
            return
        }

        let projectedHeight = min(max(metrics.baseHeight - value.predictedEndTranslation.height, metrics.minimizedHeight), metrics.expandedHeight)
        let nextPosition = nextSheetPosition(
            from: sheetPosition,
            translation: value.translation.height,
            predictedTranslation: value.predictedEndTranslation.height,
            projectedHeight: projectedHeight,
            metrics: metrics
        )

        withAnimation(.spring(response: SOOMLayout.DetailSheet.sheetSpringResponse, dampingFraction: SOOMLayout.DetailSheet.sheetSpringDamping)) {
            sheetPosition = nextPosition
            resetSheetDrag()
        }
    }

    private func resetSheetDrag() {
        sheetDrag = 0
        sheetDragActivationTranslation = 0
    }

    private func nextSheetPosition(
        from position: WorkoutSheetPosition,
        translation: CGFloat,
        predictedTranslation: CGFloat,
        projectedHeight: CGFloat,
        metrics: WorkoutSheetMetrics
    ) -> WorkoutSheetPosition {
        let intent = predictedTranslation.magnitude > translation.magnitude ? predictedTranslation : translation

        if intent < -SOOMLayout.DetailSheet.snapIntentThreshold {
            return position.nextHigher
        }

        if intent > SOOMLayout.DetailSheet.snapIntentThreshold {
            return position.nextLower
        }

        return WorkoutSheetPosition.nearest(
            to: projectedHeight,
            minimized: metrics.minimizedHeight,
            standard: metrics.standardHeight,
            expanded: metrics.expandedHeight
        )
    }
    private func togglePlayback() {
        if let playbackTask { playbackTask.cancel(); self.playbackTask = nil; return }
        let start = (playbackProgress ?? 0) >= 1 ? 0 : (playbackProgress ?? 0)
        playbackProgress = start
        playbackTask = Task { @MainActor in
            let steps = 160
            for step in (Int(start * Double(steps)) + 1)...steps {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                guard !Task.isCancelled else { return }
                playbackProgress = Double(step) / Double(steps)
            }
            playbackTask = nil
        }
    }
    private func stopPlayback() {
        playbackTask?.cancel(); playbackTask = nil; playbackProgress = nil
    }

}

enum WorkoutMapSheetRouteContext {
    static func route(for workout: Workout, override: WorkoutRoute?) -> WorkoutRoute? {
        if let override {
            return RoutePrivacyMasker().mask(route: override)
        }

        guard workout.route.count >= 2 else { return nil }

        return RoutePrivacyMasker().mask(route: WorkoutRoute(
            id: workout.id, workoutId: workout.id,
            source: .soomLocal,
            coordinates: workout.route.map {
                WorkoutRouteCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            totalDistanceMeters: workout.distanceMeters,
            totalElevationGain: workout.elevationGain > 0 ? Double(workout.elevationGain) : nil,
            createdAt: workout.date
        ))
    }

    static func coordinates(for workout: Workout, override: WorkoutRoute?) -> [CLLocationCoordinate2D] {
        route(for: workout, override: override)?.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
    }
}

/// Extend painting through system safe areas without moving content or buttons.
/// Onboarding retains its boundary; horizontal overflow always stays clipped.
struct WorkoutMapTopOverflowPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
private struct WorkoutRootTopPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct WorkoutRootClip: Shape {
    let top: CGFloat
    let bottom: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: rect.height + top + bottom))
    }
}
struct WorkoutRootViewport: ViewModifier {
    let allowsStatusBarOverflow: Bool
    @State private var allowsMapTop = false
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: WorkoutRootTopPreference.self,
                        value: max(0, geometry.frame(in: .global).minY))
                        .onAppear { bottom = geometry.safeAreaInsets.bottom }
                        .onChange(of: geometry.safeAreaInsets.bottom) { _, value in bottom = value }
                }
            }
            .onPreferenceChange(WorkoutMapTopOverflowPreference.self) { allowsMapTop = $0 }
            .onPreferenceChange(WorkoutRootTopPreference.self) { top = $0 }
            .clipShape(WorkoutRootClip(top: allowsStatusBarOverflow ? top : 0,
                bottom: allowsStatusBarOverflow ? bottom : 0))
            #if DEBUG && targetEnvironment(simulator)
            .overlay(alignment: .bottomTrailing) {
                if ProcessInfo.processInfo.environment["SOOM_DETAIL_NORMAL_LAYOUT_QA"] == "1" {
                    Text("root y=\(Int(top)) map=\(allowsMapTop ? 1 : 0)")
                        .font(.system(size: 9)).padding(2).background(.white.opacity(0.9))
                        .allowsHitTesting(false).accessibilityIdentifier("detail.root.geometry")
                }
            }
            #endif
    }
}
