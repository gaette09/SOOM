import Foundation
import Combine

/// Source observation is independent of a SOOM confirmation. No legacy time/HR
/// estimate is promoted to a user rating. HealthKit access is intentionally absent.
struct WorkoutEffortObservation: Equatable {
    enum Origin: String { case apple, appleEstimate }
    let value: Double
    let origin: Origin
    let sampleID: UUID
    let workoutID: UUID
    let observedAt: Date
    var label: String { origin == .apple ? "Apple 기록" : "Apple 추정" }
}

struct WorkoutEffortConfirmation: Codable, Equatable {
    let value: Int
    let confirmedAt: Date
    let revision: UUID
    var scaleVersion: String? = nil
    var reviewedDurationSeconds: Double? = nil
    var durationPolicy: String? = nil
    var workoutStart: Date? = nil
    var workoutEnd: Date? = nil
    var unit: String? = nil
    var origin: String? = nil
    var isCleared: Bool? = nil
    var inputControlVersion: String? = nil
}

struct WorkoutEffortSessionContext: Equatable {
    let start: Date
    let end: Date
    let duration: Double
    init(_ workout: UnifiedWorkout) { start = workout.startDate; end = workout.endDate; duration = workout.durationSeconds }
    var recordedSeconds: Double? { duration.isFinite && duration > 0 && duration <= end.timeIntervalSince(start)+1 ? duration : nil }
}

@MainActor
protocol WorkoutEffortReading {
    func observation(workoutID: UUID) async throws -> WorkoutEffortObservation?
}

/// Permission-free boundary. A future relationship query adapter must resolve the
/// exact HKWorkout, preserve source/sample IDs, and stop its query on cancellation.
struct UnconnectedWorkoutEffortReader: WorkoutEffortReading {
    func observation(workoutID: UUID) async throws -> WorkoutEffortObservation? { nil }
}

@MainActor
protocol WorkoutEffortStoring {
    func load(workoutID: UUID) throws -> WorkoutEffortConfirmation?
    func save(_ value: WorkoutEffortConfirmation, workoutID: UUID) async throws
    func history(excluding workoutID: UUID) throws -> [WorkoutEffortConfirmation]
    func clear(workoutID: UUID) async throws
}

extension WorkoutEffortStoring {
    func clear(workoutID: UUID) async throws { throw CocoaError(.featureUnsupported) }
    func history(excluding workoutID: UUID) throws -> [WorkoutEffortConfirmation] { [] }
}

/// Descriptive personal range, never a prescribed or medically "normal" range.
/// The annotation format has confirmation dates, not workout dates or sport.
/// Use only other local confirmations in the past 21 days; do not substitute
/// RelativeEffort's duration/HR-derived load or unconfirmed Apple estimates.
struct WorkoutEffortUsualRange: Equatable {
    static let minimumCount = 5
    static let lookbackDays = 21
    let lower: Double
    let upper: Double
    let count: Int
    var automaticCount = 0
    var initialEstimateCount = 0
    var referenceMean: Double? = nil
    var comparisonVersion: String? = nil
    var displayTitle: String { comparisonVersion == nil ? "내 입력 점수 범위" : automaticCount > 0 ? "점수 추정 범위" : "최근 점수 범위" }

    static func build(_ history: [WorkoutEffortConfirmation], now: Date = Date(), calendar: Calendar = .current) -> Self? {
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return nil }
        let values = history.filter {
            (ActivityLoadRules.acceptsZero($0.scaleVersion) ? 0...10 : 1...10).contains($0.value) && $0.confirmedAt >= start && $0.confirmedAt < now
        }.map { Double($0.value) }.sorted()
        guard values.count >= minimumCount else { return nil }
        func percentile(_ p: Double) -> Double {
            let index = Double(values.count - 1) * p, lo = Int(index)
            return values[lo] + (values[min(lo + 1, values.count - 1)] - values[lo]) * (index - Double(lo))
        }
        return Self(lower: percentile(0.25), upper: percentile(0.75), count: values.count, referenceMean: values.reduce(0,+) / Double(values.count))
    }
    var label: String {
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
        return lower == upper ? number(lower) : "\(number(lower))–\(number(upper))"
    }
    func relation(to value: Double, label: String = "평소 범위") -> String {
        value > upper ? label + " 이상" : value < lower ? label + " 미만" : label + " 안"
    }
}

