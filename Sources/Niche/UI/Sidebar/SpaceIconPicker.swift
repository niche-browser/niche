import AppKit
import SwiftUI

/// How a vibe moves: each icon gets the motion that suits it, played on hover and looping while
/// it is the space's icon.
enum VibeMotion {
    case bounce, pulse, breathe, wiggle, rotate, wave
}

/// A space icon with a mood: an SF Symbol (so it draws crisp in the sidebar, the dock and the
/// command bar, tinted by the space's theme) plus the motion it plays in the picker.
struct SpaceVibe: Identifiable, Hashable {
    let symbol: String
    let name: String
    let motion: VibeMotion
    /// Its two colours: the glyph runs from the first to the second; the sidebar draws the first.
    let colors: [NSColor]
    var id: String { symbol }

    init(symbol: String, name: String, motion: VibeMotion, _ from: NSColor, _ to: NSColor) {
        self.symbol = symbol
        self.name = name
        self.motion = motion
        colors = [from, to]
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(nsColor: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var tileColor: Color { Color(nsColor: colors[0]) }
}

/// The icon picker's catalogue: animated Vibes in four moods, a wider set of still icons by
/// theme, and the emoji. Every entry is a symbol the space stores by name.
enum SpaceIconCatalog {
    struct Group: Identifiable {
        let title: String
        let vibes: [SpaceVibe]
        var id: String { title }
    }

    static let vibes: [Group] = [
        Group(title: "Energy", vibes: [
            SpaceVibe(symbol: "bolt.fill", name: "Charged", motion: .bounce, .systemYellow, .systemOrange),
            SpaceVibe(symbol: "flame.fill", name: "On fire", motion: .breathe, .systemOrange, .systemRed),
            SpaceVibe(symbol: "sparkles", name: "Spark", motion: .pulse, .systemYellow, .systemPink),
            SpaceVibe(symbol: "sun.max.fill", name: "Bright", motion: .rotate, .systemYellow, .systemOrange),
            SpaceVibe(symbol: "party.popper.fill", name: "Celebrate", motion: .wiggle, .systemPink, .systemPurple),
            SpaceVibe(symbol: "figure.run", name: "Momentum", motion: .bounce, .systemGreen, .systemTeal),
            SpaceVibe(symbol: "hare.fill", name: "Quick", motion: .bounce, .systemOrange, .systemBrown),
            SpaceVibe(symbol: "trophy.fill", name: "Win", motion: .wiggle, .systemYellow, .systemOrange),
        ]),
        Group(title: "Calm", vibes: [
            SpaceVibe(symbol: "moon.stars.fill", name: "Night", motion: .breathe, .systemIndigo, .systemPurple),
            SpaceVibe(symbol: "leaf.fill", name: "Grow", motion: .wiggle, .systemGreen, .systemMint),
            SpaceVibe(symbol: "water.waves", name: "Flow", motion: .wave, .systemCyan, .systemBlue),
            SpaceVibe(symbol: "cloud.fill", name: "Drift", motion: .breathe, .systemCyan, .systemIndigo),
            SpaceVibe(symbol: "wind", name: "Breeze", motion: .wave, .systemMint, .systemTeal),
            SpaceVibe(symbol: "drop.fill", name: "Still", motion: .pulse, .systemCyan, .systemBlue),
            SpaceVibe(symbol: "snowflake", name: "Cool", motion: .rotate, .systemCyan, .systemIndigo),
            SpaceVibe(symbol: "cup.and.saucer.fill", name: "Slow", motion: .breathe, .systemBrown, .systemOrange),
        ]),
        Group(title: "Focus", vibes: [
            SpaceVibe(symbol: "scope", name: "Target", motion: .pulse, .systemRed, .systemOrange),
            SpaceVibe(symbol: "brain.head.profile", name: "Think", motion: .breathe, .systemPink, .systemPurple),
            SpaceVibe(symbol: "atom", name: "Science", motion: .rotate, .systemBlue, .systemCyan),
            SpaceVibe(symbol: "lightbulb.max.fill", name: "Idea", motion: .wave, .systemYellow, .systemOrange),
            SpaceVibe(symbol: "waveform", name: "In the zone", motion: .wave, .systemPurple, .systemPink),
            SpaceVibe(symbol: "hourglass", name: "Deep work", motion: .rotate, .systemOrange, .systemBrown),
            SpaceVibe(symbol: "chart.line.uptrend.xyaxis", name: "Growth", motion: .bounce, .systemGreen, .systemTeal),
            SpaceVibe(symbol: "checkmark.seal.fill", name: "Done", motion: .bounce, .systemBlue, .systemIndigo),
        ]),
        Group(title: "Play", vibes: [
            SpaceVibe(symbol: "gamecontroller.fill", name: "Game", motion: .wiggle, .systemPurple, .systemIndigo),
            SpaceVibe(symbol: "music.note", name: "Tune", motion: .bounce, .systemPink, .systemRed),
            SpaceVibe(symbol: "heart.fill", name: "Love", motion: .pulse, .systemRed, .systemPink),
            SpaceVibe(symbol: "theatermasks.fill", name: "Drama", motion: .wiggle, .systemPurple, .systemPink),
            SpaceVibe(symbol: "paintbrush.pointed.fill", name: "Create", motion: .wiggle, .systemOrange, .systemPink),
            SpaceVibe(symbol: "camera.aperture", name: "Shoot", motion: .rotate, .systemTeal, .systemBlue),
            SpaceVibe(symbol: "airplane", name: "Away", motion: .bounce, .systemBlue, .systemCyan),
            SpaceVibe(symbol: "balloon.2.fill", name: "Fun", motion: .breathe, .systemRed, .systemPink),
        ]),
    ]

    static let icons: [(title: String, symbols: [String])] = [
        ("Work", ["briefcase.fill", "building.2.fill", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "apple.terminal.fill",
                  "server.rack", "cpu.fill", "envelope.fill", "calendar", "checklist", "doc.text.fill", "folder.fill",
                  "tray.full.fill", "chart.bar.fill", "dollarsign.circle.fill", "person.2.fill"]),
        ("Life", ["house.fill", "cart.fill", "fork.knife", "dumbbell.fill", "bicycle", "car.fill", "bed.double.fill", "gift.fill",
                  "book.fill", "graduationcap.fill", "pawprint.fill", "stroller.fill", "cross.case.fill", "tshirt.fill",
                  "birthday.cake.fill", "film.fill"]),
        ("Places", ["globe.americas.fill", "map.fill", "mountain.2.fill", "beach.umbrella.fill", "tent.fill", "building.columns.fill",
                    "tram.fill", "ferry.fill", "sailboat.fill", "location.fill", "signpost.right.fill", "binoculars.fill"]),
        ("Shapes", ["star.fill", "heart.fill", "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill",
                    "seal.fill", "bookmark.fill", "flag.fill", "bell.fill", "asterisk", "square.grid.2x2.fill",
                    "circle.grid.3x3.fill", "square.stack.3d.up.fill", "infinity"]),
    ]

    /// A space's symbol for AppKit (the sidebar header, the dock, Manage Spaces): a vibe in its
    /// own colours, which the caller must not tint over, anything else a template to tint.
    static func image(_ name: String, size: CGFloat? = nil, weight: NSFont.Weight = .medium) -> (image: NSImage?, colored: Bool) {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        var config = size.map { NSImage.SymbolConfiguration(pointSize: $0, weight: weight) } ?? NSImage.SymbolConfiguration(scale: .medium)
        guard let vibe = vibe(name) else { return (base?.withSymbolConfiguration(config), false) }
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: vibe.colors))
        let image = base?.withSymbolConfiguration(config)
        image?.isTemplate = false
        return (image, true)
    }

