import XCTest
import UIKit
@testable import SOOM

final class StaticRoutePreviewBuilderTests: XCTestCase {
    func testRouteBuildsStaticPreviewWithImageURLAndBoundsWhenMaskingIsDisabled() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(
            route: sampleRoute,
            workoutType: .running,
            width: 320,
            height: 400,
            privacyPolicy: .none
        )

        XCTAssertTrue(preview.routeExists)
        XCTAssertNotNil(preview.imageURL)
        XCTAssertNotNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .running)
    }

    func testDefaultPrivacyPolicyMasksRouteBeforeBuildingPreview() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(route: sampleRoute, workoutType: .running)

        XCTAssertTrue(preview.routeExists)
        XCTAssertNotNil(preview.imageURL)
        XCTAssertGreaterThan(preview.bounds?.minLatitude ?? 0, sampleRoute.bounds?.minLatitude ?? 0)
        XCTAssertLessThan(preview.bounds?.maxLatitude ?? 0, sampleRoute.bounds?.maxLatitude ?? 0)
    }

    func testPrivacyMaskingCanMakeShortRouteFallBack() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100)
            ],
            totalDistanceMeters: 100
        )

        let preview = builder.build(route: route, workoutType: .cycling)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
    }

    func testNilRouteReturnsSportFallback() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )

        let preview = builder.build(route: nil, workoutType: .cycling)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertNil(preview.bounds)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
    }

    func testEmptyRouteReturnsFallbackWithoutImageURL() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "test-token")
        )
        let route = WorkoutRoute(
            workoutId: UUID(),
            source: .appleHealthKit,
            coordinates: [],
            totalDistanceMeters: 0
        )

        let preview = builder.build(route: route, workoutType: .walking)

        XCTAssertFalse(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertEqual(preview.fallbackStyle, .walking)
    }

    func testRouteWithoutTokenKeepsRouteExistsAndUsesFallbackVisual() {
        let builder = StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: nil)
        )

        let preview = builder.build(route: sampleRoute, workoutType: .cycling)

        XCTAssertTrue(preview.routeExists)
        XCTAssertNil(preview.imageURL)
        XCTAssertEqual(preview.fallbackStyle, .cycling)
    }

    func testSnapshotDownloadReceivesOnlyMaskedCoordinatesAndDisablesCache() async throws {
        let renderer = WorkoutRouteSnapshotRenderer(previewBuilder: StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "synthetic-map-token")), download: { request in
                XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
                XCTAssertEqual(request.timeoutInterval, 20)
                let url = try XCTUnwrap(request.url)
                XCTAssertEqual(url.host, "api.mapbox.com")
                let decoded = try XCTUnwrap(url.absoluteString.removingPercentEncoding)
                let start = try XCTUnwrap(decoded.range(of: "geojson("))
                let end = try XCTUnwrap(decoded.range(of: ")/auto/"))
                let json = Data(decoded[start.upperBound..<end.lowerBound].utf8)
                let feature = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
                let geometry = try XCTUnwrap(feature["geometry"] as? [String: Any])
                let points = try XCTUnwrap(geometry["coordinates"] as? [[Double]])
                XCTAssertEqual(points.count, 2)
                XCTAssertGreaterThan(try XCTUnwrap(points.first?[1]), 37.50)
                XCTAssertLessThan(try XCTUnwrap(points.last?[1]), 37.50 + 900 / 111_000)
                return (Data([1, 2, 3]), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"])!)
            })
        let result = try await renderer.render(route: sampleRoute, workoutType: .running)
        XCTAssertEqual(result, Data([1, 2, 3]))
    }

    func testFullyMaskedRouteNeverRequestsOrUploadsMapImage() async throws {
        let renderer = WorkoutRouteSnapshotRenderer(previewBuilder: StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "synthetic-map-token")), download: { _ in
                XCTFail("A hidden route must not make any image request")
                throw WorkoutRouteSnapshotError.unavailable
            })
        let short = WorkoutRoute(workoutId: UUID(), source: .manual,
            coordinates: [coordinate(atMeters: 0), coordinate(atMeters: 100)], totalDistanceMeters: 100)
        let result = try await renderer.render(route: short, workoutType: .walking)
        XCTAssertNil(result)
    }

    func testMissingMapTokenFailsBeforeAnyNetworkRequest() async throws {
        let renderer = WorkoutRouteSnapshotRenderer(previewBuilder: StaticRoutePreviewBuilder(
            urlBuilder: MapboxStaticRouteURLBuilder(accessToken: nil)), download: { _ in
                XCTFail("Missing configuration must not request any image")
                throw WorkoutRouteSnapshotError.unavailable
            })
        do {
            _ = try await renderer.render(route: sampleRoute, workoutType: .running)
            XCTFail("A real route with no map token must be a retryable error")
        } catch { XCTAssertTrue(error is WorkoutRouteSnapshotError) }
    }

    func testSnapshotRejectsErrorResponseWrongHostMIMEAndOversizedBody() async throws {
        for (status, host, mime, count) in [
            (503, "api.mapbox.com", "image/png", 10),
            (200, "example.invalid", "image/png", 10),
            (200, "api.mapbox.com", "application/json", 10),
            (200, "api.mapbox.com", "image/png", 0),
            (200, "api.mapbox.com", "image/png", WorkoutPhotoPolicy.maximumBytes + 1)
        ] {
            let renderer = WorkoutRouteSnapshotRenderer(previewBuilder: StaticRoutePreviewBuilder(
                urlBuilder: MapboxStaticRouteURLBuilder(accessToken: "synthetic-map-token")), download: { _ in
                    let url = URL(string: "https://\(host)/styles/v1/mapbox/light-v11/static")!
                    return (Data(repeating: 0, count: count), HTTPURLResponse(url: url, statusCode: status,
                        httpVersion: nil, headerFields: ["Content-Type": mime])!)
                })
            do {
                _ = try await renderer.render(route: sampleRoute, workoutType: .running)
                XCTFail("Invalid image response must not reach Storage")
            } catch { XCTAssertTrue(error is WorkoutRouteSnapshotError) }
        }
    }

    private var sampleRoute: WorkoutRoute {
        WorkoutRoute(
            workoutId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .appleHealthKit,
            coordinates: [
                coordinate(atMeters: 0),
                coordinate(atMeters: 100),
                coordinate(atMeters: 300),
                coordinate(atMeters: 600),
                coordinate(atMeters: 900)
            ],
            totalDistanceMeters: 900
        )
    }

    private func coordinate(atMeters meters: Double) -> WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            latitude: 37.50 + meters / 111_000,
            longitude: 127.00
        )
    }
}

