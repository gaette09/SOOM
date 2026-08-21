import Foundation

struct WorkoutCompanionUpdateAction {
    let updateCompanions: ([String]) async -> WorkoutCompanionUpdateResult
}

enum WorkoutCompanionUpdateResult: Equatable {
    case success([String])
    case failure(WorkoutCompanionUpdateError)
}

enum WorkoutCompanionUpdateError: Equatable {
    case persistenceFailed

    var message: String {
        switch self {
        case .persistenceFailed:
            return "동승자 태그를 저장하지 못했습니다."
        }
    }
}

/// Free-text companion name entry rules (batch 8) — no `profiles`/`follows`
/// lookup, so validation is purely local formatting, not identity matching.
enum WorkoutCompanionNameEditing {
    static let maximumNameLength = 20
    static let maximumCompanionCount = 10

    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumNameLength))
    }

    static func adding(_ raw: String, to names: [String]) -> [String] {
        guard let normalized = normalized(raw) else { return names }
        guard !names.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return names
        }
        guard names.count < maximumCompanionCount else { return names }
        return names + [normalized]
    }

    static func removing(_ name: String, from names: [String]) -> [String] {
        names.filter { $0 != name }
    }
}
