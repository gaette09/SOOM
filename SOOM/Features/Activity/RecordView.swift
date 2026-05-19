import SwiftUI

struct RecordView: View {
    var body: some View {
        SOOMScreen {
            Text("기록")
                .font(SOOMFont.display(38, relativeTo: .largeTitle))
                .foregroundStyle(SOOMColor.ink)

            SOOMCard {
                SOOMSectionHeader("운동 시작")
                SOOMActionRow(icon: SOOMIcon.swim, title: "수영 기록", subtitle: "풀 수영과 오픈워터 세션을 기록합니다.", tint: SOOMColor.swim)
                SOOMActionRow(icon: SOOMIcon.bike, title: "사이클 기록", subtitle: "파워, 케이던스, 고도 변화를 분석합니다.", tint: SOOMColor.bike)
                SOOMActionRow(icon: SOOMIcon.run, title: "러닝 기록", subtitle: "페이스, 심박, 스플릿을 기록합니다.", tint: SOOMColor.run)
            }

            SOOMCard {
                SOOMSectionHeader("데이터 연결")
                Label("Apple Health 연동 예정", systemImage: SOOMIcon.health)
                Label("Garmin, Strava, Wahoo 가져오기 구조 예정", systemImage: SOOMIcon.sync)
                Label("더미 하네스 데이터로 UI와 분석 흐름 검증 중", systemImage: SOOMIcon.package)
            }
            .font(SOOMFont.body(15, relativeTo: .subheadline))
            .foregroundStyle(SOOMColor.ink)

            SOOMCard {
                SOOMSectionHeader("수동 입력")
                SOOMActionRow(icon: SOOMIcon.edit, title: "운동 직접 추가", subtitle: "종목, 거리, 시간, 강도, 메모를 입력합니다.", tint: SOOMColor.recovery)
            }
        }
        .navigationTitle("기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}
