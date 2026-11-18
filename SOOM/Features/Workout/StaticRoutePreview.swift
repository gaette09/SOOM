import Foundation

enum StaticRouteFallbackStyle: String, Equatable {
    case running
    case cycling
    case swimming
    case walking
    case generic
    case indoor

    init(workoutType: UnifiedWorkoutType) {
        switch workoutType {
        case .running:
            self = .running
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .walking, .hiking:
            self = .walking
        case .strength, .yoga, .other:
            self = .generic
        }
    }
}

struct StaticRoutePreview: Equatable {
    let imageURL: URL?
    let bounds: WorkoutRouteBounds?
    let routeExists: Bool
    let fallbackStyle: StaticRouteFallbackStyle
    let routeWorkoutID: UUID?
    let maskedCoordinates: [ShareRouteCoordinate]
    init(imageURL: URL?, bounds: WorkoutRouteBounds?, routeExists: Bool,
         fallbackStyle: StaticRouteFallbackStyle, routeWorkoutID: UUID? = nil,
         maskedCoordinates: [ShareRouteCoordinate] = []) {
        self.imageURL = imageURL; self.bounds = bounds; self.routeExists = routeExists
        self.fallbackStyle = fallbackStyle; self.routeWorkoutID = routeWorkoutID
        self.maskedCoordinates = maskedCoordinates
    }
}

/// Share payload contains only the already-masked path, never health streams.
struct ShareRouteCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    let segmentIndex: Int
    init(latitude: Double, longitude: Double, segmentIndex: Int = 0) {
        self.latitude = latitude; self.longitude = longitude; self.segmentIndex = segmentIndex
    }
}

struct ShareRouteGeometry: Equatable {
    struct Point: Equatable { let x: Double; let y: Double; let segmentIndex: Int }
    let points: [Point]
    let extentWidth: Double
    let extentHeight: Double

    init?(coordinates: [ShareRouteCoordinate]) {
        guard coordinates.count >= 2, coordinates.count <= 100_000,
              coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite &&
                  abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else { return nil }
        // Unwrap the dateline. Preserve aspect at the path's mean latitude.
        let latitude = coordinates.map(\.latitude).reduce(0,+) / Double(coordinates.count)
        let longitudeScale = max(cos(latitude * .pi / 180), 0.000001)
        var unwrapped = coordinates[0].longitude
        var previous = coordinates[0].longitude
        var raw: [(Double,Double,Int)] = []
        for value in coordinates {
            var delta = value.longitude - previous
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            unwrapped += delta; previous = value.longitude
            raw.append((unwrapped * longitudeScale, -value.latitude, value.segmentIndex))
        }
        let minX = raw.map { $0.0 }.min()!, maxX = raw.map { $0.0 }.max()!
        let minY = raw.map { $0.1 }.min()!, maxY = raw.map { $0.1 }.max()!
        let span = max(maxX-minX, maxY-minY)
        guard span.isFinite, span > 0.000000001,
              zip(raw, raw.dropFirst()).contains(where: {
                  $0.0.2 == $0.1.2 && ($0.0.0 != $0.1.0 || $0.0.1 != $0.1.1)
              }) else { return nil }
        extentWidth = (maxX-minX)/span; extentHeight = (maxY-minY)/span
        points = raw.map { Point(x: ($0.0-(minX+maxX)/2)/span+0.5,
                                y: ($0.1-(minY+maxY)/2)/span+0.5, segmentIndex: $0.2) }
    }

    /// The same fitted points drive preview, exported line and endpoint dots.
    func fittedPoints(in rect: CGRect, inset: CGFloat = 10) -> [CGPoint] {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > inset*2, rect.height > inset*2 else { return [] }
        let width = Double(rect.width-inset*2), height = Double(rect.height-inset*2)
        let scale = min(extentWidth > 0 ? width/extentWidth : .infinity,
                        extentHeight > 0 ? height/extentHeight : .infinity)
        guard scale.isFinite else { return [] }
        return points.map { CGPoint(x: Double(rect.midX)+($0.x-0.5)*scale,
                                    y: Double(rect.midY)+($0.y-0.5)*scale) }
    }
}
/// A route fetch belongs to one selected workout and account, including reentry.
struct ShareRouteRequestGate {
    struct Token { let id: UUID; let workoutID: UUID; let scopeID: String }
    private var requestID = UUID()
    mutating func begin(workoutID: UUID, scopeID: String) -> Token {
        requestID = UUID()
        return Token(id: requestID, workoutID: workoutID, scopeID: scopeID)
    }
    func accepts(_ token: Token, workoutID: UUID, scopeID: String, isCancelled: Bool) -> Bool {
        !isCancelled && token.id == requestID && token.workoutID == workoutID && token.scopeID == scopeID
    }
}
