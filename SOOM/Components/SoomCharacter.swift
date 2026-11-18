import SwiftUI
import WebKit

enum SoomCharacterMotion: String, CaseIterable, Identifiable {
    case idle, blink, lookUp = "look_up", lookDown = "look_down"
    case think, understand, joy, wink, surprise, reject
    var id: String { rawValue }
    var loopsByDefault: Bool { self == .idle || self == .blink }
    var duration: Double {
        switch self {
        case .blink, .wink: 2.4
        case .think: 4
        case .surprise: 3.2
        case .reject: 3.4
        default: 3
        }
    }
    var label: String {
        switch self {
        case .idle: "편안한 호흡"
        case .blink: "자연스러운 깜박임"
        case .lookUp: "위를 바라보기"
        case .lookDown: "아래를 바라보기"
        case .think: "생각"
        case .understand: "이해"
        case .joy: "기쁨"
        case .wink: "윙크"
        case .surprise: "놀람"
        case .reject: "거절"
        }
    }
}

/// One player per character view. All art and animation remain on-device.
@MainActor
final class SoomCharacterPlayer: ObservableObject {
    @Published private(set) var motion: SoomCharacterMotion
    @Published private(set) var isPlaying: Bool
    @Published private(set) var loops: Bool
    @Published private(set) var speed: Double = 1
    @Published private(set) var effort: Double?
    @Published private(set) var aboveUsual = false
    func setEffort(_ value: Double, aboveUsual: Bool = false) {
        guard value.isFinite else { return }; effort = min(10, max(1, value))
        self.aboveUsual = aboveUsual
        speed = 0.6 + ((effort ?? 1) - 1) / 9 * 1.3
    }
    @Published private(set) var position: Double = 0
    @Published private(set) var revision: Int = 0

    init(motion: SoomCharacterMotion = .idle, autoplay: Bool = true) {
        self.motion = motion; self.isPlaying = autoplay
        self.loops = motion.loopsByDefault
    }
    func play(_ motion: SoomCharacterMotion, loop: Bool? = nil) {
        self.motion = motion; loops = loop ?? motion.loopsByDefault
        position = 0; revision += 1; isPlaying = true
    }
    func pause() { isPlaying = false }
    func resume() {
        if position >= motion.duration { position = 0; revision += 1 }
        isPlaying = true
    }
    /// Stops at the selected motion's original purple neutral state.
    func stop() { isPlaying = false; position = 0; revision += 1 }
    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        isPlaying = false; position = min(motion.duration, max(0, seconds)); revision += 1
    }
    func setLooping(_ loops: Bool) { self.loops = loops }
    func setSpeed(_ speed: Double) {
        guard speed.isFinite else { return }
        self.speed = min(2, max(0.25, speed))
    }
    fileprivate func didFinish(_ motionID: String, revision: Int) {
        guard motion.rawValue == motionID, self.revision == revision else { return }
        position = motion.duration; isPlaying = false
    }
}

/// A transparent square SwiftUI component using the approved R04 SVG rig.
/// Set isVisible=false for tabs or scroll containers that stay mounted offscreen.
struct SoomCharacterView: View {
    @ObservedObject var player: SoomCharacterPlayer
    var size: CGFloat = 64
    var isVisible: Bool = true
    var decorative: Bool = true
    var reduceMotionPreview: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        SoomCharacterWebView(player: player,
                             active: appeared && isVisible && scenePhase == .active,
                             reduced: reduceMotion || reduceMotionPreview)
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(player.motion.label)
            .accessibilityHidden(decorative)
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
    }
}

private struct SoomCharacterConfiguration: Encodable {
    var id: String
    var playing: Bool
    var loop: Bool
    var speed: Double
    var position: Double
    var revision: Int
    var active: Bool
    var reduced: Bool
    var effort: Double?
    var aboveUsual: Bool
}

private struct SoomCharacterWebView: UIViewRepresentable {
    @ObservedObject var player: SoomCharacterPlayer
    var active: Bool
    var reduced: Bool

    func makeCoordinator() -> Coordinator { Coordinator(player: player) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "soomCharacter")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear; view.underPageBackgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.contentInset = .zero
        view.scrollView.isScrollEnabled = false; view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false; view.navigationDelegate = context.coordinator
        context.coordinator.load(view)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let value = SoomCharacterConfiguration(id: player.motion.rawValue,
            playing: player.isPlaying, loop: player.loops, speed: player.speed,
            position: player.position, revision: player.revision,
            active: active, reduced: reduced, effort: player.effort, aboveUsual: player.aboveUsual)
        context.coordinator.configure(view, value: value)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.evaluateJavaScript("window.SoomCharacterRuntime?.dispose()")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "soomCharacter")
        view.navigationDelegate = nil; view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private weak var player: SoomCharacterPlayer?
        private var latest: SoomCharacterConfiguration?
        private var ready = false
        private var lastJSON: String?
        private static let html: String? = {
            guard let url = Bundle.main.url(forResource: "character", withExtension: "html",
                                           subdirectory: "SoomCharacterR04") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }()

        init(player: SoomCharacterPlayer) { self.player = player }
        func load(_ view: WKWebView) {
            guard let html = Self.html else {
                assertionFailure("Missing bundled SoomCharacterR04/character.html")
                return
            }
            ready = false; lastJSON = nil
            view.loadHTMLString(html, baseURL: nil)
        }
        func configure(_ view: WKWebView, value: SoomCharacterConfiguration) {
            latest = value
            guard ready, let bytes = try? JSONEncoder().encode(value),
                  let json = String(data: bytes, encoding: .utf8), json != lastJSON else { return }
            lastJSON = json
            view.evaluateJavaScript("window.SoomCharacterRuntime.configure(\(json))")
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let latest { configure(webView, value: latest) }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load(webView) }
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], body["event"] as? String == "ended",
                  let id = body["id"] as? String, let revision = body["revision"] as? Int else { return }
            player?.didFinish(id, revision: revision)
        }
    }
}

#if DEBUG
struct SoomCharacterDemoView: View {
    @StateObject private var player = SoomCharacterPlayer(autoplay: false)
    @State private var reducedPreview = false
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .bottom, spacing: 20) {
                ForEach([32, 48, 64, 96], id: \.self) { size in
                    VStack { SoomCharacterView(player: player, size: CGFloat(size), decorative: false, reduceMotionPreview: reducedPreview)
                        Text("\(size)pt").font(.caption) }
                }
            }.padding().background(Color.gray.opacity(0.12))
            Picker("모션", selection: Binding(get: { player.motion }, set: { player.play($0) })) {
                ForEach(SoomCharacterMotion.allCases) { motion in Text(motion.label).tag(motion) }
            }
            HStack {
                Button("재생") { player.resume() }; Button("일시정지") { player.pause() }
                Button("중지") { player.stop() }
            }
            Toggle("반복", isOn: Binding(get: { player.loops }, set: { player.setLooping($0) }))
            Toggle("Reduce Motion 검토", isOn: $reducedPreview)
            Slider(value: Binding(get: { player.speed }, set: { player.setSpeed($0) }), in: 0.5...1.5)
        }.padding()
    }
}
#Preview { SoomCharacterDemoView() }
#endif
