import XCTest
@testable import SOOM

final class HealthKitWorkoutLookupProviderTests: XCTestCase {
    func testInvalidExternalIdReturnsNilWithoutQueryingHealthKit() async {
        let provider = HealthKitWorkoutLookupProvider()

        let workout = await provider.lookupWorkout(externalId: "not-a-uuid")

        XCTAssertNil(workout)
    }
}
