import SwiftUI
import AppKit

/// Design tokens. A flat, monochrome look: white canvas, soft gray tiles and
/// near-black ink in light mode, mirrored in dark mode.
enum Theme {
    static let canvas = Color(light: 0xFFFFFF, dark: 0x0F1012)
    /// Large rounded blocks that group content.
    static let tile = Color(light: 0xF1F1F1, dark: 0x1A1B1E)
    /// Cards and controls that sit on top of a tile.
    static let raised = Color(light: 0xFFFFFF, dark: 0x26272B)
    static let ink = Color(light: 0x17181A, dark: 0xF3F3F4)

    static let secondary = ink.opacity(0.55)
    static let tertiary = ink.opacity(0.35)
    static let chip = ink.opacity(0.06)
    static let hairline = ink.opacity(0.08)

    /// Height of the window's top row: traffic lights, sidebar toggle, search.
    static let topBarHeight: CGFloat = 52

    enum Radius {
        static let tile: CGFloat = 28
        static let card: CGFloat = 16
        static let thumb: CGFloat = 10
    }

    /// Large headings: medium weight with slightly tight tracking.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    static func displayTracking(_ size: CGFloat) -> CGFloat {
        -size * 0.012
    }
}

extension Color {
    /// A color that follows the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Soft shadow for cards floating on a tile.
    func raisedShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    func tileBackground(radius: CGFloat = Theme.Radius.tile) -> some View {
        background(Theme.tile, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
