import SwiftUI

/// Mounted only inside the authenticated account's storage gate, and only for
/// the selected feed tab. No live FeedView/FeedItem/reader/navigation is created.
struct FeedEarlyCachePendingView: View {
    @ObservedObject var model: AccountPrivacyModel
    let onSettings: () -> Void
    @ObservedObject private var cache: FeedStaleSummaryCache
    @ObservedObject private var safety: CommunitySafetyStore

    init(model: AccountPrivacyModel, onSettings: @escaping () -> Void) {
        self.model = model; self.onSettings = onSettings
        _cache = ObservedObject(wrappedValue: .shared)
        _safety = ObservedObject(wrappedValue: .shared)
    }
    #if DEBUG
    // Dependency injection only; all production account/scene/layout gates below remain.
    init(model: AccountPrivacyModel, onSettings: @escaping () -> Void,
         cache: FeedStaleSummaryCache, safety: CommunitySafetyStore) {
        self.model = model; self.onSettings = onSettings
        _cache = ObservedObject(wrappedValue: cache)
        _safety = ObservedObject(wrappedValue: safety)
    }
    #endif
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var storage: HealthAccountStorageController
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction
    @Environment(\.legibilityWeight) private var weight
    @State private var trace: LoadTrace?
    @State private var markedFirst = false

    private var scope: FeedStaleSummaryScope? {
        guard cache.enabled, scene == .active,
              model.earlyCacheVerification == .checking || model.earlyCacheVerification == .unresolved,
              let viewer = auth.session.currentUser?.id,
              auth.session.currentUser?.authProvider == .supabase,
              viewer == storage.userID, viewer == safety.viewerID,
              !AccountDeletionWriteFence.shared.isRetired(viewer) else { return nil }
        return .init(viewerID: viewer, generation: safety.accountGeneration,
                     safetyRevision: safety.revision, policyVersion: 1)
    }
    var body: some View {
        GeometryReader { geometry in
            let snapshots = scope.map { cache.allSnapshots(scope: $0).filter { !safety.isBlocked($0.ownerID) } } ?? []
            let chrome = snapshots.compactMap(\.chromeLayout).first {
                $0.matches(width: Double(geometry.size.width), dynamicType: String(describing: dynamicType),
                    environment: FeedStaleSummaryLayout.environment(locale: locale.identifier,
                        direction: String(describing: direction), weight: String(describing: weight)))
            }
            if snapshots.isEmpty || chrome == nil {
                SocialAccessStatusView(model: model, onSettings: onSettings)
            } else {
                SOOMScreen {
                    Color.clear.frame(height: CGFloat(chrome!.height)).accessibilityHidden(true)
                    VStack(spacing: 18) {
                        ForEach(snapshots.prefix(8), id: \.id) { snapshot in
                            if let height = snapshot.layout?.height(width: Double(geometry.size.width),
                                dynamicType: String(describing: dynamicType),
                                environment: FeedStaleSummaryLayout.environment(locale: locale.identifier,
                                    direction: String(describing: direction), weight: String(describing: weight)),
                                contentRevision: snapshot.layoutRevision) {
                                FeedStaleSummaryView(snapshot: snapshot)
                                    .frame(height: CGFloat(height), alignment: .top).clipped()
                                    .modifier(FeedChromeGeometryProbe(name: "early-card-\(snapshot.id)"))
                                    .accessibilityIdentifier("feed.early.cache.card.\(snapshot.id)")
                                    .onAppear {
                                        guard !markedFirst else { return }
                                        markedFirst = true
                                        trace?.mark("first-cached-card-mounted")
                                    }
                            } else { FeedSkeletonCard() }
                        }
                    }.padding(.horizontal, -SOOMLayout.screenPadding)
                }
                .accessibilityIdentifier("feed.early.cache")
                .allowsHitTesting(false)
            }
        }
        .task(id: scope) {
            guard let scope else { return }
            if trace == nil { trace = LoadTrace("feed-early-passive") }
            cache.beginEarlyDisplay(scope: scope)
            await cache.restore(viewerID: scope.viewerID, generation: scope.generation, safetyRevision: scope.safetyRevision)
            trace?.mark("restore-returned")
        }
    }
}

#if DEBUG
private struct FeedChromeGeometryObserverKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}
extension EnvironmentValues {
    var feedChromeGeometryObserver: ((String, CGRect) -> Void)? {
        get { self[FeedChromeGeometryObserverKey.self] }
        set { self[FeedChromeGeometryObserverKey.self] = newValue }
    }
}
#endif
/// DEBUG measurement only; release has no observer or geometry work.
struct FeedChromeGeometryProbe: ViewModifier {
    let name: String
    #if DEBUG
    @Environment(\.feedChromeGeometryObserver) private var observer
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if observer != nil {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { observer?(name, $0) }
        } else { content }
        #else
        content
        #endif
    }
}

/// A same-entry reservation uses measured chrome height, never a guessed constant.
/// If fresh chrome grows, its dedicated scroll region keeps all controls reachable
/// without pushing the first card. No clipping-only overflow policy is used.
struct FeedChromeSlot<Content: View>: View {
    let reservedHeight: CGFloat?
    @ViewBuilder let content: () -> Content
    var body: some View {
        if let reservedHeight {
            ScrollView(.vertical) { content().frame(maxWidth: .infinity, alignment: .leading) }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: reservedHeight)
        } else { content() }
    }
}
#if DEBUG
private struct FeedChromeTestCacheKey: EnvironmentKey {
    static let defaultValue: FeedStaleSummaryCache? = nil
}
extension EnvironmentValues {
    var feedChromeTestCache: FeedStaleSummaryCache? {
        get { self[FeedChromeTestCacheKey.self] }
        set { self[FeedChromeTestCacheKey.self] = newValue }
    }
}
#endif

#if DEBUG
private struct FeedChromeTestSafetyKey: EnvironmentKey {
    static let defaultValue: CommunitySafetyStore? = nil
}
extension EnvironmentValues {
    var feedChromeTestSafety: CommunitySafetyStore? {
        get { self[FeedChromeTestSafetyKey.self] }
        set { self[FeedChromeTestSafetyKey.self] = newValue }
    }
}
#endif
