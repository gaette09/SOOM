import SwiftUI

struct WorkoutBottomSheet<Header: View, SheetContent: View, SheetGesture: Gesture>: View {
    let metrics: WorkoutSheetMetrics
    let isScrollDisabled: Bool
    let sheetGesture: SheetGesture
    let onScrollOffsetChange: (CGFloat) -> Void
    let header: Header
    let content: SheetContent

    init(
        metrics: WorkoutSheetMetrics,
        isScrollDisabled: Bool,
        sheetGesture: SheetGesture,
        onScrollOffsetChange: @escaping (CGFloat) -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> SheetContent
    ) {
        self.metrics = metrics
        self.isScrollDisabled = isScrollDisabled
        self.sheetGesture = sheetGesture
        self.onScrollOffsetChange = onScrollOffsetChange
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: SOOMLayout.stackSpacing) {
                    content
                }
                .padding(.horizontal, SOOMLayout.screenPadding)
                .padding(.bottom, metrics.scrollBottomPadding)
            }
            .coordinateSpace(name: "WorkoutSheetScroll")
            .scrollDisabled(isScrollDisabled)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                onScrollOffsetChange(newOffset)
            }
        }
        .frame(height: metrics.sheetFrameHeight)
        .background(SOOMColor.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: metrics.topCornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: metrics.topCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(metrics.shadowOpacity), radius: SOOMLayout.DetailSheet.shadowRadius, x: 0, y: SOOMLayout.DetailSheet.shadowYOffset)
        .contentShape(Rectangle())
        .offset(y: metrics.sheetYOffset)
        .simultaneousGesture(sheetGesture)
        .animation(.spring(response: SOOMLayout.DetailSheet.sheetAnimationResponse, dampingFraction: SOOMLayout.DetailSheet.sheetAnimationDamping), value: metrics.isExpanded)
    }
}
