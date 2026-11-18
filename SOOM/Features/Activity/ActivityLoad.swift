import Foundation
import CryptoKit

/// Local descriptive units. A heart-rate proxy is not a measured subjective RPE.
/// Never feeds the legacy duration-dependent RelativeEffort back into this model.
enum ActivityLoadRules {
    static let aggregateVersion = "finite28_hl7_q10q90_past56_v4_recorded_time"
    // One product intensity input with an estimate or explicit user override, not validated RPE.
    // Source is provenance, not a new calculation contract or a continuity boundary.
    static let referenceVersion = "soom_session_intensity_contract_v3_recorded_time"
    static let referenceUnit = "SOOM_load_AU"
    static func referenceKey(maximum: Int?) -> String { referenceVersion + ":maxHR:" + (maximum.map(String.init) ?? "none") }
    static let scaleVersion = "soom_relative_session_intensity_0_10_v2"
    static let manualMethod = "soom_user_intensity_override_v2"
    static let automaticMethod = "soom_mean_hr_fraction_estimate_v2"
    static let productPriorMethod = "soom_product_prior_hr20_v1"
    static let historyPriorMethod = "soom_product_prior_manual_history_v1"
    static let initialPolicyVersion = "initial_product_input_v1"
    static func isAutomatic(_ method: String?) -> Bool {
        guard let method else { return false }
        return [automaticMethod, productPriorMethod, historyPriorMethod].contains { method.hasPrefix($0) }
    }
    static func automaticBaselineKey(maximum: Int?) -> String? {
        if let maximum { return ActivityLoadBaseline.resolve(personalMaximum: maximum)?.key }
        return productPriorMethod
    }
    static let intensityUnit = "SOOM_session_intensity_0_10"
    static let legacySessionScale = "soom_session_global_0_10_kr_v1"
    static let completenessVersion = "workout_set_time_v2"
    static func acceptsZero(_ scale: String?) -> Bool { scale == scaleVersion || scale == legacySessionScale }
    static let durationPolicy = "recorded_workout_seconds_v2"
    static let legacyDurationPolicy = "user_reviewed_session_seconds_v1"
    static let manualInputVersion = "integer_steps_1_10_v1"
    static let changed = Notification.Name("SOOM.ActivityLoad.localInputsChanged")
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
    }
    static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        let position = Double(sorted.count - 1) * fraction
        let i = Int(position), next = min(i + 1, sorted.count - 1)
        return sorted[i] + (sorted[next] - sorted[i]) * (position - Double(i))
    }
}

enum ActivityLoadEstimateIssue: Equatable {
    case missingPersonalMaximum, invalidPersonalMaximum, missingHeartRate, invalidHeartRate, abovePersonalMaximum, invalidRecord
    var needsBaseline: Bool { self == .missingPersonalMaximum || self == .invalidPersonalMaximum || self == .abovePersonalMaximum }
    var message: String {
        switch self {
        case .missingPersonalMaximum: return "개인 최대심박 기준을 한 번 확인하면 저장된 심박으로 자동 계산할 수 있어요"
        case .invalidPersonalMaximum: return "저장된 개인 최대심박 기준을 확인해 주세요"
        case .missingHeartRate: return "저장된 평균심박과 읽을 수 있는 심박 표본이 없어요"
        case .invalidHeartRate: return "기록의 심박 정보가 계산 가능한 범위를 벗어났어요"
        case .abovePersonalMaximum: return "기록의 평균심박과 개인 최대심박 기준을 확인해 주세요"
        case .invalidRecord: return "운동 날짜 또는 완료 상태 확인이 필요해요"
        }
    }
}

/// An ephemeral projection of already-stored, same-workout measurements.
/// Never writes source records, invents HRmax, or copies data to cloud/outbox.
struct ActivityLoadHeartRateInput: Equatable {
    let value: Double
    let evidence: String
    static func stored(workout: UnifiedWorkout, telemetry: WorkoutTelemetry?) -> Self? {
        guard let telemetry, telemetry.workoutID == workout.id, telemetry.source == workout.source else { return nil }
        let valid=telemetry.validated(for:workout).coalescingSamples()
        if let summary=valid.summaryMetrics.first(where:{$0.key == "averageHeartRate" && $0.unit.lowercased() == "bpm" && (30...250).contains($0.value)}) {
            return Self(value:summary.value,evidence:"stored_summary_v1")
        }
        let samples=valid.samples.filter{($0.source ?? telemetry.source) == workout.source}.compactMap { sample -> (Date,Double)? in
            guard let value=sample.heartRateBPM,value.isFinite,(30...250).contains(value) else{return nil}
            return (sample.timestamp,value)
        }
        guard Set(samples.map(\.0)).count >= 2 else{return nil}
        return Self(value:samples.reduce(0){$0+$1.1}/Double(samples.count),evidence:"stored_samples_mean_v1")
    }
}

struct ActivityLoadEstimate: Equatable {
    let value: Double
    let method: String
    let settingsVersion: String
    let source: String
    let confidence: String
    let computedAt: Date
    var methodKey: String { method + ":" + settingsVersion }
    var isInitial: Bool { source.contains("product_prior") }
    var displaySourceLabel: String { isInitial ? "초기 추정 · 낮은 신뢰" : "자동 추정 · 낮은 신뢰" }
    /// Product starting rule, never an inferred/recorded physiological HRmax or RPE.
    /// A personal setting, including an invalid one, is never silently replaced.
    static func automatic(_ workout: UnifiedWorkout, maximum: Int?, at: Date,
                          stored: ActivityLoadHeartRateInput? = nil, history: ActivityLoadHistoryReference? = nil) -> Self? {
        guard !workout.isExcludedFromAnalysis, workout.endDate <= at, workout.updatedAt <= at,
              workout.startDate.timeIntervalSince1970.isFinite, workout.endDate > workout.startDate else { return nil }
        if let mean = measuredMean(workout, stored: stored) {
            if maximum != nil { return heartRate(workout, maxHeartRate: maximum, at: at, stored: stored) }
            return Self(value: min(10, max(1, mean.value / 20)), method: ActivityLoadRules.productPriorMethod,
                settingsVersion: ActivityLoadRules.productPriorMethod,
                source: "product_prior:" + workout.source.rawValue + ":" + mean.evidence,
                confidence: "낮음 · 평균심박÷20의 SOOM 초기 추정, 개인 생리 강도 아님" + (mean.evidence.contains("samples_mean") ? " · 저장 표본 관측 범위 미확인" : ""), computedAt: at)
        }
        // An invalid measurement is not silently reclassified as absent.
        guard workout.averageHeartRate == nil, stored == nil, let history,
              history.targetID == workout.id, history.targetRevision == workout.updatedAt,
              history.targetStart == workout.startDate, history.targetEnd == workout.endDate,
              history.sport == workout.workoutType, history.computedAt == at,
              history.value.isFinite, (1...10).contains(history.value), history.count > 0 else { return nil }
        return Self(value: history.value, method: ActivityLoadRules.historyPriorMethod,
            settingsVersion: ActivityLoadRules.historyPriorMethod + ":" + history.fingerprint,
            source: "product_prior:explicit_same_sport_history:\(history.count):" + history.fingerprint,
            confidence: "낮음 · 앞선 같은 종목 직접 입력 \(history.count)건의 중앙값, 현재 운동 측정 아님", computedAt: at)
    }
    static func measuredMean(_ workout:UnifiedWorkout,stored:ActivityLoadHeartRateInput?)->ActivityLoadHeartRateInput? {
        if let mean=workout.averageHeartRate,mean.isFinite,(30...250).contains(mean){return .init(value:mean,evidence:"record_summary")}
        guard let stored,stored.value.isFinite,(30...250).contains(stored.value) else{return nil}
        return stored
    }
    static func issue(_ workout:UnifiedWorkout,maxHeartRate:Int?,at:Date,stored:ActivityLoadHeartRateInput?=nil)->ActivityLoadEstimateIssue? {
        guard workout.endDate <= at,workout.updatedAt <= at,workout.endDate > workout.startDate else{return .invalidRecord}
        guard let mean=measuredMean(workout,stored:stored)?.value else{return workout.averageHeartRate == nil ? .missingHeartRate : .invalidHeartRate}
        guard let maximum=maxHeartRate else{return .missingPersonalMaximum}
        guard (80...240).contains(maximum) else{return .invalidPersonalMaximum}
        guard mean <= Double(maximum) else{return .abovePersonalMaximum}
        return nil
    }
    static func heartRate(_ workout: UnifiedWorkout, baseline: ActivityLoadBaseline?, at: Date, stored: ActivityLoadHeartRateInput? = nil) -> Self? {
        guard let baseline, baseline.maximumBPM.isFinite, (80...240).contains(baseline.maximumBPM),
              workout.endDate <= at, workout.updatedAt <= at, workout.endDate > workout.startDate,
              let mean = measuredMean(workout, stored: stored), mean.value <= baseline.maximumBPM else { return nil }
        return Self(value: 10 * mean.value / baseline.maximumBPM, method: ActivityLoadRules.automaticMethod,
                    settingsVersion: baseline.key, source: workout.source.rawValue + ":" + mean.evidence + ":" + baseline.origin.rawValue,
                    confidence: baseline.origin == .adultAgeEstimate ? "낮음 · 실제 나이 기반 인구 추정, 개인 오차 큼" : "낮음 · 사용자 설정 기준",
                    computedAt: at)
    }
    static func heartRate(_ workout: UnifiedWorkout, maxHeartRate: Int?, at: Date, stored:ActivityLoadHeartRateInput?=nil) -> Self? {
        guard issue(workout,maxHeartRate:maxHeartRate,at:at,stored:stored) == nil,
              let maximum=maxHeartRate,let mean=measuredMean(workout,stored:stored) else{return nil}
        // Same time-independent product proxy; samples are not claimed to cover
        // the whole workout. A workout peak never substitutes for personal HRmax.
        return Self(value:10*mean.value/Double(maximum),
                    method:ActivityLoadRules.automaticMethod + (mean.evidence == "record_summary" ? "" : ":"+mean.evidence),settingsVersion:"maxHR:\(maximum)",
                    source:workout.source.rawValue+":"+mean.evidence,
                    confidence:mean.evidence.contains("samples_mean") ? "낮음 · 저장 심박 표본 평균, 관측 범위 미확인" : "낮음 · 평균/개인최대 심박 비율, 관측 범위 미확인",computedAt:at)
    }
}


