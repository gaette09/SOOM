import SwiftUI

struct RecordView: View {
    var body: some View {
        SOOMScreen {
            firstWorkoutJourneySection

            SOOMCard {
                SOOMSectionHeader("운동 시작")
                SOOMActionRow(icon: SOOMIcon.swim, title: "수영 기록", subtitle: "풀 수영과 오픈워터 세션을 기록합니다.", tint: SOOMColor.swim)
                SOOMActionRow(icon: SOOMIcon.bike, title: "사이클 기록", subtitle: "파워, 케이던스, 고도 변화를 분석합니다.", tint: SOOMColor.bike)
                SOOMActionRow(icon: SOOMIcon.run, title: "러닝 기록", subtitle: "페이스, 심박, 스플릿을 기록합니다.", tint: SOOMColor.run)
                SOOMActionRow(icon: SOOMIcon.map, title: "경로 기반 기록", subtitle: "route와 navigation 흐름을 담을 자리입니다.", tint: SOOMColor.secondaryInk)
            }

            SOOMCard {
                SOOMSectionHeader(
                    "데이터 연결",
                    caption: "기록을 시작하거나 외부 운동 데이터를 가져오는 입구입니다."
                )

                NavigationLink {
                    HealthKitWorkoutImportViewContainer()
                } label: {
                    SOOMActionRow(
                        icon: SOOMIcon.sync,
                        title: "Apple 건강 앱 운동 가져오기",
                        subtitle: "가져온 기록은 성장 분석에 사용되고, Recovery에는 아직 미리보기로만 사용돼요.",
                        tint: SOOMColor.recovery
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apple 건강 앱 운동 가져오기")
                .accessibilityHint("HealthKit 운동 기록을 SOOM으로 가져오는 화면으로 이동합니다.")

                NavigationLink {
                    HealthKitSettingsViewContainer()
                } label: {
                    SOOMActionRow(
                        icon: SOOMIcon.health,
                        title: "Apple 건강 앱 연결 관리",
                        subtitle: "읽기 권한 요청과 연결 상태, 미리보기 화면을 관리합니다.",
                        tint: SOOMColor.bike
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apple 건강 앱 연결 관리")
                .accessibilityHint("HealthKit 권한과 연결 관리 화면으로 이동합니다.")
            }

            SOOMCard {
                SOOMSectionHeader("수동 입력")
                SOOMActionRow(icon: SOOMIcon.edit, title: "운동 직접 추가", subtitle: "종목, 거리, 시간, 강도, 메모를 입력합니다.", tint: SOOMColor.recovery)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var firstWorkoutJourneySection: some View {
        SOOMFirstJourneyCard(
            prompt: .activity,
            actions: [
                SOOMFirstJourneyAction(
                    title: "Health 앱에서 가져오기",
                    subtitle: "이미 움직인 기록이 있다면 첫 피드와 활동 흐름이 바로 시작됩니다.",
                    iconName: SOOMIcon.health
                ),
                SOOMFirstJourneyAction(
                    title: "오늘의 운동 시작하기",
                    subtitle: "짧은 움직임도 route와 story의 첫 조각이 될 수 있어요.",
                    iconName: SOOMIcon.record
                )
            ],
            footer: "첫 움직임이 기록되면 오늘의 흐름이 보이기 시작해요."
        )
    }
}
