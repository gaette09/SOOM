import SwiftUI

enum SOOMPublicInformation {
    static let operatorName = "CHUNG JIHWAN"
    static let supportEmail = "support@example.invalid"
    static let supportURL = URL(string: "mailto:support@example.invalid")!

    static var privacyPolicyURL: URL? {
        validatedPolicyURL(Bundle.main.object(forInfoDictionaryKey: "SOOMPrivacyPolicyURL") as? String)
    }

    static func validatedPolicyURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("$("), !value.isEmpty,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains("."), host != "example.com",
              !host.hasSuffix(".example.com"), url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct PrivacyAndSupportView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    var body: some View {
        List {
            if let owner = auth.session.currentUser?.id, !ReviewDemoMode.isActive { NavigationLink("계정 · 새 운동 공개범위") { AccountPrivacySettingsView(owner: owner) } }
            if let client = SupabaseClientProvider(environment: AuthEnvironmentLoader().load()).makeClient(),
               let owner = auth.session.currentUser?.id, !ReviewDemoMode.isActive {
                NavigationLink("새 기능 연결 테스트") {
                    AccountActivityPreviewScreen(service: .init(client: client, owner: owner))
                }
            }
            Section("운동과 건강 정보") {
                Text("허용한 Apple 건강 앱의 운동·심박·거리·에너지·경로 정보를 읽어 운동 분석과 회복 안내에 사용해요. SOOM은 Apple 건강 앱에 기록을 쓰지 않아요.")
                Text("Google Health 연결에 동의하면 운동 요약과 제공되는 구간·존·센서 정보를 가져와요. 위치·건강 측정값 읽기를 추가 허용하면 GPS 경로와 운동 중 심박수도 가져옵니다. 해당 운동 시간 밖의 건강 정보는 조회하지 않아요. 연결 화면에서 접근을 해제할 수 있습니다.")
                Text("로그인 후 동기화에 동의하면 운동·GPS 경로·심박 등 운동 지표, 체크인·회복 기록을 계정별로 Supabase 서버에 보관하고 복원해요. 인터넷이 없으면 기기에 임시 보관하고 연결 후 전송해요. 로그인 전 기록의 이관은 별도로 선택합니다.")
            }
            Section("운동 중 위치 기록") {
                Text("사용자가 시작한 운동은 화면이 잠긴 동안에도 GPS 경로를 기록해요. 일시정지·종료하면 운동 위치 수집을 멈춥니다. 위치 권한을 철회하면 새 위치를 수집하지 않아요.")
                Text("건강 정보에 기반한 안내와 내 기록 순위는 운동을 돌아보기 위한 참고 정보이며 진단이나 치료를 제공하지 않아요.")
            }
            Section("공유를 선택할 때") {
                Text("계정 공개범위를 먼저 선택해요. 새 운동은 선택한 기본 공개범위를 따르며, 기존 기록의 공개범위는 자동으로 바뀌지 않아요. 비공개 계정의 운동은 승인된 팔로워까지만 볼 수 있어요. 직접 기록하거나 수동 입력한 운동도 운동별로 공개범위를 선택할 수 있어요.")
                Text("피드에는 선택한 운동의 종목·시간·거리·페이스, 작성한 제목과 글, 계정 표시 정보가 전송돼요. 경로·측정 차트 공유를 별도로 켜면 선택한 운동의 측정값과 시작·끝 200m를 가린 경로도 공유돼요. AI·회복·과거 비교와 체크인 메모는 본인만 봐요. 건강 데이터 클라우드 저장 동의와 공개범위 선택은 별개예요.")
                Text("별도 공유 이미지에는 경로가 들어갈 수 있어요. 시작·종료 부근을 가려도 익숙한 장소가 드러날 수 있으니 내보내기 전에 미리보기를 확인해 주세요.")
            }
            Section("지도, 날씨와 알림") {
                Text("지도와 경로 이미지는 Mapbox를 사용해요. 지도 이용 중 위치와 서비스 사용 정보가 처리될 수 있고, 경로 이미지를 만들 때 가림 처리가 적용된 경로 좌표가 Mapbox로 전송돼요.")
                Text("위치를 허용하면 현재 위치의 날씨를 요청할 때 좌표가 OpenWeather로 전송돼요. 권한은 iPhone 설정에서 언제든 변경할 수 있어요.")
                Text("알림을 허용하고 로그인하면 기기 알림 토큰을 계정과 연결해 응원·댓글 알림을 보내요.")
            }
            Section("계정과 커뮤니티") {
                Text("로그인한 계정, 프로필, 공유한 글, 댓글·응원·저장, 클럽 정보는 온라인 서비스에서 처리해요. 신고 내용과 대상 콘텐츠는 운영 검토에 사용하며, 차단 목록은 계정에 저장돼요.")
                Text("표시 이름과 공개 게시물에 연락처나 다른 사람의 개인정보를 넣지 않도록 주의해 주세요.")
            }
            Section("삭제와 권한 변경") {
                Text("동기화를 중지하면 새 전송과 복원을 멈추며 이미 서버에 저장한 기록은 유지돼요. 계정 삭제는 온라인 계정의 운동·경로·체크인·회복 기록과 게시물·소유한 클럽, 현재 계정의 기기 사본을 삭제해요. 기기 데이터 초기화는 로그인 전 이 기기의 기록을 지워요. Apple 건강 앱의 원본은 삭제하지 않아요.")
                Text("건강·위치·알림 권한은 iPhone 설정에서 변경할 수 있어요. 다른 기기의 사본, 내보낸 이미지, iPhone 백업은 별도로 관리해 주세요.")
            }
            Section("개인정보처리방침 및 문의") {
                if let url = SOOMPublicInformation.privacyPolicyURL {
                    Link("개인정보처리방침 열기", destination: url)
                }
                Text("운영자: " + SOOMPublicInformation.operatorName)
                Link(SOOMPublicInformation.supportEmail, destination: SOOMPublicInformation.supportURL)
            }
        }
        .safeAreaPadding(.bottom, bottomOverlayInset)
        .navigationTitle("데이터 사용 안내")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CommunityRulesView: View {
    @Environment(\.soomBottomOverlayInset) private var bottomOverlayInset
    var body: some View {
        List {
            Section("함께 지켜 주세요") {
                Text("괴롭힘, 혐오와 차별, 성적 콘텐츠, 폭력과 위협, 스팸, 불법 활동 및 타인의 개인정보 공개를 금지해요.")
                Text("공유하는 글과 이미지에 대한 권리가 있어야 해요. 다른 사람의 위치·건강·연락처 정보를 동의 없이 게시하지 마세요.")
            }
            Section("신고와 차단") {
                Text("게시물·댓글·클럽의 더 보기 메뉴에서 콘텐츠 또는 사용자를 신고하고 차단할 수 있어요. 차단하면 서로의 콘텐츠와 알림이 제한돼요. 설정에서 차단을 해제할 수 있어요.")
                Text("신고는 운영자가 검토하며, 규칙을 위반한 콘텐츠는 삭제하거나 계정 이용을 제한할 수 있어요. 게시 전 필터가 일부 부적절한 표현을 차단할 수 있어요.")
                Link("고객지원 및 신고 문의: " + SOOMPublicInformation.supportEmail, destination: SOOMPublicInformation.supportURL)
            }
        }
        .safeAreaPadding(.bottom, bottomOverlayInset)
        .navigationTitle("커뮤니티 이용 규칙")
        .navigationBarTitleDisplayMode(.inline)
    }
}