/// Same product score contract as the activity graph, evaluated now using the
/// current baseline/calibration. This is descriptive and never a safety band.
/// Existing 21-day/minimum-five/central-50% constants are reused. Time never
/// weights an intensity comparison and no annotation or record is written.
/// Ephemeral aggregate diagnostics, not health samples or a persisted journal.
/// A nil range is not enough evidence to say that the user has too few records.
struct WorkoutEffortComparisonAssessment: Equatable {
    enum Availability: Equatable { case ready, insufficient, awaitingCompletedRecord, excludedRecord, invalidRecord }
    let range: WorkoutEffortUsualRange?
    let availability: Availability
    var candidateCount = 0
    var eligibleCount = 0
    var heldOutCount = 0
    enum Exclusion: String, CaseIterable {
        case recordState, quality, overlap, missingScore, scoreMethod
        var label: String {
            switch self {
            case .recordState: return "기록 상태 확인"
            case .quality: return "자료 상태 확인"
            case .overlap: return "별개 운동 시간 겹침"
            case .missingScore: return "점수 근거 확인"
            case .scoreMethod: return "점수 기준 확인"
            }
        }
    }
    // Aggregate, in-memory explanations only. Never a journal of health samples.
    var exclusions: [Exclusion: Int] = [:]
    var message: String {
        switch availability {
        case .ready: return "이전 점수의 비교 범위예요."
        case .insufficient:
            let reasons = Exclusion.allCases.compactMap { reason -> String? in
                guard let count = exclusions[reason], count > 0 else { return nil }
                return "\(reason.label) \(count)개"
            } + (heldOutCount > 0 ? ["보정 자료 경계 확인 \(heldOutCount)개"] : [])
            return "이전 21일 같은 종목 후보 \(candidateCount)개 중 비교 가능한 점수 \(eligibleCount)개 · 5개부터 범위를 표시해요."
                + (reasons.isEmpty ? "" : " " + reasons.joined(separator: " · ") + ".")
                + " 직접 입력을 추가해야 하는 것은 아니에요."
        case .awaitingCompletedRecord: return "운동 시간과 기록 갱신이 완료되면 비교 범위를 확인해요."
        case .excludedRecord: return "분석에서 제외한 기록은 비교 범위를 표시하지 않아요."
        case .invalidRecord: return "기록의 시간 정보를 확인하지 못해 비교 범위를 표시하지 못했어요."
        }
    }
}

