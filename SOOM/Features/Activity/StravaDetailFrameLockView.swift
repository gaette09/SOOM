import SwiftUI

struct StravaDetailFrameLockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheetOffset: CGFloat = FrameLock.expandedSheetTop
    @State private var dragTranslation: CGFloat = 0
    @State private var isExpanded = false

    private let screenHeight = UIScreen.main.bounds.height

    private var previewSheetTop: CGFloat {
        screenHeight * FrameLock.previewSheetTopRatio
    }

    var body: some View {
        GeometryReader { proxy in
            let safeAreaTop = proxy.safeAreaInsets.top
            let renderedOffset = clampedOffset(sheetOffset + dragTranslation)
            let progress = expansionProgress(offset: renderedOffset)

            ZStack(alignment: .top) {
                // Layer 1: full-screen map. It ignores all safe areas.
                StravaFrameLockMapLayer()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()

                // Layer 3/4: movable sheet. This is the only layer receiving offset.
                StravaFrameLockBottomSheetContainer(
                    safeAreaTop: safeAreaTop,
                    screenHeight: screenHeight,
                    isExpanded: isExpanded,
                    progress: progress,
                    previewDragGesture: sheetDragGesture(),
                    collapseDragGesture: sheetDragGesture()
                )
                .frame(width: proxy.size.width, height: screenHeight, alignment: .top)
                .offset(y: renderedOffset)
                .zIndex(1)

                // Layer 2: fixed top nav. It is outside the sheet and never offset.
                StravaFrameLockTopNavView(
                    safeAreaTop: safeAreaTop,
                    isExpanded: isExpanded,
                    progress: progress,
                    dismiss: dismiss
                )
                .frame(width: proxy.size.width, height: safeAreaTop + FrameLock.navHeight, alignment: .top)
                .zIndex(2)
            }
            .ignoresSafeArea()
            .onAppear {
                sheetOffset = isExpanded ? FrameLock.expandedSheetTop : previewSheetTop
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .hidesSOOMTabBar()
        .preferredColorScheme(.light)
    }

    private func sheetDragGesture() -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let nextOffset = clampedOffset(sheetOffset + value.translation.height)
                    dragTranslation = nextOffset - sheetOffset
                }
                .onEnded { value in
                    let releaseOffset = clampedOffset(sheetOffset + value.translation.height)
                    let predictedOffset = clampedOffset(
                        releaseOffset + value.predictedEndTranslation.height - value.translation.height
                    )
                    let target = targetAnchor(current: releaseOffset, predicted: predictedOffset)

                    dragTranslation = 0
                    sheetOffset = releaseOffset
                    isExpanded = target == FrameLock.expandedSheetTop

                    withAnimation(reduceMotion ? nil : FrameLock.transitionAnimation) {
                        sheetOffset = target
                    }
                }
        )
    }

    private func targetAnchor(current: CGFloat, predicted: CGFloat) -> CGFloat {
        let midpoint = (FrameLock.expandedSheetTop + previewSheetTop) / 2
        let projectedTravel = predicted - current

        if projectedTravel < -44 {
            return FrameLock.expandedSheetTop
        }

        if projectedTravel > 44 {
            return previewSheetTop
        }

        return current < midpoint ? FrameLock.expandedSheetTop : previewSheetTop
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(max(offset, FrameLock.expandedSheetTop), previewSheetTop)
    }

    private func expansionProgress(offset: CGFloat) -> CGFloat {
        let range = max(previewSheetTop - FrameLock.expandedSheetTop, 1)
        return min(max((previewSheetTop - offset) / range, 0), 1)
    }
}

private enum FrameLock {
    static let navHeight: CGFloat = 56
    static let navTouchTargetHeight: CGFloat = 44
    static let handleWidth: CGFloat = 40
    static let handleHeight: CGFloat = 4
    static let sheetPreviewCornerRadius: CGFloat = 14
    static let sheetExpandedCornerRadius: CGFloat = 0
    static let contentHorizontalPadding: CGFloat = 32
    static let expandedContentTopPaddingBelowNav: CGFloat = 36
    static let sectionTopSpacing: CGFloat = 36
    static let chartHeight: CGFloat = 140
    static let previewSheetTopRatio: CGFloat = 0.64
    static let expandedSheetTop: CGFloat = 0
    static let transitionAnimation = Animation.spring(response: 0.4, dampingFraction: 0.85)
}

private struct StravaFrameLockTopNavView: View {
    let safeAreaTop: CGFloat
    let isExpanded: Bool
    let progress: CGFloat
    let dismiss: DismissAction

    private var iconColor: Color {
        isExpanded ? .black.opacity(0.82) : .white
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(progress))
                .frame(height: safeAreaTop + FrameLock.navHeight)
                .allowsHitTesting(false)

            HStack {
                frameLockIconButton(systemName: "chevron.down") {
                    dismiss()
                }

                Spacer()

                Text("Ride")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)

                Spacer()

