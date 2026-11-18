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

                        Label(companions.isEmpty ? "함께한 사람 추가" : "함께한 사람 편집", soomIcon: SOOMIcon.personAdd)
                            .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
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
                    .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SOOMLayout.Metrics.actionTextSpacing)
                    .background(SOOMColor.warning.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.compactControl, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("태그")
        .accessibilityValue(companions.joined(separator: ", "))
    }
}

struct WorkoutCompanionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool

    let tint: Color
    @StateObject private var model: WorkoutCompanionEditor

    init(initialNames: [String], tint: Color, canAccess: @escaping () -> Bool = { true },
         onSave: @escaping ([String]) async -> WorkoutCompanionUpdateResult) {
        self.tint = tint
        _model = StateObject(wrappedValue: WorkoutCompanionEditor(initialNames: initialNames, canAccess: canAccess, onSave: onSave))
    }
    init(model: WorkoutCompanionEditor, tint: Color) {
        self.tint = tint; _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
            SOOMScreen {
                SOOMCard {
                    SOOMSectionHeader("함께한 사람", caption: "기록되지 않은 사람도 이름으로 추가할 수 있어요.")

                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing))
                        : AnyLayout(HStackLayout(spacing: SOOMLayout.Metrics.actionTextSpacing))
                    layout {
                        TextField("이름 입력", text: $model.newName)
                            .focused($nameFocused)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addName)
                            .accessibilityLabel("함께한 사람 이름 입력")

                        Button("추가", action: addName)
                            .frame(minHeight: 44)
                            .buttonStyle(.borderedProminent)
                            .disabled(WorkoutCompanionNameEditing.normalized(model.newName) == nil)
                    }

                    if !model.names.isEmpty {
                        companionChips
                    }
                }
            }
            .disabled(model.isSaving)
            .safeAreaInset(edge: .bottom) {
                if let message = model.errorMessage {
                    SOOMBoundedFeedback(maxHeight: max(80, viewport.size.height * 0.30)) {
                        SOOMActionFeedback(title: "함께한 사람을 저장하지 못했어요", message: message + " 이름 초안은 그대로 있어요. 다시 저장해 주세요.", isError: true)
                    }
                        .padding(SOOMLayout.screenPadding)
                        .background(SOOMColor.background)
                        .accessibilityIdentifier("companions.save.failure")
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .navigationTitle("함께한 사람")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("완료") { nameFocused = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }.disabled(model.isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isSaving ? "저장 중" : "저장") {
                        nameFocused = false
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                }
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
            ForEach(model.names, id: \.self) { name in
                HStack(spacing: 4) {
                    Text(name)
                        .font(SOOMFont.body(14, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(tint)

                    Button {
                        model.removeName(name)
                    } label: {
                        Image(soom: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .frame(minWidth: 44, minHeight: 44)
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
        model.addName()
    }
}
