import SwiftUI

// Metrics measured from Dia 1.54's import window at 2x (window 928×544 pt, left
// column inset 32, art panel from x 451); the colours keep the roles of its asset
// catalogs (BoostBrowser_UnboxingUI / BoostBrowser_Onboarding) and take their values
// from Design's inks and plates. See docs/arc-reverse-engineering.md, "Dia import onboarding".
enum ImportMetrics {
    static let inset: CGFloat = 32
    static let columnWidth: CGFloat = 440
    static let titleTop: CGFloat = 56
    static let subtitleTop: CGFloat = 104
    static let listTop: CGFloat = 174
    static let listHeight: CGFloat = 280
    static let buttonTop: CGFloat = 470
    static let buttonHeight: CGFloat = 42
    static let artX: CGFloat = 451
    static let card = CGSize(width: 215, height: 80)
    static let gap: CGFloat = 10
    /// A selectable row (a space, an extension, a system option).
    static let rowHeight: CGFloat = 52
    /// A progress tile, and the shorter one when a fourth row of them has to fit.
    static let tileHeight: CGFloat = 64
    static let tileHeightCompact: CGFloat = 52
    /// Skip beside the primary button, and the primary button beside it.
    static let skipWidth: CGFloat = 146
    static let pairedPrimaryWidth: CGFloat = 290
    /// The column a row's glyph, emoji or icon sits in.
    static let rowGlyph: CGFloat = 24
    /// A browser's logo on its card.
    static let browserLogo: CGFloat = 52
    /// The primary button's glow: how far it spreads and how far it drops.
    static let glowRadius: CGFloat = 14
    static let glowDrop: CGFloat = 6
    /// The close button's place and hit area.
    static let closeOrigin = CGPoint(x: 887, y: 16)
    static let closeSize = CGSize(width: 26, height: 22)
}

struct ImportColors {
    let dark: Bool
    /// The primary button under the pointer, and the glow under it.
    static let primaryHover = Design.accent.opacity(0.88)
    static let primaryGlow = Design.accent.opacity(0.35)
    /// A window's traffic lights, for the scenes that draw a window.
    static let trafficLights = ["#FF5F57", "#FEBC2E", "#28C840"]

    var background: Color { dark ? .black : .white }
    var ink: Color { dark ? .white : .black }
    /// Ink at an emphasis: white on the dark window, black on the light one.
    func text(_ emphasis: Design.Emphasis) -> Color { dark ? Design.onDarkColor(emphasis) : Design.onLightColor(emphasis) }
    /// A neutral plate in the window's ink.
    func plate(_ fill: Design.Fill) -> Color { ink.opacity(fill.rawValue) }
    /// Hairlines between and around things.
    var hairline: Color { dark ? Color(nsColor: Design.hairlineOnDark) : Design.hairline }
    /// RebrandAppTitleText
    var title: Color { text(.primary) }
    /// RebrandBodyText
    var body: Color { text(.secondary) }
    /// Browser card hairline: drawn half a point wide, so it takes ink rather than the hairline.
    var cardBorder: Color { dark ? Design.onDarkColor(.tertiary) : Design.onLightColor(.quaternary) }
    var cardBorderSelected: Color { dark ? Design.onDarkColor(.secondary) : Design.onLightColor(.tertiary) }
    /// BrowserItemBackground (hover)
    var cardHover: Color { plate(.subtle) }
    /// Radio ring
    var radioRing: Color { cardBorder }
    /// RebrandRowBackground / RebrandRowBorder
    var rowFill: Color { plate(dark ? .selected : .subtle) }
    var rowFillHover: Color { plate(dark ? .pressed : .hover) }
    var rowBorder: Color { hairline }
    /// ImportSelectionCaption
    var caption: Color { text(.tertiary) }
    /// The primary button carries the signal orange, the brand's one colour.
    var primaryFill: Color { Design.accent }
    var primaryFillHover: Color { Self.primaryHover }
    var primaryText: Color { Design.onDarkColor(.primary) }
    var primaryTextDisabled: Color { Design.onDarkColor(.secondary) }
    /// ButtonDefaultBackground
    var secondaryFill: Color { plate(.selected) }
    var secondaryFillHover: Color { plate(.pressed) }
    /// ImportProgressItemBorder
    var tileBorder: Color { hairline }
    /// LoadingSubtitle
    var loading: Color { text(.tertiary) }
}

