import SwiftUI

struct WorkoutSheetHandleButton: View {
    @Binding var sheetPosition: WorkoutSheetPosition

    var body: some View {
        Button {
            withAnimation(.spring(response: SOOMLayout.DetailSheet.handleSpringResponse, dampingFraction: SOOMLayout.DetailSheet.handleSpringDamping)) {
                sheetPosition = sheetPosition == .minimized ? .standard : .expanded
            }
        } label: {
            Capsule()
                .fill(SOOMColor.line)
                .frame(width: SOOMLayout.DetailSheet.handleWidth, height: SOOMLayout.DetailSheet.handleHeight)
                .padding(.vertical, SOOMLayout.DetailSheet.handleVerticalPadding)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("상세 정보 시트")
        .accessibilityHint("두 번 탭하면 상세 정보를 펼치거나 접습니다.")
    }
}

struct WorkoutSheetHeader: View {
    @Environment(\.workoutManagement) private var management
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let title: String
    let onCollapse: () -> Void
    var sharedPostManagement: FeedPostManagement? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SOOMLayout.DetailSheet.headerSpacing) {
                Button(action: onCollapse) {
                    Image(soom: SOOMIcon.collapse)
                        .font(.system(size: SOOMLayout.DetailSheet.headerCollapseIconSize, weight: .semibold))
                        .foregroundStyle(SOOMColor.ink)
                        .frame(width: max(44, SOOMLayout.DetailSheet.headerButtonSize), height: max(44, SOOMLayout.DetailSheet.headerButtonSize))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Keep native button activation and its accessible hit target.
                // A downward drag here also collapses from a scrolled body.
                .simultaneousGesture(DragGesture(minimumDistance: SOOMLayout.DetailSheet.dragMinimumDistance)
                    .onEnded { value in
                        if value.translation.height > SOOMLayout.DetailSheet.dragMinimumDistance { onCollapse() }
                    })
                .accessibilityLabel("상세 정보 접기")
                .accessibilityIdentifier("workout.detail.collapse")
                .accessibilityHint("상세 레이어를 중앙 위치로 내립니다.")

                Spacer()

                HStack(spacing: SOOMLayout.DetailSheet.titleSpacing) {
                    SOOMSportIconView(name: workout.sport.iconName, size: SOOMLayout.DetailSheet.headerIconSize)
                    Text(title)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                }
                .foregroundStyle(SOOMColor.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title) 상세")

                Spacer()

                if let management {
                    WorkoutManagementButtons(model: management, onDelete: { dismiss() })
                } else if let sharedPostManagement {
                    FeedPostManagementButtons(model:sharedPostManagement,onDelete:{ dismiss() })
                }
            }
            .padding(.horizontal, SOOMLayout.DetailSheet.headerHorizontalPadding)
            .padding(.top, SOOMLayout.DetailSheet.headerTopPadding)
            .padding(.bottom, SOOMLayout.DetailSheet.headerBottomPadding)

            Divider()
                .overlay(SOOMColor.line)
        }
        .background(SOOMColor.background)
    }
}
