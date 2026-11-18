import CryptoKit
import Foundation

struct StravaImportProgress: Equatable {
    let completedCount: Int
    let totalCount: Int
    let activityName: String?
}

enum StravaImportReviewDecision: Equatable { case importSeparately, skip }

struct StravaImportReview: Identifiable, Equatable {
    let id: String
    let activityName: String
    let activityDate: Date
    let matchingWorkoutID: UUID
}

struct StravaImportIssue: Identifiable, Equatable {
    let id: Int
    let activityName: String
    let message: String
}

struct StravaImportResult: Equatable {
    var totalRowCount = 0
    var processedCount = 0
    var importedCount = 0
    var skippedDuplicateCount = 0
    var skippedInvalidCount = 0
    var skippedByUserCount = 0
    var summaryOnlyCount = 0
    var repairedRouteCount = 0
    var failedCount = 0
    var isCancelled = false
    var stoppedForLimit = false
    var reviews: [StravaImportReview] = []
    var issues: [StravaImportIssue] = []
    var completedEntryIDs: Set<String> = []
    var importedWorkoutIDs: [UUID] = []
}

enum StravaImportError: Error { case alreadyImporting }

private actor StravaImportGate {
    static let shared = StravaImportGate()
    private var isActive = false
    func acquire() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }
    func release() { isActive = false }
}

struct StravaImportPipeline {
    let reader: StravaExportReader
    let gzipDecompressor: GzipDecompressor
    let gpxParser: GPXRouteParser
    let tcxParser: TCXRouteParser
    let fitParser: FITRouteParser
    let deduplicationEngine: UnifiedWorkoutDeduplicationEngine
    let store: UnifiedWorkoutStore
    let routeStore: WorkoutRouteStore
    let referenceDate: () -> Date
    let autoPublishNewWorkouts: Bool
    let pendingAudience: FeedPostVisibility

    init(reader: StravaExportReader = StravaExportReader(),
         gzipDecompressor: GzipDecompressor = GzipDecompressor(maximumDecompressedBytes: 10 * 1_024 * 1_024),
         gpxParser: GPXRouteParser = GPXRouteParser(), tcxParser: TCXRouteParser = TCXRouteParser(),
         fitParser: FITRouteParser = FITRouteParser(),
         deduplicationEngine: UnifiedWorkoutDeduplicationEngine = UnifiedWorkoutDeduplicationEngine(),
         store: UnifiedWorkoutStore, routeStore: WorkoutRouteStore,
         referenceDate: @escaping () -> Date = Date.init,
         autoPublishNewWorkouts: Bool = false, pendingAudience: FeedPostVisibility = .privatePost) {
        self.reader = reader
        self.gzipDecompressor = gzipDecompressor
        self.gpxParser = gpxParser
        self.tcxParser = tcxParser
        self.fitParser = fitParser
        self.deduplicationEngine = deduplicationEngine
        self.store = store
        self.routeStore = routeStore
        self.referenceDate = referenceDate
        self.autoPublishNewWorkouts = autoPublishNewWorkouts
        self.pendingAudience = pendingAudience
    }

    func importZip(_ zipData: Data,
                   decisions: [String: StravaImportReviewDecision] = [:],
                   alreadyCompleted: Set<String> = [],
                   progress: @escaping (StravaImportProgress) async -> Void = { _ in }) async throws -> StravaImportResult {
        try await perform(open: { try reader.open(zipData) }, decisions: decisions, alreadyCompleted: alreadyCompleted, progress: progress)
    }

    func importZip(from url: URL,
                   decisions: [String: StravaImportReviewDecision] = [:],
                   alreadyCompleted: Set<String> = [],
                   progress: @escaping (StravaImportProgress) async -> Void = { _ in }) async throws -> StravaImportResult {
        try await perform(open: { try reader.open(url: url) }, decisions: decisions, alreadyCompleted: alreadyCompleted, progress: progress)
    }