    /// The vibe a stored symbol belongs to, for its motion.
    static func vibe(_ symbol: String?) -> SpaceVibe? {
        guard let symbol else { return nil }
        return vibes.lazy.flatMap(\.vibes).first { $0.symbol == symbol }
    }
}

/// Plays a vibe's motion once each time `trigger` changes, and loops it while `looping`.
private struct VibeMotionModifier: ViewModifier {
    let motion: VibeMotion
    let trigger: Int
    let looping: Bool

    func body(content: Content) -> some View {
        switch motion {
        case .bounce:
            content.symbolEffect(.bounce, value: trigger)
                .symbolEffect(.pulse, options: .repeating, isActive: looping)
        case .pulse:
            content.symbolEffect(.pulse, options: .repeating, isActive: looping)
                .symbolEffect(.bounce, value: trigger)
        case .wave:
            content.symbolEffect(.variableColor.iterative, options: .repeating, isActive: looping)
                .symbolEffect(.bounce, value: trigger)
        case .breathe:
            if #available(macOS 15, *) {
                content.symbolEffect(.breathe, options: .repeating, isActive: looping)
                    .symbolEffect(.bounce, value: trigger)
            } else {
                content.symbolEffect(.pulse, options: .repeating, isActive: looping)
                    .symbolEffect(.bounce, value: trigger)
            }
        case .wiggle:
            if #available(macOS 15, *) {
                content.symbolEffect(.wiggle, value: trigger)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.6)), isActive: looping)
            } else {
                content.symbolEffect(.bounce, value: trigger)
            }
        case .rotate:
            if #available(macOS 15, *) {
                content.symbolEffect(.rotate, value: trigger)
                    .symbolEffect(.rotate, options: .repeat(.periodic(delay: 1.2)), isActive: looping)
            } else {
                content.symbolEffect(.bounce, value: trigger)
            }
        }
    }
}

