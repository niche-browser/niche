import AppKit
import NicheCore
import SwiftUI

/// The command bar: a glass panel with a large search field, quiet single-line rows, the
/// selected row tinted with the space colour, and a footer of keyboard hints. AppKit: the rows
/// are reused views that change only what changed, so a keystroke costs the search and a few
/// labels, not a SwiftUI pass over the bar.
@MainActor
final class CommandBarView: NSView {
    static let rowHeight: CGFloat = 40
    static let fieldHeight: CGFloat = 52
    static let footerHeight: CGFloat = 34
    static let corner: CGFloat = Design.Radius.panel
    /// The top corners while the bar hangs from the toolbar.
    private static let attachedCorner: CGFloat = Design.Radius.card
    /// Between one row and the next.
    private static let rowGap: CGFloat = Design.Space.xxs
    /// Around the list: from the panel's sides, the field's hairline and the footer's.
    private static let listInset: CGFloat = Design.Space.m
    /// The scope's pill and the Tab keycap.
    private static let capHeight: CGFloat = 23
    /// The field's text box: a 17 pt line with room for descenders.
    private static let textHeight: CGFloat = 26
    /// The ground under the HUD material: graphite in dark, white in light.
    private static let tintDark = NSColor(Design.graphite).withAlphaComponent(0.78)
    private static let tintLight = NSColor.white.withAlphaComponent(0.76)
    /// The panel's edge on a dark page, where a hairline disappears.
    private static let outlineDark = NSColor.labelColor.withAlphaComponent(0.14)
    /// A scope's pill is solid, whatever alpha its colour came with.
    private static let pillAlpha: CGFloat = 1
    static func height(forRows n: Int) -> CGFloat {
        fieldHeight + (n == 0 ? 0 : CGFloat(n) * rowHeight + CGFloat(n - 1) * rowGap + 2 * listInset + footerHeight)
    }

    private let controller: CommandBarController
    private let favicons: FaviconCache
    private let material = NSVisualEffectView()
    private let tint = NSView()
    private let border = CAShapeLayer()
    private let shape = CAShapeLayer()
    private let leadingIcon = NSImageView()
    private let text: CommandTextField
    private let info = NSImageView()
    /// Scoped search: the scope's pill before the field, and "Search YouTube  Tab" at the end of
    /// the row while the typed text would enter it (Arc 1.170, measured at 2x).
    private let pill = NSView()
    private let pillLabel = NSTextField.sidebarLabel(size: Design.TextSize.body.rawValue, weight: .semibold)
    private let hint = NSTextField.sidebarLabel(size: Design.TextSize.body.rawValue, weight: .semibold)
    private let keycap = NSView()
    private let keycapLabel = NSTextField.sidebarLabel(size: Design.TextSize.body.rawValue, weight: .semibold)
    private let divider = NSView()
    private let footerDivider = NSView()
    private let footer = NSTextField.sidebarLabel(size: Design.TextSize.caption.rawValue, weight: .medium)
    private var rows: [CommandBarRowView] = []
    private var syncQueued = false
    private var attached = false
    /// The scope shown last, to bounce when Tab enters one or Backspace leaves it.
    private var shownScope: CommandBarScope?
    private var splash: NSPanel?
    private var innerSplash: NSView?

