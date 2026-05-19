import SwiftUI

struct WorkoutSheetMetrics {
    let minimizedHeight: CGFloat
    let standardHeight: CGFloat
    let expandedHeight: CGFloat
    let baseHeight: CGFloat
    let sheetHeight: CGFloat
    let sheetFrameHeight: CGFloat
    let sheetYOffset: CGFloat
    let hiddenSheetHeight: CGFloat
    let scrollBottomPadding: CGFloat
    let topCornerRadius: CGFloat
    let shadowOpacity: Double
    let isExpanded: Bool

    init(proxy: GeometryProxy, position: WorkoutSheetPosition, drag: CGFloat) {
        minimizedHeight = min(max(proxy.size.height * SOOMLayout.DetailSheet.minimizedRatio, SOOMLayout.DetailSheet.minimizedMinHeight), SOOMLayout.DetailSheet.minimizedMaxHeight)
        standardHeight = min(max(proxy.size.height * SOOMLayout.DetailSheet.standardRatio, SOOMLayout.DetailSheet.standardMinHeight), SOOMLayout.DetailSheet.standardMaxHeight)
        expandedHeight = max(proxy.size.height + proxy.safeAreaInsets.top + SOOMLayout.DetailSheet.expandedTopOverflow, standardHeight)
        baseHeight = position.height(minimized: minimizedHeight, standard: standardHeight, expanded: expandedHeight)
        sheetHeight = min(max(baseHeight - drag, minimizedHeight), expandedHeight)
        isExpanded = position == .expanded
        topCornerRadius = isExpanded && drag < SOOMLayout.DetailSheet.expandedCornerDragThreshold ? 0 : SOOMLayout.DetailSheet.topCornerRadius
        sheetFrameHeight = sheetHeight + proxy.safeAreaInsets.bottom
        sheetYOffset = proxy.safeAreaInsets.bottom + (isExpanded ? SOOMLayout.DetailSheet.expandedYOffset : 0)
        hiddenSheetHeight = max(sheetFrameHeight - proxy.size.height - sheetYOffset, 0)
        scrollBottomPadding = proxy.safeAreaInsets.bottom + SOOMLayout.DetailSheet.scrollBottomPadding + (isExpanded ? hiddenSheetHeight : 0)
        shadowOpacity = isExpanded && drag < SOOMLayout.DetailSheet.expandedCornerDragThreshold ? 0 : SOOMLayout.DetailSheet.shadowOpacity
    }
}

enum WorkoutSheetPosition: CaseIterable {
    case minimized
    case standard
    case expanded

    var mapScale: Double {
        switch self {
        case .minimized:
            return 1.36
        case .standard:
            return 3.00
        case .expanded:
            return 2.36
        }
    }

    var mapLatitudeOffset: Double {
        switch self {
        case .minimized:
            return 0
        case .standard:
            return -0.50
        case .expanded:
            return -0.34
        }
    }

    func height(minimized: CGFloat, standard: CGFloat, expanded: CGFloat) -> CGFloat {
        switch self {
        case .minimized:
            return minimized
        case .standard:
            return standard
        case .expanded:
            return expanded
        }
    }

    static func nearest(to height: CGFloat, minimized: CGFloat, standard: CGFloat, expanded: CGFloat) -> WorkoutSheetPosition {
        let candidates: [(WorkoutSheetPosition, CGFloat)] = [
            (.minimized, minimized),
            (.standard, standard),
            (.expanded, expanded)
        ]

        return candidates.min { lhs, rhs in
            abs(lhs.1 - height) < abs(rhs.1 - height)
        }?.0 ?? .standard
    }
}
