import SwiftUI
import UIKit

private enum SOOMTab: String, CaseIterable, Identifiable {
    case home
    case analysis
    case record
    case feed
    case clubs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "홈"
        case .analysis:
            return "분석"
        case .record:
            return "기록"
        case .feed:
            return "피드"
        case .clubs:
            return "클럽"
        }
    }

    var iconName: String {
        switch self {
        case .home:
            return SOOMIcon.home
        case .analysis:
            return SOOMIcon.analysis
        case .record:
            return SOOMIcon.record
        case .feed:
            return SOOMIcon.feed
        case .clubs:
            return SOOMIcon.clubs
        }
    }
}

final class SOOMTabBarVisibility: ObservableObject {
    @Published var isHidden = false
}

struct RootTabView: View {
    @State private var selectedTab: SOOMTab = .home
    @StateObject private var tabBarVisibility = SOOMTabBarVisibility()
    @Namespace private var tabBarNamespace

    init() {
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayBoldName, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: SOOMFont.displayMediumName, size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor(SOOMColor.ink)
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            selectedContent
                .environmentObject(tabBarVisibility)
                .environment(\.soomBottomOverlayInset, tabBarVisibility.isHidden ? 0 : SOOMLayout.TabBar.bottomOverlayInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SOOMColor.background.ignoresSafeArea())

            if !tabBarVisibility.isHidden {
                SOOMBottomTabBar(selectedTab: $selectedTab, namespace: tabBarNamespace)
                    .padding(.horizontal, SOOMLayout.TabBar.outerHorizontalPadding)
                    .padding(.bottom, SOOMLayout.TabBar.bottomPadding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(SOOMColor.background.ignoresSafeArea())
        // SOOM v1 keeps Light Mode only while the visual system stabilizes.
        .preferredColorScheme(.light)
        .environment(\.font, SOOMFont.body(15, relativeTo: .body))
        .sensoryFeedback(.selection, trigger: selectedTab)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: tabBarVisibility.isHidden)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack {
                HomeView()
            }
        case .analysis:
            NavigationStack {
                AnalysisView()
            }
        case .record:
            NavigationStack {
                RecordView()
            }
        case .feed:
            NavigationStack {
                FeedView()
            }
        case .clubs:
            NavigationStack {
                ClubsView()
            }
        }
    }
}

private struct SOOMBottomTabBar: View {
    @Binding var selectedTab: SOOMTab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SOOMTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78, blendDuration: 0.08)) {
                        selectedTab = tab
                    }
                } label: {
                    SOOMBottomTabItem(tab: tab, isSelected: selectedTab == tab, namespace: namespace)
                }
                .buttonStyle(LiquidTabButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: SOOMLayout.TabBar.height)
        .padding(.horizontal, SOOMLayout.TabBar.containerHorizontalPadding)
        .padding(.vertical, SOOMLayout.TabBar.containerVerticalPadding)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.72),
                                SOOMColor.white.opacity(0.28),
                                SOOMColor.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SOOMColor.white.opacity(0.95),
                                SOOMColor.ink.opacity(0.10),
                                SOOMColor.white.opacity(0.54)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SOOMColor.ink.opacity(0.16), radius: SOOMLayout.TabBar.containerShadowRadius, x: 0, y: SOOMLayout.TabBar.containerShadowYOffset)
            .shadow(color: SOOMColor.white.opacity(0.62), radius: 10, x: -4, y: -4)
        }
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(SOOMColor.white.opacity(0.78))
                .frame(height: SOOMLayout.TabBar.topHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.topHighlightHorizontalPadding)
                .offset(y: 1.5)
        }
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(SOOMColor.ink.opacity(0.06))
                .frame(height: SOOMLayout.TabBar.bottomHighlightHeight)
                .padding(.horizontal, SOOMLayout.TabBar.bottomHighlightHorizontalPadding)
                .offset(y: -1)
        }
        .compositingGroup()
    }
}

private struct SOOMBottomTabItem: View {
    let tab: SOOMTab
    let isSelected: Bool
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        SOOMColor.white.opacity(0.80),
                                        SOOMColor.white.opacity(0.26),
                                        SOOMColor.ink.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(SOOMColor.white.opacity(0.72), lineWidth: 1)
                    }
                    .shadow(color: SOOMColor.ink.opacity(0.10), radius: 12, x: 0, y: 8)
                    .matchedGeometryEffect(id: "selectedLiquidTab", in: namespace)
            }

            VStack(spacing: SOOMLayout.TabBar.itemLabelSpacing) {
                Image(systemName: tab.iconName)
                    .font(.system(size: tab == .record ? SOOMLayout.TabBar.recordIconSize : SOOMLayout.TabBar.defaultIconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: SOOMLayout.TabBar.iconHeight)
                    .scaleEffect(isSelected ? SOOMLayout.TabBar.selectedIconScale : SOOMLayout.TabBar.normalIconScale)

                Text(tab.title)
                    .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                    .lineLimit(1)
                    .opacity(isSelected ? 1 : 0.74)
            }
        }
        .foregroundStyle(isSelected ? SOOMColor.ink : SOOMColor.ink.opacity(0.56))
        .frame(maxWidth: .infinity)
        .frame(height: SOOMLayout.TabBar.itemHeight)
        .contentShape(RoundedRectangle(cornerRadius: SOOMLayout.TabBar.itemCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
        .animation(.spring(response: 0.30, dampingFraction: 0.72), value: isSelected)
    }
}

private struct LiquidTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? SOOMLayout.TabBar.pressScale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

private struct SOOMTabBarHiddenModifier: ViewModifier {
    @EnvironmentObject private var visibility: SOOMTabBarVisibility

    func body(content: Content) -> some View {
        content
            .onAppear {
                visibility.isHidden = true
            }
            .onDisappear {
                visibility.isHidden = false
            }
    }
}

extension View {
    func hidesSOOMTabBar() -> some View {
        modifier(SOOMTabBarHiddenModifier())
    }
}