/// The space icon picker: Vibes (animated), Icons and Emoji tabs over one grid, and a button to
/// remove the icon. The same view sits in the Edit Space sheet and in the header's popover.
struct SpaceIconPicker: View {
    static let size = CGSize(width: 332, height: 360)

    let current: String
    let currentSymbol: String?
    let onPick: (String) -> Void
    let onPickSymbol: (String) -> Void
    let onRemove: () -> Void
    /// Shorter where it sits inside a sheet.
    var height: CGFloat = SpaceIconPicker.size.height

    enum Tab: String, CaseIterable { case vibes = "Vibes", icons = "Icons", emoji = "Emoji" }
    @State private var tab: Tab = .vibes
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SpaceIconTabs(selection: $tab)
                Button(action: onRemove) { SettingsIconTile(symbol: "trash", active: false, size: 28) }
                    .buttonStyle(.plain)
                    .help("Remove icon")
                    .accessibilityLabel("Remove icon")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
            switch tab {
            case .vibes: SpaceVibeGrid(current: currentSymbol, onPick: onPickSymbol)
            case .icons: SpaceSymbolGrid(current: currentSymbol, onPick: onPickSymbol)
            case .emoji: emojiTab
            }
        }
        .frame(width: Self.size.width, height: height)
        .onAppear {
            if !current.isEmpty { tab = .emoji }
            else if let s = currentSymbol, SpaceIconCatalog.vibe(s) == nil { tab = .icons }
        }
    }

    private var emojiTab: some View {
        // The gap sits outside the scroll view: scrolling to the current emoji's row would
        // otherwise slide the grid's own top margin away and butt it against the search.
        VStack(spacing: 10) {
            SettingsSearchField(text: $query, focused: $searchFocused)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            SpaceEmojiGrid(current: current, query: query, onPick: onPick)
        }
    }
}

