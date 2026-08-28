import Foundation

struct StravaImportResult: Equatable {
    let totalRowCount: Int
    let importedCount: Int
    let skippedDuplicateCount: Int
    let skippedInvalidCount: Int
}

struct StravaImportPipeline {
    let reader: StravaExportReader
    let gzipDecompressor: GzipDecompressor
    let gpxParser: GPXRouteParser
    let tcxParser: TCXRouteParser
    let fitParser: FITRouteParser
    let deduplicationEngine: UnifiedWorkoutDeduplicationEngine
    let store: UnifiedWorkoutStore
    let referenceDate: () -> Date

    init(
        reader: StravaExportReader = StravaExportReader(),
        gzipDecompressor: GzipDecompressor = GzipDecompressor(),
        gpxParser: GPXRouteParser = GPXRouteParser(),
        tcxParser: TCXRouteParser = TCXRouteParser(),
        fitParser: FITRouteParser = FITRouteParser(),
        deduplicationEngine: UnifiedWorkoutDeduplicationEngine = UnifiedWorkoutDeduplicationEngine(),
        store: UnifiedWorkoutStore,
        referenceDate: @escaping () -> Date = Date.init
    ) {
        self.reader = reader
        self.gzipDecompressor = gzipDecompressor
        self.gpxParser = gpxParser
        self.tcxParser = tcxParser
        self.fitParser = fitParser
        self.deduplicationEngine = deduplicationEngine
        self.store = store
        self.referenceDate = referenceDate
    }

    func importZip(_ zipData: Data) async throws -> StravaImportResult {
        let entries = try reader.readEntries(from: zipData)

        // There is no "fetch all" on UnifiedWorkoutStore; a decade is the
        // practical equivalent for a fitness app's realistic history.
        var existingWorkouts = try await store.fetchRecentWorkouts(days: 3_650)

        var imported = 0
        var skippedDuplicate = 0
        var skippedInvalid = 0

        for entry in entries {
            guard let externalId = externalId(for: entry) else {
                skippedInvalid += 1
                continue
            }

            let candidate = buildWorkout(from: entry, externalId: externalId)

            let isDuplicate = existingWorkouts.contains { existing in
                deduplicationEngine.compare(existing, candidate) != nil
            }
            if isDuplicate {
                skippedDuplicate += 1
                continue
            }

            try await store.saveWorkout(candidate)
            existingWorkouts.append(candidate)
            imported += 1
        }

        return StravaImportResult(
            totalRowCount: entries.count,
            importedCount: imported,
            skippedDuplicateCount: skippedDuplicate,
            skippedInvalidCount: skippedInvalid
        )
    }

    private func externalId(for entry: StravaExportEntry) -> String? {
        if let filename = entry.filename, !filename.isEmpty {
            return filename
        }
        if let activityId = entry.activityId, !activityId.isEmpty {
            return "strava-activity-\(activityId)"
        }
        return nil
    }

    private func buildWorkout(from entry: StravaExportEntry, externalId: String) -> UnifiedWorkout {
        if let data = entry.data, let parsed = parseFile(entry: entry, data: data) {
            return workout(from: parsed, entry: entry, externalId: externalId)
        }

        // No file was ever attached, or the attached file couldn't be
        // decompressed/parsed. Either way, the row's CSV metadata alone is
        // enough for a minimal workout — never dropped outright.
        let routeMissingReason: WorkoutRouteMissingReason = entry.data == nil ? .indoorNoLocationData : .unknown
        return csvOnlyWorkout(entry: entry, externalId: externalId, routeMissingReason: routeMissingReason)
    }

    private enum ParsedFile {
        case gpx(GPXParsedRoute)
        case tcx(TCXParsedRoute)
        case fit(FITParsedRoute)
    }

    private func parseFile(entry: StravaExportEntry, data: Data) -> ParsedFile? {
        guard let filename = entry.filename else { return nil }

        let isGzipped = filename.lowercased().hasSuffix(".gz")
        let baseName = isGzipped ? String(filename.dropLast(3)) : filename
        let lowerBaseName = baseName.lowercased()

        do {
            let fileData = isGzipped ? try gzipDecompressor.decompress(data) : data

            if lowerBaseName.hasSuffix(".fit") {
                return .fit(try fitParser.parse(fileData))
            } else if lowerBaseName.hasSuffix(".gpx") {
                return .gpx(try gpxParser.parse(fileData))
            } else if lowerBaseName.hasSuffix(".tcx") {
                return .tcx(try tcxParser.parse(fileData))
            }
            return nil
        } catch {
            return nil
        }
    }

