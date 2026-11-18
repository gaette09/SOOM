import XCTest
import Supabase
@testable import SOOM

final class GoogleHealthWorkoutPayloadTests: XCTestCase {
    func testReconciledRunningSessionUsesGoogleUnitsAndStableIdentity() throws {
        let json = """
        {
          "workouts": [{
            "name": "users/abc123/dataTypes/exercise/dataPoints/workout-1",
            "exercise": {
              "interval": {"startTime":"2026-09-20T06:00:00.123Z","endTime":"2026-09-20T07:10:00.123Z"},
              "exerciseType":"RUNNING", "displayName":"아침 달리기", "activeDuration":"4000s",
              "metricsSummary":{"distanceMillimeters":10030000,"caloriesKcal":656,"averageSpeedMillimetersPerSecond":2507.5,"averageHeartRateBeatsPerMinute":"144","elevationGainMillimeters":79000},
              "exerciseMetadata":{"hasGps":true}
            },
            "device_name":"Pixel Watch"
          }], "next_page_token":null
        }
        """
        let page = try JSONDecoder().decode(GoogleHealthWorkoutPage.self, from: Data(json.utf8))
        let first = try XCTUnwrap(page.workouts[0].makeWorkout(now: Date(timeIntervalSince1970: 1_900_000_000)))
        let repeated = try XCTUnwrap(page.workouts[0].makeWorkout(now: Date(timeIntervalSince1970: 1_900_000_001)))
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.source, .googleHealth)
        XCTAssertFalse(first.externalId?.contains("abc123") ?? true)
        XCTAssertEqual(first.workoutType, .running)
        XCTAssertEqual(first.durationSeconds, 4000)
        XCTAssertEqual(first.distanceMeters, 10030)
        XCTAssertEqual(first.averageSpeedMetersPerSecond ?? 0, 2.5075, accuracy: 0.0001)
        XCTAssertEqual(first.averageHeartRate, 144)
        XCTAssertEqual(first.elevationGainMeters, 79)
        XCTAssertEqual(first.routeMissingReason, .externalSourceRouteNotShared)
        XCTAssertEqual(first.deviceName, "Pixel Watch")
    }

    func testReimportRefreshesSourceMetricsButPreservesSOOMPrivacyAndEdits() throws {
        func payload(distance: Int) throws -> GoogleHealthWorkoutPayload {
            let json = """
            {"workouts":[{"name":"users/abc/dataTypes/exercise/dataPoints/ride-1",
              "exercise":{"interval":{"startTime":"2026-09-20T06:00:00Z","endTime":"2026-09-20T07:00:00Z"},
              "exerciseType":"BIKING","displayName":"Morning Ride",
              "metricsSummary":{"distanceMillimeters":\(distance)}}}],"next_page_token":null}
            """
            return try JSONDecoder().decode(GoogleHealthWorkoutPage.self, from: Data(json.utf8)).workouts[0]
        }
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let original = try XCTUnwrap(payload(distance: 10_000_000).makeWorkout(now: now))
        var edited = original
        edited.userTitle = "내가 고친 제목"
        edited.userDescription = "내 메모"
        edited.sharingVisibilityRaw = "private"
        edited.isBookmarked = true
        edited.locationName = "서울특별시"
        edited.deviceName = "내 자전거"
        XCTAssertNil(try payload(distance: 10_000_000).refreshedWorkout(from: edited, now: now))
        let updated = try XCTUnwrap(payload(distance: 12_000_000).refreshedWorkout(from: edited, now: now))
        XCTAssertEqual(updated.id, edited.id)
        XCTAssertEqual(updated.distanceMeters, 12_000)
        XCTAssertEqual(updated.userTitle, "내가 고친 제목")
        XCTAssertEqual(updated.userDescription, "내 메모")
        XCTAssertEqual(updated.sharingVisibilityRaw, "private")
        XCTAssertEqual(updated.isBookmarked, true)
        XCTAssertEqual(updated.locationName, "서울특별시")
        XCTAssertEqual(updated.deviceName, "내 자전거")
        XCTAssertEqual(updated.createdAt, edited.createdAt)
    }

    func testMalformedOrFutureSessionCannotBeImported() throws {
        let json = """
        {"workouts":[{"name":"users/abc123/dataTypes/exercise/dataPoints/1","exercise":{"interval":{"startTime":"2026-09-20T07:00:00Z","endTime":"2026-09-20T06:00:00Z"},"exerciseType":"BIKING"}}],"next_page_token":null}
        """
        let page = try JSONDecoder().decode(GoogleHealthWorkoutPage.self, from: Data(json.utf8))
        XCTAssertNil(page.workouts[0].makeWorkout())
        XCTAssertEqual(page.workouts[0].importRejectionReason(), "시간 순서")
    }
}


