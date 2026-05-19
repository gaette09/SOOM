import SwiftUI

struct HealthKitStatusCard: View {
    let status: HealthKitConnectionStatus

    var body: some View {
        SOOMCard {
            SOOMActionRow(
                icon: status.icon,
                title: status.title,
                subtitle: status.subtitle,
                tint: status.tint
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.title)
        .accessibilityValue(status.subtitle)
    }
}

enum HealthKitConnectionStatus {
    case notAvailable
    case notRequested
    case authorized
    case accessLimited

    var title: String {
        switch self {
        case .notAvailable:
            return "HealthKit을 사용할 수 없어요"
        case .notRequested:
            return "HealthKit 연결 안 됨"
        case .authorized:
            return "운동 데이터 접근 허용됨"
        case .accessLimited:
            return "운동 데이터 접근 확인 필요"
        }
    }

    var subtitle: String {
        switch self {
        case .notAvailable:
            return "이 기기에서는 건강 데이터 접근을 사용할 수 없습니다."
        case .notRequested:
            return "Apple 건강 앱의 운동 기록을 읽기 위한 준비 상태입니다."
        case .authorized:
            return "최근 운동 기록을 읽어올 수 있는 상태입니다."
        case .accessLimited:
            return "권한 상태를 확인하고 필요한 데이터 접근을 다시 허용해 주세요."
        }
    }

    var icon: String {
        switch self {
        case .notAvailable:
            return SOOMIcon.health
        case .notRequested:
            return SOOMIcon.sync
        case .authorized:
            return SOOMIcon.checkCircle
        case .accessLimited:
            return SOOMIcon.health
        }
    }

    var tint: Color {
        switch self {
        case .notAvailable, .accessLimited:
            return SOOMColor.warning
        case .notRequested:
            return SOOMColor.secondaryInk
        case .authorized:
            return SOOMColor.recovery
        }
    }
}

#Preview("HealthKitStatusCard") {
    SOOMScreen {
        HealthKitStatusCard(status: .notRequested)
        HealthKitStatusCard(status: .authorized)
    }
    .preferredColorScheme(.light)
}