/// Ephemeral, current account's explicit labels only. Never trains on estimates,
/// includes the target itself, or persists a copy of health samples/teacher labels.
struct ActivityLoadHistoryReference: Equatable {
    let targetID: UUID
    let targetRevision: Date
    let targetStart: Date
    let targetEnd: Date
    let sport: UnifiedWorkoutType
    let value: Double
    let count: Int
    let fingerprint: String
    let computedAt: Date
    static func resolve(for target: UnifiedWorkout, workouts: [UnifiedWorkout],
                        confirmations: [UUID: WorkoutEffortConfirmation], at: Date) -> Self? {
        guard at.timeIntervalSince1970.isFinite, target.startDate.timeIntervalSince1970.isFinite,
              target.endDate <= at, target.updatedAt <= at, !target.isExcludedFromAnalysis else { return nil }
        let earliest = target.startDate.addingTimeInterval(-90 * 86400)
        let groups = Dictionary(grouping: workouts, by: \.id)
        let unique = groups.values.compactMap { values -> UnifiedWorkout? in
            guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let rows = ActivityLoadCalculator.canonical(unique.filter { $0.startDate.timeIntervalSince1970.isFinite })
        var labels: [(Double, String)] = []
        for row in rows {
            guard row.id != target.id, row.workoutType == target.workoutType,
                  row.startDate >= earliest, row.endDate <= target.startDate, row.updatedAt <= at,
                  !row.isExcludedFromAnalysis, [.complete, .partial].contains(row.dataQuality),
                  WorkoutEffortSessionContext(row).recordedSeconds != nil,
                  !unique.contains(where: { other in other.id != row.id && min(other.endDate, row.endDate).timeIntervalSince(max(other.startDate, row.startDate)) > 1 }),
                  let c = confirmations[row.id], c.isCleared != true,
                  c.scaleVersion == ActivityLoadRules.scaleVersion, c.inputControlVersion == ActivityLoadRules.manualInputVersion,
                  c.durationPolicy == ActivityLoadRules.durationPolicy, c.unit == ActivityLoadRules.intensityUnit,
                  c.origin == "user", (1...10).contains(c.value), c.confirmedAt >= row.endDate, c.confirmedAt <= at,
                  c.workoutStart == row.startDate, c.workoutEnd == row.endDate else { continue }
            labels.append((Double(c.value), ActivityLoadRules.hash("\(row.id)|\(row.updatedAt)|\(c.revision)|\(c.value)")))
        }
        guard !labels.isEmpty else { return nil }
        let value = ActivityLoadRules.quantile(labels.map(\.0).sorted(), 0.5)
        return Self(targetID: target.id, targetRevision: target.updatedAt, targetStart: target.startDate,
            targetEnd: target.endDate, sport: target.workoutType, value: value, count: labels.count,
            fingerprint: ActivityLoadRules.hash(ActivityLoadRules.historyPriorMethod + labels.map(\.1).sorted().joined()), computedAt: at)
    }
}


/// A provenance-bearing input, not a physiological measurement inferred from workouts.
/// Age is accepted only from an already-authorized, actual adult age. No DOB read is added.
struct ActivityLoadBaseline: Equatable {
    enum Origin: String { case userSetting, adultAgeEstimate }
    let maximumBPM: Double
    let origin: Origin
    let key: String
    static func resolve(personalMaximum: Int?, actualAdultAgeYears: Int? = nil) -> Self? {
        if let maximum = personalMaximum {
            guard (80...240).contains(maximum) else { return nil }
            return Self(maximumBPM: Double(maximum), origin: .userSetting, key: "maxHR:\(maximum)")
        }
        // Population adult estimate (Tanaka 2001), with substantial individual error.
        // Neither an observed workout peak nor an arbitrary default substitutes for age.
        guard let age = actualAdultAgeYears, (18...100).contains(age) else { return nil }
        return Self(maximumBPM: 208 - 0.7 * Double(age), origin: .adultAgeEstimate,
                    key: "adult_age_tanaka2001_v1:\(age)")
    }
}

/// Product hypotheses, not validated RPE/fitness/medical calibration thresholds.
/// Learns only a bounded SOOM score offset; never writes HRmax, FTP or source ratings.
enum ActivityLoadCalibrationRules {
    static let version = "explicit_steps_hr_residual_v1"
    static let minimumPairs = 5
    static let minimumDays = 3
    static let lookbackDays = 90
    static let maximumOffset = 2.0
    static let weeklyStep = 0.25
    static let interval = 7.0 * 86400
    static let changed = Notification.Name("SOOM.ActivityLoad.calibrationChanged")
}

struct ActivityLoadCalibrationSummary: Equatable {
    let sport: UnifiedWorkoutType
    let validHeartRatePairs: Int
    let usableBasePairs: Int
    let distinctDays: Int
    var ready: Bool { usableBasePairs >= ActivityLoadCalibrationRules.minimumPairs && distinctDays >= ActivityLoadCalibrationRules.minimumDays }
}

struct ActivityLoadCalibrationInputs {
    struct Pair {
        let key: String // digest of identity/revision/source; never serialized raw HR or ratings
        let sport: UnifiedWorkoutType
        let day: String
        let residual: Double?
    }
    let pairs: [Pair]
    let baselineKey: String?
    var summaries: [ActivityLoadCalibrationSummary] {
        Dictionary(grouping: pairs, by: { $0.sport.rawValue }).keys.sorted().compactMap { sport in
            guard let type = UnifiedWorkoutType(rawValue: sport) else { return nil }
            let rows = pairs.filter { $0.sport == type }, usable = rows.filter { $0.residual != nil }
            return .init(sport: type, validHeartRatePairs: rows.count, usableBasePairs: usable.count,
                         distinctDays: Set(usable.map(\.day)).count)
        }
    }
    static func read(workouts: [UnifiedWorkout], confirmations: [UUID: WorkoutEffortConfirmation],
                     maximum: Int?, at: Date, zone: String,
                     stored: [UUID: ActivityLoadHeartRateInput] = [:]) -> Self {
        guard at.timeIntervalSince1970.isFinite else { return .init(pairs: [], baselineKey: nil) }
        let calendar = ActivityLoadRules.calendar(zone)
        let earliest = calendar.date(byAdding: .day, value: -ActivityLoadCalibrationRules.lookbackDays, to: at)!
        let groups = Dictionary(grouping: workouts, by: \.id)
        // Conflicting duplicate UUIDs are rejected rather than selecting a convenient payload.
        let unique = groups.values.compactMap { values -> UnifiedWorkout? in
            guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let canonical = ActivityLoadCalculator.canonical(unique.filter { $0.startDate.timeIntervalSince1970.isFinite })
        let pairs = canonical.compactMap { workout -> Pair? in
            // HealthKit's normal summary mapper uses .partial even with valid HR.
            // Whole-record completeness is not an HR sensor-quality verdict.
            guard [.complete, .partial].contains(workout.dataQuality), !workout.isExcludedFromAnalysis,
                  workout.startDate >= earliest, workout.endDate <= at, workout.updatedAt <= at,
                  WorkoutEffortSessionContext(workout).recordedSeconds != nil,
                  !unique.contains(where: { other in
                      other.id != workout.id && min(other.endDate, workout.endDate).timeIntervalSince(max(other.startDate, workout.startDate)) > 1
                  }),
                  let rating = confirmations[workout.id], rating.isCleared != true,
                  rating.scaleVersion == ActivityLoadRules.scaleVersion,
                  rating.inputControlVersion == ActivityLoadRules.manualInputVersion,
                  rating.durationPolicy == ActivityLoadRules.durationPolicy,
                  rating.unit == ActivityLoadRules.intensityUnit, rating.origin == "user",
                  (1...10).contains(rating.value), rating.confirmedAt >= workout.endDate, rating.confirmedAt <= at,
                  rating.workoutStart == workout.startDate, rating.workoutEnd == workout.endDate,
                  let mean = ActivityLoadEstimate.measuredMean(workout, stored: stored[workout.id]),
                  // Sparse sample arithmetic means have unknown coverage: do not train on them.
                  ["record_summary", "stored_summary_v1", "cached_healthkit_mean_v1", "cached_stored_summary_v1"].contains(mean.evidence)
            else { return nil }
            let base = ActivityLoadEstimate.automatic(workout, maximum: maximum, at: at, stored: stored[workout.id])
            let residual = base.map { Double(rating.value) - $0.value }
            let digest = ActivityLoadRules.hash("\(workout.id)|\(workout.source.rawValue)|\(workout.updatedAt.timeIntervalSince1970)|\(rating.revision)|\(rating.value)|\(workout.workoutType.rawValue)|\(workout.startDate.timeIntervalSince1970)|\(workout.endDate.timeIntervalSince1970)|\(mean.value)|\(mean.evidence)")
            return Pair(key: digest, sport: workout.workoutType,
                        day: ActivityLoadRules.dayKey(workout.startDate, calendar: calendar), residual: residual)
        }
        return .init(pairs: pairs, baselineKey: ActivityLoadRules.automaticBaselineKey(maximum: maximum))
    }
}

struct ActivityLoadCalibrationLedger: Codable, Equatable {
    struct State: Codable, Equatable {
        let baselineKey: String
        let offset: Double
        let windowStartOffset: Double
        let windowStart: Date
        let computedAt: Date
        let sampleKeys: [String]
        let pairCount: Int
        let dayCount: Int
        var fingerprint: String {
            ActivityLoadRules.hash(ActivityLoadCalibrationRules.version + baselineKey + "|\(offset)|" + sampleKeys.joined(separator: ";"))
        }
        var valid: Bool {
            offset.isFinite && abs(offset) <= 2 && windowStartOffset.isFinite && abs(windowStartOffset) <= 2 &&
            abs(offset - windowStartOffset) <= 0.250000001 &&
            windowStart.timeIntervalSince1970.isFinite && computedAt.timeIntervalSince1970.isFinite && windowStart <= computedAt &&
            pairCount >= 5 && dayCount >= 3 && dayCount <= pairCount && sampleKeys.count == pairCount &&
            Set(sampleKeys).count == sampleKeys.count && sampleKeys.allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }
        }
    }
    let schemaVersion: Int
    let methodVersion: String
    var enabled: Bool
    var states: [String: State]
    static func empty(enabled: Bool = true) -> Self {
        .init(schemaVersion: 1, methodVersion: ActivityLoadCalibrationRules.version, enabled: enabled, states: [:])
    }
    var valid: Bool {
        schemaVersion == 1 && methodVersion == ActivityLoadCalibrationRules.version &&
        states.allSatisfy { UnifiedWorkoutType(rawValue: $0.key) != nil && $0.value.valid }
    }
    var policyKey: String {
        let active = enabled ? states.keys.sorted().compactMap { key in states[key].map { key + ":" + $0.fingerprint } } : []
        return active.isEmpty ? "base" : ActivityLoadRules.hash(active.joined(separator: ";"))
    }
    func updated(inputs: ActivityLoadCalibrationInputs, maximum: Int?, at: Date) -> Self {
        guard valid, at.timeIntervalSince1970.isFinite, enabled,
              let baselineKey = ActivityLoadRules.automaticBaselineKey(maximum: maximum), inputs.baselineKey == baselineKey else { return .empty(enabled: enabled) }
        var updated = Self.empty(enabled: enabled)
        for summary in inputs.summaries where summary.ready {
            let pairs = inputs.pairs.filter { $0.sport == summary.sport && $0.residual != nil }
            let keys = pairs.map(\.key).sorted(), residuals = pairs.compactMap(\.residual).filter(\.isFinite).sorted()
            guard residuals.count == pairs.count else { continue }
            let target = min(2, max(-2, ActivityLoadRules.quantile(residuals, 0.5) * Double(pairs.count) / Double(pairs.count + 10)))
            let previous = states[summary.sport.rawValue]
            // Removing/clearing/changing a label, baseline, or clock rollback invalidates old influence.
            let reusable = previous.flatMap { old -> State? in
                old.baselineKey == baselineKey && old.computedAt <= at && Set(old.sampleKeys).isSubset(of: Set(keys)) ? old : nil
            }
            let nextWindow = reusable.map { at.timeIntervalSince($0.windowStart) >= ActivityLoadCalibrationRules.interval } ?? true
            let anchor = nextWindow ? (reusable?.offset ?? 0) : reusable!.windowStartOffset
            let windowStart = nextWindow ? at : reusable!.windowStart
            let offset = min(anchor + 0.25, max(anchor - 0.25, target))
            let state = State(baselineKey: baselineKey, offset: offset, windowStartOffset: anchor, windowStart: windowStart,
                              computedAt: at, sampleKeys: keys, pairCount: pairs.count, dayCount: summary.distinctDays)
            // Reopening/refreshing on the same inputs must not churn storage or increase the offset.
            if let old = reusable, old.offset == offset, old.sampleKeys == keys, old.windowStart == windowStart, old.dayCount == summary.distinctDays, at.timeIntervalSince(old.computedAt) < 12 * 3600 {
                updated.states[summary.sport.rawValue] = old
            } else { updated.states[summary.sport.rawValue] = state }
        }
        return updated
    }
    func applying(to estimate: ActivityLoadEstimate?, sport: UnifiedWorkoutType, at: Date) -> ActivityLoadEstimate? {
        guard let estimate, valid, enabled, let state = states[sport.rawValue], state.valid,
              state.baselineKey == estimate.settingsVersion, state.computedAt <= at, at.timeIntervalSince(state.computedAt) <= 86400 else { return estimate }
        return .init(value: min(10, max(1, estimate.value + state.offset)),
                     method: estimate.method + ":" + ActivityLoadCalibrationRules.version,
                     settingsVersion: estimate.settingsVersion + ":offset:" + state.fingerprint,
                     source: estimate.source + ":explicit_user_steps", confidence: estimate.confidence + " · 개인 수정 참고 보정(제품 가설)", computedAt: at)
    }
}

struct ActivityLoadSession: Identifiable, Equatable {
    let workout: UnifiedWorkout
    let intensity: Double?
    let automaticValue: Double?
    let automaticIssue: ActivityLoadEstimateIssue?
    let automaticSource: String?
    let confidence: String
    let durationSeconds: Double?
    let methodKey: String?
    let sourceLabel: String
    let reason: String?
    let revision: UUID?
    let confirmedAt: Date?
    var id: UUID { workout.id }
    var amount: Double? {
        guard let intensity, let durationSeconds else { return nil }
        let result = intensity * durationSeconds / 60
        return result.isFinite && result >= 0 ? result : nil
    }
    static func resolve(_ workout: UnifiedWorkout, confirmation: WorkoutEffortConfirmation?,
                        maximum: Int?, at: Date, stored:ActivityLoadHeartRateInput?=nil, calibration: ActivityLoadCalibrationLedger = .empty(), history: ActivityLoadHistoryReference? = nil) -> Self {
        let estimate = calibration.applying(to: ActivityLoadEstimate.automatic(workout, maximum: maximum, at: at,stored:stored,history:history), sport: workout.workoutType, at: at)
        let issue = estimate == nil ? ActivityLoadEstimate.issue(workout,maxHeartRate:maximum,at:at,stored:stored) : nil
        func result(_ value: Double?, _ duration: Double?, _ method: String?, _ source: String, _ reason: String?) -> Self {
            Self(workout: workout, intensity: value, automaticValue: value == nil ? nil : estimate?.value, automaticIssue:issue, automaticSource:estimate?.source,
                 confidence: method?.hasPrefix(ActivityLoadRules.manualMethod) == true ? "사용자 수정" : estimate?.confidence ?? "추정 정보 없음",
                 durationSeconds: duration, methodKey: method,
                 sourceLabel: source, reason: reason, revision: confirmation?.revision, confirmedAt: confirmation?.confirmedAt)
        }
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard !workout.isExcludedFromAnalysis, workout.endDate <= at, workout.updatedAt <= at, elapsed.isFinite, elapsed > 0 else {
            return result(nil, nil, nil, "미확인", "운동 시간 또는 완료 상태 확인 필요")
        }
        let duration = workout.durationSeconds.isFinite && workout.durationSeconds > 0 && workout.durationSeconds <= elapsed + 1 ? workout.durationSeconds : nil
        let durationIssue = duration == nil ? "기록된 운동 시간이 없어 부하를 계산하지 못했어요" : nil
        if let c = confirmation, c.scaleVersion == ActivityLoadRules.scaleVersion {
            let oldZero = c.value == 0 && c.inputControlVersion == nil && c.durationPolicy == ActivityLoadRules.legacyDurationPolicy
            guard ((1...10).contains(c.value) || oldZero), c.confirmedAt <= at, c.confirmedAt >= workout.endDate,
                  c.workoutStart == workout.startDate, c.workoutEnd == workout.endDate,
                  [ActivityLoadRules.durationPolicy, ActivityLoadRules.legacyDurationPolicy].contains(c.durationPolicy ?? ""),
                  c.unit == ActivityLoadRules.intensityUnit, c.origin == "user" else {
                return result(estimate?.value, duration, estimate?.methodKey, estimate == nil ? "직접 확인" : estimate!.displaySourceLabel + " · 이전 수정값 보존", "이전 수정값은 적용하지 않았어요. 현재 자동값을 사용하거나 직접 다시 지정할 수 있어요")
            }
            return result(Double(c.value), duration, ActivityLoadRules.manualMethod + ":recorded_time_v2", oldZero ? "이전 0점 입력 · 보존" : "사용자 지정 · 1–10단계", durationIssue)
        }
        guard let estimate else { return result(nil, nil, nil, issue?.needsBaseline == true ? "공통 기준 확인" : "심박 정보 확인", issue?.message ?? "자동 추정 정보 확인이 필요해요") }
        let source = confirmation == nil ? estimate.displaySourceLabel : estimate.displaySourceLabel + " · 이전 기준 입력 보존"
        return result(estimate.value, duration, estimate.methodKey, source, durationIssue)
    }
}

struct ActivityLoadDayApproval: Codable, Equatable {
    enum Kind: String, Codable { case recordsReviewed, noWorkout, excludedOnly }
    let fingerprint: String
    let kind: Kind
    let confirmedAt: Date
}
struct ActivityLoadJournal: Codable, Equatable {
    let schemaVersion: Int
    var timeZoneID: String
    var timeZoneRevision: UUID
    var completenessVersion: String? = ActivityLoadRules.completenessVersion
    var approvals: [String: ActivityLoadDayApproval]
    static func empty(zone: String) -> Self {
        Self(schemaVersion: 1, timeZoneID: zone, timeZoneRevision: UUID(), approvals: [:])
    }
}
enum ActivityLoadState: String, Equatable {
    case below, inside, above, building, unknown, forecast
    var label: String {
        switch self {
        case .below: "↓  범위보다 낮음"
        case .inside: "•  범위 안"
        case .above: "↑  범위보다 높음"
        case .building: "…  기준 쌓는 중"
        case .unknown: "—  미확인"
        case .forecast: "○  예상 · 운동 없음"
        }
    }
    static func classify(_ value: Double?, lower: Double?, upper: Double?, forecast: Bool = false) -> Self {
        if forecast { return .forecast }
        guard let value, value.isFinite, value >= 0 else { return .unknown }
        guard let lower, let upper, lower.isFinite, upper.isFinite, lower <= upper else { return .building }
        return value < lower ? .below : value > upper ? .above : .inside
    }
}
struct ActivityLoadDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let key: String
    let fingerprint: String
    let sessions: [ActivityLoadSession]
    let rawCount: Int
    var daily: Double?
    var smoothed: Double?
    var lower: Double?
    var upper: Double?
    var methodKey: String?
    var reason: String?
    var segment: Int = 0
    var bandGroup: Int = 0
    var isForecast = false
    var isProvisional = false
    var cannotPreviewSubtotal = false
    var projectionConflictIDs: Set<UUID> = []
    var projectionOverlapIDs: Set<UUID> = []
    var estimatedInputCount = 0
    var userInputCount = 0
    var inputSummary: String {
        let initial = sessions.contains { $0.sourceLabel.contains("초기 추정") }
        if estimatedInputCount > 0 && userInputCount > 0 { return initial ? "자동 추정·사용자 수정 · 초기 추정 포함" : "자동 추정·사용자 수정 · 추정 포함" }
        if estimatedInputCount > 0 { return initial ? "초기 추정 · 낮은 신뢰" : "자동 추정 · 낮은 신뢰" }
        if userInputCount > 0 { return "사용자 수정 입력" }
        let auto=sessions.filter{ActivityLoadRules.isAutomatic($0.methodKey)}.count
        let manual=sessions.filter{$0.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true}.count
        if auto > 0 && manual > 0{return initial ? "자동 추정·사용자 수정 · 초기 추정 포함" : "자동 추정·사용자 수정 · 추정 포함"}
        if auto > 0{return initial ? "초기 추정 · 낮은 신뢰" : "자동 추정 · 낮은 신뢰"}
        if manual > 0{return "사용자 수정 입력"}
        return sessions.contains{$0.automaticIssue?.needsBaseline == true} ? "공통 심박 기준 확인 필요" : "입력 정보 확인 필요"
    }
    var recordedSubtotal: Double? {
        guard !cannotPreviewSubtotal, !sessions.isEmpty, sessions.allSatisfy({ $0.amount != nil }) else { return nil }
        let sum = sessions.compactMap(\.amount).reduce(0,+)
        return sum.isFinite ? sum : nil
    }
    var workoutPresent: Bool { !sessions.isEmpty }
    var state: ActivityLoadState {
        if isForecast { return .forecast }
        if daily != nil && smoothed == nil { return .building }
        return ActivityLoadState.classify(smoothed, lower: lower, upper: upper)
    }
}
struct ActivityLoadSnapshot {
    let days: [ActivityLoadDay]
    let timeZoneID: String
    let asOf: Date
    let recent: [UnifiedWorkout]
    let legacyCount: Int
    let conflictingIDs: Set<UUID>
    var invalidDateCount = 0
}

