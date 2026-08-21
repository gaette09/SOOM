import SwiftUI

struct WorkoutCompanionCard: View {
    let sourceTag: String
    let companions: [String]
    let tint: Color
    let canEditCompanions: Bool
    let isUpdating: Bool
    let errorMessage: String?
    let onTapEdit: () -> Void

    var body: some View {
        SOOMCard {
            SOOMSectionHeader("태그")

            FlowTags(tags: [sourceTag], tint: tint)

            if !companions.isEmpty {
                FlowTags(tags: companions, tint: SOOMColor.secondaryInk)
            }

            if canEditCompanions {
                Button(action: onTapEdit) {
                    HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        if isUpdating {
                            ProgressView()
                                .tint(SOOMColor.secondaryInk)
                                .accessibilityHidden(true)
                        }

                        Label(companions.isEmpty ? "함께한 사람 추가" : "함께한 사람 편집", systemImage: SOOMIcon.personAdd)
                            .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SOOMLayout.Metrics.pillPadding)
                    .foregroundStyle(SOOMColor.ink)
                    .background(SOOMColor.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel(companions.isEmpty ? "함께한 사람 추가" : "함께한 사람 편집")
                .accessibilityHint("이 운동을 함께한 사람을 자유 텍스트로 추가하거나 제거합니다.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SOOMLayout.Metrics.actionTextSpacing)
                    .background(SOOMColor.warning.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("태그")
        .accessibilityValue(([sourceTag] + companions).joined(separator: ", "))
    }
}

struct WorkoutCompanionEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let tint: Color
    let onSave: ([String]) async -> Void

    @State private var names: [String]
    @State private var newName = ""
    @State private var isSaving = false

    init(initialNames: [String], tint: Color, onSave: @escaping ([String]) async -> Void) {
        self.tint = tint
        self.onSave = onSave
        _names = State(initialValue: initialNames)
    }

    var body: some View {
        NavigationStack {
            SOOMScreen {
                SOOMCard {
                    SOOMSectionHeader("함께한 사람", caption: "기록되지 않은 사람도 이름으로 추가할 수 있어요.")

                    HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                        TextField("이름 입력", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addName)
                            .accessibilityLabel("함께한 사람 이름 입력")

                        Button("추가", action: addName)
                            .buttonStyle(.borderedProminent)
                            .disabled(WorkoutCompanionNameEditing.normalized(newName) == nil)
                    }

                    if !names.isEmpty {
                        companionChips
                    }
                }
            }
            .navigationTitle("함께한 사람")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "저장 중" : "저장") {
                        Task {
                            isSaving = true
                            await onSave(names)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var companionChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: SOOMLayout.Metrics.tagMinWidth), spacing: SOOMLayout.Metrics.tagSpacing)],
            alignment: .leading,
            spacing: SOOMLayout.Metrics.tagSpacing
        ) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 4) {
                    Text(name)
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(tint)

                    Button {
                        names = WorkoutCompanionNameEditing.removing(name, from: names)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(tint.opacity(0.6))
                    }
                    .accessibilityLabel("\(name) 삭제")
                }
                .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
        }
    }

    private func addName() {
        names = WorkoutCompanionNameEditing.adding(newName, to: names)
        newName = ""
    }
}
