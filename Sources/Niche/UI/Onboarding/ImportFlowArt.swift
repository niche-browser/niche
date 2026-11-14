import SwiftUI

// The right-hand panel of the import window. Dia paints these as artwork
// (Rebrand*Screenshot in BoostBrowser_Unboxing) with a live sidebar preview
// (DiaSidebarPreviewView) on the space step; Niche draws its own from the data
// being imported: the badge ring follows Dia's composition, the window mock
// shows the hovered space in its own theme.

/// The scenes' own colours.
private enum Palette {
    /// The backdrop's two colour fields. Dia paints the default browser step warm
    /// (RebrandDefaultBrowserScreenshot); the cover, privacy and outro take the brand's orange; an
    /// import with no theme to show is a cool blue.
    static let warmDark = ["#8A5038", "#5C2A1C"]
    static let warmLight = ["#E2A585", "#F1D9C8"]
    static let brandDark = ["#4a1c0c", "#0b0c0e"]
    static let brandLight = ["#ffd8c8", "#f7f6f3"]
    static let coolDark = ["#2A3440", "#151A20"]
    static let coolLight = ["#DCE6F0", "#C4D3E2"]
    /// Dia's badge glyphs are a pale blue (#A7D3E8); a space's accent replaces it, lifted toward white
    /// by this much on the dark panel and on the light one.
    static let badgeBlue = "#8EC5E3"
    static let accentLiftDark = 0.25
    static let accentLiftLight = 0.35
    /// The panel fades in from the words' column: its mask a seventh of the way across.
    static let maskMid = Color.black.opacity(0.6)
    /// How strongly the backdrop's first and second colour field show on the dark panel and on the
    /// light one, the white highlight over the light one, and the grain over each.
    static let fieldDark = (first: 0.55, second: 0.5)
    static let fieldLight = (first: 0.75, second: 0.7)
    static let highlightLight = Color.white.opacity(0.55)
    static let grainDark = 0.08
    static let grainLight = 0.07
    /// The light backdrop's ground, and a disc or window on it: a step under white, so a white rim shows.
    static let groundLight = Color(white: 0.93)
    static let discLight = Color(white: 0.96)
    /// Glass on the light backdrop (the Dock, an empty tile) and its white rim.
    static let glassLight = Color.white.opacity(0.32)
    static let rimLight = Color.white.opacity(0.6)
    /// Shadows: something lifted off the backdrop, and a window or panel floating over it.
    static let lift = Color(nsColor: Design.Shadow.cardColor)
    static let float = Color(nsColor: Design.Shadow.panelColor)
    /// The cover's dot glows between these two strengths.
    static let glowDim = Design.accent.opacity(0.55)
    static let glowBright = Design.accent.opacity(0.9)
}

/// The scenes' own geometry.
private enum Metrics {
    /// The panel: the window's right side.
    static let panel = CGSize(width: 477, height: 544)
    /// Dia's artwork is 448 pt wide; its positions scale to the panel.
    static let diaScale: CGFloat = 477 / 448
    /// The two rings around the centre of the badge and key scenes, and the mark or disc inside them.
    static let rings: [CGFloat] = [118, 140]
    static let centre: CGFloat = 132
    static let keyGlyph: CGFloat = 58
    /// The cover: the mark's 32 grid scaled to 300 pt, where the arch starts, the dot, its glow's two
    /// radii and one breath of it.
    static let archScale: CGFloat = 300 / 32
    static let archOrigin = CGPoint(x: 150, y: 70)
    static let dot: CGFloat = 84
    static let glowRadiusDim: CGFloat = 30
    static let glowRadiusBright: CGFloat = 46
    static let glowPeriod: TimeInterval = 2.4
    /// The cover's command bar: where it floats, its width, its field and a row and its glyph plate.
    static let barOrigin = CGPoint(x: 110, y: 330)
    static let barWidth: CGFloat = 330
    static let barField: CGFloat = 48
    static let barRow: CGFloat = 36
    static let barGlyph: CGFloat = 22
    /// The Dock: its corners, and a neighbour's tile on it.
    static let dockRadius: CGFloat = 30
    static let tileRadius: CGFloat = 24
    /// The window mock: a traffic light, a sidebar row, a favorite's tile, the URL pill, an extension's tile.
    static let trafficLight: CGFloat = 13
    static let sidebarRow: CGFloat = 30
    static let favorite: CGFloat = 40
    static let pill: CGFloat = 34
    static let extensionTile: CGFloat = 58
}

