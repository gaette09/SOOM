import Foundation
import Combine

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

@MainActor
final class WorkoutCompanionEditor: ObservableObject {
    @Published var names: [String]
    @Published var newName = ""
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    private let onSave: ([String]) async -> WorkoutCompanionUpdateResult
    private let canAccess: () -> Bool
    init(initialNames: [String], canAccess: @escaping () -> Bool = { true },
         onSave: @escaping ([String]) async -> WorkoutCompanionUpdateResult) {
        names = initialNames; self.canAccess = canAccess; self.onSave = onSave
    }
    func addName() { names = WorkoutCompanionNameEditing.adding(newName, to: names); newName = "" }
    func removeName(_ name: String) { names = WorkoutCompanionNameEditing.removing(name, from: names) }
    func save() async -> Bool {
        guard !isSaving else { return false }
        guard canAccess(), !Task.isCancelled else {
            errorMessage = "계정이 변경됐어요. 현재 계정에서 다시 열어 주세요."; return false
        }
        guard WorkoutCompanionNameEditing.normalized(newName) == nil else {
            errorMessage = "입력 중인 이름을 추가하거나 지운 뒤 저장해 주세요."; return false
        }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        let result = await onSave(names)
        guard canAccess(), !Task.isCancelled else { return false }
        switch result {
        case .success(let saved): names = saved; return true
        case .failure(let error): errorMessage = error.message; return false
        }
    }
}