enum WorkoutEffortScoreComparison {
    static func build(for target: UnifiedWorkout, workouts: [UnifiedWorkout],
                      confirmations: [UUID: WorkoutEffortConfirmation], maximum: Int?, at: Date,
                      storedHeartRates: [UUID: ActivityLoadHeartRateInput] = [:],
                      calibration: ActivityLoadCalibrationLedger = .empty(), calendar: Calendar = .current) -> WorkoutEffortUsualRange? {
        assessment(for: target, workouts: workouts, confirmations: confirmations, maximum: maximum, at: at,
                   storedHeartRates: storedHeartRates, calibration: calibration, calendar: calendar).range
    }
    static func assessment(for target: UnifiedWorkout, workouts: [UnifiedWorkout],
                           confirmations: [UUID: WorkoutEffortConfirmation], maximum: Int?, at: Date,
                           storedHeartRates: [UUID: ActivityLoadHeartRateInput] = [:],
                           calibration: ActivityLoadCalibrationLedger = .empty(), calendar: Calendar = .current) -> WorkoutEffortComparisonAssessment {
        guard at.timeIntervalSince1970.isFinite, target.startDate.timeIntervalSince1970.isFinite,
              target.endDate.timeIntervalSince1970.isFinite, target.endDate > target.startDate,
              let earliest = calendar.date(byAdding: .day, value: -WorkoutEffortUsualRange.lookbackDays, to: target.startDate) else {
            return .init(range: nil, availability: .invalidRecord)
        }
        guard target.endDate <= at, target.updatedAt <= at else {
            return .init(range: nil, availability: .awaitingCompletedRecord)
        }
        guard !target.isExcludedFromAnalysis else { return .init(range: nil, availability: .excludedRecord) }
        let unique = Dictionary(grouping: workouts + [target], by: \.id).values.compactMap { group -> UnifiedWorkout? in
            guard let first = group.first, group.allSatisfy({ $0 == first }) else { return nil }; return first
        }
        let rows = ActivityLoadCalculator.canonical(unique.filter { $0.startDate.timeIntervalSince1970.isFinite })
        // Retain the existing target/future hold-out: diagnostic visibility must
        // never relax eligibility or manufacture a personal reference.
        let earlier = unique.filter { $0.id != target.id && $0.endDate <= target.startDate }
        let admissibleKeys = Set(ActivityLoadCalibrationInputs.read(workouts:earlier,confirmations:confirmations,
            maximum:maximum,at:at,zone:calendar.timeZone.identifier,stored:storedHeartRates).pairs.filter { $0.sport == target.workoutType && $0.residual != nil }.map(\.key))
        let offsetIsHeldOut = calibration.states[target.workoutType.rawValue].map { Set($0.sampleKeys).isSubset(of:admissibleKeys) } ?? true
        let candidates = rows.filter { $0.id != target.id && $0.workoutType == target.workoutType && $0.startDate >= earliest && $0.endDate <= target.startDate }
        var sessions: [ActivityLoadSession] = []
        var heldOutCount = 0
        var exclusions: [WorkoutEffortComparisonAssessment.Exclusion: Int] = [:]
        for row in candidates {
            guard row.updatedAt <= at, !row.isExcludedFromAnalysis,
                  WorkoutEffortSessionContext(row).recordedSeconds != nil else {
                exclusions[.recordState, default: 0] += 1; continue
            }
            // `missing` describes the original summary, not a veto on a later
            // validated stored-HR estimate or an explicit, valid user override.
            // Session.resolve below still requires a real 1...10 input. Unknown
            // or estimated record-quality tags are not promoted here.
            guard [.complete, .partial, .missing].contains(row.dataQuality) else {
                exclusions[.quality, default: 0] += 1; continue
            }
            // Use the same single-source representatives as the activity graph.
            // Raw copies inside one existing canonical identity are not distinct
            // simultaneous sessions. Separate canonical workouts still conflict;
            // no measurements are fused and no duplicate adds another sample.
            guard !rows.contains(where: { other in other.id != row.id && min(other.endDate,row.endDate).timeIntervalSince(max(other.startDate,row.startDate)) > 1 }) else {
                exclusions[.overlap, default: 0] += 1; continue
            }
            let saved = confirmations[row.id].flatMap { $0.isCleared == true ? nil : $0 }
            let session = ActivityLoadSession.resolve(row, confirmation: saved, maximum: maximum, at: at,
                stored: storedHeartRates[row.id], calibration: calibration)
            guard let score = session.intensity, score.isFinite, (1...10).contains(score), let method = session.methodKey else {
                exclusions[.missingScore, default: 0] += 1; continue
            }
            if method.hasPrefix(ActivityLoadRules.manualMethod) {
                guard saved?.inputControlVersion == ActivityLoadRules.manualInputVersion else {
                    exclusions[.scoreMethod, default: 0] += 1; continue
                }
            } else {
                guard method.hasPrefix(ActivityLoadRules.automaticMethod) || method.hasPrefix(ActivityLoadRules.productPriorMethod) else {
                    exclusions[.scoreMethod, default: 0] += 1; continue
                }
                if !offsetIsHeldOut && method.contains(":" + ActivityLoadCalibrationRules.version) {
                    heldOutCount += 1; continue
                }
            }
            sessions.append(session)
        }
        guard sessions.count >= WorkoutEffortUsualRange.minimumCount else {
            return .init(range: nil, availability: .insufficient, candidateCount: candidates.count,
                         eligibleCount: sessions.count, heldOutCount: heldOutCount, exclusions: exclusions)
        }
        let scores = sessions.compactMap(\.intensity).sorted()
        let range = WorkoutEffortUsualRange(lower: ActivityLoadRules.quantile(scores,0.25), upper: ActivityLoadRules.quantile(scores,0.75), count: scores.count,
            automaticCount: sessions.filter { ActivityLoadRules.isAutomatic($0.methodKey) }.count,
            initialEstimateCount: sessions.filter { ActivityLoadRules.isAutomatic($0.methodKey) && $0.sourceLabel.contains("초기 추정") }.count,
            referenceMean: scores.reduce(0,+) / Double(scores.count),
            comparisonVersion: ActivityLoadRules.referenceKey(maximum: maximum) + ":same_sport_prior21_q25q75_v1:eligible_session_evidence_v2")
        return .init(range: range, availability: .ready, candidateCount: candidates.count,
                     eligibleCount: sessions.count, heldOutCount: heldOutCount, exclusions: exclusions)
    }
}

