import SwiftUI

/// Geometry of the Settings window. Every pane is built from the parts below: a header, a card
/// of rows, a footnote. One layout everywhere, so no pane looks like a different app.
enum SettingsMetrics {
    static let windowSize = CGSize(width: 900, height: 660)
    static let minimumSize = CGSize(width: 780, height: 540)
    static let sidebarWidth: CGFloat = 228
    static let toolbarHeight: CGFloat = 76
    /// The column the title and cards share, centred in wide windows.
    static let contentWidth: CGFloat = 640
}

/// A grouped card: rows share one surface, divided by `SettingsCardDivider`.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(Design.surface))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .strokeBorder(Design.hairline, lineWidth: scheme == .dark ? 1 : 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 2, y: 1)
    }
}

/// One card row: label on the left, controls on the right, at least 52 pt tall.
struct SettingsCardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 16)
            HStack(spacing: 8) { trailing }
        }
        .font(Design.Font.body)
        .padding(.horizontal, Design.Space.rowInset)
        .padding(.vertical, 10)
        .frame(minHeight: Design.Space.rowHeight)
    }
}

/// A row's title with an optional line of detail under it.
struct SettingsLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Design.Font.body)
            if let detail, !detail.isEmpty {
                Text(detail).font(Design.Font.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A row's label with a tinted symbol plate in front of it.
struct SettingsIconLabel: View {
    let title: String
    var detail: String?
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(symbol: symbol, color: color)
            SettingsLabel(title: title, detail: detail)
        }
    }
}

/// A switch row: what it does on the left, the switch on the right.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsCardRow {
            SettingsLabel(title: title, detail: detail)
        } trailing: {
            SettingsSwitch(title: title, isOn: $isOn)
        }
    }
}

/// The switch every row uses.
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.regular)
    }
}

/// A row whose control is a pop-up menu of choices.
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    @ViewBuilder let options: Options

    var body: some View {
        SettingsCardRow {
            SettingsLabel(title: title, detail: detail)
        } trailing: {
            Picker(title, selection: $selection) { options }
                .settingsMenu()
        }
    }
}

extension View {
    /// A pop-up menu at the row controls' height.
    func settingsMenu() -> some View {
        labelsHidden().pickerStyle(.menu).controlSize(.large).fixedSize()
    }
}

/// Settings' buttons: a soft neutral plate 28 pt tall, or the accent for the one action a row
/// exists for. Hover and press darken the plate.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        SettingsButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct SettingsButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(Design.Font.control)
                .lineLimit(1)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: Design.Space.control)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovered = enabled && $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .fixedSize()
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            if prominent { return Design.accent.opacity(pressed ? 0.8 : hovered ? 0.9 : 1) }
            return Color.primary.opacity(pressed ? 0.16 : hovered ? 0.12 : 0.08)
        }
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
    static var settingsProminent: SettingsButtonStyle { SettingsButtonStyle(prominent: true) }
}

/// Hairline between card rows: inset at the label, flush at the card's edge, so the card reads
/// as one surface with rows in it rather than a stack of tiles.
struct SettingsCardDivider: View {
    var inset: CGFloat = Design.Space.rowInset
    var body: some View {
        Rectangle().fill(Design.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The title over a card ("Content blocking", "Data"), aligned with the rows' text.
struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Design.Font.section)
            .foregroundStyle(.secondary)
            .padding(.leading, Design.Space.rowInset)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A short secondary note under a card. One or two lines: anything longer belongs in a row's
/// detail, next to the switch it explains.
struct SettingsFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Design.Font.detail).foregroundStyle(.secondary)
            .padding(.horizontal, Design.Space.rowInset)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A white symbol on a small tinted plate in front of a row, as System Settings does.
/// Decoration: the row's text names it, so VoiceOver skips it.
struct SettingsGlyph: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// A pane's scrolling body: headers, cards and footnotes in one centred column.
struct SettingsCardPane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: SettingsMetrics.contentWidth, alignment: .leading)
                .padding(.horizontal, Design.Space.pane)
                .padding(.top, 4)
                .padding(.bottom, Design.Space.pane)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// A titled group: header, card, optional footnote, spaced from the group above it.
struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title)
            SettingsCard { content }
            if let footnote, !footnote.isEmpty { SettingsFootnote(footnote) }
        }
        .padding(.bottom, Design.Space.section)
    }
}

/// A text field at the controls' height, the same in every sheet and pane: a soft fill, a hairline,
/// and the accent ring while typing.
struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Design.Font.body)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? Design.accent.opacity(0.7) : Design.hairline, lineWidth: focused ? 1.5 : 1))
    }
}