struct ImportFlowView: View {
    @Bindable var model: ImportFlowModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = ImportColors(dark: scheme == .dark)
        ZStack(alignment: .topLeading) {
            c.background
            if model.step == .outro {
                // Dia's RebrandOutroView fills the window: logo, then the welcome line.
                OutroStep(model: model, c: c)
                    .transition(.opacity)
            } else {
                ImportArtPanel(model: model, colors: c)
                    .frame(width: ImportWindowController.size.width - ImportMetrics.artX, height: ImportWindowController.size.height)
                    .offset(x: ImportMetrics.artX)
                    .transition(.opacity)
                Group {
                    switch model.step {
                    case .cover: CoverStep(model: model, c: c)
                    case .defaultBrowser: DefaultBrowserStep(model: model, c: c)
                    case .privacy: PrivacyStep(model: model, c: c)
                    case .source: SourceStep(model: model, c: c)
                    case .safariExport, .passwordsFile: ExportedFileStep(model: model, c: c)
                    case .unlock: UnlockStep(model: model, c: c)
                    case .spaces: SpacesStep(model: model, c: c)
                    case .extensions: ExtensionsStep(model: model, c: c)
                    case .progress: ProgressStep(model: model, c: c)
                    case .credentialsResult: CredentialsResultStep(model: model, c: c)
                    case .pinnedTabs: PinnedTabsStep(model: model, c: c)
                    case .personalization: PersonalizationStep(model: model, c: c)
                    case .outro: EmptyView()
                    }
                }
                .frame(width: ImportMetrics.columnWidth + 2, height: ImportWindowController.size.height, alignment: .topLeading)
                .offset(x: ImportMetrics.inset)
                .id(model.step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: model.forward ? Design.Space.xl : -Design.Space.xl)),
                                        removal: .opacity.combined(with: .offset(x: model.forward ? -Design.Space.xl : Design.Space.xl))))
            }
            if !model.firstRun && (model.step != .progress || model.finished) {
                CloseButton(c: c) { model.onClose() }
                    .offset(x: ImportMetrics.closeOrigin.x, y: ImportMetrics.closeOrigin.y)
            }
        }
        .frame(width: ImportWindowController.size.width, height: ImportWindowController.size.height)
        .ignoresSafeArea()
    }
}

// MARK: - Steps

struct StepHeader: View {
    let title: String
    let subtitle: String
    let c: ImportColors
    var body: some View {
        // Dia sets these in Exposure; New York is the closest face macOS ships.
        Text(title)
            .font(Design.Font.ui(.large, .semibold))
            .tracking(-0.6)
            .foregroundStyle(c.title)
            .lineLimit(1)
            .frame(width: ImportMetrics.columnWidth, height: 36, alignment: .leading)
            .offset(y: ImportMetrics.titleTop)
        Text(subtitle)
            .font(Design.Font.ui(.title))
            .lineSpacing(2.5)
            .foregroundStyle(c.body)
            .frame(width: 431, height: 46, alignment: .topLeading)
            .offset(y: ImportMetrics.subtitleTop)
    }
}

