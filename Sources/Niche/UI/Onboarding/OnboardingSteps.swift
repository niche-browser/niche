import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The onboarding steps Dia 1.54 shows around the import: a cover page, the
// privacy (ad blocker) screen, the "Unlock your data" password step and its
// result, Safari's exported-file drop, pinned tabs, personalization and the
// outro. See docs/arc-reverse-engineering.md, "Dia onboarding steps".

private enum Metrics {
    /// The cover's glyph, the passwords result's glyph, the outro's mark and its button.
    static let coverGlyph: CGFloat = 44
    static let resultGlyph: CGFloat = 44
    static let outroMark: CGFloat = 76
    static let outroButton: CGFloat = 260
    /// A site's card on the pinned tabs step, the icon on it and the room the icon gets.
    static let pinCard: CGFloat = 76
    static let pinIcon: CGFloat = 26
    static let pinIconRow: CGFloat = 28
    /// A theme swatch on the personalization step.
    static let swatch: CGFloat = 34
    /// Dia's layout illustration at its artwork size, and the ring around the picked one: the
    /// window's corners plus its 5 pt inset.
    static let layoutArt = CGSize(width: 230, height: 180)
    static let layoutRing: CGFloat = 15
    /// The privacy step: a level's card and its shield, how far the three sit under the
    /// subtitle's second line, and the spring a choice moves with.
    static let levelCard: CGFloat = 78
    static let levelGlyph: CGFloat = 30
    static let levelListDrop: CGFloat = 26
    static let levelSpring: Double = 0.4
    static let levelDamping: Double = 0.8
}

/// A two-line step title; the import steps use StepHeader (one line).
struct TwoLineHeader: View {
    let title: String
    let subtitle: String
    let c: ImportColors
    var body: some View {
        Text(title)
            .font(Design.Font.ui(.large, .semibold))
            .tracking(-0.6)
            .foregroundStyle(c.title)
            .lineLimit(2)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.titleTop - 14)
        Text(subtitle)
            .font(Design.Font.ui(.title))
            .lineSpacing(2.5)
            .foregroundStyle(c.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 431, alignment: .topLeading)
            .offset(y: ImportMetrics.subtitleTop + 10)
    }
}

// MARK: - Cover

/// The first page: the mark, a short promise, and Get Started.
struct CoverStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                BrandGlyph(size: Metrics.coverGlyph, ink: c.title)
                Text("Welcome to Niche")
                    .font(Design.Font.section)
                    .foregroundStyle(Design.accent)
                    .padding(.top, Design.Space.pane)
                Text("Your corner\nof the web.")
                    .font(Design.Font.ui(.display, .semibold))
                    .tracking(-1.4)
                    .lineSpacing(-2)
                    .foregroundStyle(c.title)
                    .padding(.top, Design.Space.m)
                Text("A native Mac browser built around a sidebar. Spaces for every part of your life, and a command bar that finds anything in a keystroke.")
                    .font(Design.Font.ui(.title))
                    .lineSpacing(3)
                    .foregroundStyle(c.body)
                    .frame(width: 380, alignment: .leading)
                    .padding(.top, Design.Space.xl)
            }
            .offset(y: 128)
            PrimaryButton(title: "Get Started", c: c, enabled: true) { model.continueFromCover() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Privacy

/// The privacy step: one choice, how much Niche does for you, as three cards. The scene beside
/// it (PrivacyArt) shows what the picked level keeps out.
struct PrivacyStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            TwoLineHeader(title: "Private from\nthe first page",
                          subtitle: "Niche stops ads and trackers before they load. Pick how far it goes; you can change it any time in Settings.", c: c)
            VStack(spacing: ImportMetrics.gap) {
                ForEach(PrivacyLevel.allCases, id: \.self) { level in
                    PrivacyLevelCard(level: level, selected: model.privacyLevel == level, c: c) {
                        withAnimation(.spring(response: Metrics.levelSpring, dampingFraction: Metrics.levelDamping)) { model.privacyLevel = level }
                    }
                }
            }
            .frame(width: ImportMetrics.columnWidth)
            .offset(y: ImportMetrics.listTop + Metrics.levelListDrop)
            PrimaryButton(title: "Continue", c: c, enabled: true) { model.continueFromPrivacy() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

/// One privacy level: a shield that fills with the level, its name and what it is for.
private struct PrivacyLevelCard: View {
    let level: PrivacyLevel
    let selected: Bool
    let c: ImportColors
    let pick: () -> Void
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
        HStack(spacing: Design.Space.l) {
            Image(systemName: level.symbol)
                .font(.system(size: Design.Icon.large, weight: .medium))
                .foregroundStyle(selected ? Design.accent : c.body)
                .frame(width: Metrics.levelGlyph)
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                HStack(spacing: Design.Space.m) {
                    Text(level.title).font(Design.Font.ui(.title, .semibold)).foregroundStyle(c.title)
                    if level == PrivacyLevel.recommended {
                        Text("Recommended").font(Design.Font.ui(.micro, .semibold))
                            .foregroundStyle(Design.accent)
                            .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xxs)
                            .background(Capsule().fill(Design.accentWash))
                    }
                }
                Text(level.tagline).font(Design.Font.detail).foregroundStyle(c.caption)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Design.Space.m)
            RadioDot(on: selected, c: c)
        }
        .padding(.horizontal, Design.Space.rowInset)
        .frame(height: Metrics.levelCard)
        .background(shape.fill(selected ? Design.accentWash : hover ? c.rowFillHover : c.rowFill))
        .overlay(shape.strokeBorder(selected ? Design.accentRing : c.rowBorder, lineWidth: selected ? Design.Space.hair + Design.Space.hair / 2 : Design.Space.hair / 2))
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.title): \(level.tagline)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, pick)
    }
}