struct ImportArtPanel: View {
    let model: ImportFlowModel
    let colors: ImportColors

    var body: some View {
        // Dia paints the default browser step warm (RebrandDefaultBrowserScreenshot).
        let theme = model.step == .defaultBrowser
            ? SpaceTheme(colors: colors.dark ? Palette.warmDark : Palette.warmLight, intensity: 1, noise: 0.2, appearance: colors.dark ? "dark" : "light")
            : model.step == .cover || model.step == .privacy || model.step == .outro
            ? SpaceTheme(colors: colors.dark ? Palette.brandDark : Palette.brandLight, intensity: 1, noise: 0.2, appearance: colors.dark ? "dark" : "light")
            : model.previewTheme ?? SpaceTheme(colors: colors.dark ? Palette.coolDark : Palette.coolLight,
                                               intensity: 1, noise: 0.2, appearance: colors.dark ? "dark" : "light")
        ZStack(alignment: .topLeading) {
            ArtBackdrop(theme: theme, dark: colors.dark)
            switch model.step {
            case .defaultBrowser:
                DockArt(model: model, colors: colors)
            case .source:
                BadgeRing(model: model, colors: colors, accent: accent(model.previewTheme))
            case .spaces:
                WindowMock(theme: theme, colors: colors) {
                    SidebarPreview(model: model, theme: theme)
                        .id(model.previewSpace)
                        .transition(.opacity)
                } pane: { EmptyView() }
                .animation(.easeInOut(duration: Design.Motion.standard), value: model.previewSpace)
            case .extensions:
                WindowMock(theme: theme, colors: colors, origin: CGPoint(x: 96, y: 80), sidebarWidth: 120) {
                    PlaceholderSidebar(theme: theme)
                } pane: {
                    ExtensionsPreview(model: model, colors: ImportColors(dark: theme.palette.isDark))
                }
            case .progress:
                BadgeRing(model: model, colors: colors, accent: accent(model.previewTheme))
            case .cover:
                CoverArt(colors: colors)
            case .privacy:
                EmptyView()
            case .personalization:
                // A live preview of a Niche window in the picked theme colour and layout.
                WindowMock(theme: theme, colors: colors, origin: CGPoint(x: 90, y: 80), sidebarWidth: 210,
                           headerControls: !model.classicLayout) {
                    VStack(alignment: .leading, spacing: Design.Space.m) {
                        if !model.classicLayout {
                            AddressPreview(theme: theme, inSidebar: true)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        PlaceholderSidebar(theme: theme)
                    }
                } pane: {
                    if model.classicLayout {
                        AddressPreview(theme: theme, inSidebar: false)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: Design.Motion.slow), value: theme)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.classicLayout)
            case .unlock, .safariExport, .passwordsFile, .credentialsResult:
                KeyArt(colors: colors, accent: accent(model.previewTheme))
            case .pinnedTabs:
                WindowMock(theme: theme, colors: colors) {
                    PlaceholderSidebar(theme: theme)
                } pane: { EmptyView() }
            case .outro:
                EmptyView()
            }
        }
        .frame(width: Metrics.panel.width, height: Metrics.panel.height, alignment: .topLeading)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Palette.maskMid, location: 0.14),
                                     .init(color: .black, location: 0.3)], startPoint: .leading, endPoint: .trailing))
        .clipped()
        .animation(.easeInOut(duration: Design.Motion.slow), value: theme)
    }

    /// Dia's badge glyphs are a pale blue (#A7D3E8); a space's accent replaces it.
    private func accent(_ t: SpaceTheme?) -> Color {
        let base = Color(hex: t.map { $0.accent ?? $0.colors.first ?? Palette.badgeBlue } ?? Palette.badgeBlue)
        return base.blendedToward(.white, colors.dark ? Palette.accentLiftDark : Palette.accentLiftLight)
    }
}

