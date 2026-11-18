import Foundation

enum WorkoutRouteSnapshotError: LocalizedError {
    case unavailable, invalidImage
    var errorDescription: String? {
        switch self {
        case .unavailable: return "경로 지도 이미지를 만들지 못했어요. 연결을 확인하고 다시 시도해 주세요."
        case .invalidImage: return "경로 지도 이미지를 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
}

/// Used only by an explicit share/visibility action. The request contains the
/// privacy-masked route; feed metadata stores the resulting private blob path,
/// never the request URL or raw coordinates.
struct WorkoutRouteSnapshotRenderer {
    typealias Download = (URLRequest) async throws -> (Data, URLResponse)
    private let previewBuilder: StaticRoutePreviewBuilder
    private let download: Download

    init(previewBuilder: StaticRoutePreviewBuilder = StaticRoutePreviewBuilder(),
         download: Download? = nil) {
        self.previewBuilder = previewBuilder
        self.download = download ?? Self.downloadSnapshot
    }

    func render(route: WorkoutRoute, workoutType: UnifiedWorkoutType) async throws -> Data? {
        try Task.checkCancellation()
        let preview = previewBuilder.build(route: route, workoutType: workoutType, width: 640, height: 480)
        // Short/indoor routes can disappear entirely inside the privacy mask.
        guard preview.routeExists else { return nil }
        guard let url = preview.imageURL, Self.isMapboxURL(url) else { throw WorkoutRouteSnapshotError.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("image/png,image/jpeg", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await download(request) }
        catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw WorkoutRouteSnapshotError.unavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let responseURL = http.url, Self.isMapboxURL(responseURL),
              ["image/png", "image/jpeg"].contains(http.mimeType?.lowercased() ?? ""),
              !data.isEmpty, data.count <= WorkoutPhotoPolicy.maximumBytes else {
            throw WorkoutRouteSnapshotError.invalidImage
        }
        return data
    }

    private static func isMapboxURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "api.mapbox.com" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443) && url.path.hasPrefix("/styles/v1/")
    }

    private static func downloadSnapshot(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        // Download to disk before allocating image bytes. Even an oversized
        // provider response cannot allocate an unbounded Data value in the app.
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= WorkoutPhotoPolicy.maximumBytes else { throw WorkoutRouteSnapshotError.invalidImage }
        return (try Data(contentsOf: file), response)
    }
}
