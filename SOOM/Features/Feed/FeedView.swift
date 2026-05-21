import SwiftUI

struct FeedView: View {
    let items: [FeedItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    init(items: [FeedItem] = FeedMockData.items) {
        self.items = items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        SOOMScreen {
            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                Text("피드")
                    .font(SOOMFont.display(38, relativeTo: .largeTitle))
                    .foregroundStyle(SOOMColor.ink)

                Text("서로의 기록을 비교하기보다, 각자의 리듬과 성장을 차분히 나누는 공간입니다.")
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                emptyState
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FeedItemCard(item: item)
                        .feedCardReveal(
                            index: index,
                            isVisible: hasAppeared,
                            reduceMotion: reduceMotion
                        )
                }
            }
        }
        .navigationTitle("피드")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasAppeared = true
        }
    }

    private var emptyState: some View {
        SOOMCard {
            SOOMSectionHeader("아직 공유된 기록이 없어요", caption: "운동 공유 카드가 생기면 여기에서 성장 흐름을 볼 수 있어요.")
            Text("SOOM 피드는 랭킹보다 꾸준함과 회복 친화적인 선택을 나누는 방향으로 준비하고 있습니다.")
                .font(SOOMFont.body(15, relativeTo: .subheadline))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("피드 빈 상태")
    }
}

#Preview("FeedView") {
    NavigationStack {
        FeedView()
    }
    .preferredColorScheme(.light)
}

private extension View {
    func feedCardReveal(index: Int, isVisible: Bool, reduceMotion: Bool) -> some View {
        opacity(isVisible ? SOOMMotion.Opacity.visible : SOOMMotion.Opacity.hidden)
            .offset(y: reduceMotion || isVisible ? 0 : SOOMMotion.Offset.cardRevealY)
            .animation(
                reduceMotion
                    ? nil
                    : SOOMMotion.normalEaseOut.delay(Double(index) * 0.035),
                value: isVisible
            )
    }
}
