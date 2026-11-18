import Foundation
import Combine
import SwiftData

/// No CloudJournal, server schema or HealthKit permission change. Separate from imported records.
@MainActor
struct ActivityLoadStoredHeartRateReader {
    let context:ModelContext
    var scope:String?=nil
    var cache:HealthKitDetailReadCache = .shared
    /// Local SwiftData + current account annotations, no new HealthKit/server query.
    /// Only needed when the current record has no usable measured HR.
    func historicalReference(for target: UnifiedWorkout, directory: URL, at: Date,
                             allowed: @escaping () -> Bool) throws -> ActivityLoadHistoryReference? {
        guard allowed() else { throw CocoaError(.userCancelled) }
        let earliest = target.startDate.addingTimeInterval(-90 * 86400), latest = target.startDate
        let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.startDate >= earliest && $0.startDate < latest }))
        let rows = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from: $0) }
        let efforts = FileWorkoutEffortStore(scopeDirectory: directory, canAccess: allowed)
        var ratings: [UUID: WorkoutEffortConfirmation] = [:]
        for id in Set(rows.map(\.id)) {
            guard allowed() else { throw CocoaError(.userCancelled) }
            if let rating = try efforts.load(workoutID: id) { ratings[id] = rating }
        }
        guard allowed() else { throw CocoaError(.userCancelled) }
        return ActivityLoadHistoryReference.resolve(for: target, workouts: rows, confirmations: ratings, at: at)
    }
    /// Read-only comparison from the account's existing records and overrides.
    /// No HealthKit query, journal approval, calibration learning or network call.
    func effortComparison(for target: UnifiedWorkout, directory: URL, maximum: Int?, at: Date,
                          allowed: @escaping () -> Bool, calendar: Calendar = .current) throws -> WorkoutEffortUsualRange? {
        try effortComparisonAssessment(for: target, directory: directory, maximum: maximum, at: at, allowed: allowed, calendar: calendar).range
    }
    func effortComparisonAssessment(for target: UnifiedWorkout, directory: URL, maximum: Int?, at: Date,
                                    allowed: @escaping () -> Bool, calendar: Calendar = .current) throws -> WorkoutEffortComparisonAssessment {
        guard allowed(), let earliest = calendar.date(byAdding: .day, value: -ActivityLoadCalibrationRules.lookbackDays, to: target.startDate) else { throw CocoaError(.userCancelled) }
        let latest = target.startDate
        let records = try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate: #Predicate { $0.endDate > earliest && $0.startDate < latest }))
        let rows = records.map { UnifiedWorkoutPersistenceMapper().makeWorkout(from:$0) }
        let efforts = FileWorkoutEffortStore(scopeDirectory:directory,canAccess:allowed)
        var ratings: [UUID:WorkoutEffortConfirmation] = [:]
        for id in Set(rows.map(\.id)) {
            guard allowed() else { throw CocoaError(.userCancelled) }
            if let value = try efforts.load(workoutID:id) { ratings[id] = value }
        }
        let stored = try read(rows)
        let ledger = try FileActivityLoadStore(scope:directory,allowed:allowed).loadCalibration()
        guard allowed() else { throw CocoaError(.userCancelled) }
        return WorkoutEffortScoreComparison.assessment(for:target,workouts:rows,confirmations:ratings,maximum:maximum,at:at,
            storedHeartRates:stored,calibration:ledger,calendar:calendar)
    }
    func read(_ workouts:[UnifiedWorkout]) throws -> [UUID:ActivityLoadHeartRateInput] {
        let missing=workouts.filter{ActivityLoadEstimate.measuredMean($0,stored:nil) == nil}
        guard let first=missing.map(\.startDate).min() else{return [:]}
        let wanted=Dictionary(grouping:missing,by: \.id).compactMapValues { group -> UnifiedWorkout? in
            guard let first=group.first,group.allSatisfy({$0 == first}) else{return nil};return first
        }
        let rows=try context.fetch(FetchDescriptor<UnifiedWorkoutRecord>(predicate:#Predicate{$0.startDate >= first}))
        var values:[UUID:ActivityLoadHeartRateInput]=[:]
        for row in rows {
            guard let workout=wanted[row.id],let blob=row.telemetryData,
                  let detail=try? JSONDecoder().decode(WorkoutTelemetry.self,from:blob),
                  let input=ActivityLoadHeartRateInput.stored(workout:workout,telemetry:detail) else{continue}
            values[row.id]=input
        }
        if let scope {
            for workout in missing where values[workout.id] == nil && workout.source == .appleHealthKit {
                guard let external=workout.externalId,UUID(uuidString:external) != nil else{continue}
                for needsRoute in [false,true] {
                    let key=HealthKitDetailReadCache.Key(scope:scope,workoutID:workout.id,externalID:external,revision:workout.updatedAt,needsRoute:needsRoute)
                    guard let cached=cache.cachedResult(for:key) else{continue}
                    if let raw=cached.workout {
                        let projection=workout.withHealthKitDetails(raw,telemetry:cached.telemetry,updatedAt:workout.updatedAt)
                        if let mean=ActivityLoadEstimate.measuredMean(projection,stored:nil) {
                            values[workout.id] = .init(value:mean.value,evidence:"cached_healthkit_mean_v1");break
                        }
                    }
                    if let mean=ActivityLoadHeartRateInput.stored(workout:workout,telemetry:cached.telemetry) {
                        values[workout.id] = .init(value:mean.value,evidence:"cached_"+mean.evidence);break
                    }
                }
            }
        }
        return values
    }
}

@MainActor
final class FileActivityLoadStore {
    let scope: URL
    private let allowed: () -> Bool
    private var directory: URL { scope.appendingPathComponent("ActivityLoad", isDirectory: true) }
    private var file: URL { directory.appendingPathComponent("journal-v1.json") }
    init(scope: URL, allowed: @escaping () -> Bool = { true }) { self.scope = scope; self.allowed = allowed }
    private func check() throws { guard allowed() else { throw CocoaError(.userCancelled) } }
    func load(defaultZone: String = TimeZone.current.identifier) throws -> ActivityLoadJournal {
        try check()
        guard FileManager.default.fileExists(atPath: file.path) else {
            let journal = ActivityLoadJournal.empty(zone: defaultZone)
            try save(journal); return journal
        }
        let value = try JSONDecoder().decode(ActivityLoadJournal.self, from: Data(contentsOf: file))
        guard value.schemaVersion == 1, TimeZone(identifier: value.timeZoneID) != nil, value.completenessVersion == nil || value.completenessVersion == ActivityLoadRules.completenessVersion else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    private struct CalibrationFile: Codable {
        let annotationFingerprint: String
        let ledger: ActivityLoadCalibrationLedger
    }
    private var calibrationFile: URL { directory.appendingPathComponent("score-calibration-v1.json") }
    private func annotationFingerprint() throws -> String {
        let folder = scope.appendingPathComponent("WorkoutEffort", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return ActivityLoadRules.hash("empty") }
        // Metadata only: detects edits/clears before another graph load, without reading health/rating values.
        let names = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        let entries = try names.map { url in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(url.lastPathComponent)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)"
        }.sorted()
        return ActivityLoadRules.hash(entries.joined(separator: ";"))
    }
    func loadCalibration(requireCurrentAnnotations: Bool = true) throws -> ActivityLoadCalibrationLedger {
        try check()
        guard FileManager.default.fileExists(atPath: calibrationFile.path) else { return .empty() }
        let value = try JSONDecoder().decode(CalibrationFile.self, from: Data(contentsOf: calibrationFile))
        guard value.ledger.valid else { throw CocoaError(.coderReadCorrupt) }
        if requireCurrentAnnotations, value.annotationFingerprint != (try annotationFingerprint()) { return .empty(enabled: value.ledger.enabled) }
        return value.ledger
    }
    func saveCalibration(_ ledger: ActivityLoadCalibrationLedger) throws {
        try check()
        guard ledger.valid else { throw CocoaError(.validationMissingMandatoryProperty) }
        let value = CalibrationFile(annotationFingerprint: try annotationFingerprint(), ledger: ledger)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard (try? Data(contentsOf: calibrationFile)) != data else { return }
        try check()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let old = try? Data(contentsOf: calibrationFile) {
            let history = directory.appendingPathComponent("History", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            try old.write(to: history.appendingPathComponent("score-calibration-" + UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
        }
        try data.write(to: calibrationFile, options: [.atomic, .completeFileProtection])
        // Separate signal: refreshing the editor must not trigger another workout-list fetch.
        NotificationCenter.default.post(name: ActivityLoadCalibrationRules.changed, object: scope.path)
    }
    func automaticEstimate(_ workout: UnifiedWorkout, maximum: Int?, at: Date,
                           stored: ActivityLoadHeartRateInput? = nil, history: ActivityLoadHistoryReference? = nil) -> ActivityLoadEstimate? {
        guard allowed() else { return nil }
        let base = ActivityLoadEstimate.automatic(workout, maximum: maximum, at: at, stored: stored, history: history)
        return ((try? loadCalibration()) ?? .empty(enabled: false)).applying(to: base, sport: workout.workoutType, at: at)
    }
    func saveCalculation(_ snapshot: ActivityLoadSnapshot, automaticPolicy: String = "base") throws {
        try check()
        let sessions = snapshot.days.flatMap(\.sessions).map { session in
            ActivityLoadCalculationReceipt.Session(workoutID: session.id, sourceUUID: session.workout.externalId, source: session.workout.source.rawValue,
                origin: session.methodKey == nil ? "unavailable" : session.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true ? "user" : "estimated",
                methodVersion: session.methodKey, scaleVersion: session.methodKey == nil ? "unresolved" : ActivityLoadRules.scaleVersion,
                unit: session.methodKey == nil ? "unresolved" : ActivityLoadRules.referenceUnit,
                inputUnit: session.methodKey == nil ? "unresolved" : ActivityLoadRules.intensityUnit,
                intensity: session.intensity, automaticIntensity: session.automaticValue, automaticSource: session.automaticSource, confidence: session.confidence, durationSeconds: session.durationSeconds, amount: session.amount,
                workoutUpdatedAt: session.workout.updatedAt, editedAt: session.confirmedAt, confirmationRevision: session.revision)
        }.sorted { $0.workoutID.uuidString < $1.workoutID.uuidString }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let sourceInputs = String(data: try encoder.encode(sessions), encoding: .utf8)!
        let signature = ActivityLoadRules.referenceVersion + automaticPolicy + snapshot.days.map { $0.fingerprint + ($0.methodKey ?? "") }.joined() + sourceInputs
        let receipt = ActivityLoadCalculationReceipt(schemaVersion: 3, referencePolicy: ActivityLoadRules.referenceVersion, aggregateVersion: ActivityLoadRules.aggregateVersion,
            computedAt: snapshot.asOf, analysisTimeZone: snapshot.timeZoneID,
            inputSnapshotID: ActivityLoadRules.hash(signature), sessions: sessions, automaticPolicy: automaticPolicy)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("last-calculation-v1.json")
        if let old = try? Data(contentsOf: target), let fields = try? JSONSerialization.jsonObject(with: old) as? [String: Any], (fields["referencePolicy"] as? String != ActivityLoadRules.referenceVersion || (fields["automaticPolicy"] as? String ?? "base") != automaticPolicy) {
            let history = directory.appendingPathComponent("History", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            try old.write(to: history.appendingPathComponent("calculation-" + UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
        }
        try encoder.encode(receipt).write(to: target, options: [.atomic, .completeFileProtection])
    }
    func save(_ journal: ActivityLoadJournal) throws {
        try check()
        guard TimeZone(identifier: journal.timeZoneID) != nil else { throw CocoaError(.validationMissingMandatoryProperty) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            let history = directory.appendingPathComponent("History", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            try Data(contentsOf: file).write(to: history.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
        }
        try JSONEncoder().encode(journal).write(to: file, options: [.atomic, .completeFileProtection])
    }
}

struct ActivityLoadCalculationReceipt: Codable {
    struct Session: Codable {
        let workoutID: UUID
        let sourceUUID: String?
        let source: String
        let origin: String
        let methodVersion: String?
        let scaleVersion: String
        let unit: String
        let inputUnit: String
        let intensity: Double?
        let automaticIntensity: Double?
        var automaticSource: String? = nil
        let confidence: String
        let durationSeconds: Double?
        let amount: Double?
        let workoutUpdatedAt: Date
        let editedAt: Date?
        let confirmationRevision: UUID?
    }
    let schemaVersion: Int
    let referencePolicy: String
    let aggregateVersion: String
    let computedAt: Date
    let analysisTimeZone: String
    let inputSnapshotID: String
    let sessions: [Session]
    let automaticPolicy: String?
}
@MainActor
final class ActivityLoadViewModel: ObservableObject {
    @Published private(set) var snapshot: ActivityLoadSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var inputReadCount = 0
    @Published private(set) var error: String?
    @Published private(set) var calibrationSummaries: [ActivityLoadCalibrationSummary] = []
    @Published private(set) var calibration = ActivityLoadCalibrationLedger.empty()
    @Published private(set) var calibrationNotice: String?
    private var journal: ActivityLoadJournal?
    private var workouts: [UnifiedWorkout] = []
    private var confirmations: [UUID: WorkoutEffortConfirmation] = [:]
    private var storedHeartRates:[UUID:ActivityLoadHeartRateInput]=[:]
    private var maximum: Int?
    private let local: FileActivityLoadStore
    private let efforts: FileWorkoutEffortStore
    private let allowed: () -> Bool
    private let now: () -> Date
    private var generation = UUID()
    private struct RefreshFlight { let key: String; let id: UUID; let task: Task<UUID?, Never> }
    private var refreshFlight: RefreshFlight?
    private var cachedRequest: String?
    private var cacheValidUntil: Date?
    private(set) var cacheHitCount = 0
    init(directory: URL, allowed: @escaping () -> Bool = { true }, now: @escaping () -> Date = Date.init) {
        self.local = FileActivityLoadStore(scope: directory, allowed: allowed)
        self.efforts = FileWorkoutEffortStore(scopeDirectory: directory, canAccess: allowed)
        self.allowed = allowed; self.now = now
    }
    /// The view owns the account scope and supplies data/edit revisions. No TTL:
    /// reuse stops at a changed revision/baseline, clock rollback, or a real time boundary.
    func reloadIfNeeded(revision: String, store: any UnifiedWorkoutStore, maximum: Int?,
                        storedHeartRates: (([UnifiedWorkout]) throws -> [UUID:ActivityLoadHeartRateInput])? = nil) async {
        guard allowed(), !Task.isCancelled else { return }
        let zone = journal?.timeZoneID ?? TimeZone.current.identifier, at = now()
        let key = revision + "|" + String(describing: maximum) + "|" + zone + "|" + TimeZone.current.identifier
        if cachedRequest == key, error == nil, calibrationNotice == nil, let snapshot, let until = cacheValidUntil,
           at >= snapshot.asOf, at < until {
            cacheHitCount += 1; return
        }
        if let flight = refreshFlight, flight.key == key, !flight.task.isCancelled {
            // Any cancelled consumer conservatively cancels this shared local read.
            // It never installs a cache receipt; the next appearance may retry.
            _ = await withTaskCancellationHandler(operation: { await flight.task.value }, onCancel: { flight.task.cancel() })
            return
        }
        refreshFlight?.task.cancel()
        let id = UUID()
        let task = Task { await self.reload(store: store, maximum: maximum, storedHeartRates: storedHeartRates) }
        refreshFlight = RefreshFlight(key: key, id: id, task: task)
        let completed = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard refreshFlight?.id == id else { return }
        refreshFlight = nil
        if completed == generation, !task.isCancelled, allowed(), error == nil, calibrationNotice == nil, snapshot != nil {
            // A missing journal can establish a zone on its first load.
            cachedRequest = revision + "|" + String(describing: maximum) + "|" + (journal?.timeZoneID ?? zone) + "|" + TimeZone.current.identifier
            cacheValidUntil = nextCalculationBoundary()
        }
    }
    private func nextCalculationBoundary() -> Date? {
        guard let snapshot else { return nil }
        let at = snapshot.asOf, calendar = ActivityLoadRules.calendar(snapshot.timeZoneID)
        var dates = [calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: at))!]
        for w in workouts {
            dates += [w.startDate, w.endDate, w.updatedAt]
            if let cutoff = calendar.date(byAdding: .day, value: ActivityLoadCalibrationRules.lookbackDays, to: w.startDate) {
                // The oldest teacher is included at the exact cutoff, excluded just after it.
                dates.append(Date(timeIntervalSinceReferenceDate: cutoff.timeIntervalSinceReferenceDate.nextUp))
            }
        }
        dates += confirmations.values.map(\.confirmedAt)
        dates += journal?.approvals.values.map(\.confirmedAt) ?? []
        for state in calibration.states.values {
            dates += [state.computedAt.addingTimeInterval(12 * 3600), state.computedAt.addingTimeInterval(86400),
                      state.windowStart.addingTimeInterval(ActivityLoadCalibrationRules.interval)]
        }
        return dates.filter { $0 > at }.min()
    }
    @discardableResult
    func reload(store: any UnifiedWorkoutStore, maximum: Int?, storedHeartRates: (([UnifiedWorkout]) throws -> [UUID:ActivityLoadHeartRateInput])? = nil) async -> UUID? {
        guard !Task.isCancelled else { return nil }
        cachedRequest = nil; cacheValidUntil = nil
        let token = UUID(); generation = token; isLoading = true; inputReadCount += 1
        defer { if generation == token { isLoading = false } }
        do {
            #if DEBUG && targetEnvironment(simulator)
            if ReviewDemoMode.isActive && ProcessInfo.processInfo.environment["SOOM_ACTIVITY_LOAD_QA"] == "1" {
                let mode = ProcessInfo.processInfo.environment["SOOM_ACTIVITY_LOAD_QA_MODE"]
                var saved:[UUID:WorkoutEffortConfirmation]=[:]
                if let qa=ActivityLoadQAFixture.effortDirectory(base:local.scope) {
                    let fixture=ActivityLoadQAFixture.make(automated:true,missing:true)
                    let file=FileWorkoutEffortStore(scopeDirectory:qa,canAccess:allowed)
                    for workout in fixture.recent {if let value=try file.load(workoutID:workout.id){saved[workout.id]=value}}
                }
                snapshot = ActivityLoadQAFixture.make(automated: ["auto","mixed","missing","baseline","stored","history"].contains(mode ?? ""), overridden: mode == "mixed", missing: mode == "missing" || mode == "stored" || mode == "history",missingBaseline:mode == "baseline",storedSamples:mode == "stored",historyReference:mode == "history",persistedOverrides:saved); error = nil; return token
            }
            #endif
            guard allowed() else { throw CocoaError(.userCancelled) }
            // Include 90-day teachers before the 180-day graph, in the same local read.
            let rows = try await store.fetchRecentWorkouts(days: 274)
            try Task.checkCancellation()
            guard allowed(), token == generation else { return nil }
            let measured=try storedHeartRates?(rows) ?? [:]
            guard allowed(),token == generation else{return nil}
            let original = try local.load()
            let ratings = try await efforts.load(workoutIDs: Set(rows.map(\.id)))
            try Task.checkCancellation()
            guard allowed(), token == generation else { return nil }
            let previous = try? local.loadCalibration(requireCurrentAnnotations: false)
            let at = now()
            // Only value snapshots cross executors; ModelContext and allowed() stay here.
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let journal = ActivityLoadCalculator.reconciledJournal(original, workouts: rows)
                let inputs = ActivityLoadCalibrationInputs.read(workouts: rows, confirmations: ratings,
                    maximum: maximum, at: at, zone: journal.timeZoneID, stored: measured)
                let ledger = previous?.updated(inputs: inputs, maximum: maximum, at: at) ?? .empty(enabled: false)
                try Task.checkCancellation()
                let result = ActivityLoadCalculator.build(workouts: rows, confirmations: ratings,
                    journal: journal, maximum: maximum, asOf: at, storedHeartRates: measured, calibration: ledger)
                try Task.checkCancellation()
                return (journal, inputs, ledger, result)
            }
            let (journal, inputs, ledger, result) = try await withTaskCancellationHandler(
                operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard allowed(), token == generation else { return nil }
            if journal != original { try local.save(journal) }
            calibrationNotice = nil
            if previous != nil {
                do { try local.saveCalibration(ledger) }
                catch { calibrationNotice = "자동 보정을 읽지 못해 기본 추정값을 유지해요. 저장된 직접 입력은 바뀌지 않아요." }
            } else { calibrationNotice = "자동 보정을 읽지 못해 기본 추정값을 유지해요. 저장된 직접 입력은 바뀌지 않아요." }
            try local.saveCalculation(result, automaticPolicy: ActivityLoadRules.initialPolicyVersion + ":" + ledger.policyKey)
            self.workouts = rows; self.confirmations = ratings; self.maximum = maximum; self.journal = journal; self.storedHeartRates=measured
            calibrationSummaries = inputs.summaries; calibration = ledger; snapshot = result; error = nil
            return token
        } catch {
            guard token == generation, allowed(), !Task.isCancelled else { return nil }
            self.error = "기록을 불러오지 못했어요. 기존 화면은 유지돼요."
        }
        return nil
    }
    private func recalculate() throws {
        cachedRequest = nil; cacheValidUntil = nil
        generation = UUID(); refreshFlight?.task.cancel(); refreshFlight = nil; isLoading = false
        guard allowed(), let journal else { return }
        let at = now()
        let inputs = ActivityLoadCalibrationInputs.read(workouts: workouts, confirmations: confirmations,
            maximum: maximum, at: at, zone: journal.timeZoneID, stored: storedHeartRates)
        var ledger = ActivityLoadCalibrationLedger.empty(enabled: false)
        do {
            let previous = try local.loadCalibration(requireCurrentAnnotations: false)
            ledger = previous.updated(inputs: inputs, maximum: maximum, at: at)
            // All current inputs were re-read above. Revalidate per sport, then refresh
            // the metadata envelope; unchanged bytes are a no-op in the store.
            try local.saveCalibration(ledger)
            calibrationNotice = nil
        } catch {
            // A corrupt/blocked calibration must not hide valid manual values or base estimates.
            calibrationNotice = "자동 보정을 읽지 못해 기본 추정값을 유지해요. 저장된 직접 입력은 바뀌지 않아요."
        }
        guard allowed() else { return }
        let result = ActivityLoadCalculator.build(workouts: workouts, confirmations: confirmations,
            journal: journal, maximum: maximum, asOf: at,storedHeartRates:storedHeartRates,calibration:ledger)
        try local.saveCalculation(result, automaticPolicy: ActivityLoadRules.initialPolicyVersion + ":" + ledger.policyKey)
        calibrationSummaries = inputs.summaries; calibration = ledger; snapshot = result
    }
    func setAutomaticCalibrationEnabled(_ enabled: Bool) {
        do {
            guard allowed() else { return }
            // Turning off discards the derived offset, never source ratings or settings.
            try local.saveCalibration(.empty(enabled: enabled))
            try recalculate()
        } catch { calibrationNotice = "자동 보정 설정을 저장하지 못했어요. 기존 기록은 유지돼요." }
    }
    func approve(_ day: ActivityLoadDay) {
        do {
            guard allowed(), var journal, !day.isForecast,
                  let end = ActivityLoadRules.calendar(journal.timeZoneID).date(byAdding: .day, value: 1, to: day.date),
                  end <= now() else { return }
            let kind: ActivityLoadDayApproval.Kind = day.rawCount == 0 ? .noWorkout : day.sessions.isEmpty ? .excludedOnly : .recordsReviewed
            journal.approvals[day.key] = ActivityLoadDayApproval(fingerprint: day.fingerprint, kind: kind, confirmedAt: now())
            try local.save(journal); self.journal = journal; try recalculate(); error = nil
        } catch { self.error = "이 날짜의 확인을 저장하지 못했어요." }
    }
    func changeTimeZone(_ identifier: String) {
        do {
            guard allowed(), let old = journal, TimeZone(identifier: identifier) != nil, old.timeZoneID != identifier else { return }
            // Original instants and ratings stay intact. Completeness approvals must be reviewed in the new calendar.
            let updated = ActivityLoadJournal.empty(zone: identifier)
            try local.save(updated); journal = updated; try recalculate(); error = nil
        } catch { self.error = "시간대 변경을 저장하지 못했어요." }
    }
}
