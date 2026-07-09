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

    func testRouteFileExtensionsAreAcceptedCaseInsensitively() {
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.gpx")))
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.GPX")))
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.fit")))
        XCTAssertTrue(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.FIT")))
    }

    func testUnsupportedRouteFileExtensionIsRejected() {
        XCTAssertFalse(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.xml")))
        XCTAssertFalse(ActivityDetailGPXRouteFileImport.isSupportedFileURL(URL(fileURLWithPath: "/tmp/route.tcx")))
    }

    func testRouteFileFormatDetection() {
        XCTAssertEqual(ActivityDetailGPXRouteFileImport.routeFileFormat(for: URL(fileURLWithPath: "/tmp/route.gpx")), .gpx)
        XCTAssertEqual(ActivityDetailGPXRouteFileImport.routeFileFormat(for: URL(fileURLWithPath: "/tmp/route.fit")), .fit)
        XCTAssertNil(ActivityDetailGPXRouteFileImport.routeFileFormat(for: URL(fileURLWithPath: "/tmp/route.tcx")))
    }

    func testGPXAttachmentErrorsMapToDisplayErrors() {
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .invalidGPX(.malformedXML)),
            .invalidGPX
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: GPXRouteAttachmentError.routeTooShort),
            .routeTooShort
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: GPXRouteAttachmentError.alreadyHasRoute),
            .alreadyHasRoute
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: GPXRouteAttachmentError.unsupportedSource(.soomLocal)),
            .unsupportedWorkoutSource
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: GPXRouteAttachmentError.persistenceFailed),
            .persistenceFailed
        )
    }

    func testFITAttachmentErrorsMapToDisplayErrors() {
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: .invalidFIT(.invalidHeader)),
            .invalidGPX
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: FITRouteAttachmentError.routeTooShort),
            .routeTooShort
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: FITRouteAttachmentError.alreadyHasRoute),
            .alreadyHasRoute
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: FITRouteAttachmentError.unsupportedSource(.soomLocal)),
            .unsupportedWorkoutSource
        )
        XCTAssertEqual(
            ActivityDetailGPXRouteImportError(attachmentError: FITRouteAttachmentError.persistenceFailed),
            .persistenceFailed
        )
    }

    func testDisplayErrorMessagesUseCalmKoreanCopy() {
        XCTAssertEqual(ActivityDetailGPXRouteImportError.unsupportedFileType.message, "GPX 또는 FIT 파일만 가져올 수 있습니다.")
        XCTAssertEqual(ActivityDetailGPXRouteImportError.unreadableFile.message, "경로 파일을 읽을 수 없습니다.")
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