/// Dia's NewDefaultBrowserView: three DefaultBrowserCheckboxRows (title and
/// subtitle over the rebrand row background) under a two-line title.
private struct DefaultBrowserStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let system = model.system
        ZStack(alignment: .topLeading) {
            Text("Fast, secure, and packed with all your browser essentials")
                .font(Design.Font.ui(.large, .semibold))
                .tracking(-0.6)
                .foregroundStyle(c.title)
                .lineLimit(2)
                .lineSpacing(1)
                .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
                .offset(y: ImportMetrics.titleTop)
            VStack(alignment: .leading, spacing: Design.Space.m) {
                SelectableRow(c: c, checked: system.isDefaultBrowser || model.setAsDefault, disabled: system.isDefaultBrowser,
                              toggle: { model.setAsDefault.toggle() }) {
                    RowTitle(title: "Set Niche as default browser",
                             caption: system.isDefaultBrowser ? "Niche already opens your links" : "Open links and web pages in Niche by default", c: c)
                }
                SelectableRow(c: c, checked: system.isInDock || model.addToDock, disabled: system.isInDock,
                              toggle: { model.addToDock.toggle() }) {
                    RowTitle(title: "Add Niche to Dock",
                             caption: system.isInDock ? "Niche is already in your Dock" : "Quick access to Niche whenever you need it", c: c)
                }
                SelectableRow(c: c, checked: model.launchAtLogin, toggle: { model.launchAtLogin.toggle() }) {
                    RowTitle(title: "Open Niche at login", caption: "Automatically open Niche when you sign in", c: c)
                }
            }
            .frame(width: ImportMetrics.columnWidth)
            .offset(y: ImportMetrics.listTop)
            if let err = model.systemError {
                Text(err).font(Design.Font.ui(.detail)).foregroundStyle(Design.danger)
                    .frame(width: ImportMetrics.columnWidth, alignment: .leading)
                    .offset(y: ImportMetrics.buttonTop - 28)
            }
            HStack(spacing: Design.Space.s) {
                SecondaryButton(title: "Skip", c: c) { model.continueFromDefaultBrowser(applying: false) }
                    .frame(width: ImportMetrics.skipWidth)
                PrimaryButton(title: system.isPromptingDefault ? "Confirm in the macOS dialog" : "Continue",
                              c: c, enabled: !model.applyingSystemOptions, width: ImportMetrics.pairedPrimaryWidth) { model.continueFromDefaultBrowser() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct SourceStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Import now to get connected",
                       subtitle: "Import once and stay in your flow. Your spaces, tabs, folders and extensions come with you.", c: c)
            let cols = [GridItem(.fixed(ImportMetrics.card.width), spacing: ImportMetrics.gap),
                        GridItem(.fixed(ImportMetrics.card.width))]
            // Three rows of cards fit; more browsers scroll under a soft edge.
            ScrollView {
                LazyVGrid(columns: cols, alignment: .leading, spacing: ImportMetrics.gap) {
                    ForEach(model.sources) { s in
                        BrowserCard(source: s, model: model, c: c)
                    }
                }
                .padding(.vertical, Design.Space.m)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 8, alignment: .topLeading)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            if let err = model.loadError {
                Text(err).font(Design.Font.ui(.detail)).foregroundStyle(Design.danger)
                    .offset(y: ImportMetrics.buttonTop - 28)
            }
            if model.firstRun {
                // Dia's onboarding offers "skip the importing process" beside Continue.
                HStack(spacing: Design.Space.s) {
                    SecondaryButton(title: "Skip", c: c) { model.skipImport() }.frame(width: ImportMetrics.skipWidth)
                    PrimaryButton(title: "Continue", c: c, enabled: model.canContinueFromSource, width: ImportMetrics.pairedPrimaryWidth) { model.continueFromSource() }
                }
                .frame(width: ImportMetrics.columnWidth + 2)
                .offset(x: -1, y: ImportMetrics.buttonTop)
            } else {
                PrimaryButton(title: "Continue", c: c, enabled: model.canContinueFromSource) { model.continueFromSource() }
                    .offset(x: -1, y: ImportMetrics.buttonTop)
            }
        }
    }
}

