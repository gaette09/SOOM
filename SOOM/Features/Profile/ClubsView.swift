import SwiftUI

struct ClubsView: View {
    @EnvironmentObject private var viewModel: CommunityViewModel

    var body: some View {
        SOOMScreen {
            Text("클럽")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            SOOMCard {
                SOOMSectionHeader("함께 훈련하기", caption: "같은 목표를 가진 사람들과 꾸준히 쌓아가는 공간")
                Label("지역 기반 브릭 세션", systemImage: SOOMIcon.map)
                Label("주간 볼륨 랭킹과 출석", systemImage: SOOMIcon.chartBar)
                Label("대회 준비 그룹", systemImage: SOOMIcon.clubs)
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)

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
        .navigationTitle("클럽")
        .navigationBarTitleDisplayMode(.inline)
    }
}
