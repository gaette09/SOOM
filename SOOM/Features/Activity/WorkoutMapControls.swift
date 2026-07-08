import MapKit
import SwiftUI
import UIKit

struct WorkoutMapControls: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: SOOMLayout.MapControls.spacing) {
                Button(action: onDismiss) {
                    Image(systemName: SOOMIcon.back)
                        .font(.system(size: SOOMLayout.MapControls.backIconSize, weight: .semibold))
                        .foregroundStyle(SOOMColor.ink)
                        .frame(width: SOOMLayout.MapControls.buttonSize, height: SOOMLayout.MapControls.buttonSize)
                        .background(SOOMColor.surface)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(SOOMLayout.MapControls.shadowOpacity), radius: SOOMLayout.MapControls.shadowRadius, x: 0, y: SOOMLayout.MapControls.shadowYOffset)
                }
                .accessibilityLabel("뒤로가기")
                .accessibilityHint("이전 화면으로 돌아갑니다.")

                Spacer()

                MapCircleButton(icon: SOOMIcon.bookmark, accessibilityLabel: "경로 저장")
                MapCircleButton(icon: SOOMIcon.more, accessibilityLabel: "더보기")
            }
            .padding(.top, SOOMLayout.MapControls.topPadding)
            .padding(.horizontal, SOOMLayout.MapControls.horizontalPadding)

            Spacer()
        }
    }
}

private struct MapCircleButton: View {
    let icon: String
    let accessibilityLabel: String

    var body: some View {
        Button {
        } label: {
            Image(systemName: icon)
                .font(.system(size: icon == SOOMIcon.more ? SOOMLayout.MapControls.ellipsisIconSize : SOOMLayout.MapControls.defaultIconSize, weight: icon == SOOMIcon.more ? .bold : .semibold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: SOOMLayout.MapControls.buttonSize, height: SOOMLayout.MapControls.buttonSize)
                .background(SOOMColor.surface)
                .clipShape(Circle())
                .shadow(color: .black.opacity(SOOMLayout.MapControls.shadowOpacity), radius: SOOMLayout.MapControls.shadowRadius, x: 0, y: SOOMLayout.MapControls.shadowYOffset)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WorkoutMapBackground: View {
    let workout: Workout
    let routeOverride: WorkoutRoute?
    @Binding var position: MapCameraPosition
    let sheetPosition: WorkoutSheetPosition
    let cameraPadding: UIEdgeInsets

    private var route: WorkoutRoute? {
        WorkoutMapSheetRouteContext.route(for: workout, override: routeOverride)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        route?.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? []
    }

    var body: some View {
        ZStack {
            if let route, MapboxAccessTokenAvailability.hasUsableToken {
                SOOMMapboxRouteMap(
                    coordinates: coordinates,
                    bounds: route.bounds,
                    tint: SOOMRouteRenderingStyle.accentUIColor,
                    lineWidth: SOOMRouteRenderingStyle.detailLineWidth,
                    cameraPadding: cameraPadding
                )
                .accessibilityHidden(true)
            } else {
                WorkoutMapFallbackBackground(tint: workout.sport.tint)
            }
        }
        .accessibilityLabel("\(workout.sport.title) 경로 지도")
        .accessibilityValue("\(workout.formattedDistance), \(workout.formattedDuration)")
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
            Image(systemName: SOOMIcon.map)
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