/// The cover's scene: the logo's arch rising behind a glass command bar, the signal dot
/// glowing where the arch would stand. Abstract, and it shows the one key worth learning.
private struct CoverArt: View {
    let colors: ImportColors
    @State private var glow = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The arch, oversized and faint, on the mark's 32 grid scaled to 300 pt.
            Canvas { ctx, size in
                let s = Metrics.archScale
                let o = Metrics.archOrigin
                var arch = Path()
                arch.move(to: CGPoint(x: o.x + 7 * s, y: o.y + 17.5 * s))
                arch.addLine(to: CGPoint(x: o.x + 7 * s, y: o.y + 15 * s))
                arch.addArc(center: CGPoint(x: o.x + 16 * s, y: o.y + 15 * s), radius: 9 * s,
                            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                arch.addLine(to: CGPoint(x: o.x + 25 * s, y: o.y + 32 * s))
                ctx.stroke(arch, with: .color(colors.plate(.selected)), lineWidth: 6 * s)
            }
            .frame(width: Metrics.panel.width, height: Metrics.panel.height)
            Circle()
                .fill(Design.accent)
                .frame(width: Metrics.dot, height: Metrics.dot)
                .shadow(color: glow ? Palette.glowBright : Palette.glowDim, radius: glow ? Metrics.glowRadiusBright : Metrics.glowRadiusDim)
                .offset(x: Metrics.archOrigin.x + 2.5 * Metrics.archScale, y: Metrics.archOrigin.y + 20 * Metrics.archScale)
            // The command bar, floating over the scene.
            VStack(spacing: 0) {
                HStack(spacing: Design.Space.m) {
                    Image(systemName: "magnifyingglass").font(.system(size: Design.Icon.bar, weight: .medium)).foregroundStyle(colors.text(.tertiary))
                    Text("Search or enter address").font(Design.Font.ui(.title)).foregroundStyle(colors.text(.tertiary))
                    Spacer(minLength: 0)
                    Text("⌘T").font(Design.Font.ui(.caption, .semibold)).foregroundStyle(colors.body)
                        .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xxs)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(colors.plate(.selected)))
                }
                .padding(.horizontal, Design.Space.xl).frame(height: Metrics.barField)
                Rectangle().fill(colors.hairline).frame(height: Design.Space.hair)
                VStack(spacing: Design.Space.xxs) {
                    row("square.on.square", "Switch to Tab", selected: true)
                    row("clock.arrow.circlepath", "Reopen yesterday’s tabs", selected: false)
                    row("sidebar.left", "New Space", selected: false)
                }
                .padding(Design.Space.s)
            }
            .frame(width: Metrics.barWidth)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.5))
            .shadow(color: colors.dark ? Palette.float : Palette.lift, radius: Design.Shadow.panelRadius, y: Design.Shadow.panelOffset)
            .offset(x: Metrics.barOrigin.x, y: Metrics.barOrigin.y)
        }
        // The dot breathes, unless Reduce motion is on: then it keeps its resting glow.
        .onAppear {
            guard !Design.Motion.reduced else { return }
            withAnimation(.easeInOut(duration: Metrics.glowPeriod).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private func row(_ symbol: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: Design.Space.m) {
            Image(systemName: symbol).font(.system(size: Design.Icon.small)).foregroundStyle(selected ? Design.onDarkColor(.primary) : colors.body)
                .frame(width: Metrics.barGlyph, height: Metrics.barGlyph)
                .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(selected ? Design.fillOnDarkColor(.strong) : colors.plate(.hover)))
            Text(title).font(Design.Font.control).foregroundStyle(selected ? Design.onDarkColor(.primary) : colors.body)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Space.m).frame(height: Metrics.barRow)
        .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(selected ? Design.accent : .clear))
    }
}

