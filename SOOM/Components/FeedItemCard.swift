import SwiftUI

struct FeedItemCard: View {
    let item: FeedItem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        SOOMCard {
            header

            if let caption = item.caption {
                Text(caption)
                    .font(SOOMFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .lineSpacing(SOOMLayout.RecoveryAI.messageLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            cardPreview
                .padding(.top, SOOMLayout.SectionHeader.spacing)
        }
        .scaleEffect(isPressed && !reduceMotion ? SOOMMotion.Scale.pressed : 1)
        .opacity(isPressed && !reduceMotion ? SOOMMotion.Opacity.muted + 0.22 : 1)
        .animation(reduceMotion ? nil : SOOMMotion.quickEaseOut, value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        .simultaneousGesture(pressGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.authorName)의 \(item.itemType.title) 피드")
        .accessibilityValue(accessibilitySummary)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: SOOMLayout.Metrics.actionRowSpacing) {
            ZStack {
                Circle()
                    .fill(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))

                Text(initial)
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .foregroundStyle(tint)
            }
            .frame(width: SOOMLayout.Metrics.actionIconFrame, height: SOOMLayout.Metrics.actionIconFrame)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SOOMLayout.SectionHeader.spacing) {
                HStack(spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(item.authorName)
                        .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)

                    Text(item.itemType.title)
                        .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(tint)
                        .padding(.horizontal, SOOMLayout.Metrics.tagHorizontalPadding)
                        .padding(.vertical, SOOMLayout.Metrics.tagVerticalPadding * 0.7)
                        .background(tint.opacity(SOOMLayout.Metrics.actionIconBackgroundOpacity))
                        .clipShape(Capsule())
                }

                Text(metaText)
                    .font(SOOMFont.body(12, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.tertiaryInk)
            }

            Spacer()

            ShareablePrivacyBadge(title: item.visibility.title, tint: tint)
                .accessibilityLabel("공개 범위 미리보기")
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, state, _ in
                state = true
            }
    }

    @ViewBuilder
    private var cardPreview: some View {
        switch item.cardData {
        case .workoutSession(let card):
            ShareableWorkoutCardView(card: card, tint: tint)
        case .weeklyProgress(let card):
            ShareableWeeklyProgressCardView(card: card, tint: tint)
        }
    }

    private var tint: Color {
        switch item.cardData {
        case .workoutSession(let card):
            return card.workoutType.feedTint
        case .weeklyProgress:
            return SOOMColor.bike
        }
    }

    private var initial: String {
        String(item.authorName.prefix(1))
    }

    private var metaText: String {
        let handle = item.authorHandle.map { "\($0) · " } ?? ""
        return "\(handle)\(relativeTimeText)"
    }

    private var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.createdAt, relativeTo: Date(timeIntervalSince1970: 1_800_480_000))
    }

    private var accessibilitySummary: String {
        switch item.cardData {
        case .workoutSession(let card):
            return "\(card.title). \(card.distanceText), \(card.durationText). \(card.primaryMessage)"
        case .weeklyProgress(let card):
            return "\(card.weekLabel). \(card.workoutCountText), \(card.totalDistanceText), \(card.totalDurationText). \(card.progressMessage)"
        }
    }
}

private extension UnifiedWorkoutType {
    var feedTint: Color {
        switch self {
        case .running:
            return SOOMColor.run
        case .cycling:
            return SOOMColor.bike
        case .swimming:
            return SOOMColor.swim
        case .walking, .hiking, .strength, .yoga, .other:
            return SOOMColor.green
        }
    }
}

#Preview("FeedItemCard") {
    SOOMScreen {
        FeedItemCard(item: FeedMockData.items[0])
    }
    .preferredColorScheme(.light)
}
