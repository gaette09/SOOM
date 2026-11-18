import AuthenticationServices
import CryptoKit
import Foundation
import Supabase
import SwiftData
import SwiftUI
import UIKit

// Pagination state is source-local, not authorization. No workout or OAuth token is stored here.
struct GoogleHealthHistoryCheckpoint: Codable, Equatable {
    var token: String?
    var complete: Bool
}
struct GoogleHealthHistoryCursor {
    let owner: UUID
    let scope: String
    let request: String
    var defaults: UserDefaults = .standard
    private var prefix: String { "SOOM.googleHistory.v1.\(owner.uuidString.lowercased())." }
    private var key: String {
        let digest=SHA256.hash(data:Data((scope+"\n"+request).utf8)).map{String(format:"%02x",$0)}.joined()
        return prefix+digest
    }
    func load() -> GoogleHealthHistoryCheckpoint? {
        guard let data=defaults.data(forKey:key),let value=try? JSONDecoder().decode(GoogleHealthHistoryCheckpoint.self,from:data),
              value.token.map({!$0.isEmpty && $0.utf8.count<=4096}) ?? true else{return nil}
        return value
    }
    func commitPage(next:String?) {
        guard next.map({!$0.isEmpty && $0.utf8.count<=4096}) ?? true,
              let data=try? JSONEncoder().encode(GoogleHealthHistoryCheckpoint(token:next,complete:next==nil)) else{return}
        defaults.set(data,forKey:key)
    }
    func reset() {defaults.removeObject(forKey:key)}
    func clearOwner() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {defaults.removeObject(forKey:key)}
    }
    static func tokenWasRejected(_ error:Error) -> Bool {
        guard case let FunctionsError.httpError(code,data)=error,code==409,
              let body=try? JSONSerialization.jsonObject(with:data) as? [String:String] else{return false}
        return body["error"]=="invalid_page_token"
    }
}

private enum GoogleHealthConnectionError: Error {
    case signedOut, accountChanged, invalidCallback, unavailable
}

private struct GoogleHealthAction: Encodable {
    let action: String
    let page_token: String?
    let start_date: String?
    let end_date: String?
    let enabled: Bool?
    let event_ids: [Int]?
    let name: String?
    let telemetry_page_tokens: [String: String]?
    let channels: [String]?
    let include_tcx: Bool?
    init(_ action: String, pageToken: String? = nil, startDate: String? = nil,
         endDate: String? = nil, enabled: Bool? = nil, eventIDs: [Int]? = nil,
         name: String? = nil, telemetryPageTokens: [String: String]? = nil,
         channels: [String]? = nil, includeTCX: Bool? = nil) {
        self.action = action
        self.page_token = pageToken
        self.start_date = startDate
        self.end_date = endDate
        self.enabled = enabled
        self.event_ids = eventIDs
        self.name = name
        self.telemetry_page_tokens = telemetryPageTokens
        self.channels = channels
        self.include_tcx = includeTCX
    }
}

private struct GoogleHealthStatus: Decodable, Sendable {
    let configured: Bool
    let connected: Bool
    let auto_import_enabled: Bool?
    let capabilities: GoogleHealthCapabilities?
}

private struct GoogleHealthEvent: Decodable, Sendable {
    let id: Int
    let start_date: String
    let end_date: String
    let operation: String
}
private struct GoogleHealthEventList: Decodable, Sendable { let events: [GoogleHealthEvent] }
private struct GoogleHealthAcknowledgement: Decodable, Sendable { let acknowledged: Bool }
private struct GoogleHealthImportSetting: Decodable, Sendable { let auto_import_enabled: Bool }
private struct GoogleHealthDisconnected: Decodable, Sendable { let connected: Bool }

private struct GoogleHealthStart: Decodable, Sendable {
    let authorization_url: URL
}

struct GoogleHealthWorkoutPage: Decodable, Sendable {
    let workouts: [GoogleHealthWorkoutPayload]
    let next_page_token: String?
}

struct GoogleHealthWorkoutPayload: Decodable, Sendable {
    struct Exercise: Decodable, Sendable {
        struct Interval: Decodable, Sendable { let startTime: String; let endTime: String }
        struct Metrics: Decodable, Sendable {
            struct HeartRateZones: Decodable, Sendable {
                let lightTime: String?
                let moderateTime: String?
                let vigorousTime: String?
                let peakTime: String?
            }
            struct Mobility: Decodable, Sendable {
                let avgGroundContactTimeDuration: String?
                let avgCadenceStepsPerMinute: Double?
                let avgStrideLengthMillimeters: String?
                let avgVerticalOscillationMillimeters: String?
                let avgVerticalRatio: Double?
            }
            let caloriesKcal: Double?
            let distanceMillimeters: Double?
            let averageSpeedMillimetersPerSecond: Double?
            let averageHeartRateBeatsPerMinute: String?
            let elevationGainMillimeters: Double?
            let steps: String?
            let activeZoneMinutes: String?
            let averagePaceSecondsPerMeter: Double?
            let runVo2Max: Double?
            let totalSwimLengths: Double?
            let heartRateZoneDurations: HeartRateZones?
            let mobilityMetrics: Mobility?
        }
        struct Metadata: Decodable, Sendable { let hasGps: Bool?; let poolLengthMillimeters: String? }
        struct Split: Decodable, Sendable {
            let startTime: String
            let endTime: String
            let activeDuration: String?
            let splitType: String?
            let metricsSummary: Metrics?
        }
        struct Event: Decodable, Sendable { let eventTime: String; let exerciseEventType: String }
        let interval: Interval
        let exerciseType: String
        let displayName: String?
        let activeDuration: String?
        let metricsSummary: Metrics?
        let exerciseMetadata: Metadata?
        let splits: [Split]?
        let splitSummaries: [Split]?
        let exerciseEvents: [Event]?
    }
    let name: String
    let exercise: Exercise
    let device_name: String?

