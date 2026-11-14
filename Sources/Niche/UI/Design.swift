import AppKit
import SwiftUI

/// Niche's design tokens: one place for the colours, radii, spacing, type, icons and motion of
/// every window. docs/design.md says which token to use when. A view takes its values from here;
/// `scripts/lint.py` (`design-literal`) fails a file that gains a literal colour, font size,
/// corner radius or animation time.
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

    /// Ink on a bar that takes its page's colour (the toolbar, Peek's strip): neutral white or
    /// black, never tinted. Arc's cream (#E4E0D4, #F0E6CC) read as yellowed glyphs on a dark page.
    static func barInk(onLight light: Bool) -> NSColor { light ? NSColor.black.withAlphaComponent(0.8) : NSColor.white.withAlphaComponent(0.92) }
    static func barInkDim(onLight light: Bool) -> NSColor { light ? NSColor.black.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.62) }
    /// The plate under a hovered or pressed control on such a bar: dark on a light bar, light on a
    /// dark one, so it shows on any page.
    static func barFill(_ fill: Fill, onLight light: Bool) -> NSColor { (light ? NSColor.black : NSColor.white).withAlphaComponent(fill.rawValue + 0.02) }

    /// How much a text or glyph stands out. `Ink` and `onDark` take it.
    enum Emphasis: CGFloat, CaseIterable {
        /// Titles and what is being read.
        case primary = 0.92
        /// Details, idle glyphs.
        case secondary = 0.62
        /// Placeholders, hints, disabled text.
        case tertiary = 0.4
        /// Dividers drawn as ink, the faintest glyphs.
        case quaternary = 0.2
    }

    /// Ink that follows the window's appearance (label colours).
    static func ink(_ emphasis: Emphasis = .primary) -> NSColor {
        switch emphasis {
        case .primary: return .labelColor
        case .secondary: return .secondaryLabelColor
        case .tertiary: return .tertiaryLabelColor
        case .quaternary: return .quaternaryLabelColor
        }
    }
    static func inkColor(_ emphasis: Emphasis = .primary) -> Color { Color(nsColor: ink(emphasis)) }

    /// White ink on a surface that is dark in both appearances (dialogs, the Little Window bar, a
    /// video's controls).
    static func onDark(_ emphasis: Emphasis = .primary) -> NSColor { NSColor.white.withAlphaComponent(emphasis.rawValue) }
    static func onDarkColor(_ emphasis: Emphasis = .primary) -> Color { Color.white.opacity(emphasis.rawValue) }
    /// Black ink on a surface that is light in both appearances.
    static func onLight(_ emphasis: Emphasis = .primary) -> NSColor { NSColor.black.withAlphaComponent(emphasis.rawValue * 0.9) }
    static func onLightColor(_ emphasis: Emphasis = .primary) -> Color { Color.black.opacity(emphasis.rawValue * 0.9) }

    /// A neutral plate over any surface: the strength of `Color.primary` (or white on a dark
    /// surface) that fills it. Selection is never a saturated fill.
    enum Fill: CGFloat, CaseIterable {
        /// A resting card or field.
        case subtle = 0.04
        /// Under the pointer.
        case hover = 0.06
        /// Selected, or a resting control that has to read as one.
        case selected = 0.085
        /// Held down.
        case pressed = 0.12
        /// A plate that carries a glyph (a keycap, an avatar ground).
        case strong = 0.18
    }
    static func fill(_ fill: Fill) -> Color { Color.primary.opacity(fill.rawValue) }
    static func fillNS(_ fill: Fill) -> NSColor { NSColor.labelColor.withAlphaComponent(fill.rawValue) }
    static func fillOnDark(_ fill: Fill) -> NSColor { NSColor.white.withAlphaComponent(fill.rawValue) }
    static func fillOnDarkColor(_ fill: Fill) -> Color { Color.white.opacity(fill.rawValue) }

    /// The hairline as an AppKit colour.
    static let hairlineNS = NSColor.labelColor.withAlphaComponent(0.08)
    /// A hairline on a surface that is always dark.
    static let hairlineOnDark = NSColor.white.withAlphaComponent(0.1)
    static let hairlineOnDarkColor = Color(nsColor: hairlineOnDark)
    /// The accent as a wash under a selected control, and as the ring around it.
    static let accentWash = accent.opacity(0.16)
    static let accentRing = accent.opacity(0.7)

    /// What a state means, in the system's colours so they follow Increase Contrast.
    static let danger = Color(nsColor: .systemRed)
    static let dangerNS = NSColor.systemRed
    static let positive = Color(nsColor: .systemGreen)
    static let positiveNS = NSColor.systemGreen
    static let warning = Color(nsColor: .systemYellow)
    static let warningNS = NSColor.systemYellow

    /// A dark panel that keeps its look in a light window (dialogs, the command bar's ground).
    static let panelDark = NSColor(hex: "#1c1e21")
    static let panelDarkColor = Color(nsColor: panelDark)
    /// A field or raised plate on `panelDark`.
    static let panelDarkRaised = NSColor(hex: "#2b2d33")
    static let panelDarkRaisedColor = Color(nsColor: panelDarkRaised)
    /// The scrim over a window behind a panel.
    static let scrim = NSColor.black.withAlphaComponent(0.2)

    /// How strongly something shows, for the few places that fade a whole view.
    enum Opacity {
        /// A disabled control.
        static let disabled: CGFloat = 0.4
        /// Something present but out of the way (a dimmed row, an inactive window's glyph).
        static let dimmed: CGFloat = 0.62
        /// Gone, but still laid out.
        static let hidden: CGFloat = 0
    }

    /// The two shadows: a floating panel's, and a card or tile lifted off its ground.
    enum Shadow {
        static let panelColor = NSColor.black.withAlphaComponent(0.35)
        static let panelRadius: CGFloat = 24
        static let panelOffset: CGFloat = 10
        static let cardColor = NSColor.black.withAlphaComponent(0.18)
        static let cardRadius: CGFloat = 6
        static let cardOffset: CGFloat = 2
    }

    // MARK: Shape

    enum Radius {
        static let small: CGFloat = 4      // a badge, a tick box, a thumb inside a plate
        static let inset: CGFloat = 6      // a glyph plate or keycap inside something else
        static let row: CGFloat = 8        // a row in a list or sidebar
        static let control: CGFloat = 10   // a field or button around 28-32 pt
        static let card: CGFloat = 12      // a group of rows, a favorite's tile
        static let panel: CGFloat = 16     // a floating panel (command bar, a dialog)
        /// A capsule `height` tall.
        static func pill(_ height: CGFloat) -> CGFloat { height / 2 }
    }

    // MARK: Space

    enum Space {
        // The step scale: every gap and padding is one of these.
        static let hair: CGFloat = 1
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24

        static let rowInset: CGFloat = 16     // text inset inside a card row
        static let rowHeight: CGFloat = 44    // minimum card row
        static let section: CGFloat = 24      // between one card group and the next header
        static let pane: CGFloat = 28         // pane content from the window's edges
        static let control: CGFloat = 28      // buttons, menus and fields in a row
        static let controlCompact: CGFloat = 24   // a control inside a dense bar
        static let controlLarge: CGFloat = 32     // a primary action, a search field
    }

    // MARK: Icons

    /// One glyph size and weight for bars, one for rows: buttons that sit side by side match.
    enum Icon {
        /// A disclosure chevron, a badge on another glyph.
        static let tiny: CGFloat = 8
        /// Inside a field or beside a detail text.
        static let small: CGFloat = 11
        /// A row's glyph, a menu-like control.
        static let regular: CGFloat = 13
        /// A bar button (the toolbar, the sidebar's header and dock).
        static let bar: CGFloat = 14
        /// A favicon, an extension's icon: bitmaps are drawn at this size.
        static let image: CGFloat = 16
        /// The glyph of an empty state or a dialog.
        static let large: CGFloat = 20
        /// Regular, as the system's own toolbars draw theirs: a heavier stroke reads as bulk.
        static let weight = NSFont.Weight.regular
        /// The plate a bar button draws under the pointer.
        static let plate: CGFloat = 28

        static func configuration(_ size: CGFloat = bar, weight: NSFont.Weight = weight) -> NSImage.SymbolConfiguration {
            NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        }

        /// A system symbol at a token size.
        static func symbol(_ name: String, size: CGFloat = bar, weight: NSFont.Weight = weight, label: String? = nil) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(configuration(size, weight: weight))
        }
    }

    // MARK: Motion

    /// One set of timings for the chrome. A change the pointer causes shows at once and leaves in
    /// `fast`; a view arriving or a list changing takes `standard` on `curve`. Arc-measured motions
    /// (the sidebar slide, a row's bounce) keep their own numbers next to their measurement.
    enum Motion {
        /// A hover fill leaving, a press, a small fade.
        static let fast: TimeInterval = 0.12
        /// A panel arriving, the Library opening, a list changing (SwiftUI's .snappy(duration: 0.22)).
        static let standard: TimeInterval = 0.22
        /// Something large travelling: a sheet, a window-sized change.
        static let slow: TimeInterval = 0.35
        /// A panel leaving after the page has the keys back.
        static let exit: TimeInterval = 0.09
        /// Fast out, slow in: quick to answer, soft to settle.
        static let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        /// System Settings ▸ Accessibility ▸ Display ▸ Reduce motion.
        static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        /// `seconds`, or none under Reduce motion: the change still happens, it just doesn't travel.
        static func duration(_ seconds: TimeInterval) -> TimeInterval { reduced ? 0 : seconds }
        /// How far a pressed row or tile sinks.
        static let pressScale: CGFloat = 0.975
    }

    // MARK: Type

    /// The type scale. SF Pro only; a size not on it is a mistake.
    enum TextSize: CGFloat, CaseIterable {
        /// A badge, a keycap legend.
        case micro = 10
        /// A caption under something, a footnote.
        case caption = 11
        /// Details beside or under a body text.
        case detail = 12
        /// Everything read in a window: rows, buttons, fields.
        case body = 13
        /// A dialog's or panel's title.
        case title = 15
        /// A field the eye lands on first (the command bar's).
        case headline = 17
        /// A settings pane's title.
        case pane = 20
        /// Onboarding's sub-headlines.
        case large = 28
        /// Onboarding's headline.
        case display = 42
    }

    enum Font {
        static let paneTitle = ui(.pane, .semibold)
        static let section = ui(.body, .semibold)
        static let body = ui(.body)
        static let control = ui(.body, .medium)
        static let detail = ui(.detail)
        static let caption = ui(.caption)
        static let title = ui(.title, .semibold)

        /// SwiftUI text at a size of the scale.
        static func ui(_ size: TextSize, _ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            .system(size: size.rawValue, weight: weight, design: design)
        }
        /// AppKit text at a size of the scale.
        static func ns(_ size: TextSize, _ weight: NSFont.Weight = .regular) -> NSFont {
            .systemFont(ofSize: size.rawValue, weight: weight)
        }
        /// Numbers that count: fixed-width digits, so they don't change width.
        static func digits(_ size: TextSize, _ weight: NSFont.Weight = .regular) -> NSFont {
            .monospacedDigitSystemFont(ofSize: size.rawValue, weight: weight)
        }
        /// Code, an address shown as data.
        static func mono(_ size: TextSize, _ weight: NSFont.Weight = .regular) -> NSFont {
            .monospacedSystemFont(ofSize: size.rawValue, weight: weight)
        }
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
