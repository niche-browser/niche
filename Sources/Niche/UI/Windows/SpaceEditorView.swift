import SwiftUI

private enum Metrics {
    /// The icon gallery under the name.
    static let iconPickerHeight: CGFloat = 250
    /// The preview of the space, and one of the two placeholder rows in it.
    static let previewHeight: CGFloat = 96
    static let previewRow: CGFloat = 22
}

/// The profile picked for a space: Default (nil), an existing one, or a new one to make.
enum SpaceProfileChoice: Hashable {
    case existing(UUID?)
    case new
}

/// Create or edit a space: a preview, name, icon gallery and profile, and beside them the theme
/// editor (the same card Edit Theme Color… opens: pad, presets, intensity, grain, Auto / Light /
/// Dark). An existing space shows each change at once (`onPreview`); Cancel puts its theme back,
/// Save writes it.
struct SpaceEditorView: View {
    static let width: CGFloat = Design.Space.xxxl + SpaceIconPicker.size.width + Design.Space.xxl + SpaceStyleEditor.size.width + Design.Space.xxxl

    let existing: Space?
    let profiles: [BrowserProfile]
    /// Title, icon, theme, profile; a new profile comes with its name.
    let onSave: (String, SpaceIcon, SpaceTheme, SpaceProfileChoice, String) -> Void
    let onCancel: () -> Void
    let onPreview: (SpaceTheme) -> Void

    @State private var title: String
    /// Saved as it is: an untouched symbol or empty icon stays what it was (#205).
    @State private var icon: SpaceIcon
    @State private var theme: SpaceTheme
    @State private var profile: SpaceProfileChoice
    @State private var newProfileName = ""

    /// `initialProfile` is a new space's starting profile (the focused space's).
    init(existing: Space?, profiles: [BrowserProfile], initialProfile: UUID? = nil,
         onSave: @escaping (String, SpaceIcon, SpaceTheme, SpaceProfileChoice, String) -> Void, onCancel: @escaping () -> Void,
         onPreview: @escaping (SpaceTheme) -> Void = { _ in }) {
        self.existing = existing
        self.profiles = profiles
        _profile = State(initialValue: .existing(existing == nil ? initialProfile : existing?.profileID))
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPreview = onPreview
        _title = State(initialValue: existing?.title ?? "")
        _icon = State(initialValue: existing?.icon ?? .newSpace)
        _theme = State(initialValue: existing?.theme ?? SpaceColorPresets.newSpaceTheme())
    }

    var body: some View {
        VStack(spacing: Design.Space.xl) {
            Text(existing == nil ? "New Space" : "Edit Space").font(Design.Font.title)
            HStack(alignment: .top, spacing: Design.Space.xxl) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    preview
                    HStack(spacing: Design.Space.m) {
                        iconTile
                        SettingsTextField(placeholder: "Name", text: $title)
                    }
                    SpaceIconPicker(current: icon.emoji, currentSymbol: icon.symbol,
                                    onPick: { icon = .emoji($0) },
                                    onPickSymbol: { icon = .symbol($0) },
                                    onRemove: { icon = .none },
                                    height: Metrics.iconPickerHeight)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(Design.surface))
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(Design.hairline))
                    profileSection
                }
                .frame(width: SpaceIconPicker.size.width)
                SpaceStyleEditor(theme: theme) { t in
                    theme = t
                    onPreview(t)
                }
            }
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.settings)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? "Create Space" : "Save") {
                    onSave(title.isEmpty ? "Space" : title, icon, theme, profile, trimmedProfileName)
                }
                .buttonStyle(.settingsProminent)
                .keyboardShortcut(.defaultAction)
                .disabled((title.trimmingCharacters(in: .whitespaces).isEmpty && existing == nil) || (profile == .new && trimmedProfileName.isEmpty))
            }
        }
        .padding(Design.Space.xxxl)
        .frame(width: Self.width)
        .tint(Design.accent)
    }

    /// The space as the sidebar draws it, with the theme being edited.
    private var preview: some View {
        ZStack {
            SpaceBackground(palette: theme.palette)
            VStack(spacing: Design.Space.s) {
                HStack(spacing: Design.Space.s) {
                    glyph(color: theme.palette.textPrimary)
                    Text(title.isEmpty ? "Space" : title).font(Design.Font.section).foregroundStyle(theme.palette.textPrimary)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(theme.palette.selectedFill).frame(height: Metrics.previewRow)
                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(theme.palette.hoverFill).frame(height: Metrics.previewRow)
            }
            .padding(Design.Space.l)
        }
        .frame(height: Metrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(Design.hairline))
    }

    /// The chosen icon in front of the name, as the sidebar will show it.
    private var iconTile: some View {
        Group {
            if icon == .none {
                Image(systemName: "face.dashed").font(.system(size: Design.Icon.bar)).foregroundStyle(.tertiary)
            } else {
                glyph(color: .primary)
            }
        }
        .frame(width: Design.Space.controlLarge, height: Design.Space.controlLarge)
        .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(Design.fill(.hover)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).strokeBorder(Design.hairline))
        .accessibilityLabel("Space icon")
    }

    /// The icon as the sidebar draws it: an emoji, or a symbol in the space's text colour.
    @ViewBuilder
    private func glyph(color: Color) -> some View {
        switch icon {
        case .emoji(let e): Text(e).font(.system(size: Design.Icon.image))
        case .symbol(let name): Image(systemName: name).font(.system(size: Design.Icon.bar, weight: .medium)).foregroundStyle(color)
        case .none: EmptyView()
        }
    }

    private var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespaces) }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            HStack {
                Text("Profile").font(Design.Font.body)
                Spacer()
                Picker("Profile", selection: $profile) {
                    Text("Default").tag(SpaceProfileChoice.existing(nil))
                    ForEach(profiles) { p in Text(p.name).tag(SpaceProfileChoice.existing(p.id)) }
                    Divider()
                    Text("New Profile…").tag(SpaceProfileChoice.new)
                }
                .settingsMenu()
            }
            if profile == .new {
                SettingsTextField(placeholder: "Profile name", text: $newProfileName)
            }
            Text(profileNote).font(Design.Font.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileNote: String {
        if let existing, profile != .existing(existing.profileID) {
            return "Each profile has its own browser data, so you may be signed out of some websites or need to reinstall extensions. Open tabs in this space reload."
        }
        if profile == .new {
            return "This space starts fresh in a new profile, signed out of every website."
        }
        return "Profiles keep spaces separate, with their own logins, cookies and site data. Spaces on the same profile share them."
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
    }
}