                HStack(spacing: 8) {
                    frameLockIconButton(systemName: "bookmark") {}
                    frameLockIconButton(systemName: "ellipsis") {}
                }
            }
            .padding(.horizontal, 16)
            .frame(height: FrameLock.navTouchTargetHeight)
            .offset(y: safeAreaTop + ((FrameLock.navHeight - FrameLock.navTouchTargetHeight) / 2))

            Rectangle()
                .fill(Color.black.opacity(0.10 * progress))
                .frame(height: 1)
                .offset(y: safeAreaTop + FrameLock.navHeight)
        }
    }

    private func frameLockIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: FrameLock.navTouchTargetHeight, height: FrameLock.navTouchTargetHeight)
                .background {
                    Circle()
                        .fill(isExpanded ? Color.clear : Color.black.opacity(0.24))
                }
        }
        .buttonStyle(.plain)
    }
}

private struct StravaFrameLockBottomSheetContainer: View {
    let safeAreaTop: CGFloat
    let screenHeight: CGFloat
    let isExpanded: Bool
    let progress: CGFloat
    let previewDragGesture: AnyGesture<DragGesture.Value>
    let collapseDragGesture: AnyGesture<DragGesture.Value>

    private var cornerRadius: CGFloat {
        FrameLock.sheetPreviewCornerRadius * (1 - progress) + FrameLock.sheetExpandedCornerRadius * progress
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white

            if isExpanded {
                expandedHandle
                    .zIndex(2)
            }

            VStack(spacing: 0) {
                if isExpanded {
                    expandedScrollContent
                } else {
                    previewHeader
                        .highPriorityGesture(previewDragGesture)
                    Spacer(minLength: 0)
                }
            }
        }
        .clipShape(StravaFrameLockTopRoundedRectangle(radius: cornerRadius))
    }

    private var previewHeader: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 10)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Morning Ride")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)

                Text("Today · Seoul")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.black.opacity(0.55))

                HStack(alignment: .top, spacing: 24) {
                    previewMetric(value: "42.1", label: "Distance")
                    previewMetric(value: "1:42", label: "Time")
                    previewMetric(value: "24.7", label: "Speed")
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, FrameLock.contentHorizontalPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
        .background {
            Rectangle()
                .fill(Color.black.opacity(0.001))
        }
        .contentShape(Rectangle())
    }

    private var expandedHandle: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, safeAreaTop + FrameLock.navHeight + 10)
                .padding(.bottom, 12)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: safeAreaTop + FrameLock.navHeight + 44,
            alignment: .top
        )
        .background {
            Rectangle()
                .fill(Color.black.opacity(0.001))
        }
        .contentShape(Rectangle())
        .highPriorityGesture(collapseDragGesture)
    }

    private var expandedScrollContent: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: FrameLock.sectionTopSpacing) {
                placeholderBlock(height: 88, label: "Expanded content starts below fixed nav")
                placeholderBlock(height: 112, label: "Frame placeholder")
                placeholderBlock(height: FrameLock.chartHeight, label: "Section placeholder")
                placeholderBlock(height: FrameLock.chartHeight, label: "Section placeholder")
                placeholderBlock(height: 160, label: "Lower scroll placeholder")
            }
            .padding(.horizontal, FrameLock.contentHorizontalPadding)
            .padding(.top, safeAreaTop + FrameLock.navHeight + FrameLock.expandedContentTopPaddingBelowNav)
            .padding(.bottom, 48)
        }
        .scrollDisabled(!isExpanded)
    }

    private var dragHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(isExpanded ? 0.18 : 0.22))
            .frame(width: FrameLock.handleWidth, height: FrameLock.handleHeight)
    }

    private func previewMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.black.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholderBlock(height: CGFloat, label: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.045))
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.42))
                    .padding(14)
            }
    }
}

private struct StravaFrameLockMapLayer: View {
    private let route: [CGPoint] = [
        CGPoint(x: 0.18, y: 0.36),
        CGPoint(x: 0.30, y: 0.28),
        CGPoint(x: 0.44, y: 0.33),
        CGPoint(x: 0.58, y: 0.23),
        CGPoint(x: 0.72, y: 0.34),
        CGPoint(x: 0.64, y: 0.49),
        CGPoint(x: 0.48, y: 0.45),
        CGPoint(x: 0.34, y: 0.57),
        CGPoint(x: 0.22, y: 0.48)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.86, green: 0.89, blue: 0.84)

                mapGrid(size: proxy.size)

                routePath(size: proxy.size)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                routePath(size: proxy.size)
                    .stroke(Color(red: 0.98, green: 0.31, blue: 0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func mapGrid(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Path { path in
                    let y = size.height * (CGFloat(index) + 1) / 11
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addCurve(
                        to: CGPoint(x: size.width, y: y + CGFloat(index % 3 - 1) * 18),
                        control1: CGPoint(x: size.width * 0.25, y: y - 20),
                        control2: CGPoint(x: size.width * 0.72, y: y + 20)
                    )
                }
                .stroke(Color.white.opacity(index.isMultiple(of: 3) ? 0.50 : 0.28), lineWidth: index.isMultiple(of: 3) ? 2 : 1)
            }

            ForEach(0..<7, id: \.self) { index in
                Path { path in
                    let x = size.width * (CGFloat(index) + 1) / 8
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + CGFloat(index.isMultiple(of: 2) ? 18 : -18), y: size.height))
                }
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
            }
        }
    }

    private func routePath(size: CGSize) -> Path {
        Path { path in
            let points = route.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }
}

private struct StravaFrameLockTopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

#Preview("Strava Detail Frame Lock") {
    StravaDetailFrameLockView()
}