    // Keep the Google resource path (which can include its user identifier) out of SOOM storage.
    var externalID: String {
        let digest = SHA256.hash(data: Data(name.utf8))
        return "google-health:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    func makeWorkout(now: Date = Date()) -> UnifiedWorkout? {
        guard name.range(of: #"^users/[^/]+/dataTypes/exercise/dataPoints/[^/]+$"#, options: .regularExpression) != nil, name.count <= 512,
              let start = Self.parseDate(exercise.interval.startTime),
              let end = Self.parseDate(exercise.interval.endTime), end > start,
              start < now.addingTimeInterval(86_400) else { return nil }
        let elapsed = end.timeIntervalSince(start)
        let active = exercise.activeDuration.flatMap { $0.hasSuffix("s") ? Double($0.dropLast()) : nil }
        let duration = active.flatMap { $0.isFinite && $0 > 0 && $0 <= elapsed ? $0 : nil } ?? elapsed
        guard duration <= 7 * 86_400 else { return nil }
        let metrics = exercise.metricsSummary
        func nonnegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let title = exercise.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = device_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UnifiedWorkout(
            id: StravaImportPipeline.stableWorkoutID(for: externalID),
            externalId: externalID, source: .googleHealth,
            workoutType: Self.sport(for: exercise.exerciseType),
            startDate: start, endDate: end, durationSeconds: duration,
            distanceMeters: nonnegative(metrics?.distanceMillimeters).map { $0 / 1_000 },
            activeEnergyKcal: nonnegative(metrics?.caloriesKcal),
            averageHeartRate: metrics?.averageHeartRateBeatsPerMinute.flatMap(Double.init),
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nonnegative(metrics?.averageSpeedMillimetersPerSecond).map { $0 / 1_000 },
            elevationGainMeters: nonnegative(metrics?.elevationGainMillimeters).map { $0 / 1_000 },
            averageCadence: nonnegative(metrics?.mobilityMetrics?.avgCadenceStepsPerMinute),
            routeMissingReason: exercise.exerciseMetadata?.hasGps == true ? .externalSourceRouteNotShared : .indoorNoLocationData,
            dataQuality: .partial, createdAt: now, updatedAt: now,
            userTitle: title.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) },
            deviceName: device.flatMap { $0.isEmpty ? nil : String($0.prefix(100)) } ?? "Google Health"
        )
    }

    // Only aggregate categories reach the UI; never expose a resource name or timestamp.
    func importRejectionReason(now: Date = Date()) -> String {
        if name.range(of: #"^users/[^/]+/dataTypes/exercise/dataPoints/[^/]+$"#, options: .regularExpression) == nil
            || name.count > 512 { return "식별자" }
        guard let start = Self.parseDate(exercise.interval.startTime),
              let end = Self.parseDate(exercise.interval.endTime) else { return "시간 형식" }
        if end <= start { return "시간 순서" }
        if start >= now.addingTimeInterval(86_400) { return "미래 기록" }
        if end.timeIntervalSince(start) > 7 * 86_400 { return "기간 초과" }
        return "기타 형식"
    }

    // Refresh Google-owned summary values without overwriting edits made in SOOM.
    // A repeated import never changes an existing workout's sharing decision.
    func refreshedWorkout(from existing: UnifiedWorkout, now: Date = Date()) -> UnifiedWorkout? {
        guard existing.source == .googleHealth, existing.externalId == externalID,
              let latest = makeWorkout(now: now) else { return nil }
        guard existing.workoutType != latest.workoutType
                || existing.startDate != latest.startDate
                || existing.endDate != latest.endDate
                || existing.durationSeconds != latest.durationSeconds
                || existing.distanceMeters != latest.distanceMeters
                || existing.activeEnergyKcal != latest.activeEnergyKcal
                || existing.averageHeartRate != latest.averageHeartRate
                || existing.averageSpeedMetersPerSecond != latest.averageSpeedMetersPerSecond
                || existing.elevationGainMeters != latest.elevationGainMeters
                || (latest.averageCadence != nil && existing.averageCadence != latest.averageCadence)
                || (existing.deviceName == "Google Health" && latest.deviceName != existing.deviceName)
        else { return nil }
        return UnifiedWorkout(
            id: existing.id, externalId: existing.externalId, source: existing.source,
            workoutType: latest.workoutType, startDate: latest.startDate, endDate: latest.endDate,
            durationSeconds: latest.durationSeconds, distanceMeters: latest.distanceMeters,
            activeEnergyKcal: latest.activeEnergyKcal, averageHeartRate: latest.averageHeartRate,
            maxHeartRate: existing.maxHeartRate,
            averageSpeedMetersPerSecond: latest.averageSpeedMetersPerSecond,
            elevationGainMeters: latest.elevationGainMeters,
            averagePowerWatts: existing.averagePowerWatts, averageCadence: latest.averageCadence ?? existing.averageCadence,
            routeMissingReason: existing.routeMissingReason, dataQuality: existing.dataQuality,
            isExcludedFromAnalysis: existing.isExcludedFromAnalysis,
            createdAt: existing.createdAt, updatedAt: now,
            companionNames: existing.companionNames, userTitle: existing.userTitle ?? latest.userTitle,
            userDescription: existing.userDescription,
            sharingVisibilityRaw: existing.sharingVisibilityRaw,
            isBookmarked: existing.isBookmarked,
            deviceName: existing.deviceName == "Google Health" ? latest.deviceName : existing.deviceName,
            locationName: existing.locationName
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func sport(for type: String) -> UnifiedWorkoutType {
        switch type {
        case "RUNNING", "TREADMILL_RUNNING", "INCLINE_RUN": return .running
        case "BIKING", "MOUNTAIN_BIKE", "ELECTRIC_BIKE", "HAND_CYCLING", "SPINNING", "INDOOR_CYCLING": return .cycling
        case "WALKING", "INCLINE_WALK": return .walking
        case "SWIMMING", "OPEN_WATER_SWIMMING", "POOL_SWIMMING": return .swimming
        case "HIKING", "BACKPACKING": return .hiking
        case "STRENGTH_TRAINING", "WEIGHTLIFTING", "FREE_WEIGHTS", "WEIGHT_MACHINES", "FUNCTIONAL_STRENGTH_TRAINING": return .strength
        case "YOGA", "YOGA_BIKRAM", "YOGA_HATHA", "YOGA_POWER", "YOGA_VINYASA": return .yoga
        default: return .other
        }
    }
}

@MainActor
private final class GoogleHealthAPI {
    private let client: SupabaseClient
    private let owner: UUID
    init?(owner: UUID) {
        guard !ReviewDemoMode.isActive else { return nil }
        guard let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient() else { return nil }
        self.client = client
        self.owner = owner
    }
    private func invoke<T: Decodable & Sendable>(_ action: String, pageToken: String? = nil,
                                      startDate: String? = nil, endDate: String? = nil,
                                      enabled: Bool? = nil, eventIDs: [Int]? = nil,
                                      name: String? = nil, telemetryPageTokens: [String: String]? = nil,
                                      channels: [String]? = nil, includeTCX: Bool? = nil) async throws -> T {
        guard client.auth.currentSession?.user.id == owner else { throw GoogleHealthConnectionError.signedOut }
        let response: T = try await client.functions.invoke(
            "google-health", options: FunctionInvokeOptions(body: GoogleHealthAction(action, pageToken: pageToken,
                startDate: startDate, endDate: endDate, enabled: enabled, eventIDs: eventIDs,
                name: name, telemetryPageTokens: telemetryPageTokens, channels: channels, includeTCX: includeTCX)))
        guard client.auth.currentSession?.user.id == owner else { throw GoogleHealthConnectionError.accountChanged }
        return response
    }
    func status() async throws -> GoogleHealthStatus { try await invoke("status") }
    func start() async throws -> URL { try await (invoke("start") as GoogleHealthStart).authorization_url }
    func page(_ token: String?, startDate: String? = nil, endDate: String? = nil) async throws -> GoogleHealthWorkoutPage {
        try await invoke("page", pageToken: token, startDate: startDate, endDate: endDate)
    }
    func details(name: String, tokens: [String: String]? = nil) async throws -> GoogleHealthWorkoutDetails {
        try await invoke("details", name: name, telemetryPageTokens: tokens,
                         channels: tokens.map { Array($0.keys).sorted() }, includeTCX: tokens == nil)
    }
    func events() async throws -> [GoogleHealthEvent] { try await (invoke("events") as GoogleHealthEventList).events }
    func acknowledge(_ ids: [Int]) async throws {
        let _: GoogleHealthAcknowledgement = try await invoke("ack", eventIDs: ids)
    }
    func setAutomaticImport(_ enabled: Bool) async throws {
        let _: GoogleHealthImportSetting = try await invoke("auto_import", enabled: enabled)
    }
    func disconnect() async throws { let _: GoogleHealthDisconnected = try await invoke("disconnect") }
}

@MainActor
private final class GoogleHealthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow } ?? UIWindow()
    }
    func authorize(_ url: URL) async throws {
        defer { session = nil }
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "soom-auth") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: GoogleHealthConnectionError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { continuation.resume(throwing: GoogleHealthConnectionError.unavailable) }
        }
        session = nil
        guard callback.scheme == "soom-auth", callback.host == "google-health", callback.path == "/callback",
              URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "result" })?.value == "connected"
        else { throw GoogleHealthConnectionError.invalidCallback }
    }
}