/// Private, account-scoped local annotation, deliberately outside UnifiedWorkout
/// and HealthCloudJournal. Reimport and public feed snapshots cannot overwrite it.
@MainActor
final class FileWorkoutEffortStore: WorkoutEffortStoring {
    let directory: URL
    private let canAccess: () -> Bool
    init(scopeDirectory: URL, canAccess: @escaping () -> Bool = { true }) {
        directory = scopeDirectory.appendingPathComponent("WorkoutEffort", isDirectory: true)
        self.canAccess = canAccess
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    func load(workoutID: UUID) throws -> WorkoutEffortConfirmation? {
        guard canAccess() else { throw CocoaError(.userCancelled) }
        guard FileManager.default.fileExists(atPath: url(workoutID).path) else { return nil }
        let value = try JSONDecoder().decode(WorkoutEffortConfirmation.self, from: Data(contentsOf: url(workoutID)))
        guard (ActivityLoadRules.acceptsZero(value.scaleVersion) ? 0...10 : 1...10).contains(value.value) else { throw CocoaError(.coderReadCorrupt) }
        return value.isCleared == true ? nil : value
    }
    /// Snapshot files off the UI executor; account access is checked at both ends.
    /// No cross-account cache or file writes are performed by the worker.
    func load(workoutIDs: Set<UUID>) async throws -> [UUID: WorkoutEffortConfirmation] {
        guard canAccess() else { throw CocoaError(.userCancelled) }
        let directory = directory
        let worker = Task.detached(priority: .userInitiated) {
            var result: [UUID: WorkoutEffortConfirmation] = [:]
            for id in workoutIDs {
                try Task.checkCancellation()
                let file = directory.appendingPathComponent(id.uuidString + ".json")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                let value = try JSONDecoder().decode(WorkoutEffortConfirmation.self, from: Data(contentsOf: file))
                guard (ActivityLoadRules.acceptsZero(value.scaleVersion) ? 0...10 : 1...10).contains(value.value) else { throw CocoaError(.coderReadCorrupt) }
                if value.isCleared != true { result[id] = value }
            }
            return result
        }
        let values = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard canAccess() else { throw CocoaError(.userCancelled) }
        return values
    }
    func save(_ value: WorkoutEffortConfirmation, workoutID: UUID) async throws {
        guard canAccess() else { throw CocoaError(.userCancelled) }
        guard (ActivityLoadRules.acceptsZero(value.scaleVersion) ? 0...10 : 1...10).contains(value.value) else { throw CocoaError(.validationMissingMandatoryProperty) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archiveExisting(workoutID)
        try JSONEncoder().encode(value).write(to: url(workoutID), options: [.atomic, .completeFileProtection])
        NotificationCenter.default.post(name: ActivityLoadRules.changed, object: directory.deletingLastPathComponent().path)
    }
    private func archiveExisting(_ id: UUID) throws {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return }
        let history = directory.appendingPathComponent("History", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data(contentsOf: url(id)).write(to: history.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
    }
    func clear(workoutID: UUID) async throws {
        guard canAccess() else { throw CocoaError(.userCancelled) }
        guard let old = try load(workoutID: workoutID) else { return }
        var tombstone = WorkoutEffortConfirmation(value: old.value, confirmedAt: Date(), revision: UUID())
        tombstone.scaleVersion = old.scaleVersion; tombstone.isCleared = true
        try await save(tombstone, workoutID: workoutID)
    }
    func history(excluding workoutID: UUID) throws -> [WorkoutEffortConfirmation] {
        guard canAccess() else { throw CocoaError(.userCancelled) }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && $0 != url(workoutID) }
            .map { try JSONDecoder().decode(WorkoutEffortConfirmation.self, from: Data(contentsOf: $0)) }
            .filter { $0.isCleared != true }
    }
}

@MainActor
final class WorkoutEffortEditor: ObservableObject {
    let workoutID: UUID
    private let store: any WorkoutEffortStoring
    private let reader: any WorkoutEffortReading
    @Published private(set) var confirmation: WorkoutEffortConfirmation?
    @Published private(set) var observation: WorkoutEffortObservation?
    @Published private(set) var draft: Double?
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    @Published private(set) var isEditing = false
    @Published private(set) var usualRange: WorkoutEffortUsualRange?
    @Published private(set) var historyUnavailable = false
    @Published private(set) var usesCurrentScoreComparison = false
    @Published private(set) var comparisonAssessment: WorkoutEffortComparisonAssessment?
    let sessionContext: WorkoutEffortSessionContext?
    @Published private(set) var automaticEstimate: ActivityLoadEstimate?
    @Published private(set) var hasExplicitScoreChoice = false
    var usesSessionScale: Bool { sessionContext != nil }
    private var loadFailed = false
    private var hasLoaded = false
    private var loadInFlight = false

    init(workoutID: UUID, store: any WorkoutEffortStoring, reader: (any WorkoutEffortReading)? = nil,
         sessionContext: WorkoutEffortSessionContext? = nil, automaticEstimate: ActivityLoadEstimate? = nil) {
        self.workoutID = workoutID; self.store = store; self.reader = reader ?? UnconnectedWorkoutEffortReader()
        self.sessionContext = sessionContext; self.automaticEstimate = automaticEstimate
    }
    /// Updating read-only source evidence never mutates the saved override or an active draft.
    func refreshAutomaticEstimate(_ value:ActivityLoadEstimate?) { automaticEstimate=value }
    private var validSessionConfirmation: Bool {
        guard let c=confirmation, let context=sessionContext,
              c.scaleVersion == ActivityLoadRules.scaleVersion,
              ((1...10).contains(c.value) || (c.value == 0 && c.inputControlVersion == nil && c.durationPolicy == ActivityLoadRules.legacyDurationPolicy)),
              c.workoutStart == context.start, c.workoutEnd == context.end,
              c.confirmedAt >= context.end, c.confirmedAt <= Date(),
              c.unit == ActivityLoadRules.intensityUnit, c.origin == "user",
              [ActivityLoadRules.durationPolicy,ActivityLoadRules.legacyDurationPolicy].contains(c.durationPolicy ?? "") else { return false }
        return true
    }
    var displayedValue: Double? {
        if usesSessionScale {
            if let c = confirmation, c.scaleVersion == ActivityLoadRules.scaleVersion { return validSessionConfirmation ? Double(c.value) : automaticEstimate?.value }
            return automaticEstimate?.value
        }
        return confirmation.map { Double($0.value) } ?? observation?.value
    }
    var displayedLabel: String {
        if let c=confirmation,c.value == 0 { return "기존 0점 · 보존" }
        if confirmation == nil && displayedValue != nil { return automaticEstimate?.isInitial == true ? "초기 추정" : "자동 추정" }
        if usesSessionScale {
            if let c=confirmation {
                if validSessionConfirmation { return c.value == 0 ? "기존 0점 · 보존" : "\(c.value) / 10" }
                if c.scaleVersion != ActivityLoadRules.scaleVersion { return "이전 입력 \(c.value)점 · 보존" }
                return automaticEstimate == nil ? "입력하기" : automaticEstimate?.isInitial == true ? "초기 추정" : "자동 추정"
            }
            return automaticEstimate == nil ? "입력하기" : automaticEstimate?.isInitial == true ? "초기 추정" : "자동 추정"
        }
        return displayedValue.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " / 10" } ?? "선택"
    }
    var sourceLabel: String {
        if let c=confirmation {
            if usesSessionScale && c.scaleVersion == ActivityLoadRules.scaleVersion && !validSessionConfirmation { return automaticEstimate == nil ? "원본 변경 · 재확인 필요" : automaticEstimate!.displaySourceLabel + " · 이전 수정값 재확인 가능" }
            if usesSessionScale && c.scaleVersion != ActivityLoadRules.scaleVersion { return automaticEstimate?.isInitial == true ? "초기 추정 사용 · 이전 입력은 보존돼요" : "이전 입력은 보존돼요. 새 지정 때만 바뀌어요" }
            return usesSessionScale ? "직접 지정 · 이 기기" : "SOOM에서 확인 · 이 기기에 저장"
        }
        return observation?.label ?? automaticEstimate?.displaySourceLabel ?? "자료 부족 · 직접 지정은 선택 사항"
    }
    var selectedValue: Int? {
        guard let draft else { return nil }
        if !hasExplicitScoreChoice {
            guard let c=confirmation, (1...10).contains(c.value), !usesSessionScale || validSessionConfirmation else { return nil }
            return c.value
        }
        return min(10,max(1,Int(draft.rounded())))
    }
    var isUsingSavedOverride: Bool { validSessionConfirmation }
    var draftScoreLabel: String {
        if let selectedValue { return "\(selectedValue) / 10" }
        if let c=confirmation { return "기존 \(c.value)점 · 보존" }
        return "선택 전"
    }
    var draftScoreSource: String { selectedValue == nil ? (confirmation == nil ? "직접 지정 전" : "이전 입력 보존") : "운동 강도" }
    var scoreAccessibilityValue: String { draftScoreSource + ", " + draftScoreLabel + ", 새 입력은 1부터 10까지 정수 단계" }
    func adjustScore(_ delta: Int) {
        let current=draft ?? 5
        let next = !hasExplicitScoreChoice && current.rounded() != current ? (delta > 0 ? ceil(current) : floor(current)) : current.rounded()+Double(delta)
        preview(next)
    }
    var canSave: Bool {
        guard hasExplicitScoreChoice, selectedValue != nil, !isSaving, !isLoading, !loadFailed else { return false }
        if let context=sessionContext { return hasExplicitScoreChoice && context.end > context.start && context.end <= Date() }
        return true
    }

    func load() async {
        guard !hasLoaded, !loadInFlight else { return }
        loadInFlight = true
        defer { loadInFlight = false; isLoading = false }
        isLoading = true; error = nil; loadFailed = false
        do {
            confirmation = try store.load(workoutID: workoutID)
            let read = try await reader.observation(workoutID: workoutID)
            if let read, read.workoutID == workoutID, read.value.isFinite, (0...10).contains(read.value) { observation = read }
            hasLoaded = true
            refreshHistory()
        } catch {
            loadFailed = true
            self.error = "저장된 강도를 불러오지 못했어요. 다시 시도해 주세요."
        }
        isLoading = false
    }
    func refreshScoreComparison(_ value: WorkoutEffortUsualRange?, unavailable: Bool = false,
                                assessment: WorkoutEffortComparisonAssessment? = nil) {
        usesCurrentScoreComparison = true; usualRange = value; historyUnavailable = unavailable
        comparisonAssessment = assessment
    }
    private func refreshHistory() {
        if usesCurrentScoreComparison { return }
        do {
            let history = try store.history(excluding: workoutID)
            usualRange = WorkoutEffortUsualRange.build(usesSessionScale ? history.filter { $0.scaleVersion == ActivityLoadRules.scaleVersion } : history.filter { $0.scaleVersion == nil })
            historyUnavailable = false
        } catch { usualRange = nil; historyUnavailable = true }
    }
    func begin() {
        guard !isLoading, !loadFailed else { return }
        refreshHistory()
        // Keep the original value, including a historic zero, without turning it
        // into a new step selection or changing the stored automatic decimal.
        draft = displayedValue ?? (usesSessionScale ? confirmation.map { Double($0.value) } : nil)
        hasExplicitScoreChoice=false;error=nil;isEditing=true
    }
    func preview(_ value: Double) { guard isEditing, !isSaving, value.isFinite else { return }; draft=min(10,max(1,value));hasExplicitScoreChoice=true;error=nil }
    func cancel() { guard !isSaving else { return };draft=nil;hasExplicitScoreChoice=false;error=nil;isEditing=false }
    @discardableResult func save() async -> Bool {
        guard isEditing, canSave, let selectedValue else { return false }
        isSaving = true; error = nil
        defer { isSaving = false }
        var next = WorkoutEffortConfirmation(value: selectedValue, confirmedAt: Date(), revision: UUID())
        if let context = sessionContext {
            next.scaleVersion = ActivityLoadRules.scaleVersion; next.reviewedDurationSeconds = context.recordedSeconds
            next.inputControlVersion = ActivityLoadRules.manualInputVersion
            next.durationPolicy = ActivityLoadRules.durationPolicy; next.workoutStart = context.start; next.workoutEnd = context.end
            next.unit = ActivityLoadRules.intensityUnit; next.origin = "user"
        }
        do {
            try await store.save(next, workoutID: workoutID)
            confirmation = next; draft = nil; hasExplicitScoreChoice = false; isEditing = false
            return true
        } catch {
            self.error = "저장하지 못했어요. 선택은 유지돼요. 다시 시도해 주세요."
            return false
        }
    }
    @discardableResult func clearConfirmation() async -> Bool {
        guard !isSaving, !isLoading, !loadFailed else { return false }
        isSaving = true; defer { isSaving = false }
        do {
            try await store.clear(workoutID: workoutID)
            confirmation = nil; draft = nil; hasExplicitScoreChoice = false; isEditing = false; error = nil
            return true
        } catch { self.error = "직접 입력을 해제하지 못했어요."; return false }
    }
}

/// Used only by explicitly selected synthetic review fixtures and unit tests.
@MainActor
final class FixtureWorkoutEffortStore: WorkoutEffortStoring, WorkoutEffortReading {
    var historyValues: [WorkoutEffortConfirmation] = []
    var failsHistory = false
    func history(excluding workoutID: UUID) throws -> [WorkoutEffortConfirmation] {
        if failsHistory { throw CocoaError(.fileReadUnknown) }; return historyValues
    }
    var value: WorkoutEffortConfirmation?
    var observed: WorkoutEffortObservation?
    var failsNextSave = false
    var saveCount = 0
    var delay: Duration = .milliseconds(350)
    func load(workoutID: UUID) throws -> WorkoutEffortConfirmation? { value }
    func clear(workoutID: UUID) async throws { value = nil }
    func observation(workoutID: UUID) async throws -> WorkoutEffortObservation? { observed }
    func save(_ value: WorkoutEffortConfirmation, workoutID: UUID) async throws {
        saveCount += 1
        try await Task.sleep(for: delay)
        if failsNextSave { failsNextSave = false; throw CocoaError(.fileWriteUnknown) }
        self.value = value
    }
}
