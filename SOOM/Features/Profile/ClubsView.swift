import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var viewModel: CommunityViewModel

    var body: some View {
        SOOMScreen {
            SOOMCard {
                SOOMSectionHeader("함께 움직이기", caption: "기록보다 분위기와 약속이 먼저 보이는 공간")
                Label("지역 기반 브릭 세션", systemImage: SOOMIcon.map)
                Label("천천히 시작하는 그룹런", systemImage: SOOMIcon.people)
                Label("처음 오는 사람도 편한 모임", systemImage: SOOMIcon.clubs)
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)

            if viewModel.clubs.isEmpty {
                SOOMFirstJourneyCard(
                    prompt: .club,
                    actions: [
                        SOOMFirstJourneyAction(
                            title: "동네 클럽 둘러보기",
                            subtitle: "가까운 곳에서 천천히 움직이는 사람들을 먼저 찾아봅니다.",
                            iconName: SOOMIcon.map
                        ),
                        SOOMFirstJourneyAction(
                            title: "느린 페이스로 시작",
                            subtitle: "처음에는 기록보다 같이 나가는 약속이 더 중요해요.",
                            iconName: SOOMIcon.people
                        )
                    ],
                    footer: "클럽은 경쟁보다 같이 시작하는 분위기를 먼저 보여줍니다."
                )
            } else {
                ForEach(viewModel.clubs) { club in
                    NavigationLink {
                        ClubDetailView(club: club)
                    } label: {
                        SOOMCard {
                            Text(club.name)
                                .font(SOOMFont.display(20, relativeTo: .title3))
                                .foregroundStyle(SOOMColor.ink)
                            Text("\(club.location) · \(club.memberCount)명")
                                .font(SOOMFont.body(12, relativeTo: .caption))
                                .foregroundStyle(SOOMColor.secondaryInk)
                            Text(club.description)
                                .font(SOOMFont.body(15, relativeTo: .subheadline))
                                .foregroundStyle(SOOMColor.secondaryInk)
                            HStack {
                                SOOMMetricPill("멤버", "\(club.memberCount)명", tint: SOOMColor.bike)
                                SOOMMetricPill("주간 볼륨", club.weeklyVolume, tint: SOOMColor.swim)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