enum GoogleHealthConnectionPhase: Equatable {
    case loginRequired, checking, ready, connected, unavailable, failed
    var title: String {
        switch self {
        case .loginRequired: return "로그인 필요"
        case .checking: return "연결 상태 확인 중"
        case .ready: return "연결 가능"
        case .connected: return "연결됨"
        case .unavailable: return "현재 연결을 제공할 수 없어요"
        case .failed: return "연결 상태 확인 실패"
        }
    }
}

struct GoogleHealthConnectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var storage: HealthAccountStorageController
    @State private var browser = GoogleHealthBrowser()
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.soomRequestLogin) private var requestLogin
    @Environment(\.soomOpenActivities) private var openActivities
    @State private var phase: GoogleHealthConnectionPhase = .checking
    @State private var confirmingDisconnect = false
    @State private var configured = false
    @State private var connected = false
    @State private var needsDetailAuthorization = false
    @State private var consent = false
    @State private var busy = false
    @State private var result = ""
    @State private var nextPageToken: String?
    @State private var qaRefreshCount = 0
    @State private var isRefreshing = false
    private var qaScenario: String? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["SOOM_SYNTHETIC_UI_TESTS"] == "1" else { return nil }
        return ProcessInfo.processInfo.environment["SOOM_UX_GOOGLE_STATE"]
        #else
        return nil
        #endif
    }

    var body: some View {
        if ReviewDemoMode.isActive && qaScenario == nil {
            ReviewDemoIntegrationView(title: "Google Health")
        } else {
            connectionContent
        }
    }

    private var connectionContent: some View {
        SOOMScreen {
            VStack(alignment: .leading, spacing: 18) {
                Text("Google Health")
                    .font(SOOMFont.display(32, relativeTo: .largeTitle))
                Text("Google Health에 저장된 운동과 제공되는 경로·상세 측정값을 가져옵니다.")
                    .foregroundStyle(SOOMColor.secondaryInk)
                SOOMCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("연결 전 확인").font(.headline)
                        Text("운동 날짜·종목·시간·거리와 제공되는 GPS 경로, 운동 중 심박수, 속도·고도·케이던스·파워, 구간·존·수영 정보를 SOOM 활동에 저장합니다. Google에 해당 기록이 있는 항목만 가져오며 다른 시간대의 건강 정보는 조회하지 않습니다. 별도로 동의한 경우 계정 저장소에도 보관합니다. \(ImportedWorkoutPublication.usesLegacyPublication ? "가져온 운동은 현재 자동 공개 설정에 따라 피드에 공유될 수 있으며, 활동에서 개별 또는 전체 비공개로 바꿀 수 있습니다." : ImportedWorkoutPublication.profileImportDescription) 연결 해제는 이후 접근을 중단하지만 이미 가져온 기록은 활동에서 직접 삭제해야 합니다.")
                            .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                        Toggle("이 내용을 확인하고 Google 계정 연결에 동의합니다", isOn: $consent)
                            .font(.subheadline)
                    }
                }
                Label(phase.title, systemImage: phase == .connected ? "checkmark.circle" : "info.circle")
                    .font(.headline).accessibilityIdentifier("google.connection.status")
                if phase == .checking || busy { ProgressView(busy ? "요청을 처리하는 중" : "연결 상태를 확인하는 중").accessibilityIdentifier("google.connection.progress") }
                if phase == .loginRequired {
                    Button { requestLogin?(.googleHealth) } label: {
                        Text("로그인하고 Google Health 연결").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("google.connection.login")
                }
                if phase == .failed || phase == .unavailable {
                    Text(phase == .failed ? "연결이나 네트워크 상태를 확인하지 못했어요. 다시 확인해 주세요." : "현재 서버 응답에서 연결 준비가 확인되지 않았어요. 잠시 후 다시 확인해 주세요.")
                        .font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Button { Task { await refresh() } } label: { Text("연결 상태 다시 확인").frame(minHeight: 44) }
                        .accessibilityIdentifier("google.connection.retry")
                }
                if !result.isEmpty {
                    Text(result).font(.subheadline).foregroundStyle(SOOMColor.secondaryInk)
                    Button("활동에서 보기") { openActivities?() }.frame(minHeight: 44)
                }
                if connected {
                    if needsDetailAuthorization {
                        Text("경로와 운동 중 심박수를 가져오려면 Google 계정을 다시 연결해 위치·건강 측정값 읽기 권한에 동의해 주세요. 허용한 항목부터 가져옵니다.")
                            .font(.subheadline).foregroundStyle(SOOMColor.accent)
                    }
                    Toggle("새 운동 자동 가져오기", isOn: Binding(
                        get: { GoogleHealthAutomaticImport.isEnabled(for: storage) },
                        set: { desired in
                            Task {
                                if !(await GoogleHealthAutomaticImport.setEnabled(desired, for: storage)) {
                                    result = "자동 가져오기 설정을 저장하지 못했어요. 다시 시도해 주세요."
                                }
                            }
                        }
                    ))
                    .font(.subheadline)
                    Text("Google Health 변경 알림이 오면 새 운동만 가져옵니다. 다시 로그인할 때 놓친 알림을 이어 처리해요.")
                        .font(.caption).foregroundStyle(SOOMColor.secondaryInk)
                }
                Button(connected ? (nextPageToken == nil ? "운동·상세 데이터 가져오기" : "나머지 운동 이어 가져오기") : "Google 계정 연결") {
                    Task { if connected { await importWorkouts() } else { await connect() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || phase == .checking || phase == .loginRequired || phase == .failed || !configured || (!connected && !consent))
                if connected {
                    Button { Task { await connect() } } label: { Text("Google 계정 다시 연결").frame(minHeight: 44) }
                        .disabled(busy || !consent)
                    Button { confirmingDisconnect = true } label: { Text("연결 해제").frame(minHeight: 44) }
                        .disabled(busy)
                }
            }
        }
        .navigationTitle("Google Health")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: storage.scopeID) {
            configured = false; connected = false; consent = false; busy = false; isRefreshing = false; result = ""; nextPageToken = nil
            if let owner=storage.userID { nextPageToken=GoogleHealthHistoryCursor(owner:owner,scope:storage.scopeID,request:"manual-all").load()?.token }
            await refresh()
        }
        .confirmationDialog("Google Health 연결을 해제할까요?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) { Task { await disconnect() } }
            Button("취소", role: .cancel) {}
        } message: { Text("이후 접근을 중단해요. 이미 가져온 운동은 활동에 유지됩니다.") }
        .accessibilityIdentifier("integrations.googleHealth.connection")
    }

    private func api() -> GoogleHealthAPI? {
        guard authViewModel.session.currentUser?.authProvider == .supabase, let owner = storage.userID else { phase = .loginRequired; return nil }
        return GoogleHealthAPI(owner: owner)
    }
    private func refresh() async {
        guard !isRefreshing else { return }
        let refreshScope = storage.scopeID
        isRefreshing = true
        defer { if storage.scopeID == refreshScope { isRefreshing = false } }
        if let scenario = qaScenario {
            qaRefreshCount += 1; phase = .checking
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            phase = scenario == "failed" && qaRefreshCount == 1 ? .failed : scenario == "unavailable" ? .unavailable : scenario == "connected" ? .connected : .ready
            configured = phase == .ready || phase == .connected; connected = phase == .connected
            result = "QA · 합성 연결 상태. 외부 서비스에 요청하지 않습니다."
            return
        }
        guard !busy, let api = api() else { return }
        let scope = storage.scopeID
        phase = .checking; result = ""
        do {
            let status = try await api.status()
            guard storage.scopeID == scope, !Task.isCancelled else { return }
            phase = status.connected ? .connected : status.configured ? .ready : .unavailable
            configured = status.configured
            connected = status.connected
            needsDetailAuthorization = status.capabilities?.needs_reauthorization ?? status.connected
            GoogleHealthAutomaticImport.cacheEnabled(status.auto_import_enabled ?? true, for: storage)
        } catch {
            guard storage.scopeID == scope, !Task.isCancelled else { return }
            configured = false; connected = false; phase = .failed
            result = "현재 연결 상태를 확인하지 못했어요. 다시 확인해 주세요."
        }
    }
    private func connect() async {
        if qaScenario != nil { result = "연결을 취소했어요. 원할 때 다시 연결할 수 있어요."; return }
        guard !busy, let api = api() else { return }
        busy = true
        let scope = storage.scopeID
        var shouldImport = false
        do {
            let url = try await api.start()
            try await browser.authorize(url)
            guard storage.scopeID == scope, !Task.isCancelled else { return }
            let status = try await api.status()
            guard storage.scopeID == scope, !Task.isCancelled else { return }
            phase = status.connected ? .connected : status.configured ? .ready : .unavailable
            connected = status.connected
            needsDetailAuthorization = status.capabilities?.needs_reauthorization ?? status.connected
            shouldImport = connected
            if connected {
                nextPageToken = nil
                if let owner=storage.userID {GoogleHealthHistoryCursor(owner:owner,scope:scope,request:"manual-all").clearOwner()}
            }
            result = connected ? "연결됐어요. 운동을 가져오는 중이에요." : "연결 상태를 확인하지 못했어요."
        } catch {
            guard storage.scopeID == scope else { return }
            result = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? "연결을 취소했어요. 원할 때 다시 연결할 수 있어요." : "연결을 완료하지 못했어요. 다시 시도해 주세요."
        }
        guard storage.scopeID == scope else { return }
        busy = false
        if shouldImport { await importWorkouts() }
    }
    private func importWorkouts() async {
        if qaScenario != nil { result = "QA · 가져오기 상태만 확인하며 외부 요청은 보내지 않아요."; return }
        guard !busy, let owner = storage.userID, let api = api() else { return }
        busy = true
        defer { busy = false }
        let scope = storage.scopeID
        let store = SwiftDataUnifiedWorkoutStore(modelContext: modelContext)
        let cursor=GoogleHealthHistoryCursor(owner:owner,scope:scope,request:"manual-all")
        var token = cursor.load()?.token
        var saved = 0
        var updated = 0
        var unchanged = 0
        var rejected: [String: Int] = [:]
        var newIDs: [UUID] = []
        var detailsSaved = 0
        var detailsPending = 0
        do {
            for _ in 0..<100 {
                guard storage.userID == owner, storage.scopeID == scope,modelContext.container === storage.container,!Task.isCancelled else { throw GoogleHealthConnectionError.accountChanged }
                let page = try await api.page(token)
                var pageNeedsRetry=false
                for item in page.workouts {
                    guard let workout = item.makeWorkout() else {
                        rejected[item.importRejectionReason(), default: 0] += 1
                        continue
                    }
                    if let existing = try await store.fetchByExternalId(item.externalID, source: .googleHealth) {
                        if let refreshed = item.refreshedWorkout(from: existing) {
                            guard storage.userID == owner, storage.scopeID == scope else { throw GoogleHealthConnectionError.accountChanged }
                            try await store.saveWorkout(refreshed)
                            updated += 1
                        } else { unchanged += 1 }
                    } else {
                        guard storage.userID == owner, storage.scopeID == scope else { throw GoogleHealthConnectionError.accountChanged }
                        var pending = workout
                        if ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts {
                            pending.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for:storage.defaultWorkoutAudience)
                        }
                        try await store.saveWorkout(pending)
                        saved += 1
                        if ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts { newIDs.append(pending.id) }
                    }
                    let detail = try await GoogleHealthDetailImport.fetchAndSave(item: item, api: api,
                        storage: storage, owner: owner, scope: scope, context: modelContext)
                    pageNeedsRetry = pageNeedsRetry || detail.retryNeeded
                    detailsSaved += detail.saved ? 1 : 0
                    detailsPending += (detail.retryNeeded || detail.exceedsCapacity) ? 1 : 0
                    result = "\(saved + updated + unchanged)개 운동 확인 · \(detailsSaved)개 상세 저장 중"
                }
                guard storage.userID == owner,storage.scopeID == scope,modelContext.container === storage.container,!Task.isCancelled else {throw GoogleHealthConnectionError.accountChanged}
                if pageNeedsRetry {throw GoogleHealthConnectionError.unavailable}
                token = page.next_page_token
                cursor.commitPage(next:token)
                nextPageToken=token
                if token == nil { break }
            }
            if ImportedWorkoutPublication.usesLegacyPublication, !newIDs.isEmpty, storage.userID == owner, storage.scopeID == scope {
                let publication = ImportedWorkoutPublication.usesLegacyPublication && AccountActivityFeedReleaseGate.productionReady ? await ImportedWorkoutPublication(context: modelContext, storage: storage).publish(ids: newIDs) : ImportedWorkoutPublication.Result()
                result = "\(saved)개 저장, \(updated)개 갱신, \(unchanged)개 중복, \(rejected.values.reduce(0, +))개 제외 · \(publication.published)개 피드 공유"
                if publication.failed > 0 { result += " · \(publication.failed)개 공유 재시도 필요" }
            } else { result = "\(saved)개 저장, \(updated)개 갱신, \(unchanged)개 중복, \(rejected.values.reduce(0, +))개 제외" }
            if !rejected.isEmpty {
                let summary = rejected.keys.sorted().map { "\($0) \(rejected[$0, default: 0])개" }.joined(separator: ", ")
                result += " · 제외 이유: \(summary)"
            }
            nextPageToken = token
            result += " · \(detailsSaved)개 상세 저장"
            if detailsPending > 0 { result += " · \(detailsPending)개 상세 재시도 필요" }
            if needsDetailAuthorization { result += " · 경로·심박 권한은 다시 연결 후 추가할 수 있어요." }
            NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: owner)
            if token != nil { result += " · 다음 기록을 이어 가져올 수 있어요." }
        } catch {
            guard storage.userID==owner,storage.scopeID==scope else{return}
            if token != nil && GoogleHealthHistoryCursor.tokenWasRejected(error) {cursor.reset();nextPageToken=nil}
            result = "\(saved)개 저장 후 가져오기가 중단됐어요. 다시 실행하면 저장된 기록은 유지하고 이어 확인합니다."
        }
    }
    private func disconnect() async {
        if qaScenario != nil { result = "연결을 해제하지 못했어요. 다시 시도해 주세요."; return }
        guard !busy, let api = api() else { return }
        busy = true
        let scope = storage.scopeID
        defer { if storage.scopeID == scope { busy = false } }
        do {
            try await api.disconnect()
            guard storage.scopeID == scope else { return }
            phase = .ready
            connected = false
            if let owner=storage.userID {GoogleHealthHistoryCursor(owner:owner,scope:scope,request:"manual-all").clearOwner()}
            nextPageToken = nil
            result = "연결을 해제했어요. 이미 가져온 운동은 활동에서 관리할 수 있어요."
        } catch { guard storage.scopeID == scope else { return }; result = "연결을 해제하지 못했어요. 다시 시도해 주세요." }
    }
}


