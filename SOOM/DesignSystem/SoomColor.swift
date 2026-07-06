import SwiftUI
import UIKit

enum SOOMColor {
    static let purple = Color(hex: 0x7541EE)
    static let lavender = Color(hex: 0xECE5FF)
    static let purpleInk = Color(hex: 0x2D1B55)
    static let textPrimary = Color(hex: 0x111111)
    static let textSecondary = Color(hex: 0x666666)
    static let textTertiary = Color(hex: 0x999999)
    static let surfacePrimary = Color(hex: 0xFFFFFF)
    static let surfaceSecondary = Color(hex: 0xF7F7F7)
    static let blue = Color(hex: 0x3F6F8F)
    static let orange = Color(hex: 0xB9853B)
    static let green = Color(hex: 0x496B5B)
    static let red = Color(hex: 0x9A5A50)
    static let black = textPrimary
    static let white = surfacePrimary

    static let background = surfacePrimary
    static let surface = surfacePrimary
    static let surfaceMuted = surfaceSecondary
    static let surfaceAmbient = surfaceSecondary
    static let ink = textPrimary
    static let secondaryInk = textSecondary
    static let tertiaryInk = textTertiary
    static let line = textPrimary.opacity(0.08)
    static let accent = purple
    static let accentSurface = lavender
    static let accentInk = purpleInk
    static let accentMuted = purple.opacity(0.14)
    static let accentLine = purple.opacity(0.22)
    static let selectedSurface = accentSurface
    static let selectedInk = accentInk
    static let swim = blue
    static let bike = green
    static let run = red
    static let warning = orange
    static let recovery = blue.opacity(0.64)
}

enum SOOMRouteRenderingStyle {
    static let accentHex = "#2F7D5B"
    static let accentColor = Color(hex: 0x2F7D5B)
    static let accentUIColor = UIColor(red: 0x2F / 255, green: 0x7D / 255, blue: 0x5B / 255, alpha: 1)
    static let detailLineWidth: Double = 3.2
    static let feedLineWidth: Double = 2.6
    static let shareOuterLineWidth: CGFloat = 4.4
    static let shareInnerLineWidth: CGFloat = 2.4
    static let shareTransparentOuterLineWidth: CGFloat = 5.2
    static let shareTransparentInnerLineWidth: CGFloat = 3.0
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
