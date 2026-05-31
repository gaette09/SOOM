import SwiftUI

enum SOOMColor {
    static let purple = Color(hex: 0x7541EE)
    static let lavender = Color(hex: 0xECE5FF)
    static let purpleInk = Color(hex: 0x2D1B55)
    static let blue = Color(hex: 0x3F6F8F)
    static let orange = Color(hex: 0xB9853B)
    static let green = Color(hex: 0x496B5B)
    static let red = Color(hex: 0x9A5A50)
    static let black = Color(hex: 0x20211E)
    static let white = Color(hex: 0xFFFDF7)

    static let background = Color(hex: 0xF6F4EC)
    static let surface = white
    static let surfaceMuted = Color(hex: 0xF0EEE5)
    static let surfaceAmbient = Color(hex: 0xFAF8F1)
    static let ink = black
    static let secondaryInk = black.opacity(0.56)
    static let tertiaryInk = black.opacity(0.36)
    static let line = black.opacity(0.08)
    static let accent = purple
    static let accentSurface = lavender
    static let accentInk = purpleInk
    static let accentMuted = purple.opacity(0.14)
    static let accentLine = purple.opacity(0.22)
    static let selectedSurface = accent
    static let selectedInk = white
    static let swim = blue
    static let bike = green
    static let run = red
    static let warning = orange
    static let recovery = blue.opacity(0.64)
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