    init(controller: CommandBarController, favicons: FaviconCache) {
        self.controller = controller
        self.favicons = favicons
        text = CommandTextField(controller: controller)
        super.init(frame: .zero)
        wantsLayer = true
        material.blendingMode = .behindWindow
        material.state = .active
        tint.wantsLayer = true
        layer?.mask = shape
        border.fillColor = nil
        border.lineWidth = 1.5
        leadingIcon.imageScaling = .scaleProportionallyUpOrDown
        leadingIcon.wantsLayer = true
        leadingIcon.layer?.cornerCurve = .continuous
        info.image = Design.Icon.symbol("info.circle", size: Design.Icon.image)
        info.imageScaling = .scaleNone
        info.contentTintColor = .secondaryLabelColor
        divider.wantsLayer = true
        footerDivider.wantsLayer = true
        footer.attributedStringValue = Self.footerHints
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.shadowOpacity = 0.3
        pill.layer?.shadowRadius = 8
        pill.layer?.shadowOffset = .zero
        pillLabel.textColor = .white
        pill.addSubview(pillLabel)
        keycap.wantsLayer = true
        keycap.layer?.cornerRadius = Design.Radius.inset
        keycap.layer?.cornerCurve = .continuous
        keycapLabel.stringValue = "Tab"
        keycap.addSubview(keycapLabel)
        for v in [material, tint, leadingIcon, text.field, info, pill, hint, keycap, divider, footerDivider, footer] as [NSView] { addSubview(v) }
        layer?.addSublayer(border)
        border.zPosition = 10
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        sync()
    }

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        syncQueued = false
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
    }

    /// Colours turned into CGColors resolve against the current drawing appearance, which is the
    /// app's (macOS') unless set: a light bar on a dark Mac got white fills and hints.
    private func apply() {
        effectiveAppearance.performAsCurrentDrawingAppearance { applyResolved() }
    }

    private func applyResolved() {
        let c = controller
        let items = c.result.items
        let dark = self.dark
        text.update()
        attached = c.attached
        // Closest AppKit materials to SwiftUI's .ultraThinMaterial under the bar's tint (dark: compared
        // pixel for pixel over the same page).
        material.material = dark ? .hudWindow : .popover
        tint.layer?.backgroundColor = (dark ? Self.tintDark : Self.tintLight).cgColor
        border.strokeColor = (dark ? Self.outlineDark : Design.hairlineNS).cgColor
        divider.layer?.backgroundColor = Design.hairlineNS.cgColor
        footerDivider.layer?.backgroundColor = Design.hairlineNS.cgColor
        footer.attributedStringValue = Self.footerHints
        let scope = c.scope
        if c.isOpen, (scope == nil) != (shownScope == nil) {
            let site: SiteSearch? = if case .site(let site) = scope { site } else { nil }
            scopeChanged(color: site?.color.map { NSColor(hex: $0) })
        }
        shownScope = c.isOpen ? scope : nil
        // A site's brand colour; the tabs scope and Chromium's other keywords take the space's, the
        // colour of its rows.
        let highlight: NSColor
        if case .site(let site) = scope, let hex = site.color { highlight = NSColor(hex: hex) } else { highlight = NSColor(c.highlight) }
        // The hints live in the footer; an unexplained ⓘ in the field only added noise.
        info.isHidden = true
        divider.isHidden = items.isEmpty
        footer.isHidden = items.isEmpty
        footerDivider.isHidden = items.isEmpty
        pill.isHidden = scope == nil
        if let scope {
            let color = highlight.withAlphaComponent(Self.pillAlpha)
            pill.layer?.backgroundColor = color.cgColor
            pill.layer?.shadowColor = color.cgColor
            pillLabel.stringValue = scope.name
        }
        // Arc shows no hint for the actions Tab offers on the empty field.
        let offered = scope == nil && c.previewText == nil && c.result.scope != .actions ? c.result.scope : nil
        hint.isHidden = offered == nil
        keycap.isHidden = offered == nil
        if let offered {
            hint.stringValue = "Search \(offered.name)"
            hint.textColor = Design.ink(.tertiary)
            keycapLabel.textColor = Design.ink(.secondary)
            keycap.layer?.backgroundColor = Design.fillNS(.subtle).cgColor
        }

        // Follows the row the arrows moved to; otherwise the top one.
        let previewing = c.previewText != nil && items.indices.contains(c.selectedIndex)
        let row = previewing ? items[c.selectedIndex] : items.first
        let typed = c.query.trimmingCharacters(in: .whitespaces)
        let glyph = CommandBarGlyph.resolve(
            editingURL: c.mode == .editURL && scope == nil, untouched: !previewing && (typed.isEmpty || typed == c.openedPrefill),
            // Actions run the row, not a search: Arc shows the row's glyph once something is typed.
            scoped: scope != nil && scope != .actions, pageFaviconKey: c.openedPrefill.flatMap(FaviconKey.key(for:)),
            row: row.map { ($0.faviconKey, $0.symbol) }, hasFavicon: { [favicons] in favicons.image(forKey: $0) != nil })
        if case .favicon(let key) = glyph, let img = favicons.image(forKey: key) {
            leadingIcon.imageScaling = .scaleProportionallyUpOrDown
            leadingIcon.image = img
            leadingIcon.contentTintColor = nil
            leadingIcon.layer?.cornerRadius = Design.Radius.inset
            leadingIcon.layer?.masksToBounds = true
            leadingIcon.frame.size = NSSize(width: 20, height: 20)
        } else {
            leadingIcon.imageScaling = .scaleNone
            if case .symbol(let name) = glyph { leadingIcon.image = Design.Icon.symbol(name, size: Design.Icon.image) }
            leadingIcon.contentTintColor = .secondaryLabelColor
            leadingIcon.layer?.masksToBounds = false
            leadingIcon.frame.size = NSSize(width: 22, height: 22)
        }

        while rows.count < items.count {
            let r = CommandBarRowView()
            r.onHover = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }) else { return }
                if self.controller.selectedIndex != i { self.controller.selectedIndex = i }
            }
            r.onClick = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }), self.controller.result.items.indices.contains(i) else { return }
                self.controller.commit(self.controller.result.items[i])
            }
            rows.append(r)
            addSubview(r)
        }
        for (i, r) in rows.enumerated() {
            guard i < items.count else { r.isHidden = true; continue }
            r.isHidden = false
            let s = items[i]
            r.show(s, icon: s.faviconKey.flatMap { favicons.image(forKey: $0) }, selected: i == c.selectedIndex, highlight: highlight,
                   otherSpace: s.spaceID.flatMap { $0 != c.focusedSpaceID && s.tabID != nil ? c.spaceName($0) : nil },
                   queryEmpty: c.query.isEmpty, tabHint: SplitPaneFill.rowHint(fillingPane: c.fillsSplitPane), dark: dark)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let b = bounds
        // Tab into a scope empties the list and the panel shrinks to the field after the glow
        // started: the glow follows, or it stays centred on the old list below the bar.
        if let splash, let window { splash.setFrame(window.frame.insetBy(dx: -Self.splashMargin, dy: -Self.splashMargin), display: false) }
        material.frame = b
        tint.frame = b
        let top: CGFloat = attached ? Self.attachedCorner : Self.corner
        let path = Self.path(b, top: top, bottom: Self.corner)
        shape.frame = b
        shape.path = path
        border.frame = b
        border.path = path
        // Input row: 20 pt in, icon 22, 12 apart, the field 26 tall, the info glyph at the end.
        let fh = Self.fieldHeight
        let icon = leadingIcon.frame.size
        leadingIcon.frame = NSRect(x: 20 + (22 - icon.width) / 2, y: (fh - icon.height) / 2, width: icon.width, height: icon.height)
        var right = b.width - 20
        if !info.isHidden {
            info.frame = NSRect(x: right - 18, y: (fh - 18) / 2, width: 18, height: 18)
            right -= 18 + 14
        }
        if !keycap.isHidden {
            // Key cap 23 tall, 4 pt around "Tab", 10 pt after the hint.
            let kw = ceil(keycapLabel.attributedStringValue.size().width), kh = keycapLabel.intrinsicContentSize.height
            let cap = Self.capHeight
            keycap.frame = NSRect(x: right - kw - 8, y: (fh - cap) / 2, width: kw + 8, height: cap)
            keycapLabel.frame = NSRect(x: 4 - SidebarText.inset, y: (cap - kh) / 2, width: kw + 2 * SidebarText.inset, height: kh)
            right = keycap.frame.minX - 10
            let hw = ceil(hint.attributedStringValue.size().width), hh = hint.intrinsicContentSize.height
            hint.frame = NSRect(x: right - hw - SidebarText.inset, y: (fh - hh) / 2, width: hw + 2 * SidebarText.inset, height: hh)
            right -= hw + 14
        }
        var x: CGFloat = 20 + 22 + 12
        if !pill.isHidden {
            // 23 tall, fully round, 10.5 pt around the name; the field starts 11 pt after it.
            let lw = ceil(pillLabel.attributedStringValue.size().width), lh = pillLabel.intrinsicContentSize.height
            let cap = Self.capHeight
            pill.frame = NSRect(x: x, y: (fh - cap) / 2, width: lw + 21, height: cap)
            pill.layer?.cornerRadius = Design.Radius.pill(cap)
            pillLabel.frame = NSRect(x: 10.5 - SidebarText.inset, y: (cap - lh) / 2, width: lw + 2 * SidebarText.inset, height: lh)
            x = pill.frame.maxX + 11
        }
        text.field.frame = NSRect(x: x - 1.5, y: (fh - Self.textHeight) / 2 + 2, width: max(0, right - x), height: Self.textHeight)
        divider.frame = NSRect(x: 0, y: fh, width: b.width, height: 1)
        var y: CGFloat = fh + Self.listInset
        for r in rows where !r.isHidden {
            r.frame = NSRect(x: Self.listInset, y: y, width: b.width - 2 * Self.listInset, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowGap
        }
        // Footer: hints pinned to the panel's bottom edge, under a full-width hairline.
        let fy = b.height - Self.footerHeight
        footerDivider.frame = NSRect(x: 0, y: fy, width: b.width, height: 1)
        let fs = footer.intrinsicContentSize
        footer.frame = NSRect(x: 20 - SidebarText.inset, y: fy + (Self.footerHeight - fs.height) / 2,
                              width: b.width - 40 + 2 * SidebarText.inset, height: fs.height)
    }

    /// "↑↓ Select   ↩ Open   ⇥ Search a site   esc Close": keys in the label colour, words quieter.
    private static var footerHints: NSAttributedString {
        let out = NSMutableAttributedString()
        let key: [NSAttributedString.Key: Any] = [.font: Design.Font.ns(.caption, .semibold),
                                                  .foregroundColor: Design.ink(.secondary)]
        let word: [NSAttributedString.Key: Any] = [.font: Design.Font.ns(.caption),
                                                   .foregroundColor: Design.ink(.tertiary)]
        for (i, (k, w)) in [("↑↓", "Select"), ("↩", "Open"), ("⇥", "Search a site"), ("esc", "Close")].enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "     ", attributes: word)) }
            out.append(NSAttributedString(string: k + " ", attributes: key))
            out.append(NSAttributedString(string: w, attributes: word))
        }
        return out
    }

    // MARK: Entering a scope (Arc's CommandBarContainer, 1.171)

    /// Tab into a scope and Backspace out of it: the bar bounces, and a site's colour washes
    /// through it (Arc's arc_commandBarBounce and SplashView, read from its binary).
    private func scopeChanged(color: NSColor?) {
        bounce()
        splash?.parent?.removeChildWindow(splash!)
        splash?.orderOut(nil)
        splash = nil
        innerSplash?.removeFromSuperview()
        innerSplash = nil
        if let color { showSplash(color) }
    }

    /// A spring toward 0.95 (damping ratio 0.9, response 0.7) cut off after 0.1 s and played
    /// back: the bar dips about 1% and returns within 0.2 s.
    private static let bounceCutoff: TimeInterval = 0.1

    private func bounce() {
        guard let layer, !Design.Motion.reduced else { return }
        let w = layer.bounds.width, h = layer.bounds.height
        // About the bar's centre, whatever anchor AppKit gave the layer.
        let dx = (0.5 - layer.anchorPoint.x) * w, dy = (0.5 - layer.anchorPoint.y) * h
        let scaled = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), 0.95, 0.95, 1), -dx, -dy, 0)
        let a = CASpringAnimation(keyPath: "transform")
        a.mass = 1
        a.stiffness = pow(2 * .pi / 0.7, 2)
        a.damping = 4 * .pi * 0.9 / 0.7
        a.fromValue = layer.presentation()?.transform ?? CATransform3DIdentity
        a.toValue = scaled
        a.autoreverses = true
        a.repeatCount = 1
        a.fillMode = .forwards
        a.duration = Self.bounceCutoff
        layer.add(a, forKey: "arc_commandBarBounce")
    }

    /// The site's colour as a 12 pt rounded rectangle under the bar, blurring to 150 and fading
    /// out over 1.2 s (ease-out). It spreads past the bar, so it gets a panel of its own below the
    /// bar's. Arc's sits under the bar's background in the same window and shows through it: the
    /// inside turns dark red at once ((47, 20, 19) over (26, 26, 26) for YouTube), holds for 0.17 s
    /// and is gone after a second (measured at 100 fps, 3 Nov). The bar's material can't see the
    /// panel below, so the inside is the colour under the bar's tint, following that curve.
    private func showSplash(_ color: NSColor) {
        guard let window else { return }
        let inner = NSView(frame: bounds)
        inner.autoresizingMask = [.width, .height]
        inner.wantsLayer = true
        inner.layer?.backgroundColor = color.cgColor
        inner.layer?.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.keyTimes = Self.innerSplashCurve.map { NSNumber(value: $0.time) }
        fade.values = Self.innerSplashCurve.map { 0.42 * $0.level }
        fade.duration = Self.innerSplashDuration
        inner.layer?.add(fade, forKey: "splash")
        addSubview(inner, positioned: .above, relativeTo: material)
        innerSplash = inner
        let margin = Self.splashMargin
        let panel = SplashPanel(contentRect: window.frame.insetBy(dx: -margin, dy: -margin), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = window.collectionBehavior
        panel.contentView = NSHostingView(rootView: CommandBarSplash(color: Color(nsColor: color), margin: margin))
        window.addChildWindow(panel, ordered: .below)
        splash = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self, weak panel] in
            guard let self, let panel, self.splash === panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.splash = nil
            self.innerSplash?.removeFromSuperview()
            self.innerSplash = nil
        }
    }

    /// Room around the bar for the glow's blur.
    private static let splashMargin: CGFloat = 420

    /// The inside is clear again a second after Tab (the same recording as the curve below).
    private static let innerSplashDuration: TimeInterval = 1

    /// How much of the site's colour shows inside Arc's bar after Tab, relative to the start (red
    /// over green, sampled off a 100 fps recording of Arc 1.171).
    private static let innerSplashCurve: [(time: Double, level: Double)] = [
        (0, 1), (0.17, 1), (0.21, 0.89), (0.27, 0.67), (0.33, 0.52), (0.39, 0.36), (0.45, 0.30), (0.51, 0.23),
        (0.57, 0.185), (0.69, 0.107), (0.75, 0.078), (0.87, 0.06), (0.93, 0.026), (1, 0),
    ]

    /// UnevenRoundedRectangle: smaller top corners while the bar hangs from the toolbar.
    private static func path(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        // Continuous corners, like every other surface (docs/design.md, Shape). The view is flipped
        // and so is SwiftUI's space: minY is the top edge in both.
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
                               style: .continuous).path(in: r).cgPath
    }
}