@MainActor
final class SelectedWorkoutRouteShareTests: XCTestCase {
    private func route(_ id: UUID, values: [(Double, Double, Int)] = [
        (37.50,127.00,0),(37.51,127.00,0),(37.51,127.01,0),(37.52,127.01,0)]) -> WorkoutRoute {
        WorkoutRoute(workoutId: id, source: .soomLocal,
            coordinates: values.map { WorkoutRouteCoordinate(latitude: $0.0, longitude: $0.1, segmentIndex: $0.2) },
            totalDistanceMeters: 3000)
    }
    private func card(_ id: UUID, preview: StaticRoutePreview?) -> ShareableWorkoutCardModel {
        ShareableWorkoutCardModel(id: id, workoutType: .running, title: "Synthetic selected workout",
            distanceText: "3.00 km", durationText: "18분", primaryMessage: "Synthetic",
            growthMessage: "", recoveryMessage: "", footerText: "SOOM", visibility: .privateOnly, staticRoutePreview: preview)
    }
    private func preview(_ route: WorkoutRoute?, policy: RoutePrivacyMaskingPolicy = .defaultShare) -> StaticRoutePreview {
        StaticRoutePreviewBuilder(urlBuilder: MapboxStaticRouteURLBuilder(accessToken: nil))
            .build(route: route, workoutType: .running, privacyPolicy: policy)
    }
    func testActualSavedCoordinatesAndWorkoutIDSurviveMaskingAndTemplates() throws {
        let id = UUID(), saved = route(UUID())
        let selected = route(id, values: saved.coordinates.map { ($0.latitude,$0.longitude,$0.segmentIndex) })
        let payload = preview(selected), base = card(id, preview: payload)
        XCTAssertEqual(payload.routeWorkoutID, id)
        XCTAssertNil(payload.imageURL, "Local sharing does not need a map token or image request")
        let masked = RoutePrivacyMasker().mask(route: selected)
        XCTAssertEqual(payload.maskedCoordinates.map(\.latitude), masked.coordinates.map(\.latitude))
        XCTAssertNotEqual(payload.maskedCoordinates.first?.latitude, selected.coordinates.first?.latitude)
        for type in ShareCardComposerLayout.availableCardTypes(for: base) {
            let changed = base.configured(shareType: type, backgroundOption: .transparent)
            XCTAssertEqual(changed.id, id)
            XCTAssertEqual(changed.distanceText, "3.00 km")
            XCTAssertEqual(changed.durationText, "18분")
            XCTAssertEqual(changed.routeGeometry, base.routeGeometry)
            XCTAssertNotNil(ShareableWorkoutCardRenderer().render(card: changed, tint: SOOMColor.run))
        }
    }
    func testUnusedURLChangesCannotDismissTheSelectedSource() {
        let id = UUID(), original = preview(route(id))
        let urlChanged = StaticRoutePreview(imageURL: URL(string: "https://example.test/reordered-encoding"),
            bounds: original.bounds, routeExists: original.routeExists, fallbackStyle: original.fallbackStyle,
            routeWorkoutID: id, maskedCoordinates: original.maskedCoordinates)
        XCTAssertEqual(card(id,preview: original).imageSourceKey,card(id,preview: urlChanged).imageSourceKey)
        let denied = StaticRoutePreview(imageURL: nil, bounds: original.bounds, routeExists: false,
            fallbackStyle: original.fallbackStyle, routeWorkoutID: id, maskedCoordinates: original.maskedCoordinates)
        XCTAssertNotEqual(card(id,preview: original).imageSourceKey,card(id,preview: denied).imageSourceKey)
        XCTAssertNotEqual(card(id,preview: original).imageSourceKey,card(UUID(),preview: original).imageSourceKey)
        let changed = preview(route(id,values: [(37.5,127,0),(37.51,127.01,0),(37.52,127,0)]))
        XCTAssertNotEqual(card(id,preview: original).imageSourceKey,card(id,preview: changed).imageSourceKey)
    }
    func testMissingFullyMaskedAndInvalidRouteOfferOnlyNonrouteTemplates() {
        let id = UUID()
        let candidates: [WorkoutRoute?] = [nil, route(id, values: []),
            route(id, values: [(37.5,127,0),(37.5001,127,0)]),
            route(id, values: [(.nan,127,0),(37.51,127,0)]),
            route(id, values: [(91,127,0),(37.51,127,0)]),
            route(id, values: [(37.5,181,0),(37.51,127,0)]),
            route(id, values: [(37.5,127,0),(37.5,127,0)])]
        for candidate in candidates {
            let base = card(id, preview: preview(candidate))
            XCTAssertFalse(base.hasRoutePreviewPayload)
            XCTAssertFalse(base.shouldShowRouteVisual)
            XCTAssertEqual(ShareCardComposerLayout.availableCardTypes(for: base), [.workout,.recovery,.club])
            let refused = base.configured(shareType: .route, backgroundOption: .transparent)
            XCTAssertFalse(refused.canExportShareImage)
            XCTAssertNil(ShareableWorkoutCardRenderer().render(card: refused, tint: SOOMColor.run))
            XCTAssertNotNil(ShareableWorkoutCardRenderer().render(card: base.configured(shareType: .workout, backgroundOption: .transparent), tint: SOOMColor.run))
        }
    }
    func testOtherWorkoutAndLegacyImageOnlyPayloadCannotAuthorizeRoute() {
        let selected = UUID(), other = UUID()
        for payload in [preview(route(other)), StaticRoutePreview(imageURL: URL(string: "https://example.test/stale.jpg"), bounds: nil, routeExists: true, fallbackStyle: .running)] {
            let base = card(selected, preview: payload)
            XCTAssertNil(base.routeGeometry)
            XCTAssertFalse(ShareCardComposerLayout.availableCardTypes(for: base).contains(.route))
            XCTAssertNil(ShareableWorkoutCardRenderer().render(card: base.configured(shareType: .route, backgroundOption: .mapPhoto), tint: SOOMColor.run, resolvedRouteImage: UIImage()))
        }
    }
    func testFittedPathPreservesAspectCenterAndBoundsAcrossPageWidths() throws {
        let coordinates = [ShareRouteCoordinate(latitude: 0,longitude: 0), ShareRouteCoordinate(latitude: 1,longitude: 2)]
        let geometry = try XCTUnwrap(ShareRouteGeometry(coordinates: coordinates))
        for size in [CGSize(width: 200,height: 300), CGSize(width: 540,height: 220), CGSize(width: 1080,height: 1920)] {
            let rect = CGRect(origin: .zero, size: size), points = geometry.fittedPoints(in: rect)
            XCTAssertEqual(points.count, 2)
            let xSpan = abs(points[1].x-points[0].x), ySpan = abs(points[1].y-points[0].y)
            XCTAssertEqual(xSpan/ySpan, 2*cos(0.5 * .pi/180), accuracy: 0.0001)
            XCTAssertEqual((points[0].x+points[1].x)/2, rect.midX, accuracy: 0.0001)
            XCTAssertEqual((points[0].y+points[1].y)/2, rect.midY, accuracy: 0.0001)
            XCTAssertTrue(points.allSatisfy { $0.x >= 10 && $0.y >= 10 && $0.x <= size.width-10 && $0.y <= size.height-10 })
        }
    }
    func testDatelineAndPauseSegmentsDoNotProduceSyntheticConnectingRoute() throws {
        let values = [ShareRouteCoordinate(latitude: 0,longitude: 179.99), ShareRouteCoordinate(latitude: 0.01,longitude: -179.99),
            ShareRouteCoordinate(latitude: 0.02,longitude: -179.98,segmentIndex: 1),ShareRouteCoordinate(latitude: 0.03,longitude: -179.97,segmentIndex: 1)]
        let geometry = try XCTUnwrap(ShareRouteGeometry(coordinates: values))
        XCTAssertEqual(geometry.points.map(\.segmentIndex), [0,0,1,1])
        XCTAssertLessThan(geometry.extentWidth/geometry.extentHeight, 2)
        XCTAssertGreaterThan(geometry.extentWidth/geometry.extentHeight, 1)
        XCTAssertNil(ShareRouteGeometry(coordinates: [values[0],values[2]]), "Two isolated points do not imply a connecting path")
    }
    func testDifferentSavedGPSProducesDifferentExportWhileMetricsStayTheSame() throws {
        let aID = UUID(), bID = UUID()
        let a = card(aID, preview: preview(route(aID),policy: .none)).configured(shareType: .route, backgroundOption: .transparent)
        let b = card(bID, preview: preview(route(bID,values: [(37.50,127,0),(37.51,127.01,0),(37.52,127,0)]),policy: .none)).configured(shareType: .route, backgroundOption: .transparent)
        XCTAssertEqual(a.distanceText,b.distanceText)
        XCTAssertEqual(a.durationText,b.durationText)
        XCTAssertNotEqual(a.routeGeometry,b.routeGeometry)
        let renderer = ShareableWorkoutCardRenderer()
        let aImage = try XCTUnwrap(renderer.render(card: a,tint: SOOMColor.run)?.pngData())
        let bImage = try XCTUnwrap(renderer.render(card: b,tint: SOOMColor.run)?.pngData())
        XCTAssertNotEqual(aImage,bImage, "Export must depend on actual GPS, not one reusable ribbon")
    }
    func testLateRouteCannotCrossWorkoutAccountOrReentry() {
        var gate = ShareRouteRequestGate()
        let a = UUID(), b = UUID(), old = gate.begin(workoutID: a,scopeID: "synthetic-A")
        XCTAssertTrue(gate.accepts(old,workoutID: a,scopeID: "synthetic-A",isCancelled: false))
        XCTAssertFalse(gate.accepts(old,workoutID: b,scopeID: "synthetic-A",isCancelled: false))
        XCTAssertFalse(gate.accepts(old,workoutID: a,scopeID: "synthetic-B",isCancelled: false))
        let new = gate.begin(workoutID: b,scopeID: "synthetic-B")
        XCTAssertFalse(gate.accepts(old,workoutID: a,scopeID: "synthetic-A",isCancelled: false))
        XCTAssertFalse(gate.accepts(new,workoutID: b,scopeID: "synthetic-B",isCancelled: true))
        XCTAssertTrue(gate.accepts(new,workoutID: b,scopeID: "synthetic-B",isCancelled: false))
        _ = gate.begin(workoutID: b,scopeID: "synthetic-B")
        XCTAssertFalse(gate.accepts(new,workoutID: b,scopeID: "synthetic-B",isCancelled: false))
    }
    func testEmptyOrTooSmallDrawingBoundsProduceNoPath() throws {
        let geometry = try XCTUnwrap(ShareRouteGeometry(coordinates: [ShareRouteCoordinate(latitude: 0,longitude: 0),ShareRouteCoordinate(latitude: 1,longitude: 1)]))
        XCTAssertTrue(geometry.fittedPoints(in: .zero).isEmpty)
        XCTAssertTrue(geometry.fittedPoints(in: CGRect(x: 0,y: 0,width: 19,height: 19)).isEmpty)
    }
}