/// Read-only display projection. It never promotes partial records to reviewed
/// daily totals, training trends, rest days, or personal reference samples.
struct ActivityLoadComputedRecords {
    enum Issue: String, CaseIterable {
        case conflict = "원본 충돌", overlap = "시간 겹침", pending = "기록 완료 확인", invalidTime = "운동 시간 확인", missingScore = "점수 미산출"
    }
    let included: [ActivityLoadSession]
    let issues: [Issue: Int]
    var subtotal: Double? {
        guard !included.isEmpty else { return nil }
        let sum = included.compactMap(\.amount).reduce(0, +)
        return sum.isFinite ? sum : nil
    }
    init(day: ActivityLoadDay) {
        var included: [ActivityLoadSession] = [], issues: [Issue: Int] = [:]
        for session in day.sessions {
            let workout = session.workout
            let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
            let issue: Issue?
            if day.projectionConflictIDs.contains(session.id) { issue = .conflict }
            else if day.projectionOverlapIDs.contains(session.id) { issue = .overlap }
            else if !elapsed.isFinite || elapsed <= 0 || !workout.durationSeconds.isFinite || workout.durationSeconds <= 0 || workout.durationSeconds > elapsed + 1 { issue = .invalidTime }
            else if session.reason == "운동 시간 또는 완료 상태 확인 필요" { issue = .pending }
            else if session.amount == nil { issue = .missingScore }
            else { issue = nil }
            if let issue { issues[issue, default: 0] += 1 } else { included.append(session) }
        }
        self.included = included; self.issues = issues
    }
}

