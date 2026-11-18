import MapKit
import SwiftUI
import UIKit

struct WorkoutMapControls: View {
    let onDismiss: () -> Void
    var sharedPostManagement: FeedPostManagement? = nil
    @Environment(\.workoutManagement) private var management

    var body: some View {
        VStack {
            HStack(spacing: SOOMLayout.MapControls.spacing) {
                Button(action: onDismiss) {
                    Image(soom: SOOMIcon.back)
                        .font(.system(size: SOOMLayout.MapControls.backIconSize, weight: .semibold))
                        .foregroundStyle(SOOMColor.ink)
                        .frame(width: SOOMLayout.MapControls.buttonSize, height: SOOMLayout.MapControls.buttonSize)
                        .background(SOOMColor.surface)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(SOOMLayout.MapControls.shadowOpacity), radius: SOOMLayout.MapControls.shadowRadius, x: 0, y: SOOMLayout.MapControls.shadowYOffset)
                }
                .accessibilityLabel("뒤로가기")
                .accessibilityIdentifier("workout.detail.back")
                .accessibilityHint("이전 화면으로 돌아갑니다.")

                Spacer()

                if let management {
                    WorkoutManagementButtons(model: management, onDelete: onDismiss)
                } else if let sharedPostManagement {
                    FeedPostManagementButtons(model: sharedPostManagement, onDelete: onDismiss)
                        .padding(8).background(SOOMColor.surface, in: Capsule())
                }
            }
            .padding(.top, SOOMLayout.MapControls.topPadding)
            .padding(.horizontal, SOOMLayout.MapControls.horizontalPadding)

            Spacer()
        }
    }
}

struct WorkoutMapBackground: View {
    let workout: Workout
    let routeOverride: WorkoutRoute?
    @Binding var position: MapCameraPosition
    let sheetPosition: WorkoutSheetPosition
    let cameraPadding: UIEdgeInsets
    var achievements: [WorkoutAchievement] = []
    var sharedMeasurementDescription: String? = nil
    var playbackProgress: Double? = nil

    private var route: WorkoutRoute? {
        WorkoutMapSheetRouteContext.route(for: workout, override: routeOverride)
    }

    @State private var renderCache = WorkoutRouteRenderCache()

    var body: some View {
        let geometry = renderCache.resolve(route)
        ZStack {
            if let route = geometry.route, MapboxAccessTokenAvailability.hasUsableToken {
                SOOMMapboxRouteMap(
                    coordinates: geometry.coordinates,
                    coordinateSegments: geometry.segments,
                    bounds: route.bounds,
                    tint: SOOMRouteRenderingStyle.accentUIColor,
                    lineWidth: SOOMRouteRenderingStyle.detailLineWidth,
                    cameraPadding: cameraPadding,
                    scaleBarTopMargin: SOOMLayout.MapControls.scaleBarTopMargin,
                    showsScaleBar: false,
                    routeFitInset: 8,
                    cameraZoomOutset: 0.15,
                    achievements: achievements,
                    playbackProgress: playbackProgress
                )
                .accessibilityHidden(true)
            } else {
                WorkoutMapFallbackBackground(tint: workout.sport.tint)
            }
        }
        .accessibilityLabel("\(workout.sport.title) 경로 지도")
        .accessibilityValue(sharedMeasurementDescription ?? "\(workout.formattedDistance), \(workout.formattedDuration)")
    }
}

enum WorkoutRouteCameraPadding {
    static let horizontalInset: CGFloat = 44
    static let visibleRouteInset: CGFloat = 22
    static let topControlsInset: CGFloat = 112
    static let sheetClearance: CGFloat = 34
    static let expandedMaxBottomInset: CGFloat = 420

    static func padding(
        for position: WorkoutSheetPosition,
        sheetHeight: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> UIEdgeInsets {
        let topInset = safeAreaInsets.top + topControlsInset
        let visibleBottomInset = sheetHeight + safeAreaInsets.bottom + sheetClearance
        let bottomInset = position == .expanded
            ? min(visibleBottomInset, expandedMaxBottomInset)
            : visibleBottomInset

        return UIEdgeInsets(
            top: topInset,
            left: horizontalInset,
            bottom: bottomInset,
            right: horizontalInset
        )
    }
}

private struct WorkoutMapFallbackBackground: View {
    let tint: Color

    var body: some View {
        LinearGradient(
            colors: [
                tint.opacity(0.18),
                SOOMColor.surface,
                SOOMColor.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(soom: SOOMIcon.map)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(tint.opacity(0.24))
        }
    }
}

func routeRegion(for coordinates: [CLLocationCoordinate2D], scale: Double = 1.8, latitudeOffset: Double = 0) -> MKCoordinateRegion {
    guard let first = coordinates.first else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5266, longitude: 126.9271),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }

    let latitudes = coordinates.map(\.latitude)
    let longitudes = coordinates.map(\.longitude)
    let minLat = latitudes.min() ?? first.latitude
    let maxLat = latitudes.max() ?? first.latitude
    let minLon = longitudes.min() ?? first.longitude
    let maxLon = longitudes.max() ?? first.longitude

    let latitudeDelta = max((maxLat - minLat) * scale, 0.006)
    let longitudeDelta = max((maxLon - minLon) * scale, 0.006)
    let centeredLatitude = (minLat + maxLat) / 2

    return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: centeredLatitude + latitudeDelta * latitudeOffset, longitude: (minLon + maxLon) / 2),
        span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    )
}
