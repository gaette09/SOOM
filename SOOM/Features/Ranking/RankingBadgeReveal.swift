import SwiftUI

/// Visual-only presentation. Callers must supply an authoritative earned badge;
/// this component neither calculates tiers nor mutates user achievements.
struct RankingBadgeReveal: View {
    let title: String
    let detail: String
    let isPreview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    var body: some View {
        VStack(spacing: 24) {
            if isPreview { Text("동작 미리보기 · 실제 획득한 등급이 아닙니다").font(.caption).foregroundStyle(.secondary) }
            Image(systemName: "seal.fill")
                .font(.system(size: 130))
                .foregroundStyle(LinearGradient(colors: [.yellow.opacity(0.6), .white, .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "water.waves").font(.system(size: 48, weight: .light)).foregroundStyle(.white))
                .rotation3DEffect(.degrees(reduceMotion ? 0 : revealed ? 0 : -80), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(reduceMotion ? 1 : revealed ? 1 : 0.82)
                .opacity(reduceMotion || revealed ? 1 : 0)
                .accessibilityHidden(true)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(detail).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("닫기") { dismiss() }.buttonStyle(.borderedProminent).tint(.purple)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SOOMColor.background)
            .task { withAnimation(reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.78)) { revealed = true } }
            .accessibilityIdentifier("ranking.badge.reveal")
    }
}