// MARK: - Unlock passwords and cookies (Dia's ImportProfilePickerView)

struct UnlockStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let many = model.credentialProfiles.count > 1
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: "Unlock your data for import",
                       subtitle: model.unlockReadsSidebar
                           ? "Dia encrypts your spaces, tabs and passwords, so macOS will ask for your computer password."
                           : many ? "Some data is encrypted, so macOS will ask for your computer password once for each selected profile."
                                  : "Some data is encrypted, so macOS will ask for your computer password to bring it securely into Niche.", c: c)
            if many {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Space.m) {
                        ForEach(model.credentialProfiles) { p in
                            SelectableRow(c: c, checked: model.selectedProfiles.contains(p.id), toggle: { model.toggleProfile(p.id) }) {
                                RowSymbol(name: "person.crop.circle", c: c)
                                RowTitle(title: p.name, caption: "Passwords and sign-ins", c: c)
                            }
                        }
                    }
                    .padding(.bottom, Design.Space.l)
                }
                .scrollIndicators(.never)
                .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 12)
                .mask(ScrollFade())
                .offset(y: ImportMetrics.listTop - 8)
            } else {
                HStack(spacing: Design.Space.l) {
                    RowSymbol(name: "key.fill", c: c)
                    RowTitle(title: "Passwords and sign-ins",
                             caption: "So you don't have to enter all your passwords again", c: c)
                    Spacer()
                }
                .padding(.horizontal, Design.Space.rowInset).frame(width: ImportMetrics.columnWidth, height: ImportMetrics.rowHeight)
                .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(c.rowFill))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(c.rowBorder, lineWidth: 0.5))
                .offset(y: ImportMetrics.listTop)
            }
            if let err = model.unlockError {
                Text(err).font(Design.Font.detail).foregroundStyle(Design.danger)
                    .frame(width: ImportMetrics.columnWidth, alignment: .leading)
                    .offset(y: ImportMetrics.buttonTop - 44)
            }
            HStack(spacing: Design.Space.s) {
                SecondaryButton(title: "Skip", c: c) { model.skipCredentials() }.frame(width: ImportMetrics.skipWidth)
                PrimaryButton(title: model.unlocking ? "Waiting for password" : model.unlockError == nil ? "Continue" : "Try Again",
                              c: c, enabled: !model.unlocking, width: ImportMetrics.pairedPrimaryWidth) { model.unlock() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

// MARK: - Exported file (Dia's SafariExportedDataView; also Firefox and Zen passwords)

struct ExportedFileStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    @State private var dropTargeted = false

    private var isSafari: Bool { model.source?.kind == .safari }
    private var browser: String { model.source?.name ?? "Firefox" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackLink(c: c) { model.go(.source) }
            StepHeader(title: isSafari ? "Import from Safari" : "Import \(browser) passwords",
                       subtitle: isSafari ? "Open Safari and follow these steps to import your passwords, history, and bookmarks."
                                          : "In \(browser), open Settings ▸ Passwords ▸ ⋯ ▸ Export Passwords, then drop the file here.", c: c)
            VStack(alignment: .leading, spacing: Design.Space.m) {
                if isSafari {
                    InstructionRow(n: 1, text: "Open the Safari app.", c: c)
                    InstructionRow(n: 2, text: "Open File ▸ Export Browsing Data to File.", c: c)
                    InstructionRow(n: 3, text: "Save the file, then drop it below.", c: c)
                }
                DropWell(fileName: model.exportFileName, targeted: dropTargeted, reading: model.readingExport, isSafari: isSafari, c: c) {
                    chooseFile()
                } clear: {
                    model.clearExport()
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.readExport(url) } }
                    }
                    return true
                }
                if let err = model.exportError {
                    Text(err).font(Design.Font.detail).foregroundStyle(Design.danger)
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .topLeading)
            .offset(y: ImportMetrics.listTop - (isSafari ? 24 : 0))
            HStack(spacing: Design.Space.s) {
                SecondaryButton(title: "Skip", c: c) { model.skipExport() }.frame(width: ImportMetrics.skipWidth)
                PrimaryButton(title: "Continue", c: c, enabled: model.exportFileName != nil, width: ImportMetrics.pairedPrimaryWidth) { model.continueFromExport() }
            }
            .frame(width: ImportMetrics.columnWidth + 2)
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = isSafari
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = isSafari ? [.zip, .folder] : [.commaSeparatedText]
        panel.prompt = isSafari ? "Choose .zip file" : "Choose .csv file"
        if panel.runModal() == .OK, let url = panel.url { model.readExport(url) }
    }
}