/// Three tabs on a soft track; the chosen one is a raised plate.
private struct SpaceIconTabs: View {
    @Binding var selection: SpaceIconPicker.Tab
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SpaceIconPicker.Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { selection = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 12, weight: selection == t ? .semibold : .medium))
                        .foregroundStyle(selection == t ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if selection == t {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "plate", in: plate)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// One cell: the glyph on a tile, accent plate and ring when it is the space's icon.
private struct IconCell<Glyph: View>: View {
    let selected: Bool
    let help: String
    /// A colour of its own (a vibe's): the tile is softly washed in it and its ring takes it.
    var tint: Color? = nil
    let action: () -> Void
    @ViewBuilder let glyph: (Bool) -> Glyph
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            glyph(hovered)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? (tint ?? Design.accent).opacity(0.75) : .clear, lineWidth: 1.5))
                .scaleEffect(hovered && !selected ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if let tint { return tint.opacity(selected ? 0.3 : hovered ? 0.22 : 0.13) }
        return selected ? Design.accent.opacity(0.18) : Color.primary.opacity(hovered ? 0.09 : 0)
    }
}

/// Eight square tiles with an even 6 pt gap, rows and columns alike.
private let iconColumns = Array(repeating: GridItem(.flexible(minimum: 28), spacing: 6), count: 8)
private let iconRowSpacing: CGFloat = 6

private struct GridSectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 1).padding(.top, 10).padding(.bottom, 6)
    }
}

/// Vibes: animated icons in four moods. Each plays its motion on hover; the space's own vibe
/// keeps moving.
struct SpaceVibeGrid: View {
    let current: String?
    let onPick: (String) -> Void
    @State private var bumps: [String: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(SpaceIconCatalog.vibes) { group in
                    GridSectionTitle(text: group.title)
                    LazyVGrid(columns: iconColumns, spacing: iconRowSpacing) {
                        ForEach(group.vibes) { vibe in
                            let selected = vibe.symbol == current
                            IconCell(selected: selected, help: vibe.name, tint: vibe.tileColor, action: { onPick(vibe.symbol) }) { hovered in
                                Image(systemName: vibe.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(vibe.gradient)
                                    .modifier(VibeMotionModifier(motion: vibe.motion, trigger: bumps[vibe.symbol, default: 0], looping: selected))
                                    .onChange(of: hovered) { _, now in if now { bumps[vibe.symbol, default: 0] += 1 } }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

/// Icons: still symbols by theme.
struct SpaceSymbolGrid: View {
    let current: String?
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(SpaceIconCatalog.icons, id: \.title) { group in
                    GridSectionTitle(text: group.title)
                    LazyVGrid(columns: iconColumns, spacing: iconRowSpacing) {
                        ForEach(group.symbols, id: \.self) { name in
                            let selected = name == current
                            IconCell(selected: selected, help: name, action: { onPick(name) }) { _ in
                                Image(systemName: name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(selected ? Design.accent : Color.primary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

/// Emoji: the full catalogue, searchable, with a category bar to jump between sections. Opens on
/// the current emoji's row.
private struct SpaceEmojiGrid: View {
    let current: String
    let query: String
    let onPick: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: iconColumns, spacing: iconRowSpacing) {
                    let entries = query.isEmpty ? EmojiCatalog.all : EmojiCatalog.search(query)
                    ForEach(entries, id: \.self) { e in
                        IconCell(selected: e.emoji == current, help: e.name, action: { onPick(e.emoji) }) { _ in
                            Text(e.emoji).font(.system(size: 21))
                        }
                        .id(e.emoji)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .onAppear { if let anchor = rowAnchor(current) { proxy.scrollTo(anchor, anchor: .top) } }
            Rectangle().fill(Design.hairline).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(EmojiCatalog.categories) { c in
                    Button {
                        proxy.scrollTo(c.entries.first?.emoji, anchor: .top)
                    } label: {
                        Image(systemName: c.symbol).font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!query.isEmpty)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    /// Rows are 8 wide, so the current emoji's row starts at the first emoji of its row.
    private func rowAnchor(_ emoji: String) -> String? {
        guard let i = EmojiCatalog.all.firstIndex(where: { $0.emoji == emoji }) else { return nil }
        return EmojiCatalog.all[i - i % 8].emoji
    }
}
