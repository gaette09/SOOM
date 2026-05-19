import SwiftUI

private struct SOOMBottomOverlayInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var soomBottomOverlayInset: CGFloat {
        get { self[SOOMBottomOverlayInsetKey.self] }
        set { self[SOOMBottomOverlayInsetKey.self] = newValue }
    }
}

struct SOOMScreen<Content: View>: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SOOMColor.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SOOMLayout.screenPadding)
                    .padding(.top, SOOMLayout.Screen.topPadding)
                    .padding(.bottom, bottomOverlayInset + SOOMLayout.Screen.bottomPadding)
                }
            }
            .overlay(alignment: .top) {
                SOOMColor.background
                    .frame(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct SOOMCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Card.padding)
        .background(SOOMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous)
                .stroke(SOOMColor.line, lineWidth: SOOMLayout.Card.borderWidth)
        )
    }
}

#Preview("SOOMCard") {
    SOOMScreen {
        SOOMCard {
            SOOMSectionHeader("카드 제목", caption: "반복되는 표면, 여백, 라인을 통합합니다.")
            Text("SOOMCard는 화면 전반의 기본 카드 패턴입니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
    }
    .preferredColorScheme(.light)
}