    private func workout(from parsed: ParsedFile, entry: StravaExportEntry, externalId: String) -> UnifiedWorkout {
        let mappedType = Self.workoutType(fromActivityType: entry.activityType)
        let now = referenceDate()

        switch parsed {
        case .gpx(let route):
            let summary = route.summary
            let startDate = summary.startDate ?? now
            let durationSeconds = summary.durationSeconds ?? entry.elapsedTimeSeconds ?? 0
            return UnifiedWorkout(
                id: UUID(),
                externalId: externalId,
                source: .strava,
                workoutType: mappedType != .other ? mappedType : .other,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(durationSeconds),
                durationSeconds: durationSeconds,
                distanceMeters: summary.distanceMeters ?? entry.distanceMeters,
                activeEnergyKcal: nil,
                averageHeartRate: summary.averageHeartRate,
                maxHeartRate: summary.maxHeartRate,
                averageSpeedMetersPerSecond: nil,
                elevationGainMeters: summary.elevationGainMeters,
                averagePowerWatts: nil,
                averageCadence: summary.averageCadence,
                routeMissingReason: .none,
                dataQuality: .complete,
                isExcludedFromAnalysis: false,
                createdAt: now,
                updatedAt: now,
                companionNames: []
            )
        case .tcx(let route):
            let summary = route.summary
            let startDate = summary.startDate ?? now
            let durationSeconds = summary.durationSeconds ?? entry.elapsedTimeSeconds ?? 0
            let resolvedType = mappedType != .other ? mappedType : (summary.workoutType ?? .other)
            return UnifiedWorkout(
                id: UUID(),
                externalId: externalId,
                source: .strava,
                workoutType: resolvedType,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(durationSeconds),
                durationSeconds: durationSeconds,
                distanceMeters: summary.distanceMeters ?? entry.distanceMeters,
                activeEnergyKcal: summary.activeEnergyKcal,
                averageHeartRate: summary.averageHeartRate,
                maxHeartRate: summary.maxHeartRate,
                averageSpeedMetersPerSecond: summary.averageSpeedMetersPerSecond,
                elevationGainMeters: summary.elevationGainMeters,
                averagePowerWatts: summary.averagePower,
                averageCadence: summary.averageCadence,
                routeMissingReason: .none,
                dataQuality: .complete,
                isExcludedFromAnalysis: false,
                createdAt: now,
                updatedAt: now,
                companionNames: []
            )
        case .fit(let route):
            let summary = route.summary
            let startDate = summary.startDate ?? now
            let durationSeconds = summary.durationSeconds ?? entry.elapsedTimeSeconds ?? 0
            let resolvedType = mappedType != .other ? mappedType : (summary.workoutType ?? .other)
            return UnifiedWorkout(
                id: UUID(),
                externalId: externalId,
                source: .strava,
                workoutType: resolvedType,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(durationSeconds),
                durationSeconds: durationSeconds,
                distanceMeters: summary.distanceMeters ?? entry.distanceMeters,
                activeEnergyKcal: summary.activeEnergyKcal,
                averageHeartRate: summary.averageHeartRate,
                maxHeartRate: summary.maxHeartRate,
                averageSpeedMetersPerSecond: summary.averageSpeedMetersPerSecond,
                elevationGainMeters: summary.elevationGainMeters,
                averagePowerWatts: summary.averagePower,
                averageCadence: summary.averageCadence,
                routeMissingReason: .none,
                dataQuality: .complete,
                isExcludedFromAnalysis: false,
                createdAt: now,
                updatedAt: now,
                companionNames: []
            )
        }
    }

    private func csvOnlyWorkout(
        entry: StravaExportEntry,
        externalId: String,
        routeMissingReason: WorkoutRouteMissingReason
    ) -> UnifiedWorkout {
        let now = referenceDate()
        let startDate = Self.parseActivityDate(entry.activityDate) ?? now
        let durationSeconds = entry.elapsedTimeSeconds ?? 0

        return UnifiedWorkout(
            id: UUID(),
            externalId: externalId,
            source: .strava,
            workoutType: Self.workoutType(fromActivityType: entry.activityType),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(durationSeconds),
            durationSeconds: durationSeconds,
            distanceMeters: entry.distanceMeters,
            activeEnergyKcal: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            averagePowerWatts: nil,
            averageCadence: nil,
            routeMissingReason: routeMissingReason,
            dataQuality: .partial,
            isExcludedFromAnalysis: false,
            createdAt: now,
            updatedAt: now,
            companionNames: []
        )
    }

    private static func workoutType(fromActivityType activityType: String?) -> UnifiedWorkoutType {
        guard let activityType, !activityType.isEmpty else { return .other }
        let lowered = activityType.lowercased()

        if lowered.contains("run") { return .running }
        if lowered.contains("ride") || lowered.contains("cycl") || lowered.contains("bike") { return .cycling }
        if lowered.contains("walk") { return .walking }
        if lowered.contains("hik") { return .hiking }
        if lowered.contains("swim") { return .swimming }
        if lowered.contains("yoga") { return .yoga }
        if lowered.contains("weight") || lowered.contains("strength")
            || lowered.contains("crossfit") || lowered.contains("workout") {
            return .strength
        }
        return .other
    }

    private static func parseActivityDate(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: dateString) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) { return date }

        for format in ["MMM d, yyyy, h:mm:ss a", "MMM d, yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) { return date }
        }

        return nil
    }
}
