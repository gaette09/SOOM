import Foundation
@testable import SOOM

final class MockDeviceTokenRegistrar: DeviceTokenRegistering, @unchecked Sendable {
    private(set) var upsertCalls: [(tokenHex: String, userId: UUID)] = []
    private(set) var deleteCalls: [String] = []
    var deleteError: Error?
    var onUpsert: (() -> Void)?

    func upsert(tokenHex: String, userId: UUID) async throws {
        upsertCalls.append((tokenHex, userId))
        onUpsert?()
    }

    func deleteToken(tokenHex: String) async throws {
        deleteCalls.append(tokenHex)
        if let deleteError {
            throw deleteError
        }
    }
}
