import SwiftUI

enum SOOMMotion {
    enum Duration {
        static let quick: Double = 0.12
        static let normal: Double = 0.20
        static let slow: Double = 0.32
        static let background: Double = 0.80
    }

    enum Scale {
        static let pressed: CGFloat = 0.98
        static let subtlePressed: CGFloat = 0.99
        static let selected: CGFloat = 1.02
    }

    enum Offset {
        static let cardRevealY: CGFloat = 8
        static let subtleRevealY: CGFloat = 4
    }

    enum Opacity {
        static let hidden: Double = 0
        static let visible: Double = 1
        static let muted: Double = 0.72
    }

    static let quickEaseOut = Animation.easeOut(duration: Duration.quick)
    static let normalEaseOut = Animation.easeOut(duration: Duration.normal)
    static let slowEaseOut = Animation.easeOut(duration: Duration.slow)
    static let subtleSpring = Animation.spring(response: 0.28, dampingFraction: 0.88)
}
