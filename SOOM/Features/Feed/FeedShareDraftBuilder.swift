import Foundation

struct FeedShareDraftBuilder {
    var dateProvider: () -> Date = Date.init
    var idProvider: () -> UUID = UUID.init

    func build(from workout: UnifiedWorkout) -> FeedShareDraft {
        let distanceText = Self.distanceText(workout.distanceMeters)
        let title = "오늘의 \(Self.sportTitle(for: workout.workoutType))"
        let fallbackStyle = StaticRouteFallbackStyle(workoutType: workout.workoutType)

        return FeedShareDraft(
            id: idProvider(),
            sourceWorkoutId: workout.id,
            sport: workout.workoutType,
            title: title,
            body: "가볍게 리듬을 이어간 기록.",
            distanceMeters: workout.distanceMeters,
            durationSeconds: workout.durationSeconds,
            averagePaceSecondsPerKm: Self.averagePaceSecondsPerKm(
                distanceMeters: workout.distanceMeters,
                durationSeconds: workout.durationSeconds
            ),
            routePreviewPayload: FeedShareDraftRoutePreviewPayload(
                routeExists: workout.distanceMeters != nil,
                distanceText: distanceText,
                fallbackStyleRawValue: fallbackStyle.rawValue
            ),
            photoPlaceholders: [
                FeedPhotoPlaceholder(title: "오늘의 기록", tone: Self.photoTone(for: workout.workoutType))
            ],
            tags: [Self.sportTitle(for: workout.workoutType), "기록", "SOOM"],
            visibility: .draft,
            createdAt: dateProvider()
        )
    }

    private static func averagePaceSecondsPerKm(
        distanceMeters: Double?,
        durationSeconds: TimeInterval
    ) -> Int? {
        guard let distanceMeters, distanceMeters > 0, durationSeconds > 0 else {
            return nil
        }

        return Int((durationSeconds / (distanceMeters / 1_000)).rounded())
    }

    private static func distanceText(_ meters: Double?) -> String? {
        guard let meters, meters > 0 else {
            return nil
        }

        return String(format: "%.1f km", meters / 1_000)
    }

    private static func sportTitle(for workoutType: UnifiedWorkoutType) -> String {
        switch workoutType {
        case .cycling:
            return "라이딩"
        case .running:
            return "러닝"
        case .walking:
            return "걷기"
        case .hiking:
            return "하이킹"
        case .swimming:
            return "수영"
        case .strength:
            return "근력"
        case .yoga:
            return "요가"
        case .other:
            return "운동"
        }
    }

    private static func photoTone(for workoutType: UnifiedWorkoutType) -> FeedPhotoTone {
        switch workoutType {
        case .cycling, .swimming:
            return .water
        case .running, .walking:
            return .city
        case .hiking:
            return .trail
        case .strength, .yoga, .other:
            return .morning
        }
    }
}

enum RecordPostSaveShareAction: Equatable {
    case shareToFeed
    case later
}

struct RecordShareDraftCoordinator {
    let builder: FeedShareDraftBuilder
    let store: any FeedShareDraftStoreProtocol

    init(
        builder: FeedShareDraftBuilder = FeedShareDraftBuilder(),
        store: any FeedShareDraftStoreProtocol
    ) {
        self.builder = builder
        self.store = store
    }

    func handle(_ action: RecordPostSaveShareAction, workout: UnifiedWorkout) async throws -> FeedShareDraft? {
        switch action {
        case .shareToFeed:
            let draft = builder.build(from: workout)
            try await store.saveDraft(draft)
            return draft
        case .later:
            return nil
        }
    }
}