final class GoogleHealthHistoryCursorTests:XCTestCase {
    private func store() -> UserDefaults {UserDefaults(suiteName:"google-history-tests-"+UUID().uuidString)!}
    func testDurablePageResumeAcrossInstancesAndDuplicatePageIsIdempotent() {
        let defaults=store(),owner=UUID(),cursor=GoogleHealthHistoryCursor(owner:owner,scope:"A",request:"event:1:2020:2026:UPSERT",defaults:defaults)
        cursor.commitPage(next:"page-100");cursor.commitPage(next:"page-100")
        let reopened=GoogleHealthHistoryCursor(owner:owner,scope:"A",request:"event:1:2020:2026:UPSERT",defaults:defaults)
        XCTAssertEqual(reopened.load(),.init(token:"page-100",complete:false))
        // A failed page does not call commit, so retry starts from the same page.
        XCTAssertEqual(reopened.load()?.token,"page-100")
        reopened.commitPage(next:"page-101");XCTAssertEqual(cursor.load()?.token,"page-101")
    }
    func testOwnerScopeEventAndIntervalNeverReuseAnotherRequestsCursor() {
        let defaults=store(),owner=UUID()
        GoogleHealthHistoryCursor(owner:owner,scope:"A",request:"event:1:old",defaults:defaults).commitPage(next:"one")
        for cursor in [GoogleHealthHistoryCursor(owner:UUID(),scope:"A",request:"event:1:old",defaults:defaults),
            .init(owner:owner,scope:"B",request:"event:1:old",defaults:defaults),
            .init(owner:owner,scope:"A",request:"event:2:old",defaults:defaults),
            .init(owner:owner,scope:"A",request:"event:1:new",defaults:defaults),
            .init(owner:owner,scope:"A",request:"manual-all",defaults:defaults)] {XCTAssertNil(cursor.load())}
    }
    func testCompletedPageSupportsAckRetryAndResetAllowsFreshScan() {
        let cursor=GoogleHealthHistoryCursor(owner:UUID(),scope:"A",request:"event:1",defaults:store())
        cursor.commitPage(next:"last");cursor.commitPage(next:nil)
        XCTAssertEqual(cursor.load(),.init(token:nil,complete:true))
        // Completion is kept until ACK succeeds. Reset does not touch workout storage.
        cursor.reset();XCTAssertNil(cursor.load())
    }
    func testDisconnectClearsOnlyThatOwnersPaginationIncludingOldScopes() {
        let defaults=store(),owner=UUID(),other=UUID()
        let first=GoogleHealthHistoryCursor(owner:owner,scope:"A",request:"manual-all",defaults:defaults)
        let second=GoogleHealthHistoryCursor(owner:owner,scope:"B",request:"event:1",defaults:defaults)
        let untouched=GoogleHealthHistoryCursor(owner:other,scope:"A",request:"manual-all",defaults:defaults)
        for cursor in [first,second,untouched] {cursor.commitPage(next:"page")}
        first.clearOwner();XCTAssertNil(first.load());XCTAssertNil(second.load());XCTAssertEqual(untouched.load()?.token,"page")
    }
    func testMalformedNextCursorCannotReplaceLastSuccessfulPage() {
        let cursor=GoogleHealthHistoryCursor(owner:UUID(),scope:"A",request:"manual-all",defaults:store())
        cursor.commitPage(next:"valid");cursor.commitPage(next:"");cursor.commitPage(next:String(repeating:"x",count:4097))
        XCTAssertEqual(cursor.load()?.token,"valid")
    }
    func testOnlyExplicitCursorRejectionResetsNotNetworkPermissionOrServerFailure() {
        func error(_ code:Int,_ message:String)->Error {FunctionsError.httpError(code:code,data:Data("{\"error\":\"\(message)\"}".utf8))}
        XCTAssertTrue(GoogleHealthHistoryCursor.tokenWasRejected(error(409,"invalid_page_token")))
        XCTAssertFalse(GoogleHealthHistoryCursor.tokenWasRejected(error(503,"google_unavailable")))
        XCTAssertFalse(GoogleHealthHistoryCursor.tokenWasRejected(error(409,"reauthorize_required")))
        XCTAssertFalse(GoogleHealthHistoryCursor.tokenWasRejected(URLError(.timedOut)))
    }
}
