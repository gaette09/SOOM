import SwiftUI

struct WorkoutCoachStrip: View {
    @ObservedObject var coach: WorkoutCoachCoordinator
    let session: RecordWorkoutSession?
    let openSettings: () -> Void
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("기본 운동 안내").font(.caption.weight(.semibold))
                Spacer()
                Button {
                    var preference = coach.preferences
                    preference.enabled.toggle()
                    coach.configure(preference, session: session, at: now)
                } label: {
                    Image(systemName: coach.preferences.enabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(coach.preferences.enabled ? "음성 안내 끄기" : "음성 안내 켜기, 현재 출력 사용")
                .accessibilityIdentifier("coach.voiceToggle")
                Button(action: openSettings) {
                    Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
                }
                .accessibilityLabel("음성 안내 설정")
                .accessibilityIdentifier("coach.settings")
            }
            Text(coach.caption).font(.body).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coach.caption")
            Text(coach.voiceStatus).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("coach.voiceStatus")
            if session?.state == .paused {
                Button("기본 코치 한마디") { coach.localEncouragement() }
                    .frame(minHeight: 48)
                    .accessibilityHint("AI 연결 없이 기기에 저장된 격려 문구를 안내합니다")
                    .accessibilityIdentifier("coach.localPhrase")
                Text("AI 코치 · 서버 미연결\n기본 안내와 기록은 계속 사용할 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coach.aiUnavailable")
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .background(SOOMColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WorkoutCoachSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coach: WorkoutCoachCoordinator
    let session: RecordWorkoutSession?
    var body: some View {
        NavigationStack {
            Form {
                Section("기기 음성 안내 · 베타") {
                    Toggle("음성 안내", isOn: Binding(get: { coach.preferences.enabled }, set: { enabled in
                        var p = coach.preferences; p.enabled = enabled
                        coach.configure(p, session: session, at: Date())
                    }))
                    .accessibilityIdentifier("coach.enableSetting")
                    Picker("안내 간격", selection: Binding(get: { coach.preferences.interval }, set: { interval in
                        var p = coach.preferences; p.interval = interval
                        coach.configure(p, session: session, at: Date())
                    })) {
                        ForEach(CoachInterval.allCases) { value in Text(value.title).tag(value) }
                    }
                    Text("처음에는 음성이 꺼져 있어요. 1km는 변경 가능한 베타 기본값이에요. 거리와 시간 중 한 방식만 안내해요.")
                }
                Section("출력과 접근성") {
                    Text(coach.voiceStatus)
                    Text("한국어 기기 음성을 사용하며 인터넷이나 마이크가 필요하지 않아요. 기기에 한국어 음성이 없으면 텍스트 안내를 유지해요.")
                    Text("통화·출력 변경 뒤에는 음성을 껐다 켜 현재 출력 사용을 확인해 주세요. VoiceOver를 사용 중이면 자동 TTS를 쉬어요.")
                    Text("잠금 중에는 기존 위치 기록 업데이트가 있을 때 안내할 수 있어요. 위치 없는 시간 기록은 백그라운드에서 안내가 지연될 수 있으며 지나간 안내를 다시 읽지 않아요.")
                }
                Section("선택형 AI 코치") {
                    Text("서버 미연결 · 이번 빌드는 외부 AI로 데이터를 보내지 않아요.")
                    Text("연결에 필요한 항목: 서버 인증·별도 전송 동의·한도와 예산 검증·운영 모델·서버 키 설정. 앱에는 공급자 키를 넣지 않아요.")
                }
            }
            .navigationTitle("음성 안내")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.frame(minHeight: 48) } }
        }
    }
}