struct ActivityLoadWeekProjection {
    struct Slot: Identifiable {
        var id: Int { index }
        let index: Int
        let date: Date
        let day: ActivityLoadDay?
        let isFuture: Bool
        var amount: Double? {
            guard !isFuture, let day else { return nil }
            let records = ActivityLoadComputedRecords(day: day)
            return records.issues.isEmpty ? day.daily ?? records.subtotal : records.subtotal
        }
        var complete: Bool {
            guard !isFuture, let day else { return false }
            return day.daily != nil && ActivityLoadComputedRecords(day: day).issues.isEmpty
        }
    }
    struct Point: Identifiable {
        var id: Int { index }
        let index: Int
        let value: Double
        let segment: Int
    }
    let start: Date
    let slots: [Slot]
    let unlocatedCount: Int
    static func start(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -((calendar.component(.weekday, from: day) + 5) % 7), to: day)!
    }
    init(snapshot: ActivityLoadSnapshot, containing date: Date) {
        let calendar = ActivityLoadRules.calendar(snapshot.timeZoneID)
        let weekStart = Self.start(of: date, calendar: calendar)
        start = weekStart
        let today = calendar.startOfDay(for: snapshot.asOf)
        slots = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: weekStart)!
            return Slot(index: index, date: date, day: snapshot.days.first { !$0.isForecast && $0.date == date }, isFuture: date > today)
        }
        unlocatedCount = snapshot.invalidDateCount
    }
    var subtotal: Double? { subtotal(through: 6) }
    func subtotal(through index: Int) -> Double? {
        let amounts = slots.filter { $0.index <= index }.compactMap(\.amount)
        guard !amounts.isEmpty else { return nil }
        let sum = amounts.reduce(0, +)
        return sum.isFinite ? sum : nil
    }
    var isComplete: Bool { unlocatedCount == 0 && slots.allSatisfy(\.complete) }
    var computedCount: Int { slots.filter { !$0.isFuture }.compactMap(\.day).reduce(0) { $0 + ActivityLoadComputedRecords(day: $1).included.count } }
    var issues: [ActivityLoadComputedRecords.Issue: Int] {
        slots.filter { !$0.isFuture }.compactMap(\.day).reduce(into: [:]) { totals, day in
            for (issue, count) in ActivityLoadComputedRecords(day: day).issues { totals[issue, default: 0] += count }
        }
    }
    var unknownDayCount: Int { slots.filter { !$0.isFuture && !$0.complete }.count }
    var elapsedIndex: Int { slots.last(where: { !$0.isFuture })?.index ?? -1 }
    var cumulative: [Point] {
        var total = 0.0, segment = 0
        return slots.compactMap { slot in
            guard let amount = slot.amount else { segment += 1; return nil }
            total += amount
            return Point(index: slot.index, value: total, segment: segment)
        }
    }
    static func precedingThreeCompleteWeeksMean(snapshot: ActivityLoadSnapshot, before start: Date) -> Double? {
        let calendar = ActivityLoadRules.calendar(snapshot.timeZoneID)
        let weeks = (1...3).map { ActivityLoadWeekProjection(snapshot: snapshot, containing: calendar.date(byAdding: .day, value: -7 * $0, to: start)!) }
        guard weeks.allSatisfy(\.isComplete) else { return nil }
        return weeks.compactMap(\.subtotal).reduce(0, +) / 3
    }
}

