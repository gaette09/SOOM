import SwiftUI

struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSport: RecordSportMode = RecordLaunchPlan.mockToday.defaultSport
    @State private var isStartPlaceholderPresented = false
    @State private var isRoutePlaceholderPresented = false

    private let plan = RecordLaunchPlan.mockToday
    private let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RecordMapSurface(
                    sport: selectedSport,
                    routeTitle: plan.route.title,
                    routeDistance: plan.route.distanceText
                )
                    .ignoresSafeArea()

                HStack {
                    iconButton(
                        icon: "location.viewfinder",
                        accessibilityLabel: "현재 위치 다시 잡기",
                        action: { isRoutePlaceholderPresented = true }
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, proxy.safeAreaInsets.top + 142)

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, proxy.safeAreaInsets.top + 8)

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        recommendationPill
                        sportSelector
                        startButton
                    }
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18) + 28)
                }
                .padding(.horizontal, 18)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("운동 기록 준비", isPresented: $isStartPlaceholderPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("지금은 지도 위 출발 화면 foundation이에요. 실제 기록 엔진 연결은 다음 단계에서 이어갈 수 있어요.")
        }
        .alert("추천 루트", isPresented: $isRoutePlaceholderPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("v1에서는 mock route preview만 보여주고, 실제 route recommendation backend는 아직 연결하지 않았어요.")
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            closeButton

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                weatherPill
                iconButton(
                    icon: SOOMIcon.map,
                    accessibilityLabel: "추천 루트 보기",
                    action: { isRoutePlaceholderPresented = true }
                )
            }
        }
    }

    private var closeButton: some View {
        Button {
            SOOMHaptics.selection()
            if let onDismiss {
                onDismiss()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(SOOMColor.ink)
                .frame(width: 44, height: 44)
                .background(SOOMColor.surface.opacity(0.94))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SOOMColor.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed로 돌아가기")
    }

    private var recommendationPill: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(plan.recommendation.recoveryLabel)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(SOOMColor.recovery)
                .clipShape(Capsule())

            Text(shortRecommendationText)
                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SOOMColor.surface.opacity(0.88))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line, lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.045), radius: 10, x: 0, y: 6)
    }

    private var weatherPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SOOMColor.warning)

            Text(plan.weather.temperatureText)
                .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                .foregroundStyle(SOOMColor.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SOOMColor.surface.opacity(0.94))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("날씨")
        .accessibilityValue("\(plan.weather.temperatureText), \(plan.weather.conditionText)")
    }

    private var sportSelector: some View {
        HStack(spacing: 10) {
            ForEach(RecordSportMode.allCases) { sport in
                Button {
                    selectedSport = sport
                    SOOMHaptics.selection()
                } label: {
                    Image(systemName: sport.iconName)
                        .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(selectedSport == sport ? SOOMColor.white : SOOMColor.ink)
                    .frame(width: 48, height: 48)
                    .background(selectedSport == sport ? sportTint(for: sport) : SOOMColor.surface.opacity(0.90))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(selectedSport == sport ? Color.clear : SOOMColor.line, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sport.title) 선택")
            }
        }
        .padding(5)
        .background(SOOMColor.surface.opacity(0.78))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line.opacity(0.8), lineWidth: 1)
        }
    }

    private var startButton: some View {
        Button {
            SOOMHaptics.softImpact()
            isStartPlaceholderPresented = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: selectedSport.iconName)
                    .font(.system(size: 24, weight: .bold))
                Text("READY")
                    .font(SOOMFont.displayMedium(16, relativeTo: .headline))
                    .tracking(1.0)
            }
            .foregroundStyle(SOOMColor.white)
            .frame(width: 104, height: 104)
            .background(
                Circle()
                    .fill(sportTint)
                    .overlay {
                        Circle()
                            .stroke(SOOMColor.white.opacity(0.75), lineWidth: 1.4)
                            .padding(8)
                    }
            )
            .shadow(color: sportTint.opacity(0.26), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedSport.startTitle)
        .accessibilityHint("선택한 운동 모드로 기록을 시작합니다.")
    }

    private var shortRecommendationText: String {
        switch selectedSport {
        case .cycling:
            return "Z2 40분"
        case .running:
            return "조깅 25분"
        case .walking:
            return "걷기 30분"
        }
    }

    private func iconButton(icon: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button {
            SOOMHaptics.selection()
            action()
        } label: {
            iconSurface(icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func iconSurface(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(SOOMColor.ink)
            .frame(width: 46, height: 46)
            .background(SOOMColor.surface.opacity(0.88))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(SOOMColor.line.opacity(0.86), lineWidth: 1)
            }
            .shadow(color: SOOMColor.ink.opacity(0.05), radius: 9, x: 0, y: 5)
    }

    private var sportTint: Color {
        sportTint(for: selectedSport)
    }

    private func sportTint(for sport: RecordSportMode) -> Color {
        switch sport {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        }
    }
}

private struct RecordMapSurface: View {
    let sport: RecordSportMode
    let routeTitle: String
    let routeDistance: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xDDE7DC),
                        SOOMColor.background,
                        Color(hex: 0xE8E1D2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                parkShape(in: proxy.size)
                    .fill(Color(hex: 0xC9D7C4).opacity(0.70))
                    .blur(radius: 0.5)

                riverShape(in: proxy.size)
                    .fill(Color(hex: 0xB8CAD0).opacity(0.58))

                roadNetwork(in: proxy.size)
                    .stroke(SOOMColor.white.opacity(0.72), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                roadNetwork(in: proxy.size)
                    .stroke(SOOMColor.line.opacity(0.42), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                suggestedRoute(in: proxy.size)
                    .stroke(sportTint, style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: sportTint.opacity(0.22), radius: 5, x: 0, y: 3)

                routeOverlay
                    .position(x: proxy.size.width * 0.58, y: proxy.size.height * 0.38)

                routeEndpoint(at: CGPoint(x: proxy.size.width * 0.30, y: proxy.size.height * 0.60), color: sportTint)
                routeEndpoint(at: CGPoint(x: proxy.size.width * 0.72, y: proxy.size.height * 0.42), color: SOOMColor.white)

                currentLocationMarker
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.51)

                VStack {
                    Spacer()
                    Text("mock map surface · 위치 권한 요청 없음")
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                        .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }

    private var routeOverlay: some View {
        HStack(spacing: 7) {
            Text(routeTitle)
                .font(SOOMFont.body(11, weight: .bold, relativeTo: .caption2))
                .lineLimit(1)
            Text(routeDistance)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.secondaryInk)
        }
        .foregroundStyle(SOOMColor.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SOOMColor.surface.opacity(0.88))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(SOOMColor.line.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: SOOMColor.ink.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var sportTint: Color {
        switch sport {
        case .cycling:
            return SOOMColor.bike
        case .running:
            return SOOMColor.run
        case .walking:
            return SOOMColor.blue
        }
    }

    private var currentLocationMarker: some View {
        ZStack {
            Circle()
                .fill(SOOMColor.blue.opacity(0.12))
                .frame(width: 72, height: 72)
            Circle()
                .fill(SOOMColor.white)
                .frame(width: 22, height: 22)
                .shadow(color: SOOMColor.ink.opacity(0.16), radius: 7, x: 0, y: 4)
            Circle()
                .fill(SOOMColor.blue)
                .frame(width: 12, height: 12)
        }
    }

    private func routeEndpoint(at point: CGPoint, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay {
                Circle()
                    .stroke(SOOMColor.ink.opacity(0.16), lineWidth: 1)
            }
            .position(point)
    }

    private func riverShape(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: -30, y: size.height * 0.38))
            path.addCurve(
                to: CGPoint(x: size.width + 30, y: size.height * 0.58),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.26),
                control2: CGPoint(x: size.width * 0.72, y: size.height * 0.70)
            )
            path.addLine(to: CGPoint(x: size.width + 30, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: -30, y: size.height * 0.49),
                control1: CGPoint(x: size.width * 0.74, y: size.height * 0.80),
                control2: CGPoint(x: size.width * 0.18, y: size.height * 0.38)
            )
            path.closeSubpath()
        }
    }

    private func parkShape(in size: CGSize) -> Path {
        Path { path in
            path.addRoundedRect(
                in: CGRect(x: size.width * 0.58, y: size.height * 0.12, width: size.width * 0.48, height: size.height * 0.26),
                cornerSize: CGSize(width: 70, height: 70)
            )
            path.addRoundedRect(
                in: CGRect(x: -size.width * 0.10, y: size.height * 0.70, width: size.width * 0.55, height: size.height * 0.22),
                cornerSize: CGSize(width: 64, height: 64)
            )
        }
    }

    private func roadNetwork(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.18))
            path.addCurve(
                to: CGPoint(x: size.width * 0.88, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.24, y: size.height * 0.22),
                control2: CGPoint(x: size.width * 0.60, y: size.height * 0.15)
            )
            path.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.78))
            path.addCurve(
                to: CGPoint(x: size.width * 0.90, y: size.height * 0.72),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.66),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.86)
            )
            path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.08))
            path.addLine(to: CGPoint(x: size.width * 0.40, y: size.height * 0.88))
            path.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.12))
            path.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.86))
        }
    }

    private func suggestedRoute(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.60))
            path.addCurve(
                to: CGPoint(x: size.width * 0.72, y: size.height * 0.42),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.70),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.30)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.38, y: size.height * 0.47),
                control1: CGPoint(x: size.width * 0.76, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.50, y: size.height * 0.58)
            )
        }
    }
}
