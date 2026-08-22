import XCTest
@testable import SOOM

@MainActor
final class LocalAccountDataEraserTests: XCTestCase {
    func testEraseAllCallsEveryStoreErasureClosure() async {
        var workoutsErased = false
        var routesErased = false
        var draftsErased = false
        var trainingSettingsErased = false
        var clubDataErased = false

        let eraser = LocalAccountDataEraser(
            eraseWorkouts: { workoutsErased = true },
            eraseWorkoutRoutes: { routesErased = true },
            eraseFeedDrafts: { draftsErased = true },
            eraseTrainingSettings: { trainingSettingsErased = true },
            eraseClubData: { clubDataErased = true }
        )

        await eraser.eraseAll()

        XCTAssertTrue(workoutsErased)
        XCTAssertTrue(routesErased)
        XCTAssertTrue(draftsErased)
        XCTAssertTrue(trainingSettingsErased)
        XCTAssertTrue(clubDataErased)
    }

    func testEraseAllContinuesPastAFailingStore() async {
        var routesErased = false
        var trainingSettingsErased = false

        let eraser = LocalAccountDataEraser(
            eraseWorkouts: { throw SampleError.failed },
            eraseWorkoutRoutes: { routesErased = true },
            eraseFeedDrafts: { throw SampleError.failed },
            eraseTrainingSettings: { trainingSettingsErased = true },
            eraseClubData: {}
        )

        await eraser.eraseAll()

        XCTAssertTrue(routesErased)
        XCTAssertTrue(trainingSettingsErased)
    }

    private enum SampleError: Error {
        case failed
    }
}
