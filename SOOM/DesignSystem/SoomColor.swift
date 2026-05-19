import SwiftUI

enum SOOMColor {
    static let blue = Color(hex: 0x0047AB)
    static let orange = Color(hex: 0xFF8F00)
    static let green = Color(hex: 0x16302B)
    static let red = Color(hex: 0xB80F0A)
    static let black = Color(hex: 0x161616)
    static let white = Color(hex: 0xFCFCF0)

    static let background = white
    static let surface = white
    static let surfaceMuted = white.opacity(0.72)
    static let ink = black
    static let secondaryInk = black.opacity(0.62)
    static let tertiaryInk = black.opacity(0.42)
    static let line = black.opacity(0.14)
    static let swim = blue
    static let bike = green
    static let run = red
    static let warning = orange
    static let recovery = blue.opacity(0.74)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
