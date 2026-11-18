import AppKit

/// A label inside a tab or a bookmark. The tab strip stands in the window's title row, where
/// AppKit moves the window from any view that says a press there may: a plain label does, and a
/// tab pressed on its title took the window with it (17 Nov 2026). These are part of their tab.
final class StripLabel: NSTextField {
    override var mouseDownCanMoveWindow: Bool { false }

    static func make(_ size: Design.TextSize, _ weight: NSFont.Weight = .regular) -> StripLabel {
        let l = StripLabel(labelWithString: "")
        l.font = Design.Font.ns(size, weight)
        l.lineBreakMode = .byTruncatingTail
        l.usesSingleLineMode = true
        l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true
        return l
    }
}

/// A glyph inside a tab or a bookmark (StripLabel).
final class StripImage: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// One item of the tab strip: a tab, a favorite's icon, a split view or a tab group's name.
/// It draws what the strip's entry says; the strip decides where it is and what a press does.
@MainActor
final class StripItemView: NSView, NSTextFieldDelegate {
    private weak var strip: TabStripView?
    private(set) var entry: StripEntry?
    private var titled = true
    var colors = SidebarColors() { didSet { if colors != oldValue { refresh() } } }

    private var iconViews: [SidebarFaviconView] = []
    private let title = StripLabel.make(.body)
    private let ring = CAShapeLayer()
    private lazy var closeButton = SidebarGlyphButton(symbol: "xmark", size: TabStripMetrics.innerButton, iconSize: Design.Icon.tiny,
                                                      weight: .semibold, help: "Close Tab (⌘W)", colors: colors) { [weak self] in
        guard let self, let e = self.entry else { return }
        self.strip?.close(e)
    }
    private lazy var soundButton = SidebarGlyphButton(symbol: "speaker.wave.2.fill", size: TabStripMetrics.innerButton, iconSize: Design.Icon.small,
                                                      help: "Mute Tab", colors: colors) { [weak self] in
        guard let self, let e = self.entry else { return }
        self.strip?.toggleMute(e)
    }
    private var field: NSTextField?
    private var tip: ArcTooltipAnchorView?
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            refresh()
            needsLayout = true
            // The strip is in the window's title row, where a press moves the window: while the
            // pointer is on a tab the window stays put, so a press carries the tab
            // (SidebarUIState.hoverTitleRowItem).
            strip?.ui.hoverTitleRowItem(dragGuard, hovering)
        }
    }
    /// This view's name for `SidebarUIState.hoverTitleRowItem`.
    private let dragGuard = UUID()
    private var carried = false
    private var pressed = false

    init(strip: TabStripView) {
        self.strip = strip
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.row
        layer?.cornerCurve = .continuous
        addSubview(title)
        ring.fillColor = nil
        ring.lineWidth = TabStripMetrics.ringStroke
        ring.lineCap = .round
        ring.strokeEnd = TabStripMetrics.ringArc
        ring.isHidden = true
        ring.actions = ["hidden": NSNull(), "strokeColor": NSNull(), "position": NSNull(), "bounds": NSNull(), "path": NSNull()]
        layer?.addSublayer(ring)
        closeButton.isHidden = true
        soundButton.isHidden = true
        addSubview(soundButton)
        addSubview(closeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }

    /// The whole tab takes a press, not the label or icon under the pointer: AppKit asks the view
    /// it hits whether a drag there moves the window, and a label says yes, so a tab dragged by
    /// its title moved the window instead (17 Nov 2026). Its buttons and its rename field stay their own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit is SidebarGlyphButton { return hit }
        if let field, hit === field || hit.isDescendant(of: field) { return hit }
        return self
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { strip?.ui.hoverTitleRowItem(dragGuard, false) }
    }

    /// A group's name as wide as its text, with the pill's padding.
    static func groupWidth(_ title: String) -> CGFloat {
        let text = (title as NSString).size(withAttributes: [.font: Design.Font.ns(.detail, .medium)]).width
        return (min(text, groupMaxText) + 2 * TabStripMetrics.padLeading).rounded(.up)
    }
    /// The longest a group's name runs before it is cut.
    private static let groupMaxText: CGFloat = 140

    // MARK: Content

    func show(_ e: StripEntry, titled: Bool) {
        let old = entry
        guard old != e || self.titled != titled else { return }
        entry = e
        self.titled = titled
        if old?.icons.count != e.icons.count {
            for v in iconViews { v.removeFromSuperview() }
            iconViews = e.icons.map { _ in
                let v = SidebarFaviconView()
                addSubview(v, positioned: .below, relativeTo: title)
                return v
            }
        }
        for (v, icon) in zip(iconViews, e.icons) { v.show(icon.image, flip: icon.flip, colors: colors) }
        title.stringValue = e.title
        title.font = e.kind == .group ? Design.Font.ns(.detail, .medium) : Design.Font.ns(.body)
        setAccessibilityLabel(e.title)
        setAccessibilityValue(e.selected)
        // The whole title under the pointer when the tab has no room for it.
        if e.kind != .group {
            if let tip { tip.text = e.title } else { tip = ArcTooltipAnchorView.attach(to: self, help: e.title) }
        }
        soundButton.setSymbol(e.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", iconSize: Design.Icon.small,
                              help: e.muted ? "Unmute Tab" : "Mute Tab")
        if e.loading != (old?.loading ?? false) { spin(e.loading) }
        if e.editing != (old?.editing ?? false) { e.editing ? beginEditing() : endEditing() }
        refresh()
        needsLayout = true
    }

    private var showsClose: Bool {
        guard let e = entry, e.kind != .favorite, e.kind != .group, !carried else { return false }
        return hovering && (titled || e.selected)
    }

    private var showsSound: Bool {
        guard let e = entry, e.kind != .group, titled || e.kind == .favorite else { return false }
        return (e.audible || e.muted) && e.kind != .favorite
    }

    private func refresh() {
        guard let e = entry else { return }
        let ink: NSColor = e.kind == .group ? colors.textSecondary : e.selected || hovering ? colors.textPrimary : colors.textSecondary
        title.textColor = ink
        closeButton.colors = colors
        soundButton.colors = colors
        for (v, icon) in zip(iconViews, e.icons) { v.show(icon.image, flip: icon.flip, colors: colors) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeColor = colors.textSecondary.cgColor
        CATransaction.commit()
        // A tab's selection is the strip's travelling plate; a favorite carries its own. Carried,
        // it is a card of its own over its neighbours: solid, so what it passes doesn't show through.
        let fill: NSColor
        if carried { fill = colors.isDark ? Design.panelDarkRaised : .white }
        else if e.kind == .favorite, e.selected { fill = colors.plate(.selected) }
        // Under the pointer a tab lifts a little (the selection's plate is the stronger one); a
        // favorite's tile and a group's name, which rest on a plate already, a step more.
        else if hovering, !e.selected { fill = colors.plate(e.kind == .favorite || e.kind == .group ? .hover : .subtle) }
        // A favorite's tile and a group's name rest on a faint plate: a tile, and a label, not a tab.
        else if e.kind == .favorite || e.kind == .group { fill = colors.plate(.subtle) }
        else { fill = .clear }
        guard let layer else { return }
        let before = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = fill.cgColor
        CATransaction.commit()
        layer.fadeOutFill(from: before, to: fill)
    }

    override func layout() {
        super.layout()
        guard let e = entry else { return }
        let w = bounds.width, h = bounds.height
        let icon = NicheMetrics.favicon
        let iconY = ((h - icon) / 2).rounded()
        closeButton.isHidden = !showsClose
        soundButton.isHidden = !showsSound
        let button = TabStripMetrics.innerButton
        let buttonY = ((h - button) / 2).rounded()
        title.isHidden = false

        if e.kind == .group {
            title.frame = NSRect(x: TabStripMetrics.padLeading, y: ((h - title.intrinsicContentSize.height) / 2).rounded(),
                                 width: max(0, w - 2 * TabStripMetrics.padLeading), height: title.intrinsicContentSize.height)
            title.fadeTail()
            return
        }
        // Too narrow for a title (or a favorite): the icons alone, centred; the close button takes
        // their place on the open tab under the pointer.
        if !titled || e.kind == .favorite {
            title.isHidden = true
            let total = CGFloat(iconViews.count) * icon + CGFloat(max(0, iconViews.count - 1)) * Design.Space.xxs
            var x = ((w - total) / 2).rounded()
            let fits = total <= w
            for (i, v) in iconViews.enumerated() {
                v.isHidden = showsClose || (!fits && i > 0)
                v.frame = NSRect(x: fits ? x : ((w - icon) / 2).rounded(), y: iconY, width: icon, height: icon)
                x += icon + Design.Space.xxs
            }
            closeButton.frame = NSRect(x: ((w - button) / 2).rounded(), y: buttonY, width: button, height: button)
            placeRing(over: iconViews.first?.frame)
            return
        }
        var x = TabStripMetrics.padLeading
        for v in iconViews {
            v.isHidden = false
            v.frame = NSRect(x: x, y: iconY, width: icon, height: icon)
            x += icon + Design.Space.xxs
        }
        placeRing(over: iconViews.first?.frame)
        x += TabStripMetrics.iconGap - Design.Space.xxs
        var right = w - TabStripMetrics.padTrailing
        if showsClose {
            right -= button
            closeButton.frame = NSRect(x: right, y: buttonY, width: button, height: button)
        }
        if showsSound {
            right -= button
            soundButton.frame = NSRect(x: right, y: buttonY, width: button, height: button)
        }
        let th = title.intrinsicContentSize.height
        let frame = NSRect(x: x, y: ((h - th) / 2).rounded(), width: max(0, right - x - (showsClose || showsSound ? Design.Space.xxs : 0)), height: th)
        title.frame = frame
        title.fadeTail()
        // On the title's own line, a hair wider on each side for the caret.
        field?.frame = frame.insetBy(dx: -Design.Space.xxs, dy: 0)
    }

    // MARK: Loading

    private func placeRing(over frame: NSRect?) {
        guard let frame else { return }
        ring.frame = frame
        let inset = frame.insetBy(dx: Design.Space.xxs, dy: Design.Space.xxs)
        ring.path = CGPath(ellipseIn: NSRect(origin: NSPoint(x: Design.Space.xxs, y: Design.Space.xxs), size: inset.size), transform: nil)
        iconViews.first?.alphaValue = ring.isHidden ? 1 : 0
    }

    /// While its page loads a tab shows a turning ring where its icon is. Core Animation turns it,
    /// so a loading tab costs the app nothing; it stands still under Reduce motion.
    private func spin(_ on: Bool) {
        ring.isHidden = !on
        iconViews.first?.alphaValue = on ? 0 : 1
        ring.removeAnimation(forKey: "turn")
        guard on, !Design.Motion.reduced else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = TabStripMetrics.ringTurn
        turn.repeatCount = .infinity
        ring.add(turn, forKey: "turn")
    }

    // MARK: Motion

    /// A new tab grows into its place.
    func arrive(animated: Bool) {
        guard animated, let layer else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = TabStripMetrics.arrivalScale
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Design.Motion.standard
        group.timingFunction = Design.Motion.curve
        centreAnchor()
        layer.add(group, forKey: "arrive")
    }

    /// A closed tab shrinks away, then `done` removes it.
    func leave(_ done: @escaping () -> Void) {
        guard let layer else { done(); return }
        centreAnchor()
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = TabStripMetrics.arrivalScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = Design.Motion.fast
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "leave")
        CATransaction.commit()
    }

    /// AppKit anchors a view's layer at its corner; a scale is about the middle.
    private func centreAnchor() {
        guard let layer, layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let f = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = f
    }

    func setCarried(_ on: Bool) {
        guard carried != on, let layer else { return }
        carried = on
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.zPosition = on ? 1 : 0
        layer.shadowOpacity = on ? TabStripMetrics.carriedShadowOpacity : 0
        layer.shadowRadius = TabStripMetrics.carriedShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: Design.Space.xs)
        layer.masksToBounds = false
        CATransaction.commit()
        refresh()
        needsLayout = true
    }

    /// The item as it looks, on a card, for a drag that left the strip.
    func dragImage() -> NSImage {
        let size = bounds.size
        let rep = bitmapImageRepForCachingDisplay(in: bounds)
        if let rep { cacheDisplay(in: bounds, to: rep) }
        let fill = colors.plate(.strong)
        return NSImage(size: size, flipped: false) { r in
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: Design.Radius.row, yRadius: Design.Radius.row).fill()
            rep?.draw(in: r)
            return true
        }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        let inside = isUnderPointer
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if inside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
        if hovering != inside { hovering = inside }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// Looks where the pointer is. A tab that moved under a still pointer, or was carried and let
    /// go, gets no enter or exit: the strip asks after a release and when the pointer leaves it,
    /// so a hover (and the hold on the window that comes with it) never outlives the pointer.
    func syncHover() {
        let inside = isUnderPointer
        if hovering != inside { hovering = inside }
    }

    /// The part of it that shows: a tab cut by the run's edge isn't under a pointer past that edge.
    /// Within its own bounds: a view that doesn't clip (one that was carried) reports a visible
    /// rect as large as what holds it, and every such tab took the pointer for its own.
    var isUnderPointer: Bool {
        window.map { !isHiddenOrHasHiddenAncestor && visibleRect.intersection(bounds).contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }
    var showsHover: Bool { hovering }

    override func mouseDown(with event: NSEvent) {
        guard let e = entry, field == nil else { return }
        if event.clickCount == 2, e.kind != .favorite, let strip {
            strip.ui.renamingID = e.id
            return
        }
        pressed = true
        if e.kind == .favorite || e.kind == .group { setPressedLook(true) }
        strip?.itemPressed(self, e, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressed, let e = entry else { return }
        strip?.itemDragged(self, e, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed, let e = entry else { return }
        pressed = false
        setPressedLook(false)
        strip?.itemReleased(self, e, event: event)
        // A group's name folds nothing here: its tabs stay in the strip. A click does nothing more.
    }

    /// The middle button closes a tab, as in every browser.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let e = entry, e.kind != .favorite, e.kind != .group,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return super.otherMouseUp(with: event) }
        strip?.close(e)
    }

    override func menu(for event: NSEvent) -> NSMenu? { entry.flatMap { strip?.menu(for: $0) } }

    override func accessibilityPerformPress() -> Bool {
        guard let e = entry else { return false }
        strip?.select(e)
        return true
    }

    // MARK: Renaming

    private func beginEditing() {
        guard field == nil, let e = entry, titled else { return }
        let f = NSTextField(string: e.title)
        f.font = Design.Font.ns(.body)
        f.isBordered = false
        f.focusRingType = .none
        f.drawsBackground = true
        f.backgroundColor = colors.isDark ? Design.panelDarkRaised : .textBackgroundColor
        f.textColor = colors.isDark ? Design.onDark(.primary) : .textColor
        f.wantsLayer = true
        f.layer?.cornerRadius = Design.Radius.small
        f.delegate = self
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        addSubview(f)
        field = f
        title.alphaValue = 0
        needsLayout = true
        // On the next turn, as the sidebar's rows do: the field is in the window and laid out by
        // then. The window takes the keys first: a page's own window usually has them.
        DispatchQueue.main.async { [weak self, weak f] in
            guard let self, let f, self.field === f, let w = self.window else { return }
            self.layoutSubtreeIfNeeded()
            if !w.isKeyWindow { w.makeKey() }
            w.makeFirstResponder(f)
            f.currentEditor()?.selectAll(nil)
        }
    }

    private func endEditing() {
        guard let f = field else { return }
        field = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        title.alphaValue = 1
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = field, let e = entry else { return }
        let text = f.stringValue
        endEditing()
        strip?.rename(e, to: text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), let f = field, let e = entry {
            let text = f.stringValue
            endEditing()
            strip?.rename(e, to: text)
            return true
        }
        guard selector == #selector(NSResponder.cancelOperation(_:)), let e = entry else { return false }
        endEditing()
        strip?.rename(e, to: nil)
        return true
    }
}

/// The space's icon at the start of the tab strip: it names the space under the pointer and
/// opens the list of spaces.
@MainActor
final class StripSpaceChip: NSView {
    var onClick: () -> Void = {}
    /// The pointer came over the chip or left it (the strip keeps the window still meanwhile).
    var onHover: (Bool) -> Void = { _ in }
    private let emoji = StripLabel(labelWithString: "")
    private let symbol = StripImage()
    private var colors = SidebarColors()
    private var tip: ArcTooltipAnchorView?
    private var hovering = false { didSet { if hovering != oldValue { refreshFill(); onHover(hovering) } } }
    private var shown: (SpaceIcon, String)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.inset
        layer?.cornerCurve = .continuous
        emoji.alignment = .center
        emoji.font = .systemFont(ofSize: TabStripMetrics.chipEmoji)
        symbol.imageScaling = .scaleNone
        addSubview(emoji)
        addSubview(symbol)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    /// The chip takes the press, not its emoji's label (StripItemView.hitTest).
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    func show(icon: SpaceIcon, title: String, colors: SidebarColors, help: String) {
        self.colors = colors
        symbol.contentTintColor = colors.textPrimary
        if let s = shown, s.0 == icon, s.1 == help { refreshFill(); return }
        shown = (icon, help)
        switch icon {
        case .emoji(let e):
            emoji.stringValue = e
            symbol.image = nil
        case .symbol(let name):
            emoji.stringValue = ""
            symbol.image = SidebarSymbols.image(name, size: Design.Icon.bar)
        case .none:
            emoji.stringValue = ""
            symbol.image = SidebarSymbols.image("circle.fill", size: Design.Icon.tiny)
        }
        if let tip { tip.text = help } else { tip = ArcTooltipAnchorView.attach(to: self, help: help) }
        setAccessibilityLabel("Space: \(title)")
        refreshFill()
        needsLayout = true
    }

    private func refreshFill() {
        guard let layer else { return }
        let fill = hovering ? colors.plate(.hover) : NSColor.clear
        let before = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = fill.cgColor
        CATransaction.commit()
        layer.fadeOutFill(from: before, to: fill)
    }

    override func layout() {
        super.layout()
        symbol.frame = bounds
        let h = emoji.intrinsicContentSize.height
        emoji.frame = NSRect(x: 0, y: ((bounds.height - h) / 2).rounded(), width: bounds.width, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { setPressedLook(true) }
    override func mouseUp(with event: NSEvent) {
        setPressedLook(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
        hovering = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }

    override func accessibilityPerformPress() -> Bool { onClick(); return true }

    /// Looks where the pointer is (StripItemView.syncHover).
    func syncHover() {
        let inside = window.map { !isHiddenOrHasHiddenAncestor && bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if hovering != inside { hovering = inside }
    }
}
