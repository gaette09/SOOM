import Foundation

protocol RecoveryCheckInStore {
    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn]
}

protocol RecoveryCheckInWritableStore: RecoveryCheckInStore {
    func saveCheckIn(_ checkIn: RecoveryCheckIn) async throws
}

protocol RecoveryCheckInEditableStore: RecoveryCheckInWritableStore {
    func updateCheckIn(_ checkIn: RecoveryCheckIn) async throws
    func deleteCheckIn(id: UUID) async throws
    func deleteAllCheckIns() async throws
}

final class MockRecoveryCheckInStore: RecoveryCheckInEditableStore {
    static let shared = MockRecoveryCheckInStore(checkIns: [])

    private let referenceDate: Date
    private var checkIns: [RecoveryCheckIn]

    init(referenceDate: Date = Date(), checkIns: [RecoveryCheckIn]? = nil) {
        self.referenceDate = referenceDate
        self.checkIns = checkIns ?? RecoveryCheckIn.mockRecent(referenceDate: referenceDate)
    }

    func fetchRecentCheckIns(days: Int) async throws -> [RecoveryCheckIn] {
        await Task.yield()

        guard days > 0 else { return [] }

        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return checkIns.filter { $0.date >= threshold }
    }

    func saveCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        await Task.yield()
        checkIns.append(checkIn)
    }

    func updateCheckIn(_ checkIn: RecoveryCheckIn) async throws {
        await Task.yield()

        guard let index = checkIns.firstIndex(where: { $0.id == checkIn.id }) else {
            return
        }

        checkIns[index] = checkIn
    }

    func deleteCheckIn(id: UUID) async throws {
        await Task.yield()
        checkIns.removeAll { $0.id == id }
    }

    func deleteAllCheckIns() async throws {
        await Task.yield()
        checkIns.removeAll()
    }
}