/// The glow's panel reaches 420 pt past the bar, so near the top of the screen it crosses the
/// menu bar, and AppKit moves a window that does down below it: the glow sat under the bar, not
/// around it (a Little Window's bar is a third of the way down a small window). Its frame is
/// left as asked.
private final class SplashPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Arc's SplashView: `Color(nsColor:)` clipped to a 12 pt continuous rounded rectangle, blurred and
/// faded by one ease-out animation of 1.2 s that starts as it appears.
private struct CommandBarSplash: View {
    let color: Color
    /// The bar is the panel less this on every side.
    let margin: CGFloat
    @State private var blurRadius: CGFloat = 0
    @State private var opacity: Double = 1
    /// Arc's SplashView fades over 1.2 s.
    private static let fade: TimeInterval = 1.2

    var body: some View {
        color
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .padding(margin)
            .blur(radius: blurRadius, opaque: false)
            .opacity(opacity)
            .animation(.easeOut(duration: Self.fade), value: blurRadius)
            .onAppear {
                blurRadius = 150
                opacity = 0
            }
    }
}

/// One suggestion: icon, "Title — detail", and "Switch to Tab" + arrow for open tabs.
final class CommandBarRowView: NSView {
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    private let iconBox = NSView()
    private let icon = NSImageView()
    private let emoji = NSTextField.sidebarLabel(size: Design.TextSize.title.rawValue)
    private let label = NSTextField.sidebarLabel(size: Design.TextSize.body.rawValue)
    private let trailing = NSTextField.sidebarLabel(size: Design.TextSize.detail.rawValue, weight: .medium)
    private let arrowBox = NSView()
    private let arrow = NSImageView()
    private var shown: (Suggestion, NSImage?, Bool, NSColor, String?, Bool, Bool, String)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.row
        layer?.cornerCurve = .continuous
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = Design.Radius.inset
        iconBox.layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        arrowBox.wantsLayer = true
        arrowBox.layer?.cornerRadius = Design.Radius.inset
        arrowBox.layer?.cornerCurve = .continuous
        arrow.image = Design.Icon.symbol("arrow.right", size: Design.Icon.small)
        arrow.imageScaling = .scaleNone
        label.lineBreakMode = .byTruncatingMiddle
        trailing.textColor = .secondaryLabelColor
        for v in [iconBox, icon, emoji, label, trailing, arrowBox, arrow] as [NSView] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ s: Suggestion, icon image: NSImage?, selected: Bool, highlight: NSColor, otherSpace: String?, queryEmpty: Bool,
              tabHint: String, dark: Bool) {
        if let o = shown, o.0 == s, o.1 === image, o.2 == selected, o.3 == highlight, o.4 == otherSpace, o.5 == queryEmpty, o.6 == dark,
           o.7 == tabHint { return }
        let sameContent = shown.map { $0.0 == s && $0.1 === image && $0.4 == otherSpace && $0.5 == queryEmpty && $0.6 == dark && $0.7 == tabHint } ?? false
        shown = (s, image, selected, highlight, otherSpace, queryEmpty, dark, tabHint)
        layer?.backgroundColor = (selected ? highlight : .clear).cgColor
        guard !sameContent else { return }
        if let image {
            icon.isHidden = false
            emoji.isHidden = true
            iconBox.isHidden = false
            icon.image = image
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = nil
            iconBox.layer?.backgroundColor = Design.fillNS(dark ? .pressed : .hover).cgColor
        } else if case .switchSpace = s.kind, let t = s.trailing {
            icon.isHidden = true
            iconBox.isHidden = true
            emoji.isHidden = false
            emoji.stringValue = t
        } else {
            iconBox.isHidden = true
            emoji.isHidden = true
            icon.isHidden = false
            icon.image = Design.Icon.symbol(s.symbol ?? "globe", size: Design.Icon.regular)
            icon.imageScaling = .scaleNone
            icon.contentTintColor = .secondaryLabelColor
        }
        let t = NSMutableAttributedString(string: s.title, attributes: [.font: Design.Font.ns(.body, .medium), .foregroundColor: NSColor.labelColor])
        t.append(NSAttributedString(string: Self.detail(s), attributes: [.font: Design.Font.ns(.detail), .foregroundColor: NSColor.tertiaryLabelColor]))
        label.attributedStringValue = t
        let isTab = s.tabID != nil
        if isTab {
            trailing.font = Design.Font.ns(.detail, .medium)
            trailing.stringValue = otherSpace ?? (queryEmpty ? "" : tabHint)
        } else {
            trailing.font = Design.Font.ns(.detail, .medium)
            trailing.stringValue = s.trailing ?? ""
        }
        arrowBox.isHidden = !isTab
        arrow.isHidden = !isTab
        arrow.contentTintColor = Design.ink(.primary)
        arrowBox.layer?.backgroundColor = Design.fillNS(.pressed).cgColor
        needsLayout = true
    }

    private static func detail(_ s: Suggestion) -> String {
        switch s.kind {
        case .switchToTab, .search, .command, .switchSpace, .moveToSpace, .moveToFolder: return ""
        case .archived: return s.subtitle.isEmpty ? "" : "  ·  \(s.subtitle)"
        default:
            guard let url = s.url else { return "" }
            let human = SuggestionEngine.humanURL(url)
            return human.lowercased() == s.title.lowercased() ? "" : "  ·  \(human)"
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        // padding 12, icon 26, 12 apart, the title, Spacer(min 8), trailing text, 12, arrow box 20.
        iconBox.frame = NSRect(x: 12, y: (h - 26) / 2, width: 26, height: 26)
        if iconBox.isHidden {
            icon.frame = iconBox.frame
        } else {
            icon.frame = iconBox.frame.insetBy(dx: 5, dy: 5)
        }
        let es = emoji.intrinsicContentSize
        emoji.frame = NSRect(x: 12 + (26 - es.width) / 2, y: (h - es.height) / 2, width: es.width, height: es.height)
        var right = bounds.width - 12
        if !arrowBox.isHidden {
            arrowBox.frame = NSRect(x: right - 20, y: (h - 20) / 2, width: 20, height: 20)
            arrow.frame = arrowBox.frame
            right -= 20 + 12
        }
        if !trailing.stringValue.isEmpty {
            let tw = ceil(trailing.attributedStringValue.size().width)
            let th = trailing.intrinsicContentSize.height
            trailing.frame = NSRect(x: right - tw - SidebarText.inset, y: (h - th) / 2, width: tw + 2 * SidebarText.inset, height: th)
            right -= tw + 14
        } else if !arrowBox.isHidden {
            // The empty label still takes its spacing in the HStack.
            right -= 14
        }
        let x: CGFloat = 12 + 26 + 12
        let ls = label.intrinsicContentSize
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - ls.height) / 2, width: max(0, right - 8 - x) + 2 * SidebarText.inset, height: ls.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}
