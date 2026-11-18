import SwiftUI

/// Presentation only. Host must authenticate account, fetch notice status/capabilities,
/// and persist both choices. No permission prompt or address book access on appearance.
struct ContactDiscoveryConsentView: View {
    let isExistingAccount: Bool
    let capabilities: ContactDiscoveryCapabilities
    let isBusy: Bool
    let errorMessage: String?
    let connect: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 38)).foregroundStyle(Color.purple)
                .accessibilityHidden(true)
            Text(isExistingAccount ? "아는 사람과 함께 운동해요" : "함께 운동할 친구를 찾아요")
                .font(.title2.bold())
            Text("연락처 연결은 선택이에요. 연결하지 않아도 숨의 다른 기능을 사용할 수 있어요.")
                .font(.body).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label("허용한 연락처의 이메일로 친구를 찾아요", systemImage: "person.crop.rectangle")
                Label("상대가 찾기를 허용한 계정만 추천해요", systemImage: "checkmark.shield")
                Label("설정에서 연결을 끄고 저장 정보를 삭제할 수 있어요", systemImage: "slider.horizontal.3")
            }.font(.subheadline)
            Text("다음 단계에서 iPhone의 연락처 접근 권한을 따로 확인합니다. 현재 이메일이 일치하는 가입자만 찾을 수 있으며, 운동 공개 설정은 바뀌지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
            if !capabilities.ready {
                Text("연락처 연결 기능을 준비하고 있어요. 지금은 연락처를 읽거나 전송하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("contacts.error") }
            Button(action: connect) {
                HStack { if isBusy { ProgressView() }; Text("연락처 연결하기").bold() }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(isBusy || !capabilities.ready)
            .accessibilityIdentifier("contacts.connect")
            Button("나중에", action: later)
                .frame(maxWidth: .infinity).disabled(isBusy)
                .accessibilityIdentifier("contacts.later")
        }
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}