private struct InstructionRow: View {
    let n: Int
    let text: String
    let c: ImportColors
    var body: some View {
        HStack(spacing: Design.Space.l) {
            Text("\(n)").font(Design.Font.ui(.detail, .semibold)).foregroundStyle(c.title)
                .frame(width: ImportMetrics.rowGlyph, height: ImportMetrics.rowGlyph)
                .background(Circle().fill(c.secondaryFill))
            Text(text).font(Design.Font.body).foregroundStyle(c.body)
            Spacer()
        }
    }
}

private struct DropWell: View {
    let fileName: String?
    let targeted: Bool
    let reading: Bool
    let isSafari: Bool
    let c: ImportColors
    let choose: () -> Void
    let clear: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
        Button(action: { if fileName == nil { choose() } }) {
            HStack(spacing: Design.Space.l) {
                if reading {
                    ProgressView().controlSize(.small)
                    Text("Reading…").font(Design.Font.body).foregroundStyle(c.body)
                } else if let fileName {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: Design.Icon.large)).foregroundStyle(c.title)
                    Text(fileName).font(Design.Font.control).foregroundStyle(c.title).lineLimit(1)
                    Spacer()
                    Button(action: clear) { Image(systemName: "xmark.circle.fill").font(.system(size: Design.Icon.image)).foregroundStyle(c.caption) }
                        .buttonStyle(.plain)
                } else {
                    Image(systemName: "arrow.down.doc").font(.system(size: Design.Icon.image)).foregroundStyle(c.body)
                    Text(isSafari ? "Choose .zip file or drag it here" : "Choose .csv file or drag it here")
                        .font(Design.Font.body).foregroundStyle(c.body)
                    Spacer()
                }
            }
            .padding(.horizontal, Design.Space.rowInset)
            .frame(height: ImportMetrics.tileHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(targeted ? c.rowFillHover : c.rowFill))
            .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: fileName == nil ? [5, 4] : []))
                .foregroundStyle(targeted ? c.body : c.rowBorder))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Passwords result (Dia's ImportPasswordsAndCookiesResultView)

struct CredentialsResultStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        let ok = model.credentialsSucceeded
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Design.Space.xl) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: Metrics.resultGlyph)).foregroundStyle(ok ? c.title : Design.warning)
                Text(ok ? "You're all set" : "Something went wrong")
                    .font(Design.Font.ui(.large, .semibold)).tracking(-0.6).foregroundStyle(c.title)
                Text(ok ? "Your passwords and cookies are now available in Niche. Start browsing and you'll be signed in to your sites."
                        : "Niche was unable to import your passwords and cookies. You can try again now or skip this step.")
                    .font(Design.Font.ui(.title)).lineSpacing(2.5).foregroundStyle(c.body)
                    .frame(width: 420, alignment: .leading)
            }
            .offset(y: 150)
            if ok {
                PrimaryButton(title: "Continue", c: c, enabled: true) { model.afterImport() }
                    .offset(x: -1, y: ImportMetrics.buttonTop)
            } else {
                HStack(spacing: Design.Space.s) {
                    SecondaryButton(title: "Skip", c: c) { model.afterImport() }.frame(width: ImportMetrics.skipWidth)
                    PrimaryButton(title: "Try Again", c: c, enabled: true, width: ImportMetrics.pairedPrimaryWidth) { model.retryCredentials() }
                }
                .frame(width: ImportMetrics.columnWidth + 2)
                .offset(x: -1, y: ImportMetrics.buttonTop)
            }
        }
    }
}

