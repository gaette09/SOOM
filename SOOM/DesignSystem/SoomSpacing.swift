import SwiftUI

enum SOOMLayout {
    static let screenPadding: CGFloat = 20
    static let stackSpacing: CGFloat = 16
    static let cardRadius: CGFloat = SOOMRadius.card

    enum Screen {
        static let topPadding: CGFloat = 18
        static let bottomPadding: CGFloat = 28
    }

    enum Card {
        static let contentSpacing: CGFloat = 12
        static let padding: CGFloat = 16
        static let borderWidth: CGFloat = 1
    }

    enum IconButton {
        static let size: CGFloat = 44
        static let iconSize: CGFloat = 20
    }

    enum SectionHeader {
        static let spacing: CGFloat = 4
    }

    enum DetailSheet {
        static let minimizedRatio: CGFloat = 0.18
        static let minimizedMinHeight: CGFloat = 148
        static let minimizedMaxHeight: CGFloat = 190
        static let standardRatio: CGFloat = 0.56
        static let standardMinHeight: CGFloat = 468
        static let standardMaxHeight: CGFloat = 600
        static let expandedTopOverflow: CGFloat = 72
        static let expandedYOffset: CGFloat = -36
        static let expandedCornerDragThreshold: CGFloat = 12
        static let topCornerRadius: CGFloat = SOOMRadius.detailSheetTop
        static let scrollBottomPadding: CGFloat = 24
        static let dragMinimumDistance: CGFloat = 8
        static let scrollTopThreshold: CGFloat = 1
        static let shadowRadius: CGFloat = 18
        static let shadowYOffset: CGFloat = -8
        static let shadowOpacity: Double = 0.12
        static let handleWidth: CGFloat = 52
        static let handleHeight: CGFloat = 6
        static let handleVerticalPadding: CGFloat = 10
        static let headerHorizontalPadding: CGFloat = 14
        static let headerTopPadding: CGFloat = 8
        static let headerBottomPadding: CGFloat = 10
        static let headerButtonSize: CGFloat = 42
        static let headerTrailingButtonSize: CGFloat = 38
        static let headerIconSize: CGFloat = 15
        static let headerCollapseIconSize: CGFloat = 20
        static let headerActionIconSize: CGFloat = 20
        static let headerMoreIconSize: CGFloat = 19
        static let headerSpacing: CGFloat = 12
        static let headerTrailingSpacing: CGFloat = 6
        static let titleSpacing: CGFloat = 8
        static let sheetSpringResponse: Double = 0.34
        static let sheetSpringDamping: Double = 0.88
        static let sheetAnimationResponse: Double = 0.38
        static let sheetAnimationDamping: Double = 0.90
        static let handleSpringResponse: Double = 0.32
        static let handleSpringDamping: Double = 0.86
        static let mapAnimationDuration: Double = 0.45
    }

    enum Metrics {
        static let pillPadding: CGFloat = 12
        static let pillSpacing: CGFloat = 4
        static let gridSpacing: CGFloat = 12
        static let scoreRingSize: CGFloat = 82
        static let scoreRingLineWidth: CGFloat = 10
        static let scoreRingSpacing: CGFloat = 8
        static let actionRowSpacing: CGFloat = 12
        static let actionIconFrame: CGFloat = 42
        static let actionTextSpacing: CGFloat = 4
        static let actionIconBackgroundOpacity: Double = 0.12
        static let rowSpacing: CGFloat = 12
        static let rowLeadingWidth: CGFloat = 46
        static let rowTextSpacing: CGFloat = 3
        static let detailHeaderSpacing: CGFloat = 14
        static let detailIconFrame: CGFloat = 56
        static let compactListSpacing: CGFloat = 10
        static let tagMinWidth: CGFloat = 96
        static let tagSpacing: CGFloat = 8
        static let tagHorizontalPadding: CGFloat = 10
        static let tagVerticalPadding: CGFloat = 8
    }

    enum MapControls {
        static let spacing: CGFloat = 12
        static let topPadding: CGFloat = 16
        static let horizontalPadding: CGFloat = 18
        static let buttonSize: CGFloat = 46
        static let backIconSize: CGFloat = 22
        static let defaultIconSize: CGFloat = 22
        static let ellipsisIconSize: CGFloat = 21
        static let shadowRadius: CGFloat = 8
        static let shadowYOffset: CGFloat = 3
        static let shadowOpacity: Double = 0.10
        static let mapRouteLineWidth: CGFloat = 5
    }

    enum TabBar {
        static let bottomOverlayInset: CGFloat = 108
        static let outerHorizontalPadding: CGFloat = 26
        static let bottomPadding: CGFloat = 10
        static let height: CGFloat = 60
        static let containerHorizontalPadding: CGFloat = 6
        static let containerVerticalPadding: CGFloat = 5
        static let itemHeight: CGFloat = 50
        static let itemCornerRadius: CGFloat = SOOMRadius.liquidTabItem
        static let iconHeight: CGFloat = 22
        static let defaultIconSize: CGFloat = 20
        static let recordIconSize: CGFloat = 22
        static let itemLabelSpacing: CGFloat = 3
        static let topHighlightHeight: CGFloat = 1.2
        static let topHighlightHorizontalPadding: CGFloat = 28
        static let bottomHighlightHeight: CGFloat = 1
        static let bottomHighlightHorizontalPadding: CGFloat = 36
        static let selectedShadowRadius: CGFloat = 8
        static let containerShadowRadius: CGFloat = 14
        static let containerShadowYOffset: CGFloat = 8
        static let pressScale: CGFloat = 0.97
        static let selectedIconScale: CGFloat = 1.0
        static let normalIconScale: CGFloat = 0.94
    }

    enum RecoveryAI {
        static let iconFrame: CGFloat = 42
        static let iconSize: CGFloat = 19
        static let iconTextSpacing: CGFloat = 12
        static let textSpacing: CGFloat = 6
        static let scoreHeaderSpacing: CGFloat = 16
        static let trendLineHeight: CGFloat = 34
        static let trendLineWidth: CGFloat = 3
        static let ctaVerticalPadding: CGFloat = 12
        static let ctaCornerRadius: CGFloat = SOOMRadius.compactControl
        static let messageLineSpacing: CGFloat = 3
        static let promptIconFrame: CGFloat = 34
        static let promptIconSize: CGFloat = 15
        static let promptButtonVerticalPadding: CGFloat = 8
        static let promptButtonHorizontalPadding: CGFloat = 12
    }

    enum RecoveryScreen {
        static let focusCardSpacing: CGFloat = 16
        static let supportingCardSpacing: CGFloat = 12
        static let sectionGroupSpacing: CGFloat = 18
        static let compactSectionSpacing: CGFloat = 8
        static let footnoteTopPadding: CGFloat = 2
    }

    enum CheckIn {
        static let optionSpacing: CGFloat = 8
        static let optionMinHeight: CGFloat = 46
        static let optionCornerRadius: CGFloat = SOOMRadius.compactControl
        static let noteHeight: CGFloat = 104
        static let saveButtonVerticalPadding: CGFloat = 13
        static let confirmationIconFrame: CGFloat = 34
    }
}
