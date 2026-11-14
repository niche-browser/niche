import SwiftUI

private enum Metrics {
    /// The cards' width, Arc's.
    static let width: CGFloat = 450
    /// One space on the spaces step: its theme as a little window, the gap to its circle and to its
    /// name, the circle and its tick, and the row's height with all of them.
    static let choice = CGSize(width: 63, height: 95)
    static let choiceGap: CGFloat = 14.5
    static let tick: CGFloat = 16
    static let tickGlyph: CGFloat = 8.5
    static let choicesHeight: CGFloat = 155
    /// The pill's lavender circle and the chevron cut in it.
    static let pillDot: CGFloat = 14
    static let pillChevron: CGFloat = 7
    /// Change Profile's icon: the tile, the room its badge needs around it, the badge, and the glyphs on the tile.
    static let tile: CGFloat = 62
    static let tileFrame: CGFloat = 68
    static let tileBadge: CGFloat = 23
    static let tileSymbol: CGFloat = 26
    static let tileEmoji: CGFloat = 30
}

/// Arc 1.171's "Which Spaces should use this Profile?" (the second step of Create a new Profile),
/// after a 2x capture (3 Nov): a 450 pt card; each space as a 63 × 95 pt card in its
/// theme over a 16 pt circle (green with a tick when chosen) and its name, 75 pt apart.
struct ProfileSpacesStep: View {
    let spaces: [Space]
    @Binding var ticked: Set<UUID>
    let onBack: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileAvatar()
            Text("Which Spaces should use this Profile?")
                .font(Design.Font.ui(.title, .semibold))
                .foregroundStyle(DialogTheme.title)
                .padding(.top, Design.Space.xl)
            Text("These Spaces will start fresh in your brand new Profile — so you’ll have to log back in to websites, re-save your passwords, add extensions, etc. You can always switch back to your previous Profile though if you forgot something!")
                .font(Design.Font.ui(.body))
                .lineSpacing(Design.Space.hair)
                .foregroundStyle(NewProfileDialog.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Design.Space.m)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Design.Space.l) {
                    ForEach(spaces) { s in
                        SpaceChoice(space: s, on: ticked.contains(s.id)) {
                            if ticked.contains(s.id) { ticked.remove(s.id) } else { ticked.insert(s.id) }
                        }
                    }
                }
                .padding(.horizontal, Design.Space.xxxl)
            }
            .padding(.horizontal, -Design.Space.xxxl)
            .frame(height: Metrics.choicesHeight)
            .padding(.top, Design.Space.l)
            HStack(spacing: Design.Space.m) {
                Spacer()
                DialogButton(title: "Back", key: "ESC", enabled: true, primary: false, action: onBack)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Create Profile", key: "↩", enabled: true, style: .accent, action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Design.Space.xxxl)
        }
        .padding(Design.Space.xxxl)
        .frame(width: Metrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DialogSurface())
    }
}

/// One space in the step above: the theme as a little window, the circle, the name.
private struct SpaceChoice: View {
    let space: Space
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: Metrics.choiceGap) {
                ZStack {
                    space.theme.palette.isDark ? Design.panelDarkColor : Color.white
                    SpaceBackground(palette: space.theme.palette)
                }
                .frame(width: Metrics.choice.width, height: Metrics.choice.height)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(DialogTheme.outline, lineWidth: 1))
                ZStack {
                    if on {
                        Circle().fill(Design.positive)
                        Image(systemName: "checkmark").font(.system(size: Metrics.tickGlyph, weight: .bold)).foregroundStyle(Design.onLightColor(.primary))
                    } else {
                        Circle().strokeBorder(DialogTheme.faint, lineWidth: 1.5)
                    }
                }
                .frame(width: Metrics.tick, height: Metrics.tick)
                Text(space.title)
                    .font(Design.Font.ui(.detail))
                    .foregroundStyle(DialogTheme.body)
                    .lineLimit(1)
                    .frame(width: Metrics.choice.width + Design.Space.l)
            }
            .frame(width: Metrics.choice.width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space.title)
        .accessibilityValue(on ? "1" : "0")
    }
}

/// Arc 1.171's Spaces ▸ Change Profile (3 Nov): "Change <space>’s Profile" on a 450 pt
/// card, the space's icon on a blue tile with a profile badge, and a blue pill that picks Default,
/// another profile or New Profile. Change Profile with New Profile goes on to Create a new Profile.
struct ChangeProfileDialog: View {
    let space: Space
    let profiles: [BrowserProfile]
    let others: [Space]
    let onChange: (UUID?) -> Void
    let onCreate: (String, Set<UUID>) -> Void
    let onCancel: () -> Void
    @State private var choice: SpaceProfileChoice
    @State private var creating = false
    @State private var pill = CGRect.zero

