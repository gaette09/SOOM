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
    let workout: Workout
    let title: String
    let onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SOOMLayout.DetailSheet.headerSpacing) {
                Button(action: onCollapse) {
                    Image(systemName: SOOMIcon.collapse)
                        .font(.system(size: SOOMLayout.DetailSheet.headerCollapseIconSize, weight: .semibold))
                        .foregroundStyle(SOOMColor.ink)
                        .frame(width: SOOMLayout.DetailSheet.headerButtonSize, height: SOOMLayout.DetailSheet.headerButtonSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("상세 정보 접기")
                .accessibilityHint("상세 레이어를 중앙 위치로 내립니다.")

                Spacer()

                HStack(spacing: SOOMLayout.DetailSheet.titleSpacing) {
                    Image(systemName: workout.sport.iconName)
                        .font(.system(size: SOOMLayout.DetailSheet.headerIconSize, weight: .bold))
                    Text(title)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                }
                .foregroundStyle(SOOMColor.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title) 상세")

                Spacer()

                HStack(spacing: SOOMLayout.DetailSheet.headerTrailingSpacing) {
                    SheetHeaderButton(icon: SOOMIcon.bookmark, accessibilityLabel: "경로 저장")
                    SheetHeaderButton(icon: SOOMIcon.more, accessibilityLabel: "더보기")
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

private struct SheetHeaderButton: View {
    let icon: String
    let accessibilityLabel: String

    var body: some View {
        Button {
        } label: {
            Image(systemName: icon)
                .font(.system(size: icon == SOOMIcon.more ? SOOMLayout.DetailSheet.headerMoreIconSize : SOOMLayout.DetailSheet.headerActionIconSize, weight: icon == SOOMIcon.more ? .bold : .semibold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: SOOMLayout.DetailSheet.headerTrailingButtonSize, height: SOOMLayout.DetailSheet.headerTrailingButtonSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