/// Soft blurred colour fields with grain, standing in for Dia's paintings.
private struct ArtBackdrop: View {
    let theme: SpaceTheme
    let dark: Bool
    var body: some View {
        let c0 = Color(hex: theme.colors.first ?? Palette.coolLight[1])
        let c1 = Color(hex: theme.colors.count > 1 ? theme.colors[1] : (theme.colors.first ?? Palette.coolLight[0]))
        let base: Color = dark ? Design.graphite : Palette.groundLight
        let field = dark ? Palette.fieldDark : Palette.fieldLight
        ZStack {
            base
            Ellipse().fill(c0.opacity(field.first)).frame(width: 340, height: 460).blur(radius: 70).offset(x: 130, y: -120)
            Ellipse().fill(c1.opacity(field.second)).frame(width: 300, height: 360).blur(radius: 80).offset(x: 170, y: 190)
            Ellipse().fill(dark ? Design.fillOnDarkColor(.hover) : Palette.highlightLight).frame(width: 220, height: 300).blur(radius: 60).offset(x: -20, y: 40)
            Image(nsImage: NoiseTexture.image).resizable(resizingMode: .tile)
                .opacity(dark ? Palette.grainDark : Palette.grainLight).blendMode(dark ? .screen : .multiply)
        }
        .frame(width: Metrics.panel.width, height: Metrics.panel.height)
    }
}

// MARK: - Dock

/// After Dia's RebrandDefaultBrowserScreenshot (476×544 pt): the app's tile
/// lifted out of a glass Dock between two neighbours, a running dot under it.
/// The left neighbour is the current default browser, where Niche's tile lands.
private struct DockArt: View {
    let model: ImportFlowModel
    let colors: ImportColors

    var body: some View {
        let system = model.system
        let docked = system.isInDock || model.addToDock
        let glass = colors.dark ? Design.fillOnDarkColor(.strong) : Palette.glassLight
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Metrics.dockRadius, style: .continuous)
                .fill(glass)
                .overlay(RoundedRectangle(cornerRadius: Metrics.dockRadius, style: .continuous).strokeBorder(colors.dark ? Design.fillOnDarkColor(.strong) : Palette.rimLight, lineWidth: 1))
                .frame(width: 420, height: 167)
                .offset(x: 88, y: 205)
            NeighbourTile(icon: system.defaultBrowserURL.map { NSWorkspace.shared.icon(forFile: $0.path) }, dark: colors.dark)
                .offset(x: 64, y: 235)
            // Right neighbour: Arc (Dia when Arc is already the default on the left).
            NeighbourTile(icon: neighbourIcon(excluding: system.defaultBrowserURL), dark: colors.dark)
                .offset(x: 368, y: 235)
            // A macOS icon's artwork fills 824 of its 1024 pt canvas; Dia's tile is 144 pt.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 144 * 1024 / 824, height: 144 * 1024 / 824)
                .shadow(color: Palette.lift, radius: 16, y: 8)
                .scaleEffect(docked ? 1 : 0.86)
                .opacity(docked ? 1 : Design.Opacity.disabled)
                .position(x: 269, y: docked ? 199.5 : 228)
            Circle().fill(Design.panelDarkColor)
                .frame(width: 10, height: 10)
                .position(x: 269, y: 338)
                .opacity(docked ? 1 : 0)
        }
        .frame(width: Metrics.panel.width, height: Metrics.panel.height, alignment: .topLeading)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: docked)
    }

    private func neighbourIcon(excluding defaultBrowser: URL?) -> NSImage? {
        for source in [ImportSource.arc, .dia] {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID),
                  url.standardizedFileURL != defaultBrowser?.standardizedFileURL else { continue }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}

private struct NeighbourTile: View {
    let icon: NSImage?
    let dark: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
        ZStack {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 106 * 1024 / 824, height: 106 * 1024 / 824)
                    .opacity(0.85)
            } else {
                shape.fill(LinearGradient(colors: dark ? [Design.fillOnDarkColor(.strong), Design.fillOnDarkColor(.selected)] : [Palette.rimLight, Palette.glassLight],
                                          startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(dark ? Design.fillOnDarkColor(.strong) : Palette.rimLight, lineWidth: 1)
            }
        }
        .frame(width: 106, height: 106)
    }
}

/// The unlock and passwords steps: a key over the same two rings as the badge ring.
private struct KeyArt: View {
    let colors: ImportColors
    let accent: Color
    var body: some View {
        ZStack {
            ForEach(Metrics.rings, id: \.self) { r in
                Circle().strokeBorder(colors.text(.quaternary), lineWidth: 1)
                    .frame(width: r * 2 * Metrics.diaScale, height: r * 2 * Metrics.diaScale)
            }
            Circle().fill(colors.dark ? Design.panelDarkColor : Palette.discLight)
                .frame(width: Metrics.centre, height: Metrics.centre)
                .shadow(color: colors.dark ? Palette.float : Palette.lift, radius: 16, y: 6)
            Image(systemName: "key.fill").font(.system(size: Metrics.keyGlyph, weight: .regular)).foregroundStyle(accent)
        }
        .frame(width: Metrics.panel.width, height: Metrics.panel.height)
    }
}