// MARK: - Pinned tabs (Dia's PinnedTabsView)

struct PinnedTabsStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    private let cols = Array(repeating: GridItem(.flexible(), spacing: ImportMetrics.gap), count: 4)
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Keep your favorites handy",
                       subtitle: "Pin the apps you use most so they're always a click away in Niche.", c: c)
            ScrollView {
                LazyVGrid(columns: cols, spacing: ImportMetrics.gap) {
                    ForEach(model.pinCandidates) { p in
                        PinCard(candidate: p, icon: model.pinIcons[p.host], on: model.selectedPins.contains(p.host), c: c) {
                            model.togglePin(p.host)
                        }
                    }
                }
                .padding(.vertical, Design.Space.m)
            }
            .scrollIndicators(.never)
            .frame(width: ImportMetrics.columnWidth, height: ImportMetrics.listHeight + 8)
            .mask(ScrollFade())
            .offset(y: ImportMetrics.listTop - 8)
            PrimaryButton(title: model.selectedPins.isEmpty ? "Skip" : "Pin \(model.selectedPins.count)", c: c, enabled: true) {
                model.continueFromPinnedTabs()
            }
            .offset(x: -1, y: ImportMetrics.buttonTop)
        }
        .onAppear { model.loadPinCandidates() }
    }
}

private struct PinCard: View {
    let candidate: PinCandidate
    let icon: NSImage?
    let on: Bool
    let c: ImportColors
    let toggle: () -> Void
    @State private var hover = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
        VStack(spacing: Design.Space.s) {
            ZStack {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: Metrics.pinIcon, height: Metrics.pinIcon)
                } else {
                    Image(systemName: "globe").font(.system(size: Design.Icon.large)).foregroundStyle(c.body)
                }
            }
            .frame(height: Metrics.pinIconRow)
            Text(candidate.name).font(Design.Font.ui(.caption, .medium)).foregroundStyle(c.title).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: Metrics.pinCard)
        .background(shape.fill(on ? c.rowFillHover : (hover ? c.rowFillHover.opacity(Design.Opacity.dimmed) : c.rowFill)))
        .overlay(shape.strokeBorder(on ? c.cardBorderSelected : c.rowBorder, lineWidth: on ? 1.5 : 0.5))
        .overlay(alignment: .topTrailing) {
            if on { Image(systemName: "checkmark.circle.fill").font(.system(size: Design.Icon.bar)).foregroundStyle(c.title).padding(Design.Space.xs) }
        }
        .contentShape(shape)
        .onHover { hover = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: Design.Motion.fast)) { toggle() } }
    }
}

// MARK: - Personalization (Dia's PersonalizationView)

