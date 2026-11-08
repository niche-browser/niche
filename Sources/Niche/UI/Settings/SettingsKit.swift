import SwiftUI

/// Geometry of the Settings window. Every pane is built from the parts below: a header, a card
/// of rows, a footnote. One layout everywhere, so no pane looks like a different app.
enum SettingsMetrics {
    static let windowSize = CGSize(width: 860, height: 600)
    static let sidebarWidth: CGFloat = 220
    static let toolbarHeight: CGFloat = 64
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
                .strokeBorder(Design.hairline, lineWidth: scheme == .dark ? 0.5 : 0))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 1.5, y: 1)
    }
}

/// One card row: label on the left, control on the right, at least 44 pt tall.
struct SettingsCardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .font(Design.Font.body)
        .padding(.horizontal, Design.Space.rowInset)
        .padding(.vertical, 9)
        .frame(minHeight: Design.Space.rowHeight)
    }
}

/// A row's title with an optional line of detail under it.
struct SettingsLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Design.Font.body)
            if let detail, !detail.isEmpty {
                Text(detail).font(Design.Font.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
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
                .labelsHidden().fixedSize()
        }
    }
}

/// Hairline between card rows: inset at the label, flush at the card's edge, so the card reads
/// as one surface with rows in it rather than a stack of tiles.
struct SettingsCardDivider: View {
    var body: some View {
        Rectangle().fill(Design.hairline)
            .frame(height: 1)
            .padding(.leading, Design.Space.rowInset)
    }
}

/// The title over a card ("Content blocking", "Data"), aligned with the rows' text.
struct SettingsHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Design.Font.section)
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.leading, Design.Space.rowInset)
            .padding(.top, 6)
            .padding(.bottom, 8)
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
            .padding(.top, 7)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small tinted symbol in front of a row. Decoration: the row's text names it, so
/// VoiceOver skips it.
struct SettingsGlyph: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

/// A pane's scrolling body: headers, cards and footnotes in one column.
struct SettingsCardPane<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, Design.Space.pane)
                .padding(.top, 4)
                .padding(.bottom, Design.Space.pane)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
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