// MARK: - Badge ring

/// Positions follow Dia's RebrandImportScreenshot (448×544 pt) scaled to the
/// 477 pt panel: five badges around the app mark inside two rings.
private struct BadgeRing: View {
    let model: ImportFlowModel
    let colors: ImportColors
    let accent: Color

    private static let scale = Metrics.diaScale
    private static let badges: [(id: String, symbol: String, x: CGFloat, y: CGFloat, r: CGFloat)] = [
        ("tabs", "pin.fill", 155, 145, 29),
        ("spaces", "square.stack.fill", 376, 120, 44),
        ("favorites", "star.fill", 392, 277, 21),
        ("extensions", "puzzlepiece.extension.fill", 122, 362, 23),
        ("archive", "archivebox.fill", 288, 434, 34),
    ]

    var body: some View {
        let s = Self.scale
        ZStack(alignment: .topLeading) {
            ForEach(Metrics.rings, id: \.self) { r in
                Circle().strokeBorder(colors.text(.quaternary), lineWidth: 1)
                    .frame(width: r * 2 * s, height: r * 2 * s)
                    .position(x: 263 * s, y: 272)
            }
            BrandMark(size: Metrics.centre)
                .shadow(color: Palette.lift, radius: 18, y: 6)
                .position(x: 263 * s, y: 272)
            ForEach(Self.badges, id: \.id) { b in
                Badge(symbol: b.symbol, radius: b.r * s, state: state(b.id), colors: colors, accent: accent)
                    .position(x: b.x * s, y: b.y)
            }
        }
        .frame(width: Metrics.panel.width, height: Metrics.panel.height, alignment: .topLeading)
    }

    private func state(_ id: String) -> ImportCategory.State? {
        guard model.step == .progress else { return nil }
        // Pinned tabs and folders share a tile with spaces' contents.
        return model.categories.first { $0.id == id }?.state ?? .waiting
    }
}

private struct Badge: View {
    let symbol: String
    let radius: CGFloat
    let state: ImportCategory.State?
    let colors: ImportColors
    let accent: Color

    var body: some View {
        let lit = state == nil || state == .done || state == .working
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(colors.dark ? Design.panelDarkColor : Palette.discLight)
                Circle().strokeBorder(colors.dark ? colors.hairline : .white, lineWidth: colors.dark ? 1 : 2.5)
                Image(systemName: symbol).font(.system(size: radius * 0.78, weight: .medium)).foregroundStyle(accent)
            }
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: colors.dark ? Palette.float : Palette.lift, radius: 8, y: 3)
            if state == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: max(Design.Icon.bar, radius * 0.5)))
                    .foregroundStyle(colors.ink, colors.dark ? Design.panelDarkColor : .white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(lit ? 1 : Design.Opacity.disabled)
        .scaleEffect(state == .working ? 1.08 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state)
    }
}

// MARK: - Window mock