@MainActor
private enum GoogleHealthDetailImport {
    struct Result { var saved = false; var retryNeeded = false; var exceedsCapacity = false }

    static func fetchAndSave(item: GoogleHealthWorkoutPayload, api: GoogleHealthAPI,
                             storage: HealthAccountStorageController, owner: UUID,
                             scope: String, context: ModelContext) async throws -> Result {
        func checkOwner() throws {
            try Task.checkCancellation()
            guard storage.userID == owner, storage.scopeID == scope,
                  context.container === storage.container else { throw GoogleHealthConnectionError.accountChanged }
        }
        try checkOwner()
        let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
        guard let workout = try await store.fetchByExternalId(item.externalID, source: .googleHealth) else { return .init() }
        var combined = WorkoutTelemetry(workoutID: workout.id, source: .googleHealth)
        var route: WorkoutRoute?
        var tcxSummary: TCXWorkoutSummary?
        var retryNeeded = false
        var exceedsCapacity = false
        var tokens: [String: String]?
        var seenTokens = Set<String>()
        do {
            for index in 0..<100 {
                let response = try await api.details(name: item.name, tokens: tokens)
                try checkOwner()
                guard response.workout.externalID == item.externalID else { throw GoogleHealthConnectionError.invalidCallback }
                let next = response.makeTelemetry(for: workout, includeSummary: index == 0)
                combined.samples += next.samples
                combined.intervals += next.intervals
                combined.splits += next.splits
                combined.heartRateZones += next.heartRateZones
                combined.summaryMetrics += next.summaryMetrics
                combined.events += next.events
                if index == 0 {
                    route = response.makeRoute(for: workout)
                    if let tcx = response.tcx {
                        tcxSummary = try? TCXRouteParser(maximumLapCount: 2_000, maximumCoordinateCount: 100_000)
                            .parse(Data(tcx.utf8), allowMissingRoute: true).summary
                    }
                }
                retryNeeded = retryNeeded || response.hasRetryableFailure
                let pending = response.next_page_tokens ?? [:]
                if pending.isEmpty { tokens = nil; break }
                // A repeated cursor is a provider failure, never a reason to loop forever.
                let signature = pending.keys.sorted().map { "\($0):\(pending[$0]!)" }.joined(separator: "|")
                guard seenTokens.insert(signature).inserted else { retryNeeded = true; break }
                tokens = pending
            }
            if tokens != nil { retryNeeded = true }
        } catch {
            try checkOwner()
            retryNeeded = true
        }
        try checkOwner()
        // Save successful channels even when one optional endpoint is unavailable.
        // Existing measured channels survive incomplete retries in the common store.
        var saved = false
        combined = combined.coalescingSamples()
        if !combined.isEmpty {
            do {
                try WorkoutTelemetryStore(modelContext: context).save(combined)
                saved = true
            } catch WorkoutTelemetryError.tooLarge {
                // Retrying the same oversized export cannot succeed; do not
                // prevent newer webhook events from being processed behind it.
                exceedsCapacity = true
            } catch { retryNeeded = true }
        }
        if let route {
            try await SwiftDataWorkoutRoutePersistenceStore(modelContext: context).saveRoute(route)
            saved = true
        }
        // Re-read after network awaits to preserve any edits made while importing.
        if let current = try await store.fetchWorkout(id: workout.id), saved {
            let retained = try WorkoutTelemetryStore(modelContext: context).load(workoutID: current.id)
            let maxHeartRate = retained?.samples.compactMap(\.heartRateBPM).max() ?? tcxSummary?.maxHeartRate
            let enriched = UnifiedWorkout(
                id: current.id, externalId: current.externalId, source: current.source,
                workoutType: current.workoutType, startDate: current.startDate, endDate: current.endDate,
                durationSeconds: current.durationSeconds,
                distanceMeters: current.distanceMeters ?? tcxSummary?.distanceMeters,
                activeEnergyKcal: current.activeEnergyKcal ?? tcxSummary?.activeEnergyKcal,
                averageHeartRate: current.averageHeartRate ?? tcxSummary?.averageHeartRate,
                maxHeartRate: maxHeartRate ?? current.maxHeartRate,
                averageSpeedMetersPerSecond: current.averageSpeedMetersPerSecond ?? tcxSummary?.averageSpeedMetersPerSecond,
                elevationGainMeters: current.elevationGainMeters ?? tcxSummary?.elevationGainMeters,
                // Legacy TCX summary averages discard zero/coasting samples.
                // Keep real provider summaries; timestamped channels supply the graphs.
                averagePowerWatts: current.averagePowerWatts,
                averageCadence: current.averageCadence,
                routeMissingReason: route == nil ? current.routeMissingReason : .none,
                dataQuality: current.dataQuality, isExcludedFromAnalysis: current.isExcludedFromAnalysis,
                createdAt: current.createdAt, updatedAt: Date(), companionNames: current.companionNames,
                userTitle: current.userTitle, userDescription: current.userDescription,
                sharingVisibilityRaw: current.sharingVisibilityRaw, isBookmarked: current.isBookmarked,
                deviceName: current.deviceName, locationName: current.locationName)
            try await store.saveWorkout(enriched)
        }
        return Result(saved: saved, retryNeeded: retryNeeded, exceedsCapacity: exceedsCapacity)
    }
}

 
@MainActor
enum GoogleHealthAutomaticImport {
    private static var running = false
    private static var runAgain = false

