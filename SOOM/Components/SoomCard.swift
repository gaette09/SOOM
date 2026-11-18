import SwiftUI

/// Resolve the vertical scroll container before any image/row supplies an ideal width.
struct SOOMScrollContentLayout: Equatable {
    let viewportWidth: CGFloat
    let horizontalPadding: CGFloat

    init(viewportWidth: CGFloat, horizontalPadding: CGFloat) {
        let width = viewportWidth.isFinite ? max(0, viewportWidth) : 0
        let padding = horizontalPadding.isFinite ? max(0, horizontalPadding) : 0
        self.viewportWidth = width
        self.horizontalPadding = min(padding, width / 2)
    }

    var contentWidth: CGFloat { viewportWidth - 2 * horizontalPadding }
}

/// Reserve verified geometry while content is hidden for permission revalidation.
/// The measurement uses size, never a scrolling/global coordinate.
struct SOOMContentHeightReservation: Equatable {
    private(set) var verifiedSize: CGSize?

    mutating func record(_ size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return false }
        if let old = verifiedSize,
           abs(old.width - size.width) < 0.5, abs(old.height - size.height) < 0.5 { return false }
        verifiedSize = size
        return true
    }

    func height(forViewportWidth width: CGFloat?) -> CGFloat? {
        guard let size = verifiedSize else { return nil }
        guard let width else { return size.height }
        guard width.isFinite, width > 0, abs(size.width - width) < 0.5 else { return nil }
        return size.height
    }

    static func initialHeight(hasKnownMedia: Bool) -> CGFloat {
        // Reserve a card-sized loading slot, not a tiny row that triggers pagination early.
        224 + (hasKnownMedia ? 260 : 0)
    }
}

private struct SOOMScrollViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var soomScrollViewportWidth: CGFloat? {
        get { self[SOOMScrollViewportWidthKey.self] }
        set { self[SOOMScrollViewportWidthKey.self] = newValue }
    }
}

private struct SOOMBottomOverlayInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var soomBottomOverlayInset: CGFloat {
        get { self[SOOMBottomOverlayInsetKey.self] }
        set { self[SOOMBottomOverlayInsetKey.self] = newValue }
    }
}

/// Let scrolled media continue under transparent system chrome, with a soft
/// legibility fade rather than an opaque strip. Initial controls retain safe insets.
private struct SOOMScrollPaintingBounds: Shape {
    let topOverflow: CGFloat
    let bottomOverflow: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - max(0, topOverflow), width: rect.width,
                    height: rect.height + max(0, topOverflow) + max(0, bottomOverflow)))
    }
}

/// Opt-in observation belongs to this exact vertical ScrollView, not to
/// descendant photo pagers. The default path adds no scroll-target observer.
private struct SOOMScrollTargetVisibilityObserver: ViewModifier {
    let action: (([UUID]) -> Void)?
    @ViewBuilder func body(content: Content) -> some View {
        if let action {
            content.onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.1, action)
        } else {
            content
        }
    }
}

struct SOOMScreen<Content: View>: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    var tracksTabBarScroll = false
    var onVisibleScrollTargetIDs: (([UUID]) -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let layout = SOOMScrollContentLayout(viewportWidth: proxy.size.width,
                                                 horizontalPadding: SOOMLayout.screenPadding)
            ZStack {
                SOOMColor.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SOOMLayout.stackSpacing) {
                        content
                    }
                    .frame(width: layout.contentWidth, alignment: .leading)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, SOOMLayout.Screen.topPadding)
                    .padding(.bottom, bottomOverlayInset + SOOMLayout.Screen.bottomPadding)
                }
                .modifier(SOOMScrollTargetVisibilityObserver(action: onVisibleScrollTargetIDs))
                .scrollClipDisabled()
                .modifier(SOOMTabBarScrollTracking(enabled: tracksTabBarScroll))
                .frame(width: layout.viewportWidth)
                .clipShape(SOOMScrollPaintingBounds(topOverflow: proxy.safeAreaInsets.top, bottomOverflow: proxy.safeAreaInsets.bottom))
                .overlay(alignment: .top) {
                    LinearGradient(stops: [
                        .init(color: SOOMColor.background.opacity(0.98), location: 0),
                        .init(color: SOOMColor.background.opacity(0.98), location: 0.70),
                        .init(color: SOOMColor.background.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                        .frame(height: max(0, proxy.safeAreaInsets.top))
                        .offset(y: -max(0, proxy.safeAreaInsets.top))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .environment(\.soomScrollViewportWidth, layout.viewportWidth)

        }
    }
}

enum SOOMCardDepth {
    case primary
    case secondary
    case ambient

    var background: Color {
        switch self {
        case .primary:
            return SOOMColor.surfacePrimary
        case .secondary:
            return SOOMColor.surfacePrimary
        case .ambient:
            return SOOMColor.surfaceSecondary
        }
    }

    var borderOpacity: Double {
        switch self {
        case .primary:
            return 1
        case .secondary:
            return 0.72
        case .ambient:
            return 0.44
        }
    }
}

struct SOOMCard<Content: View>: View {
    let depth: SOOMCardDepth
    @ViewBuilder let content: Content

    init(depth: SOOMCardDepth = .secondary, @ViewBuilder content: () -> Content) {
        self.depth = depth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SOOMLayout.Card.contentSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Card.padding)
        .background(depth.background)
        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous)
                .stroke(SOOMColor.line.opacity(depth.borderOpacity), lineWidth: SOOMLayout.Card.borderWidth)
        )
    }
}

