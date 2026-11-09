import AppKit
import SwiftUI

/// Niche's design tokens: one place for the colours, radii, spacing and type that settings,
/// the command bar and onboarding share. docs/design.md says which token to use when.
enum Design {
    // MARK: Colour

    /// The signal orange from the logo: the only brand colour in the interface. Switches,
    /// selection and the command bar's highlighted row use it; nothing else does.
    static let accent = Color(nsColor: .dynamic(light: NSColor(hex: "#ef4f1f"), dark: NSColor(hex: "#f45120")))
    static let accentNS = NSColor.dynamic(light: NSColor(hex: "#ef4f1f"), dark: NSColor(hex: "#f45120"))
    /// Graphite, the ground of the logo's tile and of dark surfaces.
    static let graphite = Color(hex: "#16181b")

    /// A grouped card on a window's background.
    static let surface = Color(nsColor: .dynamic(light: NSColor.white.withAlphaComponent(0.86),
                                                 dark: NSColor.white.withAlphaComponent(0.055)))
    /// Hairlines between rows and around floating panels.
    static let hairline = Color.primary.opacity(0.08)
    static let rowHover = Color.primary.opacity(0.05)
    static let rowSelected = Color.primary.opacity(0.085)

    // MARK: Shape

    enum Radius {
        static let inset: CGFloat = 6      // a glyph plate or keycap inside something else
        static let row: CGFloat = 8        // a row in a list or sidebar
        static let control: CGFloat = 10   // a field or button around 28-32 pt
        static let card: CGFloat = 12      // a group of rows
        static let panel: CGFloat = 16     // a floating panel (command bar)
    }

    // MARK: Space

    enum Space {
        static let rowInset: CGFloat = 16     // text inset inside a card row
        static let rowHeight: CGFloat = 52    // minimum card row
        static let section: CGFloat = 28      // between one card group and the next header
        static let pane: CGFloat = 32         // pane content from the window's edges
        static let control: CGFloat = 28      // buttons, menus and fields in a row
    }

    // MARK: Type

    enum Font {
        static let paneTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let control = SwiftUI.Font.system(size: 13, weight: .medium)
        static let detail = SwiftUI.Font.system(size: 12)
    }
}

extension NSColor {
    /// A colour that follows the appearance it is drawn in.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        }
    }
}