    static func isEnabled(for storage: HealthAccountStorageController) -> Bool {
        guard !ReviewDemoMode.isActive, storage.userID != nil else { return false }
        return UserDefaults.standard.object(forKey: "SOOM.googleHealthAutoImport.\(storage.scopeID)") as? Bool ?? true
    }

    static func cacheEnabled(_ enabled: Bool, for storage: HealthAccountStorageController) {
        UserDefaults.standard.set(enabled, forKey: "SOOM.googleHealthAutoImport.\(storage.scopeID)")
        storage.objectWillChange.send()
    }

    static func setEnabled(_ enabled: Bool, for storage: HealthAccountStorageController) async -> Bool {
        guard let owner = storage.userID, let api = GoogleHealthAPI(owner: owner) else { return false }
        do {
            try await api.setAutomaticImport(enabled)
            guard storage.userID == owner else { return false }
            cacheEnabled(enabled, for: storage)
            if enabled { await run(storage: storage) }
            return true
        } catch { return false }
    }

    /// Drains only durable webhook events. App activation never scans Google
    /// Health itself; the exercise API is read only for intervals Google sent.
    static func run(storage: HealthAccountStorageController) async {
        guard isEnabled(for: storage), let owner = storage.userID else { return }
        if running { runAgain = true; return }
        running = true
        defer { running = false }
        repeat {
            runAgain = false
            let scope = storage.scopeID
            guard let api = GoogleHealthAPI(owner: owner) else { return }
            do {
                let events = try await api.events()
                guard storage.userID == owner, storage.scopeID == scope else { return }
                if events.isEmpty { return }
                let context = ModelContext(storage.container)
                let store = SwiftDataUnifiedWorkoutStore(modelContext: context)
                for event in events {
                    guard storage.userID == owner, storage.scopeID == scope,isEnabled(for:storage),!Task.isCancelled else { return }
                    // A Google deletion does not silently delete a user's SOOM
                    // activity, which may have its own title or visibility edits.
                    if event.operation != "UPSERT" {
                        try await api.acknowledge([event.id])
                        continue
                    }
                    let cursor=GoogleHealthHistoryCursor(owner:owner,scope:scope,request:"event:\(event.id):\(event.start_date):\(event.end_date):\(event.operation)")
                    if cursor.load()?.complete == true {try await api.acknowledge([event.id]);cursor.reset();continue}
                    var token=cursor.load()?.token
                    var changed = false
                    for _ in 0..<100 {
                        guard storage.userID==owner,storage.scopeID==scope,context.container === storage.container,isEnabled(for:storage),!Task.isCancelled else{return}
                        let page:GoogleHealthWorkoutPage
                        do {page = try await api.page(token, startDate: event.start_date, endDate: event.end_date)}
                        catch {
                            if storage.userID==owner,storage.scopeID==scope,token != nil,GoogleHealthHistoryCursor.tokenWasRejected(error) {cursor.reset()}
                            throw error
                        }
                        guard storage.userID == owner, storage.scopeID == scope,
                              context.container === storage.container,isEnabled(for:storage),!Task.isCancelled else { return }
                        for item in page.workouts {
                            guard let workout = item.makeWorkout() else { continue }
                            if let existing = try await store.fetchByExternalId(item.externalID, source: .googleHealth) {
                                if let refreshed = item.refreshedWorkout(from: existing) {
                                    try await store.saveWorkout(refreshed)
                                    changed = true
                                }
                            } else {
                                var pending = workout
                                if ImportedWorkoutPublication.usesLegacyPublication && storage.autoPublishImportedWorkouts {
                                    pending.sharingVisibilityRaw = ImportedWorkoutPublication.pendingVisibility(for:storage.defaultWorkoutAudience)
                                }
                                try await store.saveWorkout(pending)
                                changed = true
                            }
                            let detail = try await GoogleHealthDetailImport.fetchAndSave(item: item, api: api,
                                storage: storage, owner: owner, scope: scope, context: context)
                            changed = changed || detail.saved
                            // Keep the event queued if a transient detail request failed.
                            // Permission/missing data is terminal until an explicit reconnect.
                            if detail.retryNeeded { return }
                        }
                        guard storage.userID==owner,storage.scopeID==scope,context.container === storage.container,isEnabled(for:storage),!Task.isCancelled else{return}
                        token = page.next_page_token
                        if token != nil {cursor.commitPage(next:token)}
                        if token == nil { break }
                    }
                    // Never acknowledge a truncated interval. The next event
                    // delivery safely retries because workout IDs are stable.
                    if token != nil { return }
                    guard storage.userID == owner, storage.scopeID == scope,isEnabled(for:storage),!Task.isCancelled else { return }
                    let publication = ImportedWorkoutPublication.usesLegacyPublication && AccountActivityFeedReleaseGate.productionReady ? await ImportedWorkoutPublication(context: context, storage: storage).publish() : ImportedWorkoutPublication.Result()
                    if publication.failed > 0 { return }
                    guard storage.userID==owner,storage.scopeID==scope,context.container === storage.container,isEnabled(for:storage),!Task.isCancelled else{return}
                    cursor.commitPage(next:nil)
                    if changed { NotificationCenter.default.post(name: WorkoutRecordManagement.didChange, object: owner) }
                    try await api.acknowledge([event.id])
                    cursor.reset()
                }
                if events.count == 50 { runAgain = true }
            } catch { return }
        } while runAgain && isEnabled(for: storage)
    }
}