private struct SpacesStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let plan = model.plan
        let name = model.source?.rawValue ?? "Arc"
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: "Select spaces to import",
                       subtitle: "We'll import your \(name) spaces, tabs, and folders to Niche.", c: c)
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    ForEach(Array((plan?.spaces ?? []).enumerated()), id: \.offset) { i, sp in
                        SelectableRow(c: c, checked: model.selectedSpaces.contains(i),
                                      onHover: { if $0 { model.previewSpace = i } },
                                      toggle: { model.toggleSpace(i) }) {
                            Text(sp.emoji).font(.system(size: Design.Icon.large)).frame(width: ImportMetrics.rowGlyph)
                            RowTitle(title: sp.title, caption: "\(sp.itemCount) tab\(sp.itemCount == 1 ? "" : "s")", c: c)
                        }
                    }
                    if let plan, !plan.favorites.isEmpty || !plan.archive.isEmpty || model.includeSettings {
                        Text("Also bring over")
                            .font(Design.Font.ui(.detail, .medium)).foregroundStyle(c.caption)
                            .padding(.top, Design.Space.m).padding(.leading, Design.Space.xxs)
                        if !plan.favorites.isEmpty {
                            SelectableRow(c: c, checked: model.includeFavorites, toggle: { model.includeFavorites.toggle() }) {
                                RowSymbol(name: "star.fill", c: c)
                                RowTitle(title: "Favorites", caption: "\(plan.favorites.count) in your current space", c: c)
                            }
                        }
                        if !plan.archive.isEmpty {
                            SelectableRow(c: c, checked: model.includeArchive, toggle: { model.includeArchive.toggle() }) {
                                RowSymbol(name: "archivebox.fill", c: c)
                                RowTitle(title: "Archived Tabs", caption: "\(plan.archive.count) tabs", c: c)
                            }
                        }
                        if !plan.settings.isEmpty {
                            SelectableRow(c: c, checked: model.includeSettings, toggle: { model.includeSettings.toggle() }) {
                                RowSymbol(name: "gearshape.fill", c: c)
                                RowTitle(title: "Settings", caption: plan.settings.linkRoutes.isEmpty ? "Auto-archive, sidebar width and toolbar" : "Auto-archive, toolbar and Air Traffic Control", c: c)
                            }
                        }
                    }
                }
                .padding(.bottom, Design.Space.l)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: "Continue", c: c, enabled: model.hasAnythingSelected) { model.continueFromSpaces() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct ExtensionsStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.spaces) }
            StepHeader(title: "Import your extensions",
                       subtitle: "Pick your essentials. You can always add more extensions later as you settle in with Niche.", c: c)
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    ForEach(model.extensions) { e in
                        let installed = ExtensionStore.isInstalled(id: e.id)
                        // Arc keeps extensions per profile: say which profiles it goes to (#131).
                        let profiles = model.profileNames(of: e).map { " · " + $0.joined(separator: ", ") } ?? ""
                        SelectableRow(c: c, checked: model.selectedExtensions.contains(e.id), toggle: { model.toggleExtension(e.id) }) {
                            ExtensionIcon(image: e.icon, size: ImportMetrics.rowGlyph, c: c)
                            RowTitle(title: e.name,
                                     caption: installed ? "Already in Niche · \(e.version)"
                                        : (e.isEnabled ? e.version + profiles : "Turned off in \(model.source?.rawValue ?? "Arc")"),
                                     c: c)
                        }
                    }
                }
                .padding(.bottom, Design.Space.l)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            HStack(spacing: Design.Space.s) {
                SecondaryButton(title: "Skip", c: c) { model.startImport(withExtensions: false) }
                    .frame(width: ImportMetrics.skipWidth)
                PrimaryButton(title: model.selectedExtensions.isEmpty ? "Continue" : "Import \(model.selectedExtensions.count) Extension\(model.selectedExtensions.count == 1 ? "" : "s")",
                              c: c, enabled: true, width: ImportMetrics.pairedPrimaryWidth) { model.startImport(withExtensions: true) }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

private struct ProgressStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\(model.finished ? "Imported" : "Importing") from \(model.source?.rawValue ?? "Arc")")
                .font(Design.Font.ui(.large, .semibold))
                .tracking(-0.6)
                .foregroundStyle(c.title)
                .frame(width: ImportMetrics.columnWidth, height: 36, alignment: .leading)
                .offset(y: ImportMetrics.titleTop)
            HStack(spacing: Design.Space.m) {
                if !model.finished { ProgressView().controlSize(.small) }
                Text(model.finished ? (model.failures.isEmpty ? "Everything is in place." : "Some import steps failed:") : "Hold on while we fetch your data")
                    .font(Design.Font.ui(.title)).foregroundStyle(model.finished ? c.body : c.loading)
            }
            .frame(height: 22)
            .offset(y: ImportMetrics.subtitleTop)
            // Up to eight tiles: a fourth row only fits above the notes and the button when the
            // tiles are shorter.
            let compact = model.categories.count > 6
            let gap: CGFloat = compact ? Design.Space.m : ImportMetrics.gap
            let cols = [GridItem(.fixed(ImportMetrics.card.width), spacing: ImportMetrics.gap),
                        GridItem(.fixed(ImportMetrics.card.width))]
            VStack(alignment: .leading, spacing: Design.Space.l) {
                LazyVGrid(columns: cols, alignment: .leading, spacing: gap) {
                    ForEach(model.categories) { CategoryTile(category: $0, c: c, height: compact ? ImportMetrics.tileHeightCompact : ImportMetrics.tileHeight) }
                }
                // The notes follow the grid, so they never run into the tiles.
                if model.finished {
                    VStack(alignment: .leading, spacing: Design.Space.xs) {
                        ForEach(model.failures, id: \.self) { Text($0).lineLimit(2) }
                        if model.importedExtensionCount > 0 {
                            Text("Niche restarts once to load your extensions. Their settings and sign-ins stay in \(model.source?.rawValue ?? "Arc").")
                        } else if model.credentialsStaged {
                            Text("Niche restarts once to bring in your passwords and sign-ins.")
                        }
                    }
                    .font(Design.Font.ui(.detail)).foregroundStyle(c.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: model.needsRelaunch && !model.firstRun && !model.credentialsAttempted ? "Restart Niche" : "Continue",
                          c: c, enabled: model.finished) { model.continueFromProgress() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Controls

/// Soft top and bottom edges on the scrolling lists.
struct ScrollFade: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Design.Space.m)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Design.Space.xl)
        }
    }
}

