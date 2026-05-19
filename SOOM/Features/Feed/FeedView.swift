import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var viewModel: CommunityViewModel

    var body: some View {
        SOOMScreen {
            Text("피드")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            ForEach(viewModel.posts) { post in
                NavigationLink {
                    FeedPostDetailView(post: post)
                } label: {
                    SOOMCard {
                        HStack {
                            Image(systemName: post.sport.iconName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(post.sport.tint)
                                .frame(width: 48, height: 48)
                                .background(post.sport.tint.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.cardRadius, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.athleteName)
                                    .font(SOOMFont.displayMedium(17, relativeTo: .headline))
                                    .foregroundStyle(SOOMColor.ink)
                                Text(post.handle)
                                    .font(SOOMFont.body(12, relativeTo: .caption))
                                    .foregroundStyle(SOOMColor.secondaryInk)
                            }
                            Spacer()
                            Text(post.sport.title)
                                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(post.sport.tint)
                        }

                        Text(post.title)
                            .font(SOOMFont.display(20, relativeTo: .title3))
                            .foregroundStyle(SOOMColor.ink)
                        Text(post.caption)
                            .font(SOOMFont.body(15, relativeTo: .subheadline))
                            .foregroundStyle(SOOMColor.secondaryInk)
                            .lineLimit(3)

                        HStack {
                            SOOMMetricPill("거리", post.distance, tint: post.sport.tint)
                            SOOMMetricPill("시간", post.duration, tint: SOOMColor.ink)
                        }

                        HStack(spacing: 16) {
                            Label("\(post.likes)", systemImage: SOOMIcon.thumbsUp)
                            Label("\(post.comments)", systemImage: SOOMIcon.comment)
                        }
                        .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(SOOMColor.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("피드")
        .navigationBarTitleDisplayMode(.inline)
    }
}