/// Dia 1.54's PersonalizationView: the colour swatches in one row, then "Choose how you would like
/// to view your tabs:" over two PersonalizationTabLayoutButtons (window illustrations, Dia's
/// TabLayout/* artwork, with a ring around the picked one and its name underneath). The two
/// layouts are Niche's `WindowLayout`: the tabs down the sidebar, or across the top of the window.
struct PersonalizationStep: View {
    @Bindable var model: ImportFlowModel
    let c: ImportColors
    var body: some View {
        ZStack(alignment: .topLeading) {
            StepHeader(title: "Make it yours",
                       subtitle: "Pick the theme color and layout that feel right for you.", c: c)
            HStack(spacing: (ImportMetrics.columnWidth - Metrics.swatch * CGFloat(SpaceTheme.presets.count)) / CGFloat(SpaceTheme.presets.count - 1)) {
                ForEach(SpaceTheme.presets.indices, id: \.self) { i in
                    ThemeSwatch(theme: SpaceTheme.presets[i], on: model.chosenTheme == i, c: c) { model.chooseTheme(i) }
                }
            }
            .frame(width: ImportMetrics.columnWidth, alignment: .leading)
            .offset(y: ImportMetrics.listTop)
            Text("Choose where your tabs go:")
                .font(Design.Font.body)
                .foregroundStyle(c.body)
                .offset(y: 228)
            HStack(spacing: Design.Space.l) {
                LayoutTile(top: false, title: WindowLayout.sidebar.title, model: model, c: c)
                LayoutTile(top: true, title: WindowLayout.top.title, model: model, c: c)
            }
            .offset(y: 252)
            PrimaryButton(title: "Continue", c: c, enabled: true) { model.continueFromPersonalization() }
                .offset(x: -1, y: ImportMetrics.buttonTop)
        }
    }
}

/// Dia's PersonalizationTabLayoutButton: the illustration at its 230×180 artwork size scaled to
/// the column, a 3 pt ring when picked, the name in TabLayoutLabelText underneath.
private struct LayoutTile: View {
    let top: Bool
    let title: String
    @Bindable var model: ImportFlowModel
    let c: ImportColors

    private static let width: CGFloat = (ImportMetrics.columnWidth - Design.Space.l) / 2

    var body: some View {
        let selected = model.tabsOnTop == top
        let k = Self.width / Metrics.layoutArt.width
        VStack(spacing: Design.Space.s) {
            LayoutArt(top: top, selected: selected, dark: c.dark)
                .frame(width: Metrics.layoutArt.width, height: Metrics.layoutArt.height)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: Metrics.layoutArt.width * k, height: Metrics.layoutArt.height * k, alignment: .topLeading)
            // TabLayoutLabelText
            Text(title)
                .font(Design.Font.body)
                .foregroundStyle(c.body)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: Design.Motion.duration(Design.Motion.fast))) { model.tabsOnTop = top } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(top ? "Tabs on top: a tab strip, the address and your bookmarks across the top of the window"
                                : "Sidebar: tabs, favorites and spaces down the side of the window")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.tabsOnTop = top }
    }
}

/// Drawn after Dia's TabLayout/SidebarSelected and friends (230×180 pt): a 3 pt ring, a 2 pt gap,
/// the window inset 5 pt (radius 10) and 5 pt traffic lights. The sidebar layout has 54×14 pt
/// rows on a 19 pt pitch beside the page; tabs on top has three tabs after the traffic lights,
/// the address under them and the page across the whole window.
private struct LayoutArt: View {
    let top: Bool
    let selected: Bool
    let dark: Bool

    /// The drawing's own measures, at the artwork's 230×180 pt.
    private enum Art {
        static let window = CGSize(width: 220, height: 170)
        static let inset: CGFloat = 5
        static let ring: CGFloat = 3
        static let light: CGFloat = 5
        static let lightPitch: CGFloat = 8.5
        static let lightOrigin = CGPoint(x: 13, y: 14)
        static let row = CGSize(width: 54, height: 14)
        static let rowPitch: CGFloat = 19
        static let rowOrigin = CGPoint(x: 10, y: 27)
        static let sidePane = CGRect(x: 70, y: 10, width: 150, height: 160)
        static let tab = CGSize(width: 42, height: 13)
        static let tabPitch: CGFloat = 45
        static let tabOrigin = CGPoint(x: 44, y: 10)
        static let address = CGRect(x: 12, y: 29, width: 206, height: 11)
        static let topPane = CGRect(x: 10, y: 46, width: 210, height: 124)
    }