/// Dia's ImportBrowserItemView: logo, name, radio; the selected card shows how
/// many spaces will come over, which opens the space picker.
private struct BrowserCard: View {
    let source: ImportSource
    let model: ImportFlowModel
    let c: ImportColors
    @State private var hover = false

    var body: some View {
        let selected = model.source == source
        let shape = RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(hover ? c.cardHover : .clear)
            shape.strokeBorder(selected ? c.cardBorderSelected : c.cardBorder, lineWidth: 0.5)
            Image(nsImage: source.icon)
                .resizable().interpolation(.high)
                .frame(width: ImportMetrics.browserLogo, height: ImportMetrics.browserLogo)
                .offset(x: 19, y: 14)
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(source.rawValue).font(Design.Font.ui(.title, .medium)).foregroundStyle(c.title)
                if selected, let plan = model.plan, !plan.spaces.isEmpty {
                    Button { model.continueFromSource() } label: {
                        Text("\(model.selectedSpaces.count) of \(plan.spaces.count) spaces")
                            .font(Design.Font.ui(.caption)).foregroundStyle(c.body).underline(hover)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(width: 80, height: ImportMetrics.card.height, alignment: .leading)
            .offset(x: 82)
            RadioDot(on: selected, c: c)
                .offset(x: 161.5, y: 28)
        }
        .frame(width: ImportMetrics.card.width, height: ImportMetrics.card.height)
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: Design.Motion.duration(Design.Motion.standard))) { model.select(source) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { withAnimation(.easeOut(duration: Design.Motion.duration(Design.Motion.standard))) { model.select(source) } }
    }
}

/// 24 pt ring (1.5 pt); selected adds a 17.5 pt disc.
struct RadioDot: View {
    let on: Bool
    let c: ImportColors
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? c.title : c.radioRing, lineWidth: 1.5)
            if on { Circle().fill(c.title).frame(width: 17.5, height: 17.5).transition(.scale.combined(with: .opacity)) }
        }
        .frame(width: 24, height: 24)
    }
}

/// Dia's rebrand_checkbox: 18 pt rounded square, filled with a tick when on.
struct CheckBox: View {
    let on: Bool
    let c: ImportColors
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
        ZStack {
            if on {
                shape.fill(c.title)
                Image(systemName: "checkmark").font(Design.Font.ui(.micro, .bold)).foregroundStyle(c.background)
            } else {
                shape.strokeBorder(c.radioRing, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// Dia's ImportSelectableCheckBox / SpaceCheckboxView row.
struct SelectableRow<Content: View>: View {
    let c: ImportColors
    let checked: Bool
    /// Already true on this Mac: shown ticked, not changeable.
    var disabled = false
    var onHover: (Bool) -> Void = { _ in }
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
        HStack(spacing: Design.Space.l) {
            content()
            Spacer(minLength: Design.Space.m)
            CheckBox(on: checked, c: c).opacity(disabled ? Design.Opacity.disabled : 1)
        }
        .padding(.horizontal, Design.Space.rowInset)
        .frame(height: ImportMetrics.rowHeight)
        .background(shape.fill(hover && !disabled ? c.rowFillHover : c.rowFill))
        .overlay(shape.strokeBorder(c.rowBorder, lineWidth: 0.5))
        .contentShape(shape)
        .onHover { hover = $0; onHover($0) }
        .onTapGesture { if !disabled { withAnimation(.easeOut(duration: Design.Motion.fast)) { toggle() } } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if !disabled { withAnimation(.easeOut(duration: Design.Motion.fast)) { toggle() } } }
    }
}

struct RowTitle: View {
    let title: String
    let caption: String
    let c: ImportColors
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.hair) {
            Text(title).font(Design.Font.control).foregroundStyle(c.title).lineLimit(1)
            Text(caption).font(Design.Font.detail).foregroundStyle(c.caption).lineLimit(1)
        }
    }
}

struct RowSymbol: View {
    let name: String
    let c: ImportColors
    var body: some View {
        Image(systemName: name).font(.system(size: Design.Icon.bar)).foregroundStyle(c.body).frame(width: ImportMetrics.rowGlyph)
    }
}

struct ExtensionIcon: View {
    let image: NSImage?
    let size: CGFloat
    let c: ImportColors
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Image(systemName: "puzzlepiece.extension.fill").font(.system(size: size * 0.6)).foregroundStyle(c.body).frame(width: size, height: size)
        }
    }
}

