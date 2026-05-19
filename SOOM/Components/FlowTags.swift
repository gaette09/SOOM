import SwiftUI

struct FlowTags: View {
    let tags: [String]
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: SOOMLayout.Metrics.tagMinWidth), spacing: SOOMLayout.Metrics.tagSpacing)], alignment: .leading, spacing: SOOMLayout.Metrics.tagSpacing) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(tint)
                    .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                    .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding)
                    .frame(maxWidth: .infinity)
                    .background(tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
            }
        }
    }
}

#Preview("FlowTags") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("태그")
            FlowTags(tags: ["브릭", "회복", "러닝", "오픈워터", "주말 모임"], tint: SOOMColor.bike)
        }
    }
    .preferredColorScheme(.light)
}