/// After Dia's RebrandArcImportPreviewScreenshot: a window entering from the
/// lower right, traffic lights at its top left, sidebar beside a content pane.
private struct WindowMock<Sidebar: View, Pane: View>: View {
    let theme: SpaceTheme
    let colors: ImportColors
    /// Dia's window enters at (124, 80) of its 448 pt artwork, sidebar 243 pt wide.
    var origin = CGPoint(x: 132, y: 80)
    var sidebarWidth: CGFloat = 236
    /// The toolbar-hidden title row: sidebar toggle after the traffic lights, ← → ↻ at the right.
    var headerControls = false
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let pane: () -> Pane

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
        let palette = theme.palette
        ZStack(alignment: .topLeading) {
            SpaceBackground(palette: palette)
                .background(palette.isDark ? Design.graphite : Palette.discLight)
            sidebar()
                .frame(width: sidebarWidth, alignment: .topLeading)
                .padding(.top, 48)
            HStack(spacing: Design.Space.m) {
                ForEach(ImportColors.trafficLights, id: \.self) { Circle().fill(Color(hex: $0)).frame(width: Metrics.trafficLight, height: Metrics.trafficLight) }
            }
            .offset(x: 19, y: 20)
            if headerControls {
                let tone = ImportColors(dark: palette.isDark).body
                HStack(spacing: Design.Space.xxs) {
                    Image(systemName: "sidebar.left").frame(width: 24)
                    Spacer()
                    ForEach(["arrow.left", "arrow.right", "arrow.clockwise"], id: \.self) { Image(systemName: $0).frame(width: 24) }
                }
                .font(.system(size: Design.Icon.regular, weight: .regular))
                .foregroundStyle(tone)
                .frame(width: sidebarWidth - 86, height: 26)
                .offset(x: 80, y: 13.5)
                .transition(.opacity)
            }
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(palette.isDark ? Design.panelDarkColor : .white)
                .shadow(color: Palette.lift, radius: Design.Shadow.cardRadius, y: Design.Shadow.cardOffset)
                .overlay(alignment: .topLeading) { pane() }
                .frame(width: 400, height: 500)
                .offset(x: sidebarWidth + 6, y: 10)
        }
        .frame(width: 520, height: 520, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.dark ? colors.hairline : Palette.rimLight, lineWidth: 0.5))
        .shadow(color: colors.dark ? Palette.float : Palette.lift, radius: Design.Shadow.panelRadius, y: Design.Shadow.panelOffset)
        .offset(x: origin.x, y: origin.y)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }
}

/// Dia's DiaSidebarPreviewView: favourites grid, space name, pinned tabs and
/// folders of the space being looked at.
private struct SidebarPreview: View {
    let model: ImportFlowModel
    let theme: SpaceTheme

    var body: some View {
        let p = theme.palette
        if let plan = model.plan, let i = model.previewSpace, i < plan.spaces.count {
            let space = plan.spaces[i]
            let favorites = Array((space.favorites + (model.includeFavorites ? plan.favorites : [])).filter { !$0.isFolder }.prefix(8))
            VStack(alignment: .leading, spacing: Design.Space.m) {
                if !favorites.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Design.Space.s), count: 4), spacing: Design.Space.s) {
                        ForEach(Array(favorites.enumerated()), id: \.offset) { _, f in
                            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(p.pillFill)
                                .frame(height: Metrics.favorite)
                                .overlay(Favicon(image: model.favicon(for: f), size: Design.Icon.image, palette: p))
                        }
                    }
                }
                HStack(spacing: Design.Space.s) {
                    Text(space.emoji).font(Design.Font.ui(.detail))
                    Text(space.title).font(Design.Font.ui(.detail, .semibold)).foregroundStyle(p.textSecondary)
                }
                .padding(.leading, Design.Space.xs)
                VStack(alignment: .leading, spacing: Design.Space.hair) {
                    ForEach(Array(space.pinned.prefix(9).enumerated()), id: \.offset) { _, item in
                        PreviewRow(item: item, model: model, palette: p)
                    }
                    if !space.today.isEmpty {
                        Rectangle().fill(p.separator).frame(height: Design.Space.hair).padding(.vertical, Design.Space.s).padding(.horizontal, Design.Space.s)
                        ForEach(Array(space.today.prefix(4).enumerated()), id: \.offset) { _, item in
                            PreviewRow(item: item, model: model, palette: p)
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Space.l)
            .opacity(model.selectedSpaces.contains(i) ? 1 : Design.Opacity.disabled)
        }
    }
}

private struct PreviewRow: View {
    let item: ImportedItem
    let model: ImportFlowModel
    let palette: SpacePalette
    var body: some View {
        HStack(spacing: Design.Space.m) {
            if item.isFolder {
                Image(systemName: "folder.fill").font(.system(size: Design.Icon.regular)).foregroundStyle(palette.folderTint).frame(width: Design.Icon.image)
            } else {
                Favicon(image: model.favicon(for: item), size: Design.Icon.image, palette: palette)
            }
            Text(item.customTitle ?? (item.pageTitle.isEmpty ? (item.url ?? "") : item.pageTitle))
                .font(Design.Font.body).foregroundStyle(palette.textPrimary).lineLimit(1)
            if item.isFolder {
                Text("\(item.children.count)").font(Design.Font.caption).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Design.Space.m)
        .frame(height: Metrics.sidebarRow)
    }
}

private struct Favicon: View {
    let image: NSImage?
    let size: CGFloat
    let palette: SpacePalette
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous))
        } else {
            Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundStyle(palette.textTertiary).frame(width: size, height: size)
        }
    }
}

