import SwiftUI

struct SOOMSectionHeader: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
            Text(title)
                .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                .foregroundStyle(SOOMColor.ink)

            if let caption {
                Text(caption)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }
        }
    }
}

#Preview("SOOMSectionHeader") {
    VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
        SOOMSectionHeader("운동 요약", caption: "초보자도 이해할 수 있는 한 줄 설명")
        SOOMSectionHeader("그래프")
    }
    .padding(SOOMLayout.screenPadding)
    .background(SOOMColor.background)
    .preferredColorScheme(.light)
}
