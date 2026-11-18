import Foundation
import SwiftData
import UIKit

struct WorkoutRouteMapper {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let courseIdentityBuilder: CourseIdentityBuilder

    init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        courseIdentityBuilder: CourseIdentityBuilder = CourseIdentityBuilder()
    ) {
        self.encoder = encoder
        self.decoder = decoder
        self.courseIdentityBuilder = courseIdentityBuilder
    }

    func makeRecord(
        from route: WorkoutRoute,
        updatedAt: Date = Date()
    ) -> PersistedWorkoutRoute {
        PersistedWorkoutRoute(
            id: route.id,
            workoutId: route.workoutId,
            sourceRaw: route.source.rawValue,
            encodedCoordinates: encodeCoordinates(route.coordinates),
            coordinateCount: route.coordinates.count,
            totalDistanceMeters: route.totalDistanceMeters,
            totalElevationGain: route.totalElevationGain,
            createdAt: route.createdAt,
            updatedAt: updatedAt,
            courseIdentity: courseIdentityBuilder.build(from: route)?.courseId
        )
    }

    func update(
        _ record: PersistedWorkoutRoute,
        with route: WorkoutRoute,
        updatedAt: Date = Date()
    ) {
        record.id = route.id
        record.workoutId = route.workoutId
        record.sourceRaw = route.source.rawValue
        record.encodedCoordinates = encodeCoordinates(route.coordinates)
        record.coordinateCount = route.coordinates.count
        record.totalDistanceMeters = route.totalDistanceMeters
        record.totalElevationGain = route.totalElevationGain
        record.createdAt = route.createdAt
        record.updatedAt = updatedAt
        record.courseIdentity = courseIdentityBuilder.build(from: route)?.courseId
    }

    func makeRoute(from record: PersistedWorkoutRoute) -> WorkoutRoute {
        return WorkoutRoute(
            id: record.id,
            workoutId: record.workoutId,
            source: UnifiedDataSource(rawValue: record.sourceRaw) ?? .unknown,
            coordinates: decodeCoordinates(record.encodedCoordinates),
            totalDistanceMeters: record.totalDistanceMeters,
            totalElevationGain: record.totalElevationGain,
            createdAt: record.createdAt
        )
    }

    func encodeCoordinates(_ coordinates: [WorkoutRouteCoordinate]) -> String? {
        let payload = coordinates.map(EncodedCoordinate.init)

        guard let data = try? encoder.encode(payload) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func decodeCoordinates(_ encodedCoordinates: String?) -> [WorkoutRouteCoordinate] {
        #if DEBUG
        WorkoutCardPerformanceProbe.hit("routeDecode")
        #endif
        guard
            let encodedCoordinates,
            let data = encodedCoordinates.data(using: .utf8),
            let payload = try? decoder.decode([EncodedCoordinate].self, from: data)
        else {
            return []
        }

        return payload.map(\.coordinate)
    }
}

private struct EncodedCoordinate: Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let timestamp: Date?
    let segmentIndex: Int?

    init(coordinate: WorkoutRouteCoordinate) {
        id = coordinate.id
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        altitude = coordinate.altitude
        timestamp = coordinate.timestamp
        segmentIndex = coordinate.segmentIndex
    }

    var coordinate: WorkoutRouteCoordinate {
        WorkoutRouteCoordinate(
            id: id,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            timestamp: timestamp,
            segmentIndex: segmentIndex ?? 0
        )
    }
}

#if DEBUG
/// Opt-in local fixture instrumentation. Counts operations, not server requests or FPS.
final class WorkoutCardPerformanceProbe: @unchecked Sendable {
    static let shared = WorkoutCardPerformanceProbe()
    private let lock = NSLock()
    private var active = false
    private var values: [String: Int] = [:]
    static var enabled: Bool { shared.lock.withLock { shared.active } }
    static func start() { shared.lock.withLock { shared.active = true; shared.values = [:] } }
    static func stop() { shared.lock.withLock { shared.active = false } }
    static func hit(_ name: String, by amount: Int = 1) { shared.lock.withLock { if shared.active { shared.values[name, default: 0] += amount } } }
    static var counts: [String: Int] { shared.lock.withLock { shared.values } }
}
#endif


/// Value-only copy: no SwiftData model crosses into the decoding worker.
struct WorkoutRouteReadSnapshot: Equatable {
    let id: UUID, workoutID: UUID
    let source: String
    let encoded: String?
    let distance: Double, elevation: Double?
    let createdAt: Date, updatedAt: Date
    init(_ record: PersistedWorkoutRoute) {
        id = record.id; workoutID = record.workoutId; source = record.sourceRaw
        encoded = record.encodedCoordinates; distance = record.totalDistanceMeters
        elevation = record.totalElevationGain; createdAt = record.createdAt; updatedAt = record.updatedAt
    }
    func route() -> WorkoutRoute {
        WorkoutRoute(id: id, workoutId: workoutID, source: UnifiedDataSource(rawValue: source) ?? .unknown,
            coordinates: WorkoutRouteMapper().decodeCoordinates(encoded), totalDistanceMeters: distance,
            totalElevationGain: elevation, createdAt: createdAt)
    }
}

/// One derived value per mounted card. Complete contents, not timestamps alone,
/// determine validity. Large routes remain exact but are not retained here.
@MainActor
final class WorkoutCardRouteProjection {
    private var containerID: ObjectIdentifier?
    private var input: WorkoutRouteReadSnapshot?
    private var decoded: WorkoutRoute?
    private var maskInput: WorkoutRoute?
    private var masked: WorkoutRoute?
    private var warning: NSObjectProtocol?
    init() {
        warning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.clear() } }
    }
    deinit { if let warning { NotificationCenter.default.removeObserver(warning) } }
    func clear() { containerID = nil; input = nil; decoded = nil; maskInput = nil; masked = nil }
    var retainedPointCount: Int { (decoded?.coordinates.count ?? 0) + (masked?.coordinates.count ?? 0) }
    func route(_ record: PersistedWorkoutRoute?, context: ModelContext) -> WorkoutRoute? {
        let scope = ObjectIdentifier(context.container)
        guard let record else { containerID = scope; input = nil; decoded = nil; return nil }
        let next = WorkoutRouteReadSnapshot(record)
        if scope == containerID, input == next { return decoded }
        let result = next.route()
        containerID = scope; input = nil; decoded = nil
        if result.coordinates.count <= 10_000, (next.encoded?.utf8.count ?? 0) <= 2 * 1_024 * 1_024 {
            input = next; decoded = result
        }
        return result
    }
    func preview(_ route: WorkoutRoute?) -> WorkoutRoute? {
        guard let route else { maskInput = nil; masked = nil; return nil }
        if route == maskInput { return masked }
        let result = RoutePrivacyMasker().mask(route: route)
        maskInput = nil; masked = nil
        if route.coordinates.count <= 10_000 { maskInput = route; masked = result }
        return result
    }
}
