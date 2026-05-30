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

enum SOOMCardDepth {
    case primary
    case secondary
    case ambient

    var background: Color {
        switch self {
        case .primary:
            return SOOMColor.surface
        case .secondary:
            return SOOMColor.surfaceAmbient
        case .ambient:
            return SOOMColor.surfaceMuted
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
    case coach
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

    static let coach = SOOMFirstJourneyPrompt(
        context: .coach,
        title: "조금 더 움직임이 쌓이면 회복 흐름을 읽을 수 있어요",
        message: "지금은 무리한 판단보다 오늘의 컨디션을 부드럽게 확인하는 companion으로 머물게요.",
        iconName: SOOMIcon.recovery,
        accent: .recovery
    )

    static let profile = SOOMFirstJourneyPrompt(
        context: .profile,
        title: "Health 앱과 연결하면 움직임을 더 자연스럽게 이어볼 수 있어요",
        message: "계정과 기록은 천천히 연결해도 괜찮아요. 이 기기의 기록은 사용자가 확인하기 전까지 로컬에 머뭅니다.",
        iconName: SOOMIcon.health,
        accent: .neutral
    )
}

struct SOOMFirstJourneyAction: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let iconName: String

    init(title: String, subtitle: String, iconName: String) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
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
                Image(systemName: prompt.iconName)
                    .font(.system(size: 17, weight: .semibold))
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
                        HStack(alignment: .top, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                            Image(systemName: action.iconName)
                                .font(.system(size: 12, weight: .semibold))
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
                }
                .padding(.top, 2)
            }

            if let footer {
                Text(footer)
                    .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                    .padding(.top, 2)
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