private struct PlaceholderSidebar: View {
    let theme: SpaceTheme
    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: Design.Space.l) {
            ForEach([0.7, 0.5, 0.82, 0.6, 0.44], id: \.self) { w in
                HStack(spacing: Design.Space.m) {
                    RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(p.textTertiary.opacity(Design.Opacity.dimmed)).frame(width: Design.Icon.image, height: Design.Icon.image)
                    Capsule().fill(p.textTertiary.opacity(Design.Opacity.disabled)).frame(width: 70 * w, height: Design.Space.m)
                }
            }
        }
        .padding(.horizontal, Design.Space.xl)
        .padding(.top, Design.Space.m)
    }
}

/// The address bar of the personalization preview: Arc's second sidebar row
/// (nav buttons and a URL pill), or the toolbar strip above the page.
private struct AddressPreview: View {
    let theme: SpaceTheme
    let inSidebar: Bool
    var body: some View {
        let p = theme.palette
        if inSidebar {
            // Arc's toolbar-hidden URL pill: the sidebar's width less 8 pt a side, the bare host.
            RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(p.pillFill)
                .frame(height: Metrics.pill)
                .overlay(alignment: .leading) {
                    Text("nichebrowser.app").font(Design.Font.detail).foregroundStyle(p.textPrimary).padding(.leading, Design.Space.l)
                }
                .padding(.horizontal, Design.Space.m)
        } else {
            let c = ImportColors(dark: p.isDark)
            VStack(spacing: 0) {
                HStack(spacing: Design.Space.m) {
                    Image(systemName: "sidebar.left").font(.system(size: Design.Icon.small)).foregroundStyle(c.text(.tertiary))
                    navButtons(p, ink: c.text(.tertiary))
                    Text("nichebrowser.app").font(Design.Font.ui(.micro)).foregroundStyle(c.body)
                    Spacer()
                }
                .padding(.horizontal, Design.Space.m)
                .frame(height: Metrics.sidebarRow)
                Rectangle().fill(c.hairline).frame(height: Design.Space.hair)
            }
        }
    }

    private func navButtons(_ p: SpacePalette, ink: Color? = nil) -> some View {
        HStack(spacing: Design.Space.s) {
            ForEach(["arrow.left", "arrow.right", "arrow.clockwise"], id: \.self) {
                Image(systemName: $0).font(Design.Font.ui(.micro, .medium)).foregroundStyle(ink ?? p.textTertiary)
            }
        }
    }
}

/// The content pane on the extensions step: a toolbar pill of the picked
/// extensions (Dia's screenshot puts its Chat pill there) and their icons.
private struct ExtensionsPreview: View {
    let model: ImportFlowModel
    let colors: ImportColors
    var body: some View {
        let picked = model.extensions.filter { model.selectedExtensions.contains($0.id) }
        let fill = colors.plate(colors.dark ? .selected : .hover)
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            HStack(spacing: Design.Space.m) {
                ForEach(picked.prefix(5)) { ExtensionIcon(image: $0.icon, size: Design.Icon.image, c: colors) }
                Image(systemName: "puzzlepiece.extension").font(.system(size: Design.Icon.regular)).foregroundStyle(colors.body)
            }
            .padding(.horizontal, Design.Space.l)
            .frame(height: Metrics.pill)
            .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(fill))
            .animation(.easeOut(duration: Design.Motion.standard), value: model.selectedExtensions)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Metrics.extensionTile), spacing: Design.Space.l), count: 3), alignment: .leading, spacing: Design.Space.l) {
                ForEach(picked.prefix(9)) { e in
                    RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(fill)
                        .frame(width: Metrics.extensionTile, height: Metrics.extensionTile)
                        .overlay(ExtensionIcon(image: e.icon, size: 30, c: colors))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.selectedExtensions)
        }
        .padding(.top, Design.Space.l)
        .padding(.leading, Design.Space.xl)
    }
}