/// Display projection only. Unreviewed records never become complete days,
/// smoothed history, personal bands, or inferred rest zeros through this path.
enum ActivityLoadGraphMetric: Equatable {
    case recentTrend, recordedDays
    init(days: [ActivityLoadDay]) {
        self = days.contains { $0.smoothed != nil } ? .recentTrend : .recordedDays
    }
    var label: String { self == .recentTrend ? "최근 부하" : "일별 기록 부하" }
    func value(_ day: ActivityLoadDay) -> Double? {
        if self == .recentTrend { return day.smoothed }
        guard !day.isForecast, !day.cannotPreviewSubtotal else { return nil }
        return day.daily ?? day.recordedSubtotal
    }
    func stateLabel(_ day: ActivityLoadDay) -> String {
        if self == .recentTrend { return day.state.label }
        guard value(day) != nil else { return day.workoutPresent ? "점수 미산출 기록 포함" : "이 날짜에 확인된 부하 없음" }
        return day.daily == nil ? "기록 기준 · 누락 미확인" : "일별 기록 합계"
    }
    static func selectedDay(in snapshot: ActivityLoadSnapshot, selected: Date?, calendar: Calendar) -> ActivityLoadDay? {
        if let selected, let match = snapshot.days.first(where: { calendar.isDate($0.date, inSameDayAs: selected) }) { return match }
        let today = calendar.startOfDay(for: snapshot.asOf)
        let past = snapshot.days.filter { !$0.isForecast && $0.date <= today && ($0.date < today || $0.workoutPresent) }
        guard let latest = past.last else { return nil }
        // A valid recent trend can include reviewed rest. Without it, an
        // initial empty date must not conceal existing workout scores.
        if latest.smoothed != nil { return latest }
        return past.last(where: \.workoutPresent) ?? latest
    }
}

struct ActivityLoadInputPlan {
    let sessions:[ActivityLoadSession]
    init(_ snapshot:ActivityLoadSnapshot?) {
        var seen=Set<UUID>()
        sessions=(snapshot?.days.flatMap(\.sessions) ?? []).filter{seen.insert($0.id).inserted}
    }
    var baseline:[ActivityLoadSession]{sessions.filter{$0.intensity == nil && $0.automaticIssue?.needsBaseline == true}}
    var recordInputs:[ActivityLoadSession]{sessions.filter{$0.intensity == nil && $0.automaticIssue?.needsBaseline != true && $0.automaticIssue != .invalidRecord}.sorted{$0.workout.startDate > $1.workout.startDate}}
    var automaticCount:Int{sessions.filter{ActivityLoadRules.isAutomatic($0.methodKey)}.count}
    var manualCount:Int{sessions.filter{$0.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true}.count}
    var initialCount:Int{sessions.filter{$0.sourceLabel.contains("초기 추정") && ActivityLoadRules.isAutomatic($0.methodKey)}.count}
}

