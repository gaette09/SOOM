import SwiftUI

/// Ephemeral, account-root-owned presentation state. Contains no measurements.
final class WorkoutDetailPresentationStore {
    struct Snapshot {
        var sheet: WorkoutSheetPosition = .standard
        var scroll: CGFloat = 0
        var charts = false
        var splits = false
        var revealed: Set<String> = []
    }
    private var values: [UUID: Snapshot] = [:]
    private var order: [UUID] = []
    func value(_ id: UUID) -> Snapshot { values[id] ?? Snapshot() }
    func update(_ id: UUID, _ edit: (inout Snapshot) -> Void) {
        if values[id] == nil { order.append(id) }
        edit(&values[id, default: Snapshot()])
        if order.count > 24 { values.removeValue(forKey: order.removeFirst()) }
    }
    func hasRevealed(_ id: UUID, key: String) -> Bool { value(id).revealed.contains(key) }
    func claimReveal(_ id: UUID, key: String) -> Bool {
        guard !hasRevealed(id, key: key) else { return false }
        update(id) { $0.revealed.insert(key) }
        return true
    }
    func resetReveal(_ id: UUID, prefix: String) {
        update(id) { $0.revealed = $0.revealed.filter { !$0.hasPrefix(prefix) } }
    }
    func clear() { values = [:]; order = [] }
}
private struct WorkoutDetailPresentationStoreKey: EnvironmentKey {
    static let defaultValue: WorkoutDetailPresentationStore? = nil
}
extension EnvironmentValues {
    var workoutDetailPresentationStore: WorkoutDetailPresentationStore? {
        get { self[WorkoutDetailPresentationStoreKey.self] }
        set { self[WorkoutDetailPresentationStoreKey.self] = newValue }
    }
}

struct WorkoutRevealContext {
    let store: WorkoutDetailPresentationStore
    let workoutID: UUID
    func contains(_ key: String) -> Bool { store.hasRevealed(workoutID, key: key) }
    func claim(_ key: String) -> Bool { store.claimReveal(workoutID, key: key) }
    func reset(_ prefix: String) { store.resetReveal(workoutID, prefix: prefix) }
}
private struct WorkoutRevealContextKey: EnvironmentKey { static let defaultValue: WorkoutRevealContext? = nil }
extension EnvironmentValues {
    var workoutRevealContext: WorkoutRevealContext? {
        get { self[WorkoutRevealContextKey.self] }
        set { self[WorkoutRevealContextKey.self] = newValue }
    }
}

struct WorkoutBottomSheet<Header: View, SheetContent: View, SheetGesture: Gesture>: View {
    let metrics: WorkoutSheetMetrics
    let isScrollDisabled: Bool
    let sheetGesture: SheetGesture
    let onScrollOffsetChange: (CGFloat) -> Void
    let header: Header
    let content: SheetContent
    let restoredScrollOffset: CGFloat
    let onUserScrollOffsetChange: (CGFloat) -> Void
    let resetScrollRevision: Int
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var didRestoreScroll = false
    @State private var isUserScrolling = false

    init(
        metrics: WorkoutSheetMetrics,
        isScrollDisabled: Bool,
        sheetGesture: SheetGesture,
        onScrollOffsetChange: @escaping (CGFloat) -> Void,
        restoredScrollOffset: CGFloat = 0,
        resetScrollRevision: Int = 0,
        onUserScrollOffsetChange: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> SheetContent
    ) {
        self.metrics = metrics
        self.isScrollDisabled = isScrollDisabled
        self.sheetGesture = sheetGesture
        self.onScrollOffsetChange = onScrollOffsetChange
        self.restoredScrollOffset = restoredScrollOffset
        self.resetScrollRevision = resetScrollRevision
        self.onUserScrollOffsetChange = onUserScrollOffsetChange
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
                .padding(.top, metrics.isExpanded ? SOOMLayout.stackSpacing : 0)
                .padding(.bottom, metrics.scrollBottomPadding)
            }
            .coordinateSpace(name: "WorkoutSheetScroll")
            .scrollDisabled(isScrollDisabled)
            .scrollPosition($scrollPosition)
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .interacting || phase == .decelerating
            }
            .task {
                guard !didRestoreScroll else { return }
                await Task.yield()
                if restoredScrollOffset > 0 { scrollPosition.scrollTo(y: restoredScrollOffset) }
                await Task.yield()
                didRestoreScroll = true
            }
            .onChange(of: resetScrollRevision) { _, _ in
                isUserScrolling = false
                var transaction = Transaction(); transaction.animation = nil
                withTransaction(transaction) { scrollPosition.scrollTo(y: 0) }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                onScrollOffsetChange(newOffset)
                if didRestoreScroll && isUserScrolling { onUserScrollOffsetChange(newOffset) }
            }
        }
        .frame(height: metrics.sheetFrameHeight)
        .background(SOOMColor.background)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: metrics.topCornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: metrics.topCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(metrics.shadowOpacity), radius: SOOMLayout.DetailSheet.shadowRadius, x: 0, y: SOOMLayout.DetailSheet.shadowYOffset)
        .contentShape(Rectangle())
        .offset(y: metrics.sheetYOffset)
        // In map preview a vertical drag must cancel descendant profile taps.
        // Expanded content keeps its own native scroll gesture.
        .highPriorityGesture(sheetGesture, including: metrics.isExpanded ? .none : .all)
        .simultaneousGesture(sheetGesture, including: metrics.isExpanded ? .all : .none)
        .animation(.spring(response: SOOMLayout.DetailSheet.sheetAnimationResponse, dampingFraction: SOOMLayout.DetailSheet.sheetAnimationDamping), value: metrics.isExpanded)
    }
}

private struct WorkoutDetailVisitStoreKey: EnvironmentKey { static let defaultValue: WorkoutDetailPresentationStore? = nil }
extension EnvironmentValues {
    var workoutDetailVisitStore: WorkoutDetailPresentationStore? {
        get { self[WorkoutDetailVisitStoreKey.self] }
        set { self[WorkoutDetailVisitStoreKey.self] = newValue }
    }
}