    private func perform(open: () throws -> StravaExportArchive,
                         decisions: [String: StravaImportReviewDecision],
                         alreadyCompleted: Set<String>,
                         progress: @escaping (StravaImportProgress) async -> Void) async throws -> StravaImportResult {
        guard await StravaImportGate.shared.acquire() else { throw StravaImportError.alreadyImporting }
        do {
            let result = try await run(archive: open(), decisions: decisions, alreadyCompleted: alreadyCompleted, progress: progress)
            await StravaImportGate.shared.release()
            return result
        } catch {
            await StravaImportGate.shared.release()
            throw error
        }
    }

    private func run(archive: StravaExportArchive,
                     decisions: [String: StravaImportReviewDecision],
                     alreadyCompleted: Set<String>,
                     progress: @escaping (StravaImportProgress) async -> Void) async throws -> StravaImportResult {
        // Fuzzy comparisons use recent history; exact identity is looked up independently for every row.
        var existingWorkouts = try await store.fetchRecentWorkouts(days: 3_650)
        var result = StravaImportResult(totalRowCount: archive.entries.count)
        for index in archive.entries.indices {
            if Task.isCancelled { result.isCancelled = true; break }
            let metadata = archive.entries[index]
            let name = metadata.activityName ?? "활동 \(index + 1)"
            await progress(StravaImportProgress(completedCount: result.processedCount,
                                                totalCount: result.totalRowCount, activityName: name))
            do {
                try Task.checkCancellation()
                guard let externalID = Self.externalId(for: metadata) else {
                    result.skippedInvalidCount += 1
                    result.issues.append(StravaImportIssue(id: index, activityName: name, message: "활동 식별자가 없어 저장하지 않았어요."))
                    result.processedCount += 1
                    continue
                }
                if alreadyCompleted.contains(externalID) {
                    result.skippedDuplicateCount += 1
                    result.completedEntryIDs.insert(externalID)
                    result.processedCount += 1
                    continue
                }
                if let existing = try await exactWorkout(for: metadata, externalID: externalID) {
                    try await repairOrSkip(existing: existing, archive: archive, index: index, result: &result)
                    result.completedEntryIDs.insert(externalID)
                    result.processedCount += 1
                    continue
                }
                if decisions[externalID] == .skip {
                    result.skippedByUserCount += 1
                    result.processedCount += 1
                    continue
                }
                let entry = try archive.readEntry(at: index)
                let parsed = try parseFile(entry: entry, archive: archive)
                guard var candidate = buildWorkout(entry: entry, parsed: parsed, externalID: externalID) else {
                    result.skippedInvalidCount += 1
                    result.issues.append(StravaImportIssue(id: index, activityName: name,
                        message: "유효한 운동 날짜 또는 시간이 없어 저장하지 않았어요."))
                    result.processedCount += 1
                    continue
                }
                if decisions[externalID] != .importSeparately,
                   let match = existingWorkouts.first(where: { deduplicationEngine.compare($0, candidate) != nil }) {
                    if !result.reviews.contains(where: { $0.id == externalID }) {
                        result.reviews.append(StravaImportReview(id: externalID, activityName: name,
                            activityDate: candidate.startDate, matchingWorkoutID: match.id))
                    }
                    result.processedCount += 1
                    continue
                }
                try Task.checkCancellation()
                if autoPublishNewWorkouts { candidate.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for:pendingAudience) }
                // Until the route commits, the durable workout explicitly records that its route is missing.
                try await store.saveWorkout(candidate)
                result.importedWorkoutIDs.append(candidate.id)
                result.importedCount += 1
                existingWorkouts.append(candidate)
                if let parsed, parsed.coordinates.count >= 2 {
                    try await saveRoute(parsed, to: candidate, completesImport: true)
                } else {
                    result.summaryOnlyCount += 1
                    result.issues.append(StravaImportIssue(id: index, activityName: name,
                        message: parsed == nil
                            ? "GPS 파일을 읽을 수 없어 CSV의 날짜·시간·거리만 저장했어요."
                            : "GPS 좌표 없이 파일의 운동 요약을 저장했어요."))
                }
                result.completedEntryIDs.insert(externalID)
                result.processedCount += 1
            } catch is CancellationError {
                result.isCancelled = true
                break
            } catch {
                result.failedCount += 1
                result.processedCount += 1
                let limitReached: Bool
                if case StravaExportReaderError.expansionLimitExceeded = error { limitReached = true }
                else { limitReached = false }
                result.issues.append(StravaImportIssue(id: index, activityName: name,
                    message: limitReached
                        ? "한 번의 압축 해제 한도에 도달했어요. 완료한 항목은 유지되며 재시도로 나머지를 이어갈 수 있어요."
                        : "이 활동의 가져오기를 마치지 못했어요. 저장된 기록은 유지되며 재시도할 수 있어요."))
                if limitReached { result.stoppedForLimit = true; break }
            }
        }
        await progress(StravaImportProgress(completedCount: result.processedCount,
                                            totalCount: result.totalRowCount, activityName: nil))
        return result
    }

    private func exactWorkout(for entry: StravaExportEntry, externalID: String) async throws -> UnifiedWorkout? {
        if let workout = try await store.fetchByExternalId(externalID, source: .strava) { return workout }
        // The first released importer used the filename as its key. Preserve those IDs and user edits.
        if let filename = entry.filename, filename != externalID,
           let workout = try await store.fetchByExternalId(filename, source: .strava) { return workout }
        if let workout = try await store.fetchWorkout(id: Self.stableWorkoutID(for: externalID)),
           workout.source == .strava, workout.externalId == externalID { return workout }
        return nil
    }

    private func repairOrSkip(existing: UnifiedWorkout, archive: StravaExportArchive, index: Int,
                              result: inout StravaImportResult) async throws {
        if try await routeStore.fetchRoute(workoutId: existing.id) != nil {
            if existing.routeMissingReason == .routePersistenceFailed {
                try await store.saveWorkout(routeState(existing, reason: .none, quality: .complete))
                result.repairedRouteCount += 1
            } else { result.skippedDuplicateCount += 1 }
            return
        }
        let entry = try archive.readEntry(at: index)
        guard let parsed = try parseFile(entry: entry, archive: archive), parsed.coordinates.count >= 2 else {
            if existing.routeMissingReason == .none {
                try await store.saveWorkout(routeState(existing, reason: .externalSourceRouteNotShared, quality: .partial))
            }
            result.skippedDuplicateCount += 1
            return
        }
        try Task.checkCancellation()
        let pending = routeState(existing, reason: .routePersistenceFailed, quality: .partial)
        try await store.saveWorkout(pending)
        try await saveRoute(parsed, to: pending, completesImport: existing.routeMissingReason == .routePersistenceFailed || existing.dataQuality == .complete)
        result.repairedRouteCount += 1
    }

    private func saveRoute(_ parsed: ParsedActivity, to workout: UnifiedWorkout, completesImport: Bool) async throws {
        let route = WorkoutRoute(id: Self.stableWorkoutID(for: "route:\(workout.id.uuidString)"),
            workoutId: workout.id, source: .strava, coordinates: parsed.coordinates,
            totalDistanceMeters: parsed.routeDistance, totalElevationGain: parsed.elevationGain,
            createdAt: referenceDate())
        try await routeStore.saveRoute(route)
        // Only route metadata changes on retries; identity, exclusions, metrics, and user edits stay intact.
        try await store.saveWorkout(routeState(workout, reason: .none, quality: completesImport ? .complete : workout.dataQuality))
    }

    private func routeState(_ workout: UnifiedWorkout, reason: WorkoutRouteMissingReason,
                            quality: UnifiedDataQuality) -> UnifiedWorkout {
        UnifiedWorkout(id: workout.id, externalId: workout.externalId, source: workout.source,
            workoutType: workout.workoutType, startDate: workout.startDate, endDate: workout.endDate,
            durationSeconds: workout.durationSeconds, distanceMeters: workout.distanceMeters,
            activeEnergyKcal: workout.activeEnergyKcal, averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate, averageSpeedMetersPerSecond: workout.averageSpeedMetersPerSecond,
            elevationGainMeters: workout.elevationGainMeters, averagePowerWatts: workout.averagePowerWatts,
            averageCadence: workout.averageCadence, routeMissingReason: reason, dataQuality: quality,
            isExcludedFromAnalysis: workout.isExcludedFromAnalysis, createdAt: workout.createdAt,
            updatedAt: referenceDate(), companionNames: workout.companionNames,
            userTitle: workout.userTitle, userDescription: workout.userDescription,
            sharingVisibilityRaw: workout.sharingVisibilityRaw, isBookmarked: workout.isBookmarked,
            deviceName: workout.deviceName, locationName: workout.locationName)
    }

    static func externalId(for entry: StravaExportEntry) -> String? {
        if let activityID = entry.activityId?.trimmingCharacters(in: .whitespacesAndNewlines), !activityID.isEmpty {
            return "strava-activity-\(activityID)"
        }
        return entry.filename.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func stableWorkoutID(for externalID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("soom:strava:" + externalID).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private struct ParsedActivity {
        let coordinates: [WorkoutRouteCoordinate]
        let routeDistance: Double
        let type: UnifiedWorkoutType?
        let startDate: Date?
        let duration: Double?
        let distance: Double?
        let energy: Double?
        let heartRate: Double?
        let maxHeartRate: Double?
        let speed: Double?
        let elevationGain: Double?
        let power: Double?
        let cadence: Double?
    }

    private func parseFile(entry: StravaExportEntry, archive: StravaExportArchive) throws -> ParsedActivity? {
        guard let filename = entry.filename?.lowercased(), let data = entry.data else { return nil }
        let gzip = filename.hasSuffix(".gz")
        let name = gzip ? String(filename.dropLast(3)) : filename
        do {
            let bytes = gzip ? try gzipDecompressor.decompress(data) : data
            if gzip { try archive.chargeExpandedBytes(bytes.count) }
            try Task.checkCancellation()
            if name.hasSuffix(".gpx") {
                let route = try gpxParser.parse(bytes)
                let s = route.summary
                return ParsedActivity(coordinates: route.coordinates, routeDistance: route.totalDistanceMeters,
                    type: nil, startDate: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                    energy: nil, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                    speed: nil, elevationGain: s.elevationGainMeters, power: nil, cadence: s.averageCadence)
            }
            if name.hasSuffix(".tcx") {
                let route = try tcxParser.parse(bytes, allowMissingRoute: true)
                let s = route.summary
                return ParsedActivity(coordinates: route.coordinates, routeDistance: route.totalDistanceMeters,
                    type: s.workoutType, startDate: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                    energy: s.activeEnergyKcal, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                    speed: s.averageSpeedMetersPerSecond, elevationGain: s.elevationGainMeters,
                    power: s.averagePower, cadence: s.averageCadence)
            }
            if name.hasSuffix(".fit") {
                let route = try fitParser.parse(bytes, allowMissingRoute: true)
                let s = route.summary
                return ParsedActivity(coordinates: route.coordinates, routeDistance: route.totalDistanceMeters,
                    type: s.workoutType, startDate: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                    energy: s.activeEnergyKcal, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                    speed: s.averageSpeedMetersPerSecond, elevationGain: s.elevationGainMeters,
                    power: s.averagePower, cadence: s.averageCadence)
            }
            return nil
        } catch is CancellationError { throw CancellationError() }
        catch let error as StravaExportReaderError { throw error }
        catch { return nil }
    }

    private func buildWorkout(entry: StravaExportEntry, parsed: ParsedActivity?, externalID: String) -> UnifiedWorkout? {
        guard let start = parsed?.startDate ?? Self.parseActivityDate(entry.activityDate),
              start.timeIntervalSince1970.isFinite,
              let duration = Self.positive(parsed?.duration) ?? Self.positive(entry.elapsedTimeSeconds) else { return nil }
        let csvType = Self.workoutType(fromActivityType: entry.activityType)
        let hasRoute = (parsed?.coordinates.count ?? 0) >= 2
        let now = referenceDate()
        return UnifiedWorkout(id: Self.stableWorkoutID(for: externalID), externalId: externalID, source: .strava,
            workoutType: csvType == .other ? (parsed?.type ?? .other) : csvType,
            startDate: start, endDate: start.addingTimeInterval(duration), durationSeconds: duration,
            distanceMeters: Self.nonnegative(parsed?.distance) ?? Self.nonnegative(entry.distanceMeters),
            activeEnergyKcal: Self.nonnegative(parsed?.energy), averageHeartRate: Self.positive(parsed?.heartRate),
            maxHeartRate: Self.positive(parsed?.maxHeartRate), averageSpeedMetersPerSecond: Self.nonnegative(parsed?.speed),
            elevationGainMeters: Self.nonnegative(parsed?.elevationGain), averagePowerWatts: Self.positive(parsed?.power),
            averageCadence: Self.positive(parsed?.cadence),
            routeMissingReason: hasRoute ? .routePersistenceFailed : .externalSourceRouteNotShared,
            dataQuality: .partial,
            isExcludedFromAnalysis: false, createdAt: now, updatedAt: now, companionNames: [],
            userTitle: entry.activityName.map { String($0.prefix(80)) }, deviceName: entry.deviceName.map { String($0.prefix(100)) })
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
    private static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func workoutType(fromActivityType value: String?) -> UnifiedWorkoutType {
        let value = value?.lowercased() ?? ""
        if value.contains("run") { return .running }
        if value.contains("ride") || value.contains("cycl") || value.contains("bike") { return .cycling }
        if value.contains("walk") { return .walking }
        if value.contains("hik") { return .hiking }
        if value.contains("swim") { return .swimming }
        if value.contains("yoga") { return .yoga }
        if value.contains("weight") || value.contains("strength") || value.contains("crossfit") || value.contains("workout") { return .strength }
        return .other
    }

    static func parseActivityDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        for format in ["MMM d, yyyy, h:mm:ss a", "MMM d, yyyy", "MMM d yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

// Imports an activity-original file without requiring a Strava CSV or partner account.
// File bytes identify retries even when a user renames the file.
enum WorkoutFileImportOutcome {
    case imported(UUID, routeSaved: Bool)
    case duplicate
    case similarWorkout
}

enum WorkoutFileImportError: LocalizedError {
    case unsupportedFile, fileTooLarge, missingSummary, invalidSummary
    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "FIT, TCX 또는 GPX 운동 파일을 선택해 주세요."
        case .fileTooLarge: return "운동 파일은 10MB 이하여야 해요."
        case .missingSummary: return "운동 시작 시각과 총 시간이 파일에 없어 새 운동을 만들 수 없어요."
        case .invalidSummary: return "파일의 운동 날짜 또는 시간이 올바르지 않아요."
        }
    }
}

struct WorkoutFileImportService {
    let store: UnifiedWorkoutStore
    let routeStore: WorkoutRouteStore

    func importFile(_ data: Data, filename: String, sport: UnifiedWorkoutType,
                    deviceName: String, autoPublish: Bool, pendingAudience: FeedPostVisibility = .privatePost, allowSimilar: Bool = false) async throws -> WorkoutFileImportOutcome {
        guard data.count <= 10 * 1_024 * 1_024 else { throw WorkoutFileImportError.fileTooLarge }
        let extensionName = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let parsed: ParsedFile
        switch extensionName {
        case "fit":
            let route = try FITRouteParser().parse(data, allowMissingRoute: true)
            let s = route.summary
            parsed = ParsedFile(coordinates: route.coordinates, type: s.workoutType,
                start: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                energy: s.activeEnergyKcal, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                speed: s.averageSpeedMetersPerSecond, elevation: s.elevationGainMeters,
                power: s.averagePower, cadence: s.averageCadence)
        case "tcx":
            let route = try TCXRouteParser().parse(data, allowMissingRoute: true)
            let s = route.summary
            parsed = ParsedFile(coordinates: route.coordinates, type: s.workoutType,
                start: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                energy: s.activeEnergyKcal, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                speed: s.averageSpeedMetersPerSecond, elevation: s.elevationGainMeters,
                power: s.averagePower, cadence: s.averageCadence)
        case "gpx":
            let route = try GPXRouteParser().parse(data)
            let s = route.summary
            parsed = ParsedFile(coordinates: route.coordinates, type: nil,
                start: s.startDate, duration: s.durationSeconds, distance: s.distanceMeters,
                energy: nil, heartRate: s.averageHeartRate, maxHeartRate: s.maxHeartRate,
                speed: nil, elevation: s.elevationGainMeters, power: nil, cadence: s.averageCadence)
        default: throw WorkoutFileImportError.unsupportedFile
        }
        guard let start = parsed.start, let duration = parsed.duration else { throw WorkoutFileImportError.missingSummary }
        guard start.timeIntervalSince1970.isFinite, duration.isFinite, duration > 0,
              duration < 7 * 24 * 3_600 else { throw WorkoutFileImportError.invalidSummary }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let externalID = "file-import-\(digest)"
        if try await store.fetchByExternalId(externalID, source: .unknown) != nil { return .duplicate }
        let now = Date()
        let hasRoute = parsed.coordinates.count >= 2
        var workout = UnifiedWorkout(
            id: StravaImportPipeline.stableWorkoutID(for: externalID), externalId: externalID,
            source: .unknown, workoutType: sport == .other ? (parsed.type ?? .other) : sport,
            startDate: start, endDate: start.addingTimeInterval(duration), durationSeconds: duration,
            distanceMeters: Self.valid(parsed.distance), activeEnergyKcal: Self.valid(parsed.energy),
            averageHeartRate: Self.valid(parsed.heartRate), maxHeartRate: Self.valid(parsed.maxHeartRate),
            averageSpeedMetersPerSecond: Self.valid(parsed.speed), elevationGainMeters: Self.valid(parsed.elevation),
            averagePowerWatts: Self.valid(parsed.power), averageCadence: Self.valid(parsed.cadence),
            routeMissingReason: hasRoute ? .routePersistenceFailed : .externalSourceRouteNotShared,
            dataQuality: .partial, isExcludedFromAnalysis: false, createdAt: now, updatedAt: now,
            deviceName: String(deviceName.prefix(100))
        )
        if !allowSimilar {
            let existing = try await store.fetchRecentWorkouts(days: 3_650)
            if existing.contains(where: { UnifiedWorkoutDeduplicationEngine().compare($0, workout) != nil }) {
                return .similarWorkout
            }
        }
        if autoPublish { workout.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for:pendingAudience) }
        try await store.saveWorkout(workout)
        guard hasRoute else { return .imported(workout.id, routeSaved: false) }
        let route = WorkoutRoute(
            id: StravaImportPipeline.stableWorkoutID(for: "route:\(workout.id.uuidString)"),
            workoutId: workout.id, source: .unknown, coordinates: parsed.coordinates,
            totalDistanceMeters: parsed.distance ?? 0, totalElevationGain: parsed.elevation,
            createdAt: now
        )
        do {
            try await routeStore.saveRoute(route)
            let complete = UnifiedWorkout(
                id: workout.id, externalId: workout.externalId, source: workout.source,
                workoutType: workout.workoutType, startDate: workout.startDate, endDate: workout.endDate,
                durationSeconds: workout.durationSeconds, distanceMeters: workout.distanceMeters,
                activeEnergyKcal: workout.activeEnergyKcal, averageHeartRate: workout.averageHeartRate,
                maxHeartRate: workout.maxHeartRate, averageSpeedMetersPerSecond: workout.averageSpeedMetersPerSecond,
                elevationGainMeters: workout.elevationGainMeters, averagePowerWatts: workout.averagePowerWatts,
                averageCadence: workout.averageCadence, routeMissingReason: .none, dataQuality: .complete,
                isExcludedFromAnalysis: false, createdAt: workout.createdAt, updatedAt: Date(),
                userTitle: workout.userTitle, userDescription: workout.userDescription,
                sharingVisibilityRaw: workout.sharingVisibilityRaw, deviceName: workout.deviceName
            )
            try await store.saveWorkout(complete)
            return .imported(workout.id, routeSaved: true)
        } catch {
            // The workout remains durably saved with routePersistenceFailed and may be repaired later.
            return .imported(workout.id, routeSaved: false)
        }
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
    private struct ParsedFile {
        let coordinates: [WorkoutRouteCoordinate]
        let type: UnifiedWorkoutType?
        let start: Date?
        let duration: Double?
        let distance: Double?
        let energy: Double?
        let heartRate: Double?
        let maxHeartRate: Double?
        let speed: Double?
        let elevation: Double?
        let power: Double?
        let cadence: Double?
    }
}