    init(space: Space, profiles: [BrowserProfile], spaces: [Space], onChange: @escaping (UUID?) -> Void,
         onCreate: @escaping (String, Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.space = space
        self.profiles = profiles
        self.others = spaces
        self.onChange = onChange
        self.onCreate = onCreate
        self.onCancel = onCancel
        _choice = State(initialValue: .existing(space.profileID))
    }

    var body: some View {
        if creating {
            NewProfileDialog(spaces: others, ticked: [space.id], onCreate: onCreate, onCancel: onCancel)
        } else {
            picker
        }
    }

    private var choiceName: String {
        switch choice {
        case .new: return "New Profile"
        case .existing(let id): return profiles.first { $0.id == id }?.name ?? "Default"
        }
    }

    private func showMenu() {
        // The dialog's own window, which needn't be key (Niche may be in the background).
        guard let content = NSApp.windows.last(where: { $0 is DialogPanel && $0.isVisible })?.contentView else { return }
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Default") { choice = .existing(nil) }
        for p in profiles { MenuItems.add(m, p.name) { choice = .existing(p.id) } }
        m.addItem(.separator())
        MenuItems.add(m, "New Profile") { choice = .new }
        // SwiftUI's global frame is top-left based in the window; the content view is not flipped.
        let y = content.isFlipped ? pill.maxY + Design.Space.xs : content.bounds.height - pill.maxY - Design.Space.xs
        // Next turn of the run loop, so the button's press returns before the menu tracks.
        DispatchQueue.main.async { m.popUp(positioning: nil, at: NSPoint(x: pill.minX, y: y), in: content) }
    }

    private func confirm() {
        switch choice {
        case .new: creating = true
        case .existing(let id): if id == space.profileID { onCancel() } else { onChange(id) }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpaceProfileIcon(space: space)
            (Text("Change ") + Text("\(space.title)’s").bold() + Text(" Profile"))
                .font(Design.Font.ui(.title))
                .foregroundStyle(DialogTheme.title)
                .padding(.top, Design.Space.xl)
            Text("Each Profile has different browser data, so you might get logged out of some websites, see different Favorites up top, or need to re-install extensions.")
                .font(Design.Font.ui(.body))
                .lineSpacing(Design.Space.hair)
                .foregroundStyle(NewProfileDialog.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Design.Space.m)
            HStack(spacing: Design.Space.s) {
                (Text("\(space.title)’s").bold() + Text(" Profile"))
                    .font(Design.Font.ui(.body))
                    .foregroundStyle(DialogTheme.title)
                // An NSMenu under the pill, like Arc's (Default, the other profiles, New Profile).
                Button(action: showMenu) {
                    // Arc's lavender circle with the chevron cut in the pill's blue, 14 pt.
                    HStack(spacing: Design.Space.xs) {
                        ZStack {
                            Circle().fill(ProfilePalette.pillInk)
                            Image(systemName: "chevron.down").font(.system(size: Metrics.pillChevron, weight: .heavy)).foregroundStyle(ProfilePalette.pill)
                                .offset(y: 0.5)
                        }
                        .frame(width: Metrics.pillDot, height: Metrics.pillDot)
                        Text(choiceName).font(Design.Font.ui(.body)).foregroundStyle(ProfilePalette.pillInk)
                    }
                    .padding(.horizontal, Design.Space.m)
                    .frame(height: Design.Space.controlCompact)
                    .background(ProfilePalette.pill, in: RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous))
                    .background(GeometryReader { g in Color.clear.onAppear { pill = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in pill = f } })
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(choiceName)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showMenu() }
            }
            .padding(.top, Design.Space.m)
            HStack(spacing: Design.Space.m) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, primary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Change Profile", key: "↩", enabled: true, style: .accent, action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Design.Space.xxxl)
        }
        .padding(Design.Space.xxxl)
        .frame(width: Metrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DialogSurface())
    }
}

/// The space's emoji (or Icon-tab glyph) on Arc's 62 pt blue tile, with the profile smiley badge.
private struct SpaceProfileIcon: View {
    let space: Space

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(ProfilePalette.tile)
                if let symbol = space.symbol {
                    Image(systemName: symbol).font(.system(size: Metrics.tileSymbol, weight: .medium)).foregroundStyle(DialogTheme.title)
                } else {
                    Text(space.emoji.isEmpty ? "🌱" : space.emoji).font(.system(size: Metrics.tileEmoji))
                }
            }
            .frame(width: Metrics.tile, height: Metrics.tile)
            .frame(width: Metrics.tileFrame, height: Metrics.tileFrame, alignment: .topLeading)
            ZStack {
                Circle().fill(ProfilePalette.face)
                Circle().strokeBorder(ProfilePalette.ring, lineWidth: 1.5)
                VStack(spacing: 2.5) {
                    HStack(spacing: 3.5) {
                        Capsule().fill(ProfilePalette.features).frame(width: 2, height: 5)
                        Capsule().fill(ProfilePalette.features).frame(width: 2, height: 5)
                    }
                    SmileArc().stroke(ProfilePalette.features, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 10, height: 2.5)
                }
            }
            .frame(width: Metrics.tileBadge, height: Metrics.tileBadge)
            .overlay(Circle().strokeBorder(NewProfileDialog.card, lineWidth: 2))
        }
        .frame(width: Metrics.tileFrame, height: Metrics.tileFrame)
    }
}
