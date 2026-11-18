import Combine
import CoreLocation
import HealthKit
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWorkoutRecorder: NSObject, ObservableObject {
    static let shared = WatchWorkoutRecorder()
    @Published private(set) var snapshot: WorkoutLiveState?
    @Published private(set) var message: String?
    @Published private(set) var isStarting = false
    @Published private(set) var phoneRecording = false
    @Published private(set) var canRetrySave = false
    @Published private(set) var isRecovering = false
    @Published private(set) var isChangingState = false
    @Published private(set) var needsRecoveryLookup = false
    @Published private(set) var canFinishWithoutRoute = false
    private let healthStore = HKHealthStore()
    private let location = CLLocationManager()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var routeWrites: Task<Void, Never>?
    private var routeError: Error?
    private var route: [WatchRouteFix] = []
    private var savedWorkout: HKWorkout?
    private var collectionEnded = false
    private var finishAcknowledged = false
    #if DEBUG && targetEnvironment(simulator)
    /// Explicit fault injection for the normal save/retry UI; absent from device and Release builds.
    private var failNextSaveForUITest = ProcessInfo.processInfo.arguments.contains("--watch-qa-fail-save-once")
    #endif
    private var saveInFlight = false
    private var recoveryAttempted = false
    private var timer: Timer?
    private var indoor = false
    private var recordsRoute: Bool { !indoor && snapshot?.poolLengthMeters == nil }
    private var lastAltitude: CLLocation?
    private var stepsReading: (count: Double, elapsed: TimeInterval)?
    private var lastKilometer = 0
    private var lastPublishedAt = Date.distantPast
    private var scope = "guest"
    private var reportedPhoneRecording = false
    private let checkpointURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-workout.json")

    override private init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.activityType = .fitness
        location.distanceFilter = 3
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            let context = WCSession.default.receivedApplicationContext
            applyContext(scope: context["soomScope"] as? String, phoneRecording: context["phoneRecording"] as? Bool ?? false)
        }
    }
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .swimmingStrokeCount, .stepCount, .runningPower, .runningSpeed, .walkingSpeed, .cyclingPower, .cyclingCadence, .cyclingSpeed] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) { types.insert(type) }
        }
        return types
    }
    func start(configuration: HKWorkoutConfiguration) async {
        guard let plan = WatchWorkoutPlan(configuration: configuration) else {
            message = "운동 설정을 확인해 주세요. 수영장 운동에는 수영장 길이가 필요해요."; return
        }
        await start(plan)
    }
    func start(_ plan: WatchWorkoutPlan) async {
        guard snapshot == nil, session == nil, !isStarting, !isRecovering, !phoneRecording else { return }
        guard plan.isValid else { message = "수영장 길이를 10~150m로 설정해 주세요."; return }
        let sport = plan.sport, indoor = plan.indoor
        isStarting = true; message = nil
        defer { isStarting = false }
        guard HKHealthStore.isHealthDataAvailable() else { message = "이 워치에서 건강 데이터를 사용할 수 없어요."; return }
        do {
            var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(sport.distanceQuantity)]
            if plan.recordsRoute { shareTypes.insert(HKSeriesType.workoutRoute()) }
            if sport == .swimming { shareTypes.insert(HKQuantityType(.swimmingStrokeCount)) }
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            // Phone state can change while the Health authorization sheet is visible.
            guard !phoneRecording else { message = "iPhone의 운동을 먼저 종료해 주세요."; return }
            guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                message = "건강 설정에서 SOOM의 운동 저장을 허용해 주세요."; return
            }
            let configuration = plan.configuration
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            self.session = session; self.indoor = indoor
            let builder = session.associatedWorkoutBuilder()
            self.builder = builder
            let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            for id in sport.additionalQuantities {
                if let type = HKQuantityType.quantityType(forIdentifier: id) { source.enableCollection(for: type, predicate: nil) }
            }
            builder.dataSource = source
            builder.delegate = self; session.delegate = self
            let now = Date()
            snapshot = WorkoutLiveState(id: UUID(), scope: scope, sport: sport, phase: .running,
                startedAt: now, updatedAt: now, elapsed: 0, distance: 0, isWatch: true)
            snapshot?.poolLengthMeters = plan.poolLengthMeters
            var metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: indoor, "SOOMWorkoutID": snapshot!.id.uuidString]
            if sport == .swimming {
                metadata[HKMetadataKeySwimmingLocationType] = configuration.swimmingLocationType.rawValue
                if let length = configuration.lapLength { metadata[HKMetadataKeyLapLength] = length }
            }
            try await builder.addMetadata(metadata)
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            prepareRoute()
            beginTimer()
            publish(force: true)
            WKInterfaceDevice.current().play(.start)
            do { try await session.startMirroringToCompanionDevice() }
            catch { message = "iPhone과 연결되면 진행 상태를 전송해요. 워치는 계속 기록 중이에요." }
        } catch {
            location.stopUpdatingLocation(); timer?.invalidate()
            session?.end(); builder?.discardWorkout(); session = nil; builder = nil; routeBuilder = nil; snapshot = nil
            message = "운동을 시작하지 못했어요. 건강 권한을 확인하고 다시 시도해 주세요."
        }
    }
    private func prepareRoute() {
        guard recordsRoute else { return }
        guard healthStore.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized else {
            message = "경로 저장 권한이 꺼져 있어요. 워치 설정에서 건강·위치 권한을 확인해 주세요."; return
        }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        location.requestWhenInUseAuthorization()
        if snapshot?.phase == .running { location.startUpdatingLocation() }
    }
    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMetrics(); self?.publish() }
        }
    }
    func togglePause() {
        guard let state = snapshot, let session, !isStarting, !isChangingState else { return }
        if state.phase == .running { isChangingState = true; session.pause() }
        else if state.phase == .paused { isChangingState = true; session.resume() }
    }
    func finish() {
        guard !isStarting, let state = snapshot, state.phase == .running || state.phase == .paused else { return }
        refreshMetrics(); snapshot?.phase = .saving
        isChangingState = false
        location.stopUpdatingLocation(); timer?.invalidate(); lastAltitude = nil
        publish(force: true)
        session?.stopActivity(with: Date())
        WKInterfaceDevice.current().play(.stop)
    }
    func retrySave() {
        guard canRetrySave else { return }
        Task { if needsRecoveryLookup { await recoverSavedWorkout() } else { await save() } }
    }
    private func save() async {
        guard !saveInFlight, let state = snapshot, state.phase == .saving else { return }
        saveInFlight = true; canRetrySave = false
        defer { saveInFlight = false }
        do {
            if !collectionEnded, let builder {
                try await builder.endCollection(at: state.updatedAt); collectionEnded = true
                persistCheckpoint()
            }
            #if DEBUG && targetEnvironment(simulator)
            if failNextSaveForUITest {
                failNextSaveForUITest = false
                throw NSError(domain: "SOOM.SimulatorSaveTest", code: 1)
            }
            #endif
            // Keep the first saved workout when route saving needs a retry: never create a second workout.
            if savedWorkout == nil {
                // Also covers a successful finish while the device was locked or a crash before checkpointing its UUID.
                savedWorkout = try await findSavedWorkout(sessionID: state.id)
            }
            if savedWorkout == nil, !finishAcknowledged, let builder {
                if let gain = state.elevationGain {
                    try await builder.addMetadata([HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: gain)])
                }
                savedWorkout = try await builder.finishWorkout()
                // nil without an error means HealthKit saved while locked. Never call finishWorkout again in that case.
                finishAcknowledged = true
                snapshot?.savedWorkoutID = savedWorkout?.uuid
                persistCheckpoint()
            }
            guard let workout = savedWorkout else { throw WatchSaveError.missingWorkout }
            await routeWrites?.value
            if let error = routeError { throw error }
            if let routeBuilder, !route.isEmpty, !(try await hasSavedRoute(for: workout, sessionID: state.id)) {
                _ = try await routeBuilder.finishRoute(with: workout, metadata: ["SOOMRouteID": state.id.uuidString])
                self.routeBuilder = nil
            }
            completeSavedWorkout(workout)
        } catch {
            canRetrySave = true
            canFinishWithoutRoute = savedWorkout != nil
            if finishAcknowledged && savedWorkout == nil { needsRecoveryLookup = true }
            message = finishAcknowledged && savedWorkout == nil ? "저장 결과를 확인하고 있어요. 워치를 잠금 해제한 뒤 다시 확인해 주세요."
                : savedWorkout == nil ? "저장을 완료하지 못했어요. 다시 시도해 주세요. 복구 정보는 보관하고 있어요."
                : "운동은 저장했지만 경로 저장에 실패했어요. 다시 시도하면 경로를 이어서 저장해요."
            // A failed insert can be rebuilt from the durable, accepted coordinates.
            if routeError != nil {
                routeError = nil
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                queueRoute(route.map(\.location))
            }
        }
    }
    private func completeSavedWorkout(_ workout: HKWorkout) {
        // Keep the latest sequence; snapshots may have been requested while saving.
        snapshot?.elapsed = workout.duration
        snapshot?.updatedAt = workout.endDate
        if let sport = snapshot?.sport,
           let distance = workout.statistics(for: HKQuantityType(sport.distanceQuantity))?.sumQuantity()?.doubleValue(for: .meter()) ?? workout.totalDistance?.doubleValue(for: .meter()) {
            snapshot?.distance = distance
        }
        snapshot?.energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        if snapshot?.sport == .swimming {
            snapshot?.swimmingStrokeCount = workout.statistics(for: HKQuantityType(.swimmingStrokeCount))?.sumQuantity()?.doubleValue(for: .count())
        }
        snapshot?.phase = .finished; snapshot?.savedWorkoutID = workout.uuid
        message = nil; canRetrySave = false; canFinishWithoutRoute = false; needsRecoveryLookup = false
        publish(force: true)
        session?.end(); session = nil; builder = nil
        try? FileManager.default.removeItem(at: checkpointURL)
        WKInterfaceDevice.current().play(.success)
    }
    func finishWithoutRoute() {
        guard !saveInFlight, canFinishWithoutRoute, let savedWorkout else { return }
        completeSavedWorkout(savedWorkout)
        message = "운동은 저장했어요. 경로는 포함되지 않을 수 있어요."
    }
    func clearUnrecoverableCheckpoint() {
        guard needsRecoveryLookup, !saveInFlight, !isRecovering, savedWorkout == nil else { return }
        snapshot?.phase = .discarded; publish(force: true); session?.end(); reset()
    }
    func enableWaterLock() {
        guard snapshot?.sport == .swimming, snapshot?.phase == .running || snapshot?.phase == .paused else { return }
        WKInterfaceDevice.current().enableWaterLock()
    }
    func discard() {
        guard !saveInFlight, !isStarting, let phase = snapshot?.phase, phase == .running || phase == .paused else { return }
        snapshot?.phase = .discarded; publish(force: true)
        builder?.discardWorkout(); session?.end(); reset()
    }
    func reset() {
        guard !saveInFlight else { return }
        location.stopUpdatingLocation(); timer?.invalidate(); timer = nil
        session = nil; builder = nil; routeBuilder = nil; routeWrites = nil; routeError = nil
        snapshot = nil; route = []; savedWorkout = nil; collectionEnded = false; finishAcknowledged = false
        isChangingState = false; needsRecoveryLookup = false; canFinishWithoutRoute = false
        lastAltitude = nil; stepsReading = nil; lastKilometer = 0; canRetrySave = false; message = nil
        try? FileManager.default.removeItem(at: checkpointURL)
    }
    func recover(force: Bool = false) async {
        guard session == nil, !isStarting, !isRecovering, force || !recoveryAttempted else { return }
        recoveryAttempted = true; isRecovering = true
        defer { isRecovering = false }
        do {
            let data = try? Data(contentsOf: checkpointURL)
            let checkpoint = data.flatMap { try? JSONDecoder().decode(WatchWorkoutCheckpoint.self, from: $0) }
            // A fresh install has nothing to recover and should not report a HealthKit error before authorization.
            guard force || FileManager.default.fileExists(atPath: checkpointURL.path) else { return }
            guard let recovered = try await healthStore.recoverActiveWorkoutSession() else {
                if let checkpoint, checkpoint.state.isValid {
                    restore(checkpoint); await recoverSavedWorkout()
                }
                return
            }
            session = recovered; builder = recovered.associatedWorkoutBuilder()
            recovered.delegate = self; builder?.delegate = self
            if let checkpoint, checkpoint.state.isValid,
               abs((recovered.startDate ?? checkpoint.state.startedAt).timeIntervalSince(checkpoint.state.startedAt)) < 5 {
                restore(checkpoint)
                if let savedID = checkpoint.state.savedWorkoutID { savedWorkout = try? await findSavedWorkout(savedID) }
            } else if let plan = WatchWorkoutPlan(configuration: recovered.workoutConfiguration) {
                // A missing local checkpoint must not discard the live HealthKit session.
                let id = (builder?.metadata["SOOMWorkoutID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                let start = recovered.startDate ?? builder?.startDate ?? Date()
                // Without the checkpoint we cannot establish the prior SOOM account. Keep recovery local.
                snapshot = WorkoutLiveState(id: id, scope: "recovery-" + id.uuidString, sport: plan.sport, phase: .running,
                    startedAt: start, updatedAt: Date(), elapsed: builder?.elapsedTime ?? 0, distance: 0, isWatch: true,
                    sequence: Int(Date().timeIntervalSince1970 * 1000))
                snapshot?.poolLengthMeters = plan.poolLengthMeters; indoor = plan.indoor
                message = "운동을 복구했어요. 중단 전의 GPS 경로는 일부 없을 수 있어요."
            } else {
                message = "이 운동의 복구 설정을 확인하지 못했어요. 건강 앱에서 기록을 확인해 주세요."
                return
            }
            snapshot?.phase = recovered.state == .paused ? .paused : (recovered.state == .stopped || recovered.state == .ended) ? .saving : .running
            prepareRoute()
            if !route.isEmpty { queueRoute(route.map(\.location)) }
            refreshMetrics(); publish(force: true)
            if snapshot?.phase == .saving { await save() } else { beginTimer(); try? await recovered.startMirroringToCompanionDevice() }
        } catch { message = "진행 중인 운동을 복구하지 못했어요. Apple 건강에서 저장 상태를 확인해 주세요." }
    }
    private func restore(_ checkpoint: WatchWorkoutCheckpoint) {
        snapshot = checkpoint.state; route = checkpoint.route; indoor = checkpoint.indoor
        collectionEnded = checkpoint.collectionEnded
        finishAcknowledged = checkpoint.finishAcknowledged ?? (checkpoint.state.savedWorkoutID != nil)
    }
    private func recoverSavedWorkout() async {
        guard let state = snapshot, !saveInFlight else { return }
        needsRecoveryLookup = true; canRetrySave = false; snapshot?.phase = .saving
        do {
            if let id = state.savedWorkoutID { savedWorkout = try await findSavedWorkout(id) }
            if savedWorkout == nil { savedWorkout = try await findSavedWorkout(sessionID: state.id) }
            guard savedWorkout != nil else { throw WatchSaveError.missingWorkout }
            if recordsRoute, !route.isEmpty, routeBuilder == nil {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                queueRoute(route.map(\.location))
            }
            needsRecoveryLookup = false; await save()
        } catch {
            canRetrySave = true
            message = "중단된 운동의 저장 상태를 확인하지 못했어요. 잠금 해제·건강 권한 확인 후 다시 확인해 주세요."
        }
    }
    private func findSavedWorkout(sessionID: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: "SOOMWorkoutID", allowedValues: [sessionID.uuidString])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            healthStore.execute(query)
        }
    }
    private func hasSavedRoute(for workout: HKWorkout, sessionID: UUID) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? []).contains { $0.metadata?["SOOMRouteID"] as? String == sessionID.uuidString }) }
            }
            healthStore.execute(query)
        }
    }
    private func findSavedWorkout(_ id: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: id), limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            healthStore.execute(query)
        }
    }
    private func refreshMetrics() {
        guard let builder, var state = snapshot, state.phase == .running || state.phase == .paused else { return }
        let now = Date()
        state.elapsed = builder.elapsedTime; state.updatedAt = now
        func statistics(_ id: HKQuantityTypeIdentifier) -> HKStatistics? {
            HKQuantityType.quantityType(forIdentifier: id).flatMap { builder.statistics(for: $0) }
        }
        state.distance = statistics(state.sport.distanceQuantity)?.sumQuantity()?.doubleValue(for: .meter()) ?? state.distance
        let heartRateStatistics = statistics(.heartRate)
        state.heartRate = heartRateStatistics?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        state.heartRateMeasuredAt = heartRateStatistics?.mostRecentQuantityDateInterval()?.end
        state.energy = statistics(.activeEnergyBurned)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        state.power = state.sport == .swimming || state.sport == .walking ? nil : statistics(state.sport == .cycling ? .cyclingPower : .runningPower)?.mostRecentQuantity()?.doubleValue(for: .watt())
        if state.sport == .cycling {
            state.cadence = statistics(.cyclingCadence)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        } else if state.sport == .swimming {
            state.swimmingStrokeCount = statistics(.swimmingStrokeCount)?.sumQuantity()?.doubleValue(for: .count())
        } else if let steps = statistics(.stepCount)?.sumQuantity()?.doubleValue(for: .count()) {
            if let old = stepsReading, state.phase == .running, state.elapsed - old.elapsed >= 5 {
                let value = (steps - old.count) / (state.elapsed - old.elapsed) * 60
                if value >= 0 && value <= 300 { state.cadence = value }
            }
            stepsReading = (steps, state.elapsed)
        }
        if state.phase == .paused { state.cadence = nil; state.power = nil }
        snapshot = state
        let kilometer = Int(state.distance / 1000)
        if kilometer > lastKilometer { lastKilometer = kilometer; WKInterfaceDevice.current().play(.notification) }
    }
    private func publish(force: Bool = false) {
        guard var state = snapshot else { return }
        guard force || Date().timeIntervalSince(lastPublishedAt) >= 5 else { return }
        lastPublishedAt = Date()
        state.sequence += 1; snapshot = state
        guard state.isValid, let data = try? JSONEncoder().encode(state) else { return }
        if let session { session.sendToRemoteWorkoutSession(data: data) { _, _ in } }
        if WCSession.default.activationState == .activated {
            if WCSession.default.isReachable { WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
            if state.isTerminal { WCSession.default.transferUserInfo(["soomWorkout": data]) }
        }
        if !state.isTerminal { persistCheckpoint() }
    }
    private func persistCheckpoint() {
        guard let snapshot else { return }
        let checkpoint = WatchWorkoutCheckpoint(state: snapshot, route: route, indoor: indoor, collectionEnded: collectionEnded, finishAcknowledged: finishAcknowledged)
        if let data = try? JSONEncoder().encode(checkpoint) {
            try? data.write(to: checkpointURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var url = checkpointURL
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
    private func queueRoute(_ fixes: [CLLocation]) {
        guard let routeBuilder, !fixes.isEmpty else { return }
        let previous = routeWrites
        routeWrites = Task {
            await previous?.value
            do { try await routeBuilder.insertRouteData(fixes) }
            catch { if self.routeBuilder === routeBuilder { self.routeError = error } }
        }
    }
    private func applyContext(scope: String?, phoneRecording: Bool) {
        if let scope, !scope.isEmpty { self.scope = scope }
        reportedPhoneRecording = phoneRecording
        // An old application context must not permanently block standalone recording while the phone is offline.
        self.phoneRecording = phoneRecording && WCSession.default.isReachable
    }
    private func receiveCommand(_ data: Data) {
        guard let command = try? JSONDecoder().decode(WorkoutRemoteCommand.self, from: data) else { return }
        if command.action == .snapshot {
            guard snapshot?.scope == command.scope else { return }
            refreshMetrics(); publish(force: true); return
        }
        guard let state = snapshot, command.scope == state.scope, command.workoutID == state.id else { return }
        switch command.action {
        case .pause: if state.phase == .running { togglePause() }
        case .resume: if state.phase == .paused { togglePause() }
        case .finish: finish()
        case .snapshot: break
        }
    }
    private enum WatchSaveError: Error { case missingWorkout }
}

extension WatchWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession, let state = self.snapshot, !state.isTerminal else { return }
            if toState == .stopped || toState == .ended {
                if state.phase != .saving {
                    self.refreshMetrics(); self.snapshot?.phase = .saving
                    self.location.stopUpdatingLocation(); self.timer?.invalidate(); self.publish(force: true)
                }
                self.isChangingState = false
                await self.save(); return
            }
            if toState == .paused || toState == .running {
                guard state.phase != .saving else { return }
                self.isChangingState = false
                self.refreshMetrics(); self.snapshot?.phase = toState == .paused ? .paused : .running
                self.stepsReading = nil; self.lastAltitude = nil
                if toState == .running && self.routeBuilder != nil { self.location.startUpdatingLocation() }
                else { self.location.stopUpdatingLocation() }
                self.publish(force: true); WKInterfaceDevice.current().play(.click)
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession, self.snapshot?.isTerminal == false else { return }
            self.isChangingState = false
            self.message = "운동 센서 오류가 발생했어요. 종료 후 저장하거나 다시 시도해 주세요."
            if self.session?.state == .ended || self.session?.state == .stopped {
                self.refreshMetrics(); self.snapshot?.phase = .saving
                self.location.stopUpdatingLocation(); self.timer?.invalidate(); self.publish(force: true)
                await self.save()
            } else { self.finish() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach { self.receiveCommand($0) } }
    }
}
extension WatchWorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor in guard self.builder === workoutBuilder else { return }; self.refreshMetrics(); self.publish(force: true) }
    }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in guard self.builder === workoutBuilder else { return }; self.refreshMetrics(); self.publish() }
    }
}
extension WatchWorkoutRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.snapshot != nil, self.recordsRoute else { return }
            if status == .denied || status == .restricted {
                self.location.stopUpdatingLocation()
                self.message = "위치 권한이 꺼져 있어요. GPS 경로 없이 운동을 기록해요."
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.snapshot?.phase == .running, self.routeBuilder != nil { self.location.startUpdatingLocation() }
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.snapshot?.phase == .running, self.routeBuilder != nil else { return }
            var accepted: [CLLocation] = []
            for fix in locations where CLLocationCoordinate2DIsValid(fix.coordinate) && fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 25 && abs(fix.timestamp.timeIntervalSinceNow) < 15 {
                if let last = self.route.last?.location {
                    let dt = fix.timestamp.timeIntervalSince(last.timestamp)
                    guard dt > 0 else { continue }
                    let limit = self.snapshot?.sport == .cycling ? 35.0 : self.snapshot?.sport == .swimming ? 4.0 : 12.0
                    guard fix.distance(from: last) / dt <= limit else { continue }
                }
                if self.snapshot?.sport != .swimming && fix.altitude.isFinite && fix.verticalAccuracy >= 0 && fix.verticalAccuracy <= 20 {
                    if self.snapshot?.elevationGain == nil { self.snapshot?.elevationGain = 0 }
                    if let last = self.lastAltitude, fix.altitude - last.altitude >= 3 && fix.altitude - last.altitude <= 20 {
                        self.snapshot?.elevationGain = (self.snapshot?.elevationGain ?? 0) + fix.altitude - last.altitude
                        self.lastAltitude = fix
                    } else if self.lastAltitude == nil || fix.altitude < self.lastAltitude!.altitude { self.lastAltitude = fix }
                }
                self.route.append(WatchRouteFix(fix)); accepted.append(fix)
            }
            self.queueRoute(accepted); self.persistCheckpoint()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.message = "GPS를 확인하고 있어요. 운동 시간과 건강 센서는 계속 기록돼요." }
    }
}
extension WatchWorkoutRecorder: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.applyContext(scope: nil, phoneRecording: self.reportedPhoneRecording) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let scope = session.receivedApplicationContext["soomScope"] as? String
        let recording = session.receivedApplicationContext["phoneRecording"] as? Bool ?? false
        Task { @MainActor in self.applyContext(scope: scope, phoneRecording: recording); self.publish(force: true) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let scope = applicationContext["soomScope"] as? String
        let recording = applicationContext["phoneRecording"] as? Bool ?? false
        Task { @MainActor in self.applyContext(scope: scope, phoneRecording: recording) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.receiveCommand(messageData) }
    }
}
private struct WatchWorkoutCheckpoint: Codable {
    var state: WorkoutLiveState
    var route: [WatchRouteFix]
    var indoor: Bool
    var collectionEnded: Bool
    var finishAcknowledged: Bool?
}
private struct WatchRouteFix: Codable {
    var latitude: Double; var longitude: Double; var altitude: Double
    var accuracy: Double; var verticalAccuracy: Double; var timestamp: Date
    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude; longitude = location.coordinate.longitude
        altitude = location.altitude; accuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy; timestamp = location.timestamp
    }
    var location: CLLocation { CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude, horizontalAccuracy: accuracy, verticalAccuracy: verticalAccuracy, timestamp: timestamp) }
}