enum ActivityLoadCalculator {
    /// Fingerprint covers the current canonical/source snapshot, not annotations:
    /// rating edits recalculate immediately; import/delete/duration changes revoke completeness.
    static func canonical(_ rows: [UnifiedWorkout]) -> [UnifiedWorkout] {
        // Reuse canonical identity/representative choice, never fuse other providers' measurements.
        UnifiedWorkoutDeduplicationEngine().canonicalGroups(rows).map { group in
            group.sourceWorkouts.first(where: { $0.id == group.workout.id }) ?? group.workout
        }
    }
    static func reconciledJournal(_ journal: ActivityLoadJournal, workouts: [UnifiedWorkout]) -> ActivityLoadJournal {
        var result = journal
        let calendar = ActivityLoadRules.calendar(journal.timeZoneID)
        let byDay = Dictionary(grouping: canonical(workouts.filter { $0.startDate.timeIntervalSince1970.isFinite })) { ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        for (key, approval) in journal.approvals {
            let rows = byDay[key] ?? []
            if journal.completenessVersion == nil, approval.fingerprint == legacyFingerprint(rows, zone: journal.timeZoneID) {
                result.approvals[key] = ActivityLoadDayApproval(fingerprint: fingerprint(rows, zone: journal.timeZoneID), kind: approval.kind, confirmedAt: approval.confirmedAt)
            } else if approval.fingerprint != fingerprint(rows, zone: journal.timeZoneID) {
                result.approvals.removeValue(forKey: key)
            }
        }
        result.completenessVersion = ActivityLoadRules.completenessVersion
        return result
    }
    static func legacyFingerprint(_ rows: [UnifiedWorkout], zone: String) -> String {
        let items = rows.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.source.rawValue)|\($0.externalId ?? "")|\($0.startDate.timeIntervalSince1970)|\($0.endDate.timeIntervalSince1970)|\($0.durationSeconds)|\($0.updatedAt.timeIntervalSince1970)|\($0.isExcludedFromAnalysis)"
        }
        return ActivityLoadRules.hash(zone + "|" + items.joined(separator: ";"))
    }
    static func fingerprint(_ rows: [UnifiedWorkout], zone: String) -> String {
        let items = rows.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id)|\($0.source.rawValue)|\($0.externalId ?? "")|\($0.startDate.timeIntervalSince1970)|\($0.endDate.timeIntervalSince1970)|\($0.durationSeconds)|\($0.isExcludedFromAnalysis)"
        }
        return ActivityLoadRules.hash(zone + "|" + items.joined(separator: ";"))
    }

    static func build(workouts: [UnifiedWorkout], confirmations: [UUID: WorkoutEffortConfirmation],
                      journal: ActivityLoadJournal, maximum: Int?, asOf: Date, historyDays: Int = 180, storedHeartRates:[UUID:ActivityLoadHeartRateInput]=[:], calibration: ActivityLoadCalibrationLedger = .empty()) -> ActivityLoadSnapshot {
        let calendar = ActivityLoadRules.calendar(journal.timeZoneID)
        let today = calendar.startOfDay(for: asOf)
        let start = calendar.date(byAdding: .day, value: -historyDays, to: today)!
        // Identical reimports count once. Equal-UUID conflicting payloads are not arbitrarily selected.
        var unique: [UUID: UnifiedWorkout] = [:], conflicts = Set<UUID>()
        let invalidDateCount = workouts.filter { !$0.startDate.timeIntervalSince1970.isFinite }.count
        for w in workouts where w.startDate.timeIntervalSince1970.isFinite {
            if let old = unique[w.id], old != w { conflicts.insert(w.id) } else { unique[w.id] = w }
        }
        let canonical = canonical(Array(unique.values))
        // A conflicting source must not become trusted just because a different
        // provider wins the representative identity for that same activity.
        let projectionConflicts = Set(UnifiedWorkoutDeduplicationEngine().canonicalGroups(Array(unique.values))
            .filter { $0.sourceWorkouts.contains { conflicts.contains($0.id) } }.map { $0.workout.id })
        // Display-only exclusion identities also catch overlaps across midnight.
        // The existing strict day/review/trend calculation below remains intact.
        let ordered = canonical.filter { !$0.isExcludedFromAnalysis && $0.endDate.timeIntervalSince1970.isFinite }.sorted { $0.startDate < $1.startDate }
        var projectionOverlaps = Set<UUID>()
        for a in ordered.indices {
            for b in ordered.indices where b > a {
                if ordered[b].startDate >= ordered[a].endDate { break }
                if ordered[a].keepSeparate != true && ordered[b].keepSeparate != true &&
                   min(ordered[a].endDate, ordered[b].endDate).timeIntervalSince(ordered[b].startDate) > 1 {
                    projectionOverlaps.insert(ordered[a].id); projectionOverlaps.insert(ordered[b].id)
                }
            }
        }
        let byDay = Dictionary(grouping: canonical) { ActivityLoadRules.dayKey($0.startDate, calendar: calendar) }
        var days: [ActivityLoadDay] = []
        for offset in 0...historyDays {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = ActivityLoadRules.dayKey(date, calendar: calendar)
            let raw = byDay[key] ?? []
            let included = raw.filter { !$0.isExcludedFromAnalysis }
            let sessions = included.map { workout in
                let history = ActivityLoadEstimate.measuredMean(workout, stored: storedHeartRates[workout.id]) == nil
                    ? ActivityLoadHistoryReference.resolve(for: workout, workouts: canonical, confirmations: confirmations, at: asOf) : nil
                return ActivityLoadSession.resolve(workout, confirmation: confirmations[workout.id], maximum: maximum,
                    at: asOf, stored: storedHeartRates[workout.id], calibration: calibration, history: history)
            }
            let fingerprint = fingerprint(raw, zone: journal.timeZoneID)
            let approval = journal.approvals[key]
            let amounts = sessions.compactMap(\.amount)
            let unresolvedOverlap = included.indices.contains { a in
                included.indices.contains { b in
                    b > a && included[a].keepSeparate != true && included[b].keepSeparate != true &&
                    min(included[a].endDate, included[b].endDate).timeIntervalSince(max(included[a].startDate, included[b].startDate)) > 1
                }
            }
            var daily: Double?, reason: String?
            if invalidDateCount > 0 { reason = "날짜가 올바르지 않은 원본 기록을 확인해 주세요" }
            else if date == today { reason = "오늘은 아직 마감되지 않았어요" }
            else if raw.contains(where: { conflicts.contains($0.id) }) { reason = "같은 UUID의 원본 내용이 충돌해요" }
            else if approval?.fingerprint != fingerprint || approval!.confirmedAt > asOf { reason = "이 날짜의 기록·누락 상태 확인 필요" }
            else if sessions.isEmpty {
                if approval!.kind == .noWorkout && raw.isEmpty || approval!.kind == .excludedOnly && !raw.isEmpty {
                    daily = 0
                } else { reason = "운동 없음과 분석 제외를 구분해 확인해 주세요" }
            } else if approval!.kind != .recordsReviewed { reason = "가져온 운동 목록이 바뀌었어요" }
            else if unresolvedOverlap { reason = "겹치는 운동의 병합·분리를 먼저 확인해 주세요" }
            else if amounts.count != sessions.count { reason = sessions.first(where: { $0.reason != nil })?.reason ?? "강도 또는 시간 미확인" }
            else {
                let sum = amounts.reduce(0, +)
                if sum.isFinite { daily = sum } else { reason = "계산 가능한 범위를 벗어났어요" }
            }
            var day = ActivityLoadDay(date: date, key: key, fingerprint: fingerprint, sessions: sessions, rawCount: raw.count,
                                         daily: daily, methodKey: daily == nil ? nil : ActivityLoadRules.referenceKey(maximum: maximum), reason: reason)
            day.cannotPreviewSubtotal = unresolvedOverlap || invalidDateCount > 0 || raw.contains { conflicts.contains($0.id) }
            day.projectionConflictIDs = Set(raw.map(\.id)).intersection(projectionConflicts)
            day.projectionOverlapIDs = Set(raw.map(\.id)).intersection(projectionOverlaps)
            days.append(day)
        }
        var segment = 0, key: String?, run: [Int] = [], bandGroup = 0, previousBand = false
        let lambda = pow(2.0, -1.0 / 7.0)
        let weights = (0..<28).map { pow(lambda, Double($0)) }, denominator = (0..<28).reduce(0.0) { $0 + pow(lambda, Double($1)) }
        for i in days.indices {
            guard let _ = days[i].daily else {
                segment += 1; key = nil; run = []; previousBand = false; continue
            }
            let nextKey = days[i].methodKey ?? key ?? ActivityLoadRules.referenceKey(maximum: maximum)
            if key != nil && key != nextKey { segment += 1; run = []; previousBand = false }
            key = nextKey; days[i].methodKey = nextKey; days[i].segment = segment; run.append(i)
            // Keep numeric continuity. Native provenance is retained for interpretation below.
            let inputs = run.suffix(28).flatMap { days[$0].sessions }
            days[i].estimatedInputCount = inputs.filter { ActivityLoadRules.isAutomatic($0.methodKey) }.count
            days[i].userInputCount = inputs.filter { $0.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true }.count
            guard run.count >= 28 else { continue }
            days[i].smoothed = zip(run.suffix(28).reversed(), weights).reduce(0) { $0 + days[$1.0].daily! * $1.1 } / denominator
            let prior = run.dropLast().suffix(56)
            let priorF = prior.compactMap { days[$0].smoothed }.sorted()
            let positiveSessions = prior.flatMap { days[$0].sessions }.filter { ($0.amount ?? 0) > 0 }.count
            let activeDays = prior.filter { days[$0].sessions.contains { ($0.amount ?? 0) > 0 } }.count
            // Provenance is not a second unit or a reason to withhold a personal reference range.
            if priorF.count >= 28 && positiveSessions >= 8 && activeDays >= 4 {
                days[i].lower = ActivityLoadRules.quantile(priorF, 0.1)
                days[i].upper = ActivityLoadRules.quantile(priorF, 0.9)
                if !previousBand { bandGroup += 1 }
                days[i].bandGroup = bandGroup; previousBand = true
            } else { previousBand = false }
        }
        // Today's known input total is a clearly marked provisional value, not a
        // completed/rest observation and never a sample in prior personal ranges.
        if let i = days.indices.last, let subtotal = days[i].recordedSubtotal, days[i].date == today {
            let previous = Array(days[..<i].suffix(27))
            if previous.count == 27 && previous.allSatisfy({ $0.daily != nil }) {
                let values = previous.map { $0.daily! } + [subtotal]
                days[i].smoothed = zip(values.reversed(), weights).reduce(0) { $0 + $1.0 * $1.1 } / denominator
                days[i].isProvisional = true
                days[i].methodKey = ActivityLoadRules.referenceKey(maximum: maximum)
                days[i].reason = "오늘 입력된 기록만 반영한 집계 중 값이에요. 하루 마감 전에는 달라질 수 있어요"
                let prior = Array(days[..<i].suffix(56))
                let priorF = prior.compactMap(\.smoothed).sorted()
                if priorF.count >= 28 && prior.flatMap(\.sessions).filter({ ($0.amount ?? 0) > 0 }).count >= 8 && prior.filter({ $0.workoutPresent }).count >= 4 {
                    days[i].lower = ActivityLoadRules.quantile(priorF,0.1); days[i].upper = ActivityLoadRules.quantile(priorF,0.9)
                    days[i].bandGroup = days[i-1].bandGroup
                }
                let inputs = previous.flatMap(\.sessions) + days[i].sessions
                days[i].estimatedInputCount = inputs.filter { ActivityLoadRules.isAutomatic($0.methodKey) }.count
                days[i].userInputCount = inputs.filter { $0.methodKey?.hasPrefix(ActivityLoadRules.manualMethod) == true }.count
            }
        }
        // Forecast is a conditional finite-window calculation, never a rest observation.
        // Only a complete last closed day with an uninterrupted 28-day window can seed it.
        if let last = days.dropLast().last, last.smoothed != nil, last.daily != nil,
           !days.last!.workoutPresent {
            let closed = Array(days.dropLast())
            var window = Array(closed.suffix(28))
            if window.count == 28 && window.allSatisfy({ $0.daily != nil && $0.methodKey == last.methodKey }) {
                for step in 1...3 {
                    let date = calendar.date(byAdding: .day, value: step, to: last.date)!
                    var next = ActivityLoadDay(date: date, key: ActivityLoadRules.dayKey(date, calendar: calendar),
                        fingerprint: "", sessions: [], rawCount: 0, daily: 0, methodKey: last.methodKey, reason: "추가 운동이 없을 때의 조건 계산",
                        segment: last.segment, bandGroup: last.bandGroup, isForecast: true)
                    window.removeFirst(); window.append(next)
                    next.smoothed = zip(window.reversed(), weights).reduce(0) { $0 + $1.0.daily! * $1.1 } / denominator
                    next.lower = last.lower; next.upper = last.upper
                    if step == 1 { days.removeLast() }
                    days.append(next)
                }
            }
        }
        return ActivityLoadSnapshot(days: days, timeZoneID: journal.timeZoneID, asOf: asOf,
            recent: canonical.filter { !$0.isExcludedFromAnalysis && $0.endDate <= asOf }.sorted { $0.startDate > $1.startDate },
            legacyCount: confirmations.values.filter { $0.scaleVersion != ActivityLoadRules.scaleVersion }.count,
            conflictingIDs: conflicts, invalidDateCount: invalidDateCount)
    }
}

