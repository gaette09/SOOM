import MapKit
import SwiftUI

struct WorkoutMapSheetScaffold<SheetContent: View>: View {
    let workout: Workout
    let navigationTitle: String
    let sheetContent: SheetContent

    @Environment(\.dismiss) private var dismiss
    @State private var sheetPosition: WorkoutSheetPosition = .standard
    @State private var mapPosition: MapCameraPosition
    @State private var sheetScrollOffset: CGFloat = 0
    @State private var sheetDrag: CGFloat = 0
    @State private var sheetDragCanMove: Bool?
    @State private var sheetDragActivationTranslation: CGFloat = 0

    private var coordinates: [CLLocationCoordinate2D] {
        workout.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    init(workout: Workout, navigationTitle: String, @ViewBuilder sheetContent: () -> SheetContent) {
        self.workout = workout
        self.navigationTitle = navigationTitle
        self.sheetContent = sheetContent()
        let coordinates = workout.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        self._mapPosition = State(initialValue: .region(routeRegion(
            for: coordinates,
            scale: WorkoutSheetPosition.standard.mapScale,
            latitudeOffset: WorkoutSheetPosition.standard.mapLatitudeOffset
        )))
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WorkoutSheetMetrics(proxy: proxy, position: sheetPosition, drag: sheetDrag)
            let isSheetTakingOverScroll = sheetDragCanMove == true

            ZStack(alignment: .bottom) {
                SOOMColor.background
                    .ignoresSafeArea()

                WorkoutMapBackground(workout: workout, position: $mapPosition, sheetPosition: sheetPosition)
                    .ignoresSafeArea()

                SOOMColor.background
                    .ignoresSafeArea()
                    .opacity(metrics.isExpanded ? 1 : 0)
                    .allowsHitTesting(false)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .zIndex(1)

                WorkoutMapControls {
                    dismiss()
                }
                    .opacity(metrics.isExpanded ? 0 : 1)
                    .allowsHitTesting(!metrics.isExpanded)
                    .zIndex(2)

                WorkoutBottomSheet(
                    metrics: metrics,
                    isScrollDisabled: sheetPosition != .expanded || isSheetTakingOverScroll,
                    sheetGesture: sheetGesture(metrics: metrics),
                    onScrollOffsetChange: { sheetScrollOffset = $0 },
                    header: {
                        if metrics.isExpanded {
                            WorkoutSheetHeader(
                                workout: workout,
                                title: workout.sport.title,
                                onCollapse: {
                                    collapseToPreview()
                                }
                            )
                            .overlay(alignment: .leading) {
                                expandedCollapseTarget
                            }
                            .contentShape(Rectangle())
                            .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            WorkoutSheetHandleButton(sheetPosition: $sheetPosition)
                                .transition(.opacity)
                        }
                    },
                    content: {
                        sheetContent
                    }
                )
                .zIndex(3)
            }
            .onChange(of: sheetPosition) { _, newPosition in
                withAnimation(.easeInOut(duration: SOOMLayout.DetailSheet.mapAnimationDuration)) {
                    mapPosition = .region(routeRegion(
                        for: coordinates,
                        scale: newPosition.mapScale,
                        latitudeOffset: newPosition.mapLatitudeOffset
                    ))
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var expandedCollapseTarget: some View {
        Color.clear
            .frame(
                width: SOOMLayout.DetailSheet.headerHorizontalPadding + SOOMLayout.DetailSheet.headerButtonSize + SOOMLayout.DetailSheet.headerSpacing,
                height: SOOMLayout.DetailSheet.headerTopPadding + SOOMLayout.DetailSheet.headerButtonSize + SOOMLayout.DetailSheet.headerBottomPadding
            )
            .contentShape(Rectangle())
            .onTapGesture {
                collapseToPreview()
            }
            .highPriorityGesture(expandedCollapseDragGesture)
    }

    private var expandedCollapseDragGesture: some Gesture {
        DragGesture(minimumDistance: SOOMLayout.DetailSheet.dragMinimumDistance, coordinateSpace: .global)
            .onEnded { value in
                guard value.translation.height > SOOMLayout.DetailSheet.dragMinimumDistance else { return }
                collapseToPreview()
            }
    }

    private func collapseToPreview() {
        sheetDragCanMove = nil
        resetSheetDrag()

        withAnimation(.spring(response: SOOMLayout.DetailSheet.sheetSpringResponse, dampingFraction: SOOMLayout.DetailSheet.sheetSpringDamping)) {
            sheetPosition = sheetPosition.nextLower
        }
    }

    private func sheetGesture(metrics: WorkoutSheetMetrics) -> some Gesture {
        DragGesture(minimumDistance: SOOMLayout.DetailSheet.dragMinimumDistance, coordinateSpace: .global)
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
}
