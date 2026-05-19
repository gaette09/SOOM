import SwiftUI

struct SOOMIconButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: SOOMLayout.IconButton.iconSize, weight: .semibold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: SOOMLayout.IconButton.size, height: SOOMLayout.IconButton.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("SOOMIconButton") {
    HStack {
        SOOMIconButton(icon: SOOMIcon.back, accessibilityLabel: "뒤로가기") {}
        SOOMIconButton(icon: SOOMIcon.bookmark, accessibilityLabel: "저장") {}
        SOOMIconButton(icon: SOOMIcon.more, accessibilityLabel: "더보기") {}
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
    .preferredColorScheme(.light)
}