#if DEBUG && targetEnvironment(simulator)
/// R02's synthetic 119-day fixture only. Never compiled into a Release binary.
enum ActivityLoadQAFixture {
    static func effortDirectory(base: URL) -> URL? {
        guard ProcessInfo.processInfo.environment["SOOM_SIMPLE_EFFORT_QA"] == "1",
              let token=ProcessInfo.processInfo.environment["SOOM_SIMPLE_EFFORT_QA_SESSION"], UUID(uuidString:token) != nil else { return nil }
        return base.appendingPathComponent("ActivityLoadUIQA").appendingPathComponent(token)
    }
    static func weeklyPartial(persistedOverrides: [UUID: WorkoutEffortConfirmation]) -> ActivityLoadSnapshot {
        let date = ISO8601DateFormatter().date(from: "2026-11-04T03:12:00Z")!
        func row(_ id: String, _ start: Date, seconds: Double, hr: Double?, type: UnifiedWorkoutType = .running) -> UnifiedWorkout {
            .init(id: UUID(uuidString: id)!, externalId: id, source: .manual, workoutType: type,
                  startDate: start, endDate: start.addingTimeInterval(seconds), durationSeconds: seconds,
                  distanceMeters: nil, activeEnergyKcal: nil, averageHeartRate: hr, maxHeartRate: nil,
                  averageSpeedMetersPerSecond: nil, elevationGainMeters: nil, dataQuality: .complete,
                  createdAt: start, updatedAt: start.addingTimeInterval(seconds))
        }
        let rows = [row("D4110000-0000-4000-8000-000000000001", date, seconds: 1020, hr: 124),
                    row("D4120000-0000-4000-8000-000000000002", date.addingTimeInterval(7200), seconds: 600, hr: nil, type: .cycling),
                    row("D4130000-0000-4000-8000-000000000003", date.addingTimeInterval(-7*86400), seconds: 1200, hr: 124)]
        let at = max(date.addingTimeInterval(9*3600), (persistedOverrides.values.map(\.confirmedAt).max() ?? date).addingTimeInterval(1))
        return ActivityLoadCalculator.build(workouts: rows, confirmations: persistedOverrides, journal: .empty(zone: "Asia/Seoul"), maximum: nil, asOf: at)
    }
    static func make(automated: Bool = false, overridden: Bool = false, missing: Bool = false, missingBaseline:Bool = false, storedSamples:Bool = false, historyReference:Bool = false, persistedOverrides: [UUID: WorkoutEffortConfirmation] = [:]) -> ActivityLoadSnapshot {
        if ProcessInfo.processInfo.environment["SOOM_WEEKLY_PARTIAL_QA"] == "1" { return weeklyPartial(persistedOverrides: persistedOverrides) }
        let tuples: [(String, Double, Double, Double, Int, Double)] = [
            ("1AD6FB16-9898-539A-8990-8C5F51EBC437", 1782961200.0, 1782962370.0, 1170.0, 4, 1782964170.0),
            ("B82E4255-9404-55E2-B296-0CBB0237A9F1", 1783134000.0, 1783134780.0, 780.0, 4, 1783136580.0),
            ("585E7732-ACFB-52A2-B6E8-9655E0F89A19", 1783306800.0, 1783308360.0, 1560.0, 4, 1783310160.0),
            ("D44227CB-273B-54DE-80A8-BD95A84BCDB0", 1783566000.0, 1783567170.0, 1170.0, 4, 1783568970.0),
            ("4E9A7B07-DE65-5543-8EEC-7A6C116C2DAB", 1783738800.0, 1783739580.0, 780.0, 4, 1783741380.0),
            ("78221DFA-8343-5F73-8E53-E27F3E65D7AD", 1783911600.0, 1783913160.0, 1560.0, 4, 1783914960.0),
            ("A53D01F2-8E3B-5A7B-9384-F673826E4910", 1784170800.0, 1784173050.0, 2250.0, 4, 1784174850.0),
            ("A5B1CEBC-B81F-58C6-8579-31103A257606", 1784343600.0, 1784345100.0, 1500.0, 4, 1784346900.0),
            ("88F1FFBD-27A9-5765-B79F-4A7133BA4831", 1784516400.0, 1784519400.0, 3000.0, 4, 1784521200.0),
            ("8896E2C6-EA0F-5001-80F0-E0B4564DA758", 1784775600.0, 1784777850.0, 2250.0, 4, 1784779650.0),
            ("C636D714-3968-5BF1-B2CD-B132DC1B56EF", 1784948400.0, 1784949900.0, 1500.0, 4, 1784951700.0),
            ("45EB7B38-6695-5513-B446-EED39BBB8148", 1785121200.0, 1785124200.0, 3000.0, 4, 1785126000.0),
            ("EEADCC71-2DA6-5731-B313-77D25D8D2D86", 1785380400.0, 1785381930.0, 1530.0, 4, 1785383730.0),
            ("60B3B778-F024-56A0-9A7D-20968F4B31C4", 1785553200.0, 1785554220.0, 1020.0, 4, 1785556020.0),
            ("BBEE9C30-84A9-51DB-80E8-5D509EEBA64E", 1785726000.0, 1785728040.0, 2040.0, 4, 1785729840.0),
            ("C0ABFD54-4074-5463-A9BD-16A2B8DB29EB", 1785985200.0, 1785986730.0, 1530.0, 4, 1785988530.0),
            ("821AF46A-1BF5-51AA-B38A-224318AB98DD", 1786158000.0, 1786159020.0, 1020.0, 4, 1786160820.0),
            ("0E6CD367-481D-507D-9C56-77CB27FADE21", 1786330800.0, 1786332840.0, 2040.0, 4, 1786334640.0),
            ("767FCE49-79EA-5B73-B187-B93AFBB706AB", 1786590000.0, 1786592610.0, 2610.0, 4, 1786594410.0),
            ("4DD4B2C6-073E-58AB-BC20-51AA162CC675", 1786762800.0, 1786764540.0, 1740.0, 4, 1786766340.0),
            ("CB8CA5EE-FB71-5690-85AD-007AA6CD34FE", 1786935600.0, 1786939080.0, 3480.0, 4, 1786940880.0),
            ("B40C9A8F-7570-57BC-858D-7B056D9A7C5F", 1787194800.0, 1787197410.0, 2610.0, 4, 1787199210.0),
            ("7195EACB-F862-57A3-833D-F07B95243ECB", 1787367600.0, 1787369340.0, 1740.0, 4, 1787371140.0),
            ("88F45343-234D-56DB-8EC0-CA93EDCAEC69", 1787540400.0, 1787543880.0, 3480.0, 4, 1787545680.0),
            ("9019310C-696F-5952-8893-7F8BAF388196", 1787799600.0, 1787801220.0, 1620.0, 4, 1787803020.0),
            ("7122A660-FAC8-5463-82F9-B64E6B9FA53B", 1787972400.0, 1787973480.0, 1080.0, 4, 1787975280.0),
            ("B8420C55-FAD7-575A-953F-EBE60F1CEDB2", 1788145200.0, 1788147360.0, 2160.0, 4, 1788149160.0),
            ("7A75A0E1-D4CA-5CE6-B24D-23165C6F91D8", 1788404400.0, 1788406020.0, 1620.0, 4, 1788407820.0),
            ("E9CC6A3D-3E13-5358-B196-0F7CE59DE7A4", 1788577200.0, 1788578280.0, 1080.0, 4, 1788580080.0),
            ("01957A6B-7B78-500E-9ECB-83D9BE218ED3", 1788750000.0, 1788752160.0, 2160.0, 4, 1788753960.0),
            ("148F801B-6832-5BDC-8592-CD6B4F532D5A", 1789009200.0, 1789010370.0, 1170.0, 4, 1789012170.0),
            ("F2403C0B-4145-5208-A9C3-8AD26D1D7A79", 1789182000.0, 1789182780.0, 780.0, 4, 1789184580.0),
            ("35741CBA-49EA-5D8C-B6BD-04FD3DEC6CC0", 1789354800.0, 1789356360.0, 1560.0, 4, 1789358160.0),
            ("AD564B5F-BF7F-59C2-81E0-781019C80C6C", 1789614000.0, 1789615170.0, 1170.0, 4, 1789616970.0),
            ("9E2C8296-DF6B-5BFE-B02C-FB7DF09E0FAF", 1789786800.0, 1789787580.0, 780.0, 4, 1789789380.0),
            ("417AC054-8402-52FD-AE91-D65460C01550", 1789959600.0, 1789961160.0, 1560.0, 4, 1789962960.0),
            ("8450E5EE-B595-5E3D-BE2A-2B8776E27AAF", 1790218800.0, 1790221050.0, 2250.0, 4, 1790222850.0),
            ("86C00B82-4FF4-564B-90A3-309221CC70F7", 1790391600.0, 1790393100.0, 1500.0, 4, 1790394900.0),
            ("4BD1DF21-5217-5EE6-9A1C-AD82413FD526", 1790564400.0, 1790567400.0, 3000.0, 4, 1790569200.0),
            ("32EA573C-7A61-561C-B584-7CE14D9D657C", 1790823600.0, 1790825850.0, 2250.0, 4, 1790827650.0),
            ("7DBEB1C2-C447-5684-A0E6-3E2F9D77988B", 1790996400.0, 1790997900.0, 1500.0, 4, 1790999700.0),
            ("769DCB58-FEF4-5C07-854B-470A1E4D9114", 1791169200.0, 1791172200.0, 3000.0, 4, 1791174000.0),
            ("F6497CFF-8CC5-50D0-92BD-D19B3D46F267", 1791428400.0, 1791429930.0, 1530.0, 4, 1791431730.0),
            ("C55C6005-37C6-5162-981E-EC9984E43237", 1791601200.0, 1791602220.0, 1020.0, 4, 1791604020.0),
            ("B7664367-E9A5-5FD3-BBE2-45D0F372A575", 1791774000.0, 1791776040.0, 2040.0, 4, 1791777840.0),
            ("52173C55-6CB1-5B56-8ABA-C780D57A8B2C", 1792033200.0, 1792034730.0, 1530.0, 4, 1792036530.0),
            ("1AC6BEC8-7095-5C48-9144-934396D390B2", 1792206000.0, 1792207020.0, 1020.0, 4, 1792208820.0),
            ("5BF505A0-9794-5C0F-8759-757F30148E6A", 1792378800.0, 1792380840.0, 2040.0, 4, 1792382640.0),
            ("32381B2F-6620-5C53-87EF-2694988E8D91", 1792465200.0, 1792466100.0, 900.0, 4, 1792467900.0),
            ("A9483876-1BF7-5474-9000-1F4014A0951D", 1792638000.0, 1792639350.0, 1350.0, 4, 1792641150.0),
            ("A2D039FF-4F1A-5A00-9426-5232C62B0A9D", 1792724400.0, 1792728900.0, 4500.0, 4, 1792730700.0),
            ("D2F85654-F4D9-5602-93AB-53DE487AB46C", 1792810800.0, 1792812600.0, 1800.0, 4, 1792814400.0),
        ]
        let asOf = Date(timeIntervalSince1970: 1793113200.0)
        var rows: [UnifiedWorkout] = [], confirmations: [UUID: WorkoutEffortConfirmation] = [:]
        for (id, start, end, duration, effort, confirmed) in tuples {
            let id = UUID(uuidString: id)!, start = Date(timeIntervalSince1970: start), end = Date(timeIntervalSince1970: end)
            let w = UnifiedWorkout(id: id, externalId: id.uuidString, source: .manual, workoutType: .running,
                startDate: start, endDate: end, durationSeconds: duration, distanceMeters: nil,
                activeEnergyKcal: nil, averageHeartRate: automated && !missing ? (missingBaseline ? 150 : 80) : nil, maxHeartRate: nil, averageSpeedMetersPerSecond: nil,
                elevationGainMeters: nil, dataQuality: .complete, createdAt: start, updatedAt: end)
            rows.append(w)
            var c = WorkoutEffortConfirmation(value: automated && overridden ? 9 : effort, confirmedAt: Date(timeIntervalSince1970: confirmed), revision: id)
            c.scaleVersion = ActivityLoadRules.scaleVersion; c.reviewedDurationSeconds = duration
            c.durationPolicy = ActivityLoadRules.durationPolicy; c.workoutStart = start; c.workoutEnd = end
            c.unit = ActivityLoadRules.intensityUnit; c.origin = "user"
            if historyReference && (rows.count <= 3 || rows.count == 30) { c.inputControlVersion = ActivityLoadRules.manualInputVersion; confirmations[id] = c }
            if !automated || (overridden && id.uuidString == tuples.last!.0) { confirmations[id] = c }
        }
        var journal = ActivityLoadJournal.empty(zone: "Asia/Seoul")
        let calendar = ActivityLoadRules.calendar(journal.timeZoneID)
        let start = Date(timeIntervalSince1970: 1782831600.0)
        for i in 0..<119 {
            let date = calendar.date(byAdding: .day, value: i, to: start)!
            let key = ActivityLoadRules.dayKey(date, calendar: calendar)
            let matches = rows.filter { ActivityLoadRules.dayKey($0.startDate, calendar: calendar) == key }
            journal.approvals[key] = .init(fingerprint: ActivityLoadCalculator.fingerprint(matches, zone: journal.timeZoneID),
                kind: matches.isEmpty ? .noWorkout : .recordsReviewed, confirmedAt: calendar.date(byAdding: .day, value: 1, to: date)!)
        }
        // Synthetic UI reproduction: real scores with no completeness approvals.
        // Release excludes this whole fixture; no user journal is modified.
        if ProcessInfo.processInfo.environment["SOOM_ACTIVITY_UNREVIEWED_QA"] == "1" { journal.approvals = [:] }
        confirmations.merge(persistedOverrides) { _, saved in saved }
        let current = persistedOverrides.values.map(\.confirmedAt).max().map { max($0,asOf) } ?? asOf
        var stored:[UUID:ActivityLoadHeartRateInput]=[:]
        if storedSamples {
            for row in rows {
                var detail=WorkoutTelemetry(workoutID:row.id,source:row.source)
                detail.samples=[.init(timestamp:row.startDate.addingTimeInterval(10),heartRateBPM:140,source:row.source),.init(timestamp:row.endDate.addingTimeInterval(-10),heartRateBPM:160,source:row.source)]
                stored[row.id]=ActivityLoadHeartRateInput.stored(workout:row,telemetry:detail)
            }
        }
        return ActivityLoadCalculator.build(workouts: rows, confirmations: confirmations, journal: journal, maximum: automated && !missingBaseline ? 200 : nil, asOf: current, historyDays: 119,storedHeartRates:stored)
    }
}
#endif