    var body: some View {
        let c = ImportColors(dark: dark)
        let window = c.plate(dark ? .strong : .hover)
        let row: Color = dark ? Design.onDarkColor(.tertiary) : Design.onLightColor(.quaternary)
        let pane: Color = dark ? Design.panelDarkColor : .white
        let accent: Color = dark ? Design.onDarkColor(.secondary) : Design.onLightColor(.tertiary)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Metrics.layoutRing, style: .continuous)
                .strokeBorder(c.title, lineWidth: Art.ring)
                .opacity(selected ? 1 : 0)
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(window)
                .frame(width: Art.window.width, height: Art.window.height)
                .offset(x: Art.inset, y: Art.inset)
            ForEach(Array(ImportColors.trafficLights.enumerated()), id: \.offset) { i, hex in
                Circle().fill(Color(hex: hex)).frame(width: Art.light, height: Art.light)
                    .offset(x: Art.lightOrigin.x + CGFloat(i) * Art.lightPitch, y: Art.lightOrigin.y)
            }
            if top {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
                        .fill(i == 0 ? accent : row)
                        .frame(width: Art.tab.width, height: Art.tab.height)
                        .offset(x: Art.tabOrigin.x + CGFloat(i) * Art.tabPitch, y: Art.tabOrigin.y)
                }
                Capsule().fill(row)
                    .frame(width: Art.address.width, height: Art.address.height)
                    .offset(x: Art.address.minX, y: Art.address.minY)
                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(pane)
                    .frame(width: Art.topPane.width, height: Art.topPane.height)
                    .offset(x: Art.topPane.minX, y: Art.topPane.minY)
            } else {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
                        .fill(i == 0 ? accent : row)
                        .frame(width: Art.row.width, height: Art.row.height)
                        .offset(x: Art.rowOrigin.x, y: Art.rowOrigin.y + CGFloat(i) * Art.rowPitch)
                }
                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(pane)
                    .frame(width: Art.sidePane.width, height: Art.sidePane.height)
                    .offset(x: Art.sidePane.minX, y: Art.sidePane.minY)
            }
        }
        .frame(width: Metrics.layoutArt.width, height: Metrics.layoutArt.height, alignment: .topLeading)
    }
}

private struct ThemeSwatch: View {
    let theme: SpaceTheme
    let on: Bool
    let c: ImportColors
    let tap: () -> Void
    var body: some View {
        let colors = theme.colors.map { Color(hex: $0) }
        Circle()
            .fill(LinearGradient(colors: colors.count > 1 ? colors : [colors.first ?? .gray, colors.first ?? .gray],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: Metrics.swatch, height: Metrics.swatch)
            .overlay(Circle().strokeBorder(on ? c.title : .clear, lineWidth: 2).padding(-3))
            .overlay(on ? Image(systemName: "checkmark").font(.system(size: Design.Icon.small, weight: .bold)).foregroundStyle(.white).shadow(radius: 1) : nil)
            .contentShape(Circle())
            .onTapGesture { withAnimation(.easeOut(duration: Design.Motion.fast)) { tap() } }
    }
}


// MARK: - Outro (Dia's RebrandOutroView)

struct OutroStep: View {
    let model: ImportFlowModel
    let c: ImportColors
    @State private var shown = false
    var body: some View {
        VStack(spacing: Design.Space.xxl) {
            BrandMark(size: Metrics.outroMark)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            Text("Welcome to your new\nhome on the internet")
                .font(Design.Font.ui(.large, .semibold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(c.title)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : Design.Space.l)
            PrimaryButton(title: "Start browsing", c: c, enabled: true, width: Metrics.outroButton) { model.finish() }
                .opacity(shown ? 1 : 0)
                .padding(.top, Design.Space.m)
        }
        .frame(width: ImportWindowController.size.width, height: ImportWindowController.size.height)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) { shown = true } }
    }
}