struct CategoryTile: View {
    let category: ImportCategory
    let c: ImportColors
    var height: CGFloat = ImportMetrics.tileHeight
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
        HStack(spacing: Design.Space.l) {
            Image(systemName: category.symbol).font(.system(size: Design.Icon.bar)).foregroundStyle(c.body).frame(width: 22)
            VStack(alignment: .leading, spacing: Design.Space.hair) {
                Text(category.title).font(Design.Font.control).foregroundStyle(c.title)
                Text(category.detail).font(Design.Font.detail).foregroundStyle(c.caption).lineLimit(1)
            }
            Spacer(minLength: Design.Space.xs)
            Group {
                switch category.state {
                case .waiting: Circle().strokeBorder(c.radioRing, lineWidth: 1.5).frame(width: 18, height: 18)
                case .working: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: Design.Icon.image)).foregroundStyle(c.title)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: Design.Icon.bar)).foregroundStyle(Design.warning)
                }
            }
            .frame(width: 22, height: 22)
            .transition(.scale.combined(with: .opacity))
        }
        .padding(.horizontal, Design.Space.l)
        .frame(width: ImportMetrics.card.width, height: height)
        .overlay(shape.strokeBorder(c.tileBorder, lineWidth: 1))
        .animation(.easeOut(duration: Design.Motion.duration(Design.Motion.standard)), value: category.state)
    }
}

/// Full-width primary button with Dia's return-key glyph.
struct PrimaryButton: View {
    let title: String
    let c: ImportColors
    let enabled: Bool
    var width: CGFloat = ImportMetrics.columnWidth + 2
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button { if enabled { action() } } label: {
            HStack(spacing: Design.Space.m) {
                Text(title).font(Design.Font.section)
                Image(systemName: "return").font(.system(size: Design.Icon.small, weight: .medium)).opacity(Design.Opacity.dimmed)
            }
            .foregroundStyle(enabled ? c.primaryText : c.primaryTextDisabled)
            .frame(maxWidth: .infinity)
            .frame(height: ImportMetrics.buttonHeight)
            .background(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
                .fill(hover && enabled ? c.primaryFillHover : c.primaryFill)
                .opacity(enabled ? 1 : Design.Opacity.disabled)
                .shadow(color: enabled ? ImportColors.primaryGlow : .clear, radius: ImportMetrics.glowRadius, y: ImportMetrics.glowDrop))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
        .frame(width: width)
    }
}

struct SecondaryButton: View {
    let title: String
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(Design.Font.section).foregroundStyle(c.body)
                .frame(maxWidth: .infinity)
                .frame(height: ImportMetrics.buttonHeight)
                .background(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous).fill(hover ? c.secondaryFillHover : c.secondaryFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }
}

struct BackLink: View {
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: "chevron.left").font(.system(size: Design.Icon.small, weight: .semibold))
                Text("Back").font(Design.Font.control)
            }
            .foregroundStyle(hover ? c.title : c.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .offset(y: 22)
    }
}

private struct CloseButton: View {
    let c: ImportColors
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: Design.Icon.bar, weight: .light))
                .foregroundStyle(c.text(hover ? .primary : .secondary))
                .shadow(color: c.dark ? Color(nsColor: Design.Shadow.cardColor) : .clear, radius: Design.Space.xxs)
                .frame(width: ImportMetrics.closeSize.width, height: ImportMetrics.closeSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hover = $0 }
        .accessibilityLabel("Close")
    }
}
