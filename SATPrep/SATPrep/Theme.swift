import SwiftUI

/// Palette and metrics approximating the College Board Bluebook testing app,
/// so practising here feels like the real thing. Light mode only by design.
enum BB {
    // Core blue used for selection, links and primary buttons.
    static let blue        = Color(hex: 0x324DC7)
    static let blueDeep    = Color(hex: 0x1B2A78)
    static let blueWash    = Color(hex: 0xEDF0FC)

    // Result states.
    static let green       = Color(hex: 0x0B7A3E)
    static let greenWash   = Color(hex: 0xE8F4ED)
    static let red         = Color(hex: 0xBE2A2A)
    static let redWash     = Color(hex: 0xFBECEC)

    // Ink and rules.
    static let ink         = Color(hex: 0x1B1B1B)
    static let inkSoft     = Color(hex: 0x5A5A5A)
    static let rule        = Color(hex: 0xC7C7C7)
    static let ruleSoft    = Color(hex: 0xE3E3E3)
    static let surface     = Color.white
    static let surfaceAlt  = Color(hex: 0xF5F6F8)

    // Test accents: SAT and PSAT badges must read apart at a glance.
    static let sat         = Color(hex: 0x1B2A78)
    static let psat        = Color(hex: 0x6A3D9A)

    // Difficulty accents.
    static let easy        = Color(hex: 0x156B3F)
    static let medium      = Color(hex: 0x8A5A00)
    static let hard        = Color(hex: 0xA32626)

    static let choiceRadius: CGFloat = 8
    static let cardRadius: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
