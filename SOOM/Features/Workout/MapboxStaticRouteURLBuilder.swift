import Foundation

struct MapboxStaticRouteURLBuilder {
    private let accessToken: String?
    private let defaultStyleID: String

    init(
        accessToken: String? = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
        defaultStyleID: String = SOOMMapboxConfiguration.staticImagesStyleID
    ) {
        self.accessToken = accessToken
        self.defaultStyleID = defaultStyleID
    }

    func buildURL(
        for route: WorkoutRoute,
        width: Int = 640,
        height: Int = 800,
        styleID: String? = nil
    ) -> URL? {
        guard route.coordinates.count >= 2,
              (1...1280).contains(width),
              (1...1280).contains(height),
              let accessToken,
              !accessToken.isEmpty
        else {
            return nil
        }

        let style = styleID ?? defaultStyleID
        let encodedToken = accessToken.addingPercentEncoding(withAllowedCharacters: Self.geoJSONAllowedCharacters) ?? accessToken
        // Static Images requests have an 8,192-character limit. Simplify each
        // pause segment independently, retaining endpoints and route corners.
        // A replacement chord can reenter a hidden endpoint area even
        // when every point in the original segment is safe. No chord
        // simplification for a server-checked path; fall back if oversized.
        let tolerances = route.hasAuthoritativeShareMask ? [0.0]
            : [0.0, 0.00001, 0.00002, 0.00005, 0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01]
        for tolerance in tolerances {
            guard let encodedGeoJSON = encodedGeoJSON(from: route, tolerance: tolerance) else { return nil }
            let padding = max(48, min(width, height) / 5)
            let urlString = "https://api.mapbox.com/styles/v1/\(style)/static/geojson(\(encodedGeoJSON))/auto/\(width)x\(height)@2x?padding=\(padding)&access_token=\(encodedToken)"
            if urlString.utf8.count <= 8192 { return URL(string: urlString) }
        }
        return nil
    }

    private func encodedGeoJSON(from route: WorkoutRoute, tolerance: Double) -> String? {
        guard route.coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude)<=90 && abs($0.longitude)<=180 }) else { return nil }
        let segments = route.coordinateSegments.filter { $0.count >= 2 }.map { segment in
            Self.simplified(segment, tolerance: tolerance).map {
                [($0.longitude * 1_000_000).rounded() / 1_000_000, ($0.latitude * 1_000_000).rounded() / 1_000_000]
            }
        }
        guard !segments.isEmpty else { return nil }
        let geoJSON: [String: Any] = [
            "type": "Feature",
            "properties": [
                "stroke": SOOMRouteRenderingStyle.accentHex,
                "stroke-width": SOOMRouteRenderingStyle.detailLineWidth,
                "stroke-opacity": 0.88
            ],
            "geometry": [
                "type": segments.count == 1 ? "LineString" : "MultiLineString",
                "coordinates": segments.count == 1 ? segments[0] as Any : segments as Any
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: geoJSON, options: []) else {
            return nil
        }

        let json = String(decoding: data, as: UTF8.self)
        return json.addingPercentEncoding(withAllowedCharacters: Self.geoJSONAllowedCharacters)
    }

    private static let geoJSONAllowedCharacters: CharacterSet = {
        var characters = CharacterSet.alphanumerics
        characters.insert(charactersIn: "-._~")
        return characters
    }()

    private static func simplified(_ points: [WorkoutRouteCoordinate], tolerance: Double) -> [WorkoutRouteCoordinate] {
        guard tolerance > 0, points.count > 2 else { return points }
        var keep: Set<Int> = [0, points.count - 1]
        var ranges = [(0, points.count - 1)]
        while let (start, end) = ranges.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            let dx = b.longitude - a.longitude, dy = b.latitude - a.latitude
            let length = dx * dx + dy * dy
            var maximum = tolerance * tolerance
            var selected: Int?
            for index in (start + 1)..<end {
                let p = points[index]
                let t = length > 0 ? max(0, min(1, ((p.longitude-a.longitude)*dx + (p.latitude-a.latitude)*dy) / length)) : 0
                let x = p.longitude-a.longitude-t*dx, y = p.latitude-a.latitude-t*dy
                if x*x+y*y > maximum { maximum=x*x+y*y; selected=index }
            }
            if let selected { keep.insert(selected); ranges.append((start, selected)); ranges.append((selected, end)) }
        }
        return keep.sorted().map { points[$0] }
    }
}
