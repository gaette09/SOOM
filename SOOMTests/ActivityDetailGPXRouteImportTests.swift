import XCTest
@testable import SOOM

final class ActivityDetailGPXRouteImportTests: XCTestCase {
    func testHealthKitImportedMissingRouteWorkoutCanAttachGPXRoute() {
        let workout = makeWorkout(source: .appleHealthKit, routeMissingReason: .externalSourceRouteNotShared)

        XCTAssertTrue(
            ActivityDetailGPXRouteImportEligibility.canAttachGPXRoute(
                to: workout,
                hasRoute: false
            )
        )
    }

    func testLocalRecordMissingRouteWorkoutCannotAttachGPXRoute() {
        let workout = makeWorkout(source: .soomLocal, routeMissingReason: .healthKitRouteUnavailable)

        XCTAssertFalse(
            ActivityDetailGPXRouteImportEligibility.canAttachGPXRoute(
                to: workout,
                hasRoute: false
            )
        )
    }

    func testRouteBackedImportedWorkoutCannotAttachGPXRouteByDefault() {
        let workout = makeWorkout(source: .appleHealthKit, routeMissingReason: .externalSourceRouteNotShared)

        XCTAssertFalse(
            ActivityDetailGPXRouteImportEligibility.canAttachGPXRoute(
                to: workout,
                hasRoute: true
            )
        )
    }

    func testNonActionableRouteMissingReasonCannotAttachGPXRoute() {
        let workout = makeWorkout(source: .appleHealthKit, routeMissingReason: .none)

        XCTAssertFalse(
            ActivityDetailGPXRouteImportEligibility.canAttachGPXRoute(
                to: workout,
                hasRoute: false
            )
        )
    }

    func testGPXFileExtensionIsAcceptedCaseInsensitively() {
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.gpx")))
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.GPX")))
    }

    func testNonGPXFileExtensionIsRejected() {
        XCTAssertFalse(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.fit")))
        XCTAssertFalse(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.xml")))
    }

    func testAttachmentErrorsMapToDisplayErrors() {
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .invalidGPX(.malformedXML)),
            .invalidGPX
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .routeTooShort),
            .routeTooShort
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .alreadyHasRoute),
            .alreadyHasRoute
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .unsupportedSource(.soomLocal)),
            .unsupportedWorkoutSource
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .persistenceFailed),
            .persistenceFailed
        )
    }

    func testDisplayErrorMessagesUseCalmKoreanCopy() {
        XCTAssertEqual(ActivityDetailGPXRouteImportError.unreadableFile.message, "GPX 파일을 읽을 수 없습니다.")
        XCTAssertEqual(ActivityDetailGPXRouteImportError.routeTooShort.message, "경로 좌표가 충분하지 않습니다.")
        XCTAssertEqual(ActivityDetailGPXRouteImportError.alreadyHasRoute.message, "이미 경로가 있는 운동입니다.")
    }

    private func makeWorkout(
        source: UnifiedDataSource,
        routeMissingReason: WorkoutRouteMissingReason
    ) -> UnifiedWorkout {
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        return UnifiedWorkout(
            id: UUID(),
            externalId: UUID().uuidString,
            source: source,
            workoutType: .cycling,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 25_000,
            activeEnergyKcal: 600,
            averageHeartRate: nil,
            maxHeartRate: nil,
            averageSpeedMetersPerSecond: nil,
            elevationGainMeters: nil,
            routeMissingReason: routeMissingReason,
            dataQuality: .partial,
            createdAt: startDate,
            updatedAt: startDate
        )
    }
}
