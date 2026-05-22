import Foundation

struct MapboxStaticRouteURLBuilder {
    private let accessToken: String?
    private let defaultStyleID: String

    init(
        accessToken: String? = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
        defaultStyleID: String = "mapbox/outdoors-v12"
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
              width > 0,
              height > 0,
              let accessToken,
              !accessToken.isEmpty,
              let encodedGeoJSON = encodedGeoJSON(from: route)
        else {
            return nil
        }

        let style = styleID ?? defaultStyleID
        let encodedToken = accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accessToken
        let urlString = "https://api.mapbox.com/styles/v1/\(style)/static/geojson(\(encodedGeoJSON))/auto/\(width)x\(height)@2x?padding=64&access_token=\(encodedToken)"

        return URL(string: urlString)
    }

    private func encodedGeoJSON(from route: WorkoutRoute) -> String? {
        let coordinates = route.coordinates.map { coordinate in
            [coordinate.longitude, coordinate.latitude]
        }
        let geoJSON: [String: Any] = [
            "type": "Feature",
            "properties": [
                "stroke": "#2F7D5B",
                "stroke-width": 4,
                "stroke-opacity": 0.88
            ],
            "geometry": [
                "type": "LineString",
                "coordinates": coordinates
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
}
