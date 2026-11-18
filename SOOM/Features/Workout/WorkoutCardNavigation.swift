import SwiftUI

/// Register destinations on the screen, outside lazy rows. Cards only emit
/// selection actions, so recycled rows cannot remove an active destination.
extension View {
    func workoutCardDestination(selection: Binding<UnifiedWorkout?>) -> some View {
        modifier(OwnWorkoutCardDestination(selection: selection))
    }

    func feedCardDestination(selection: Binding<FeedItem?>,
                             onSubmitComment: ((FeedItem, String) async throws -> Void)? = nil) -> some View {
        modifier(FeedWorkoutCardDestination(selection: selection, onSubmitComment: onSubmitComment))
    }
}

private struct OwnWorkoutCardDestination: ViewModifier {
    @Binding var selection: UnifiedWorkout?
    @ObservedObject private var safety = CommunitySafetyStore.shared
    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: Binding(
            get: { selection != nil }, set: { if !$0 { selection = nil } }
        )) {
            if let workout = selection { OwnWorkoutDetailDestination(workout: workout) }
        }
        .onChange(of: safety.accountGeneration) { _, _ in selection = nil }
    }
}

private struct FeedWorkoutCardDestination: ViewModifier {
    @Binding var selection: FeedItem?
    let onSubmitComment: ((FeedItem, String) async throws -> Void)?
    @ObservedObject private var safety = CommunitySafetyStore.shared
    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: Binding(
            // The destination's SocialAccessBoundary masks/revalidates access.
            // A temporary verification pause is not a user back-navigation.
            get: { selection != nil }, set: { if !$0 { selection = nil } }
        )) {
            if let item = selection {
                if let onSubmitComment {
                    FeedItemDetailDestination(item: item, onSubmitComment: { try await onSubmitComment(item, $0) })
                } else { FeedItemDetailDestination(item: item) }
            }
        }
        .onChange(of: safety.accountGeneration) { _, _ in selection = nil }
        .onChange(of: safety.revision) { _, _ in
            if let item = selection, safety.isBlocked(item.authorId) { selection = nil }
        }
    }
}
