import SwiftUI

struct FeedPostDetailView: View {
    let post: FeedPost

    var body: some View {
        Group {
            if let workout = post.linkedWorkout, !workout.route.isEmpty {
                WorkoutMapSheetScaffold(workout: workout, navigationTitle: "피드 상세") {
                    FeedPostDetailContent(post: post)
                }
            } else {
                SOOMScreen {
                    FeedPostDetailContent(post: post)
                }
                .navigationTitle("피드 상세")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .hidesSOOMTabBar()
    }
}

struct FeedPostDetailContent: View {
    let post: FeedPost

    var body: some View {
        Group {
            DetailHeader(icon: post.sport.iconName, title: post.title, subtitle: "\(post.athleteName) \(post.handle)", tint: post.sport.tint)

            SOOMCard {
                SOOMSectionHeader("운동 공유")
                Text(post.caption)
                    .font(SOOMFont.body(17, relativeTo: .body))
                    .foregroundStyle(SOOMColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    SOOMMetricPill("거리", post.distance, tint: post.sport.tint)
                    SOOMMetricPill("시간", post.duration, tint: SOOMColor.ink)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("운동 공유")
            .accessibilityValue(post.caption)

            if let workout = post.linkedWorkout {
                WorkoutMetricsSection(workout: workout)
                WorkoutChartStack(workout: workout)
                WorkoutSplitsCard(workout: workout)
            }

            SOOMCard {
                SOOMSectionHeader("반응")
                HStack {
                    SOOMMetricPill("좋아요", "\(post.likes)", tint: SOOMColor.run)
                    SOOMMetricPill("댓글", "\(post.comments)", tint: SOOMColor.swim)
                }
                Label("좋은 페이스 유지네요. 다음 브릭 세션도 기대됩니다.", systemImage: SOOMIcon.comment)
                Label("후반 자세 유지가 좋아 보여요.", systemImage: SOOMIcon.comment)
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("반응")
            .accessibilityValue("좋아요 \(post.likes), 댓글 \(post.comments)")
        }
    }
}
