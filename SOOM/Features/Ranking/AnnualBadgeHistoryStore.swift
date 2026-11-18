import Foundation

/// Local estimates only. No method promotes an estimate to an earned badge.
@MainActor final class AnnualBadgeHistoryStore {
    struct Context: Equatable { let ownerID: UUID; let generation: Int }
    struct Estimate: Codable, Equatable {
        let ownerID: UUID
        let year: Int
        let points: Double
        let calculatedAt: Date
        let status: String
    }
    enum Failure: Error { case accountChanged, invalidEstimate }
    private let pinned: Context
    private let context: () -> Context?
    private let url: URL
    init(context initial: Context, directory: URL? = nil, current: @escaping () -> Context?) {
        pinned = initial; context = current
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HealthAccounts/\(initial.ownerID.uuidString.lowercased())")
        url = base.appendingPathComponent("annual-badge-estimates-v1.json")
    }
    private func active() throws {
        guard context() == pinned else { throw Failure.accountChanged }
    }
    func read() throws -> [Estimate] {
        try active()
        return try AccountDeletionWriteFence.shared.withActiveScope(pinned.ownerID) {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let rows = try JSONDecoder().decode([Estimate].self, from: Data(contentsOf: url))
            guard rows.allSatisfy({ $0.ownerID == pinned.ownerID && $0.status == "provisional" && $0.points.isFinite && $0.points >= 0 }), Set(rows.map(\.year)).count == rows.count else { throw Failure.invalidEstimate }
            return rows.sorted { $0.year > $1.year }
        }
    }
    func save(_ result: AnnualBadgeScoring.Result, at: Date = Date()) throws {
        try active()
        guard result.points.isFinite, result.points >= 0 else { throw Failure.invalidEstimate }
        var rows = try read().filter { $0.year != result.year }
        try AccountDeletionWriteFence.shared.withActiveScope(pinned.ownerID) {
            rows.append(Estimate(ownerID:pinned.ownerID,year:result.year,points:result.points,calculatedAt:at,status:"provisional"))
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(rows).write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            var values=URLResourceValues();values.isExcludedFromBackup=true
            var file=url;try file.setResourceValues(values)
        }
    }
}
