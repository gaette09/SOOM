import SwiftUI

struct ProfileHeroStat: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

struct ProfileSummaryCard: View {
    let name: String
    let handle: String
    let identityTitle: String
    let representativeBadgeTitle: String
    let representativeBadgeSubtitle: String
    let representativeBadgeState: String
    let compactStats: [ProfileHeroStat]
    let authStatus: String

    init(
        name: String = "SOOM 사용자",
        handle: String = "@soom.local",
        identityTitle: String = "나의 운동 리듬을 만드는 중",
        representativeBadgeTitle: String = "첫 리듬",
        representativeBadgeSubtitle: String = "정체성 준비 중",
        representativeBadgeState: String = "준비 중",
        compactStats: [ProfileHeroStat] = [
            ProfileHeroStat(id: "active-days", title: "움직인 날", value: "첫 기록 대기"),
            ProfileHeroStat(id: "distance", title: "누적 거리", value: "0km"),
            ProfileHeroStat(id: "sport", title: "대표 종목", value: "준비 중")
        ],
        authStatus: String = "로컬 사용자"
    ) {
        self.name = name
        self.handle = handle
        self.identityTitle = identityTitle
        self.representativeBadgeTitle = representativeBadgeTitle
        self.representativeBadgeSubtitle = representativeBadgeSubtitle
        self.representativeBadgeState = representativeBadgeState
        self.compactStats = compactStats
        self.authStatus = authStatus
    }

    var body: some View {
        SOOMCard(depth: .primary) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(SOOMColor.accentSurface.opacity(0.72))
                    .frame(width: 132, height: 132)
                    .offset(x: 44, y: -58)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        avatar

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: SOOMLayout.Metrics.actionTextSpacing) {
                                Text(name)
                                    .font(SOOMFont.display(25, relativeTo: .title2))
                                    .foregroundStyle(SOOMColor.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)

                                Text(authStatus)
                                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                    .foregroundStyle(SOOMColor.accentInk)
                                    .padding(.horizontal, SOOMLayout.Metrics.tagSpacing)
                                    .padding(.vertical, 4)
                                    .background(SOOMColor.accentSurface)
                                    .clipShape(Capsule())
                            }

                            Text(handle)
                                .font(SOOMFont.body(12, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.secondaryInk)
                        }
                    }

                    Text(identityTitle)
                        .font(SOOMFont.displayMedium(29, relativeTo: .title))
                        .foregroundStyle(SOOMColor.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    representativeBadge
                    compactStatsRow
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Movement Identity Card")
        .accessibilityValue("\(name), \(handle), \(identityTitle), 대표 뱃지 \(representativeBadgeTitle), \(compactStats.map(\.value).joined(separator: ", ")), \(authStatus)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(SOOMColor.surface)
            Circle()
                .stroke(SOOMColor.accentLine, lineWidth: 2)
                .padding(2)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(SOOMColor.accent)
        }
        .frame(width: 66, height: 66)
        .shadow(color: SOOMColor.accent.opacity(0.10), radius: 14, x: 0, y: 8)
        .accessibilityHidden(true)
    }

    private var representativeBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "seal.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SOOMColor.accent)
                .frame(width: 42, height: 42)
                .background(SOOMColor.accentSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("대표 뱃지")
                    .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.tertiaryInk)
                Text(representativeBadgeTitle)
                    .font(SOOMFont.body(17, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(SOOMColor.ink)
                Text(representativeBadgeSubtitle)
                    .font(SOOMFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(SOOMColor.secondaryInk)
            }

            Spacer(minLength: 0)

            Text(representativeBadgeState)
                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                .foregroundStyle(SOOMColor.accentInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(SOOMColor.accentSurface)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(SOOMColor.surfaceMuted.opacity(0.92))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(SOOMColor.accent)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: SOOMRadius.card, style: .continuous))
    }

    private var compactStatsRow: some View {
        HStack(spacing: SOOMLayout.Metrics.compactListSpacing) {
            ForEach(Array(compactStats.enumerated()), id: \.element.id) { _, stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.title)
                        .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(SOOMColor.tertiaryInk)
                    Text(stat.value)
                        .font(SOOMFont.body(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
    }
}