enum SOOMFirstJourneyAccent: Equatable {
    case recovery
    case run
    case bike
    case club
    case neutral

    var color: Color {
        switch self {
        case .recovery:
            return SOOMColor.recovery
        case .run:
            return SOOMColor.run
        case .bike:
            return SOOMColor.bike
        case .club:
            return SOOMColor.green
        case .neutral:
            return SOOMColor.secondaryInk
        }
    }
}

enum SOOMFirstJourneyContext: String, Equatable {
    case feed
    case activity
    case club
    case profile
}

struct SOOMFirstJourneyPrompt: Equatable {
    let context: SOOMFirstJourneyContext
    let title: String
    let message: String
    let iconName: String
    let accent: SOOMFirstJourneyAccent

    static let feed = SOOMFirstJourneyPrompt(
        context: .feed,
        title: "움직임이 쌓이면 여기에 리듬이 보여요",
        message: "오늘의 첫 기록, 가벼운 루트, 같이 움직일 클럽이 생기면 피드가 조용히 살아납니다.",
        iconName: SOOMIcon.sparkles,
        accent: .recovery
    )

    static let activity = SOOMFirstJourneyPrompt(
        context: .activity,
        title: "첫 운동이 쌓이면 여기에 리듬이 남아요",
        message: "Health 앱에서 운동을 가져오거나 오늘의 움직임을 기록하면 route와 split, 회복 흐름을 이어서 볼 수 있어요.",
        iconName: SOOMIcon.activity,
        accent: .bike
    )

    static let club = SOOMFirstJourneyPrompt(
        context: .club,
        title: "오늘은 천천히 같이 시작해도 좋아요",
        message: "지역, 페이스, 분위기가 맞는 그룹을 찾으면 운동이 기록보다 약속에 가까워집니다.",
        iconName: SOOMIcon.clubs,
        accent: .club
    )

    static let profile = SOOMFirstJourneyPrompt(
        context: .profile,
        title: "Health 앱과 연결하면 움직임을 더 자연스럽게 이어볼 수 있어요",
        message: "계정과 기록은 천천히 연결해도 괜찮아요. 이 기기의 기록은 사용자가 확인하기 전까지 로컬에 머뭅니다.",
        iconName: SOOMIcon.health,
        accent: .neutral
    )
}

struct SOOMFirstJourneyAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let iconName: String

    let action: () -> Void

    init(title: String, subtitle: String, iconName: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.action = action
    }
}

struct SOOMFirstJourneyCard: View {
    let prompt: SOOMFirstJourneyPrompt
    let actions: [SOOMFirstJourneyAction]
    let footer: String?

    init(
        prompt: SOOMFirstJourneyPrompt,
        actions: [SOOMFirstJourneyAction] = [],
        footer: String? = nil
    ) {
        self.prompt = prompt
        self.actions = actions
        self.footer = footer
    }

    var body: some View {
        SOOMCard(depth: .ambient) {
            HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionRowSpacing) {
                Image(soom: prompt.iconName)
                    .font(.system(size: SOOMFont.Size.headline, weight: .semibold))
                    .foregroundStyle(prompt.accent.color)
                    .frame(width: 36, height: 36)
                    .background(prompt.accent.color.opacity(0.1))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                    Text(prompt.title)
                        .font(SOOMFont.displayMedium(18, relativeTo: .headline))
                        .foregroundStyle(SOOMColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(prompt.message)
                        .font(SOOMFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !actions.isEmpty {
                VStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
                    ForEach(actions) { action in
                        Button(action: action.action) {
                            HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                                Image(soom: action.iconName)
                                    .font(.system(size: SOOMFont.Size.caption, weight: .semibold))
                                    .foregroundStyle(prompt.accent.color.opacity(0.78))
                                    .frame(width: 24, height: 24)
                                    .background(prompt.accent.color.opacity(0.08))
                                    .clipShape(Circle())
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.title)
                                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                                        .foregroundStyle(SOOMColor.ink)
                                    Text(action.subtitle)
                                        .font(SOOMFont.body(12, relativeTo: .caption))
                                        .foregroundStyle(SOOMColor.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, SOOMLayout.Spacing.xs)
            }

            if let footer {
                Text(footer)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .padding(.top, SOOMLayout.Spacing.xs)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt.title)
        .accessibilityValue(prompt.message)
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

/// Summary values remain together; only accessibility sizes switch to one column.
struct SOOMAdaptiveSummaryGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SOOMLayout.Spacing.sm),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: SOOMLayout.Spacing.sm) { content }
    }
}

/// Important action results use body text and a semantic icon, not color alone.
struct SOOMActionFeedback: View {
    let title: String
    let message: String
    var isError = false
    var body: some View {
        HStack(alignment: .top, spacing: SOOMLayout.Spacing.sm) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(isError ? SOOMColor.red : SOOMColor.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SOOMFont.body(16, weight: .bold, relativeTo: .body))
                Text(message).font(SOOMFont.body(14, relativeTo: .subheadline))
            }.foregroundStyle(SOOMColor.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SOOMLayout.Spacing.md)
        .background(SOOMColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SOOMRadius.compactControl))
        .accessibilityElement(children: .combine)
    }
}


/// Keep long accessible result copy readable without squeezing the adjacent CTA.
/// Only the form/result consumers opt in; global screen layout is unchanged.
struct SOOMBoundedFeedback<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content.fixedSize(horizontal: false, vertical: true) }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("soom.feedback.scroll")
                .frame(height: maxHeight)
        }
        .frame(maxHeight: maxHeight)
    }
}
