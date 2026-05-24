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
                SOOMSectionHeader(
                    "데이터 연결",
                    caption: "외부 운동 기록을 SOOM 분석용 데이터로 가져옵니다."
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

                NavigationLink {
                    UnifiedWorkoutLibraryViewContainer()
                } label: {
                    SOOMActionRow(
                        icon: SOOMIcon.package,
                        title: "가져온 운동 기록 보기",
                        subtitle: "SOOM에 저장된 공통 운동 기록과 분석 제외 상태를 확인합니다.",
                        tint: SOOMColor.secondaryInk
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("가져온 운동 기록 보기")
                .accessibilityHint("SOOM에 저장된 운동 기록 목록으로 이동합니다.")
            }

            SOOMCard {
                SOOMSectionHeader("수동 입력")
                SOOMActionRow(icon: SOOMIcon.edit, title: "운동 직접 추가", subtitle: "종목, 거리, 시간, 강도, 메모를 입력합니다.", tint: SOOMColor.recovery)
            }

            SOOMCard {
                SOOMSectionHeader(
                    "마이 / 설정",
                    caption: "프로필, 공개 범위, 운동 기준값을 관리합니다."
                )

                NavigationLink {
                    SettingsView()
                } label: {
                    SOOMActionRow(
                        icon: "person.crop.circle",
                        title: "마이페이지 열기",
                        subtitle: "HealthKit 관리, FTP, 최대 심박, 공개 범위 설정을 확인합니다.",
                        tint: SOOMColor.secondaryInk
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("마이페이지 열기")
                .accessibilityHint("프로필과 설정 화면으로 이동합니다.")
            }
        }
        .navigationTitle("기록")
        .navigationBarTitleDisplayMode(.inline)
    }
}
