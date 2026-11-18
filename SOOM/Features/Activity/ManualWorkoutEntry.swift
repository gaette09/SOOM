import Foundation

/// A stable id belongs to the form, so retrying a failed save cannot create
/// duplicate workouts. Manual values never masquerade as sensor measurements.
struct ManualWorkoutDraft: Equatable {
    let id: UUID
    var workoutType: UnifiedWorkoutType = .running
    var startedAt: Date
    var hours = "0"
    var minutes = "30"
    var seconds = "0"
    var distanceKilometers = ""
    var title = ""
    var description = ""
    var locationName = ""

    init(id: UUID = UUID(), now: Date = Date()) {
        self.id = id
        startedAt = now.addingTimeInterval(-30 * 60)
    }

    static let workoutTypes: [UnifiedWorkoutType] = [
        .running, .cycling, .walking, .swimming, .hiking, .strength, .yoga, .other
    ]

    func makeWorkout(now: Date = Date(), locale: Locale = .current) throws -> UnifiedWorkout {
        func component(_ value: String, maximum: Int) throws -> Int {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return 0 }
            guard text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(text), number <= maximum else {
                throw ManualWorkoutEntryError.invalidDuration
            }
            return number
        }
        let duration = try TimeInterval(component(hours, maximum: 167) * 3600
            + component(minutes, maximum: 59) * 60 + component(seconds, maximum: 59))
        guard duration > 0 else { throw ManualWorkoutEntryError.invalidDuration }
        guard startedAt.timeIntervalSince1970.isFinite,
              startedAt >= Date(timeIntervalSince1970: 0),
              startedAt.addingTimeInterval(duration) <= now else {
            throw ManualWorkoutEntryError.invalidDate
        }

        let rawDistance = distanceKilometers.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance: Double?
        if rawDistance.isEmpty {
            distance = nil
        } else {
            let normalized = rawDistance.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
            guard normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let kilometers = Double(normalized), kilometers.isFinite,
                  kilometers >= 0.001, kilometers <= 10_000 else {
                throw ManualWorkoutEntryError.invalidDistance
            }
            distance = kilometers * 1000
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? "\(workoutType.shareDisplayName) 기록" : cleanTitle
        try WorkoutRecordEditPolicy.validate(title: resolvedTitle, description: description)
        let region = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard region.count <= 100 else { throw ManualWorkoutEntryError.invalidLocation }

        var workout = UnifiedWorkout(
            id: id, externalId: nil, source: .manual, workoutType: workoutType,
            startDate: startedAt, endDate: startedAt.addingTimeInterval(duration),
            durationSeconds: duration, distanceMeters: distance,
            activeEnergyKcal: nil, averageHeartRate: nil, maxHeartRate: nil,
            averageSpeedMetersPerSecond: distance.map { $0 / duration },
            elevationGainMeters: nil, routeMissingReason: .notApplicable,
            dataQuality: .estimated, createdAt: now, updatedAt: now,
            userTitle: resolvedTitle, userDescription: description,
            sharingVisibilityRaw: FeedPostVisibility.privatePost.rawValue
        )
        workout.locationName = region.isEmpty ? nil : region
        return workout
    }
}

enum ManualWorkoutEntryError: LocalizedError, Equatable {
    case invalidDuration, invalidDate, invalidDistance, invalidLocation, accountChanged

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "운동 시간은 1초 이상, 7일 미만으로 입력해 주세요. 분과 초는 각각 0~59까지 입력할 수 있어요."
        case .invalidDate:
            return "운동 시작과 종료 시간이 현재보다 이전인지 확인해 주세요."
        case .invalidDistance:
            return "거리는 0.001~10,000km 사이로 입력해 주세요. 거리를 모르면 비워 두어도 돼요."
        case .invalidLocation:
            return "지역명은 100자까지 입력할 수 있어요."
        case .accountChanged:
            return "계정이 변경되어 저장을 중단했어요. 현재 계정에서 다시 열어 주세요."
        }
    }
}

@MainActor
struct ManualWorkoutEntrySaver {
    let store: any UnifiedWorkoutStore
    let expectedScopeID: String
    let currentScopeID: () -> String

    func save(_ draft: ManualWorkoutDraft, now: Date = Date(), locale: Locale = .current) async throws -> UnifiedWorkout {
        guard expectedScopeID == currentScopeID() else { throw ManualWorkoutEntryError.accountChanged }
        let workout = try draft.makeWorkout(now: now, locale: locale)
        try await store.saveWorkout(workout)
        guard expectedScopeID == currentScopeID() else { throw ManualWorkoutEntryError.accountChanged }
        return workout
    }
}

/// Feed previews are account-scoped just like the workout cache. Keeping the
/// same draft id also makes retries after either storage commit idempotent.
@MainActor
struct ManualWorkoutFeedDraftCoordinator {
    let store: any FeedShareDraftStoreProtocol
    let expectedScopeID: String
    let currentScopeID: () -> String

    private func validate() throws {
        guard expectedScopeID == currentScopeID() else { throw ManualWorkoutEntryError.accountChanged }
    }

    func savePreview(for workout: UnifiedWorkout) async throws {
        try validate()
        let builder = FeedShareDraftBuilder(dateProvider: { workout.createdAt }, idProvider: { workout.id })
        try await store.saveDraft(builder.build(from: workout))
        try validate()
    }

    func removePreviewAfterConfirmedRemotePost(workoutID: UUID) async throws {
        try validate()
        let drafts = try await store.fetchDrafts()
        try validate()
        for draft in drafts where draft.sourceWorkoutId == workoutID {
            try validate()
            try await store.deleteDraft(id: draft.id)
            try validate()
        }
    }
}
