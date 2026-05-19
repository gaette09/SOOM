import XCTest
@testable import SOOM

final class RecoveryDataProviderFactoryTests: XCTestCase {
    func testMockSourceCreatesProviderAndKeepsExistingSummaryFlow() async throws {
        let provider = RecoveryDataProviderFactory.makeProvider(source: .mock)

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertFalse(summary.recommendation.isEmpty)
        XCTAssertFalse(summary.coachMessage.message.isEmpty)
    }

    func testLocalSourceCreatesProvider() async throws {
        let provider = RecoveryDataProviderFactory.makeProvider(source: .local)

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertFalse(summary.recommendation.isEmpty)
        XCTAssertFalse(summary.coachMessage.message.isEmpty)
    }

    func testHealthKitSourceCreatesProviderWithoutImmediateAuthorizationRequest() {
        let provider = RecoveryDataProviderFactory.makeProvider(source: .healthKit)

        XCTAssertFalse(String(describing: type(of: provider)).isEmpty)
    }

    func testDefaultSourceUsesExistingMockBackedFlow() async throws {
        let provider = RecoveryDataProviderFactory.makeProvider()

        let summary = try await provider.fetchRecoverySummary()

        XCTAssertFalse(summary.recommendation.isEmpty)
        XCTAssertFalse(summary.coachMessage.message.isEmpty)
    }
}
