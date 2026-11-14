import SwiftUI

struct SidebarIconButton: View {
    let symbol: String
    let palette: SpacePalette
    var help: String = ""
    /// Tooltip while ⌥ is held, for buttons that do something else on ⌥-click.
    var optionHelp: String? = nil
    var enabled: Bool = true
    var size: CGFloat = 28
    var height: CGFloat? = nil
    var iconSize: CGFloat = Design.Icon.regular
    /// Regular, like `Design.Icon.weight`.
    var weight: Font.Weight = .regular
    /// Header buttons follow the app's active state (nil: the plain sidebar tone).
    var active: Bool? = nil
    let action: () -> Void
    @State private var hover = false

    /// As in Arc 1.170, a light sidebar's glyphs (sidebar toggle, library, +) are faint while the
    /// app is in the background or the button is disabled (quaternary ink) and its header glyphs
    /// darken with the app active (secondary ink). The same inks as SidebarGlyphButton's.
    private var tint: Color {
        let disabled = palette.textTertiary.opacity(Design.Opacity.disabled)
        if palette.isDark { return enabled ? Design.onDarkColor(.secondary) : disabled }
        guard let active else { return enabled ? Design.onLightColor(.quaternary) : disabled }
        return Design.onLightColor(enabled && active ? .secondary : .quaternary)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: weight))
                .foregroundStyle(tint)
                .frame(width: size, height: height ?? min(size, 28))
                .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(hover && enabled ? palette.hoverFill : .clear))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .arcTooltip(help, optionHelp: optionHelp)
    }
}
