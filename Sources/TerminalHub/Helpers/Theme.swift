import SwiftUI

/// Color palette and fonts matching Claude.ai's dark interface.
enum Theme {
    // Backgrounds — Claude's exact greys
    static let bg        = color(0x24, 0x24, 0x23)  // dark grey
    static let surface   = color(0x26, 0x26, 0x24)  // default grey
    static let raised    = color(0x2E, 0x2E, 0x2C)
    static let selected  = color(0x33, 0x33, 0x30)
    static let hover     = color(0x2A, 0x2A, 0x28)

    // Borders / dividers
    static let border    = color(0x33, 0x33, 0x30)
    static let borderLt  = color(0x3A, 0x3A, 0x37)

    // Text — warm whites and grays
    static let textPrimary   = color(0xEC, 0xEC, 0xEA)
    static let textSecondary = color(0xB4, 0xB0, 0xA9)
    static let textMuted     = color(0x7C, 0x78, 0x71)
    static let textDim       = color(0x56, 0x53, 0x4E)
    static let textFaint     = color(0x3C, 0x3A, 0x37)

    // Accents — Claude's orange #d97857
    static let accent    = color(0xD9, 0x78, 0x57)
    static let accentDim = color(0x8C, 0x55, 0x3E)
    static let green     = color(0x6B, 0xB8, 0x7A)
    static let red       = color(0xD9, 0x6C, 0x6C)
    static let redDim    = color(0x8C, 0x5A, 0x5A)
    static let redBg     = color(0x30, 0x22, 0x22)

    // Terminal background — matches dark grey
    static let termBg    = color(0x24, 0x24, 0x23)
    static let termBgNS  = NSColor(srgbRed: 0x24/255, green: 0x24/255, blue: 0x23/255, alpha: 1)

    // Terminal font
    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 24

    // Fonts
    /// Brand font for "Claudex" logo text — uses serif like Claude's logo
    static let brandFont: Font = .custom("Georgia", size: 16).weight(.semibold)
    /// UI font — system font (matches Anthropic Sans feel)
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Mono font for paths, badges, terminal-related text
    static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Helper
    private static func color(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
        Color(nsColor: NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1))
    }
}
