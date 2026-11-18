import XCTest
@testable import SOOM

final class ApprovedWorkoutMapRepairTests: XCTestCase {
    func testPrivateOwnerSpecificRepairRequiresPrivateQA() throws {
        throw XCTSkip("Owner-specific repair and private route fixtures are excluded from the public snapshot.")
    }
}
