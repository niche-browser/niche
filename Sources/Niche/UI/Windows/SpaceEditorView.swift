import SwiftUI

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
    static let width: CGFloat = 24 + SpaceIconPicker.size.width + 20 + 355 + 24

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
        VStack(spacing: 18) {
            Text(existing == nil ? "New Space" : "Edit Space").font(.system(size: 17, weight: .semibold))
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    HStack(spacing: 8) {
                        iconTile
                        SettingsTextField(placeholder: "Name", text: $title)
                    }
                    SpaceIconPicker(current: icon.emoji, currentSymbol: icon.symbol,
                                    onPick: { icon = .emoji($0) },
                                    onPickSymbol: { icon = .symbol($0) },
                                    onRemove: { icon = .none },
                                    height: 250)
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
        .padding(24)
        .frame(width: Self.width)
        .tint(Design.accent)
    }

    /// The space as the sidebar draws it, with the theme being edited.
    private var preview: some View {
        ZStack {
            SpaceBackground(palette: theme.palette)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    glyph(size: 15, color: theme.palette.textPrimary)
                    Text(title.isEmpty ? "Space" : title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.palette.textPrimary)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 6).fill(theme.palette.selectedFill).frame(height: 22)
                RoundedRectangle(cornerRadius: 6).fill(theme.palette.hoverFill).frame(height: 22)
            }
            .padding(12)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(Design.hairline))
    }

    /// The chosen icon in front of the name, as the sidebar will show it.
    private var iconTile: some View {
        Group {
            if icon == .none {
                Image(systemName: "face.dashed").font(.system(size: 14)).foregroundStyle(.tertiary)
            } else {
                glyph(size: 17, color: .primary)
            }
        }
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Design.hairline))
        .accessibilityLabel("Space icon")
    }

    /// The icon as the sidebar draws it: an emoji, or a symbol in the space's text colour.
    @ViewBuilder
    private func glyph(size: CGFloat, color: Color) -> some View {
        switch icon {
        case .emoji(let e): Text(e).font(.system(size: size))
        case .symbol(let name): Image(systemName: name).font(.system(size: size - 2, weight: .medium)).foregroundStyle(color)
        case .none: EmptyView()
        }
    }

    private var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespaces) }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
