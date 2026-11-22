import AppKit
import UniformTypeIdentifiers

/// Arc's downloads list: hovering the Library button lists the recent downloads over the
/// bottom of the sidebar, newest at the bottom, and the tab list behind them fades out.
/// Measured on Arc 1.170 (window captures at 60 fps, 27 Oct 2026): rows 56 pt apart, a
/// 40 pt thumbnail with 6 pt corners 8 pt in, the name at x 61 (body size, primary ink) and
/// "54 seconds ago" under it (detail size, secondary ink); the last row ends 2 pt below the list
/// area. The tab list is hidden from 3 pt above the first row and fades back in over the
/// 170 pt above that. It opens 0.2 s into the hover, rows rising 5 pt and fading in bottom
/// first 25 ms apart; it closes 0.07 s after the pointer leaves.
enum DownloadsTrayMetrics {
    static let rowPitch: CGFloat = 56
    static let thumbnail: CGFloat = 40
    static let fade: CGFloat = 170
    /// Arc's timings: how far into a hover it opens and how soon after it closes; the stagger
    /// between rows on the way in and out; a row's drop back (it rises in `Design.Motion.fast`).
    static let openDelay: TimeInterval = 0.2
    static let closeDelay: TimeInterval = 0.07
    static let riseStagger: TimeInterval = 0.025
    static let dropStagger: TimeInterval = 0.015
    static let drop: TimeInterval = 0.05
    /// How far a row rises as it comes in.
    static let rise: CGFloat = 5
    /// A file with no thumbnail yet: a white tile.
    static let placeholder = NSColor.white.withAlphaComponent(0.9)
    /// The line over the rows: "Downloads" and Clear.
    static let header: CGFloat = 28
    /// A row's plate reaches this far past its thumbnail, above and below; rows stay 56 pt apart.
    static let plateBleed: CGFloat = 4
    /// The plate's distance from the sidebar's edges, and the text's and buttons' from the plate's.
    static let plateInset: CGFloat = 4
    static let plateTextInset: CGFloat = 8
    /// The bar under a running download's two lines.
    static let progressHeight: CGFloat = 3
    /// What the bar shows of a download with no size: a third of the track, crossing it.
    static let sweepShare: CGFloat = 0.3
    static let sweep: TimeInterval = 1.2
    /// The track under the bar's fill, as a share of the ink.
    static let trackAlpha: CGFloat = 0.14
    /// How long a list opened for a held download stays up untouched (as long as the rename card).
    static let attentionTime: TimeInterval = 8
    static func listHeight(rows: Int) -> CGFloat { rows == 0 ? 0 : header + CGFloat(rows) * rowPitch - (rowPitch - thumbnail) }
    /// The view reaches this far past the list, under its last row (Arc: the last row ends 2 pt below the area).
    static let overhang: CGFloat = 4
    /// The tab list behind is hidden from this far under the view's top (as before the list moved
    /// over the player, 22 Nov 2026).
    static let maskLead: CGFloat = 3
}

extension SidebarUIState {
    /// A download Chromium held for a decision (DownloadDanger): the list opens on its own, as
    /// Chrome's bubble does, and closes like a hovered one once the pointer has been and gone, or
    /// after `attentionTime` untouched.
    func showDownloadsListForAttention() {
        downloadsListWork?.cancel()
        downloadsListOpen = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.libraryHovered, !self.downloadsListHovered else { return }
                self.downloadsListOpen = false
            }
        }
        downloadsListWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DownloadsTrayMetrics.attentionTime, execute: work)
    }

    func downloadsHoverChanged() {
        downloadsListWork?.cancel()
        let open = (libraryHovered || downloadsListHovered) && !DownloadHistory.shared.recent.isEmpty
        guard open != downloadsListOpen else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.downloadsListOpen = open } }
        downloadsListWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? DownloadsTrayMetrics.openDelay : DownloadsTrayMetrics.closeDelay), execute: work)
    }
}

/// The list itself, pinned to the bottom of the tab list's area.
@MainActor
final class DownloadsTrayView: NSView {
    private let ui: SidebarUIState
    var colors = SidebarColors() { didSet { if colors != oldValue { for r in rows { r.colors = colors }; header.colors = colors } } }
    private var rows: [DownloadsTrayRowView] = []
    private var shownOpen = false
    private var ticker: Timer?
    private let header: DownloadsTrayHeaderView

    /// `showAll` opens Library ▸ Downloads.
    init(ui: SidebarUIState, showAll: @escaping () -> Void = {}) {
        self.ui = ui
        header = DownloadsTrayHeaderView(showAll: showAll)
        super.init(frame: .zero)
        wantsLayer = true
        header.alphaValue = 0
        addSubview(header)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        let (entries, open, _) = withObservationTracking {
            (DownloadHistory.shared.recent, ui.downloadsListOpen, DownloadHistory.shared.thumbnails.count)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        while rows.count < entries.count {
            let r = DownloadsTrayRowView()
            r.colors = colors
            r.alphaValue = shownOpen ? 1 : 0
            rows.append(r)
            addSubview(r)
        }
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        // The last row went under the pointer (Clear, Remove): a hidden view gets no mouseExited.
        if entries.isEmpty { setHovered(false) }
        for (r, e) in zip(rows, entries) { r.show(e) }
        header.canClear = DownloadHistory.shared.canClear
        refreshAges()
        if open != shownOpen {
            animate(open: open)
            // The pointer may already rest where a row has just come up.
            let point = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            if open, let point, shownPartContains(point) { pointer(at: point) } else { for r in rows { r.hovering = false } }
        }
        // TimelineView(.periodic(by: 1)): the ages tick while the list is up.
        if open, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAges() }
            }
        } else if !open {
            ticker?.invalidate()
            ticker = nil
        }
        needsLayout = true
    }

    private func refreshAges() {
        let now = Date()
        for r in rows { r.now = now }
    }

    /// Rows rise 5 pt and fade in bottom first, 25 ms apart; they drop back faster.
    private func animate(open: Bool) {
        shownOpen = open
        let n = rows.count
        // The header is the top line: last in, first out.
        for (i, r) in ([header] + rows as [NSView]).enumerated() {
            guard let layer = r.layer else { continue }
            let fromBottom = Double(n - i)
            let m = DownloadsTrayMetrics.self
            let delay = fromBottom * (open ? m.riseStagger : m.dropStagger)
            let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
            let fromShift = (layer.presentation()?.value(forKeyPath: "sublayerTransform.translation.y") as? CGFloat) ?? (open ? m.rise : 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            r.alphaValue = open ? 1 : 0
            layer.sublayerTransform = CATransform3DMakeTranslation(0, open ? 0 : m.rise, 0)
            CATransaction.commit()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = open ? 1 : 0
            let move = CABasicAnimation(keyPath: "sublayerTransform.translation.y")
            move.fromValue = fromShift
            move.toValue = open ? 0 : m.rise
            let group = CAAnimationGroup()
            // Under Reduce motion the rows fade where they are.
            group.animations = Design.Motion.reduced ? [fade] : [fade, move]
            group.duration = open ? Design.Motion.fast : m.drop
            group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
            layer.add(group, forKey: "openClose")
        }
    }

    override func layout() {
        super.layout()
        // VStack spacing 16 between 40 pt rows, 2 pt lower than the area (.offset(y: 2)).
        let m = DownloadsTrayMetrics.self
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: m.header)
        for (i, r) in rows.enumerated() {
            r.frame = NSRect(x: 0, y: m.header + 2 + CGFloat(i) * m.rowPitch - m.plateBleed, width: bounds.width,
                             height: m.thumbnail + 2 * m.plateBleed)
        }
    }

    // MARK: Pointer

    /// The list's own height: the view reaches further down, to the Library button, only to keep
    /// the pointer (SidebarBottom.trayHoverBottom); a click there goes to what is under it.
    var listHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shownOpen else { return nil }
        // `point` is in the superview's coordinates; the list's part is its top `listHeight`.
        guard convert(point, from: superview).y < listHeight else { return nil }
        return super.hitTest(point)
    }

    /// One tracking area for the tray: it says which row the pointer is on. Rows change under the
    /// pointer (their buttons come and go), which re-makes tracking areas; an area made under a
    /// resting pointer gets no mouseEntered, so it is told the pointer is inside.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        let point = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        let inside = point.map { shownPartContains($0) } ?? false
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        if inside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
        pointer(at: inside ? point : nil)
    }

    override func mouseEntered(with event: NSEvent) { pointer(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { pointer(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { pointer(at: nil) }

    /// The row under the pointer shows its plate and buttons; nil when the pointer is off the tray.
    private func pointer(at point: NSPoint?) {
        let open = ui.downloadsListOpen
        for r in rows { r.hovering = open && point.map { r.frame.contains($0) } ?? false }
        setHovered(open && point != nil)
    }

    /// `niche://debug?downloadsHover=<row>`: the row (0 is the top one) as the pointer would have
    /// it, for a check that can't move the pointer; -1 for none.
    func debugHover(row: Int) {
        for (i, r) in rows.enumerated() { r.hovering = i == row }
    }

    private func setHovered(_ h: Bool) {
        guard ui.downloadsListHovered != h else { return }
        ui.downloadsListHovered = h
        ui.downloadsHoverChanged()
    }
}

/// The line over the tray's rows: "Downloads", which opens Library ▸ Downloads, and Clear.
@MainActor
private final class DownloadsTrayHeaderView: NSView {
    var colors = SidebarColors() { didSet { refresh() } }
    var canClear = false { didSet { if canClear != oldValue { refresh() } } }
    private let title = TrayTextButton(title: "Downloads", chevron: true, help: "Show All Downloads")
    private let clear = TrayTextButton(title: "Clear", chevron: false, help: "Clear Downloads")

    init(showAll: @escaping () -> Void) {
        super.init(frame: .zero)
        wantsLayer = true
        title.action = showAll
        clear.action = { DownloadHistory.shared.clear() }
        addSubview(title)
        addSubview(clear)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func refresh() {
        title.colors = colors
        clear.colors = colors
        clear.isHidden = !canClear
    }

    override func layout() {
        super.layout()
        let m = DownloadsTrayMetrics.self
        let h = Design.Space.controlCompact
        let y = (bounds.height - h) / 2
        title.frame = NSRect(x: m.plateInset, y: y, width: title.fittingWidth, height: h)
        let w = clear.fittingWidth
        clear.frame = NSRect(x: bounds.width - m.plateInset - w, y: y, width: w, height: h)
    }
}

/// A word in the tray's header that is a button: a hover plate under it, a chevron after it when
/// it leads somewhere.
@MainActor
private final class TrayTextButton: NSView {
    var action: () -> Void = {}
    var colors = SidebarColors() { didSet { refresh() } }
    private let label = NSTextField.sidebarLabel(size: Design.TextSize.caption.rawValue, weight: .semibold)
    private let chevron = NSImageView()
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }

    init(title: String, chevron shows: Bool, help: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.inset
        layer?.cornerCurve = .continuous
        label.stringValue = title
        addSubview(label)
        chevron.image = Design.Icon.symbol("chevron.right", size: Design.Icon.tiny, weight: .bold)
        chevron.isHidden = !shows
        addSubview(chevron)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat {
        let text = ceil(label.intrinsicContentSize.width)
        return Design.Space.m + text + (chevron.isHidden ? 0 : Design.Space.xs + Design.Icon.tiny) + Design.Space.m
    }

    private func refresh() {
        label.textColor = colors.ink(.secondary)
        chevron.contentTintColor = colors.ink(.tertiary)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = (hovering ? colors.plate(.hover) : .clear).cgColor
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let text = ceil(label.intrinsicContentSize.width), h = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Design.Space.m - SidebarText.inset, y: (bounds.height - h) / 2, width: text + 2 * SidebarText.inset, height: h)
        chevron.frame = NSRect(x: Design.Space.m + text + Design.Space.xs, y: (bounds.height - Design.Icon.tiny) / 2,
                               width: Design.Icon.tiny, height: Design.Icon.tiny)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHiddenOrHasHiddenAncestor && frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func viewDidHide() { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isHiddenOrHasHiddenAncestor else { return false }
        action()
        return true
    }
}

/// A download in the tray: its thumbnail, its name over what it is doing, a bar while it runs, and
/// under the pointer a plate with the two buttons its state calls for (`DownloadAction`). A
/// right-click has every action. A finished file opens on a click and drags out.
@MainActor
private final class DownloadsTrayRowView: NSView, NSDraggingSource {
    var colors = SidebarColors() { didSet { if colors != oldValue { refresh() } } }
    private var listed: DownloadHistory.Listed?
    /// The finished file this row stands for (live rows have nothing to open or drag yet).
    private var entry: DownloadHistory.Entry? {
        if case .finished(let e)? = listed { return e }
        return nil
    }
    var now = Date() { didSet { refreshAge() } }
    private let plate = CALayer()
    private let thumb = NSView()
    private let name = NSTextField.sidebarLabel(size: Design.TextSize.body.rawValue)
    private let age = NSTextField.sidebarLabel(size: Design.TextSize.detail.rawValue)
    private let progress = DownloadProgressBar()
    private var buttons: [SidebarGlyphButton] = []
    private var shownButtons: [DownloadAction] = []
    private var downAt: NSPoint?
    /// Set by the tray, which follows the pointer for all its rows.
    var hovering = false { didSet { if hovering != oldValue { refreshHover() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        plate.cornerRadius = Design.Radius.row
        plate.cornerCurve = .continuous
        plate.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(plate)
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = Design.Radius.inset
        thumb.layer?.cornerCurve = .continuous
        thumb.layer?.masksToBounds = true
        thumb.layer?.contentsGravity = .resizeAspectFill
        addSubview(thumb)
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)
        age.font = Design.Font.digits(.detail)
        addSubview(age)
        addSubview(progress)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Also when only a thumbnail arrived, and on every progress report.
    func show(_ l: DownloadHistory.Listed) {
        listed = l
        refresh()
    }

    private func refresh() {
        name.textColor = colors.ink(.primary)
        guard let listed else { return }
        var image: NSImage?
        switch listed {
        case .finished(let e):
            name.stringValue = (e.path as NSString).lastPathComponent
            image = DownloadHistory.shared.thumbnail(for: e.path)
        case .live(let l):
            // Still running, failed or cancelled: the file type's icon, as in the bin before it lands.
            name.stringValue = l.name
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (l.name as NSString).pathExtension) ?? .data)
        }
        if let image {
            // .aspectRatio(contentMode: .fill): the layer fills and crops.
            let scale = window?.backingScaleFactor ?? 2
            var rect = NSRect(x: 0, y: 0, width: DownloadsTrayMetrics.thumbnail, height: DownloadsTrayMetrics.thumbnail)
            thumb.layer?.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
            thumb.layer?.contentsScale = scale
            thumb.layer?.backgroundColor = nil
        } else {
            thumb.layer?.contents = nil
            thumb.layer?.backgroundColor = DownloadsTrayMetrics.placeholder.cgColor
        }
        progress.colors = colors
        switch listed.state {
        case .downloading:
            if case .live(let l) = listed { progress.show(.running(l.fraction)) }
        case .paused:
            if case .live(let l) = listed { progress.show(.paused(l.fraction ?? 0)) }
        case .failed, .cancelled, .held, .blocked, .finished:
            progress.show(nil)
        }
        setButtons(DownloadAction.buttons(for: listed.state))
        refreshAge()
        refreshHover()
        needsLayout = true
    }

    /// "54 seconds ago", "6 minutes ago"; progress and time left, "Paused", "Failed to Download" or
    /// "Cancelled" (DownloadRow).
    private func refreshAge() {
        guard let listed else { return }
        let s = DownloadRow.subtitle(listed.state, now: now, detail: hovering ? .brief : .compact)
        if age.stringValue != s { age.stringValue = s }
        age.textColor = listed.state.isWarning ? Design.dangerNS : colors.ink(.secondary)
        setAccessibilityLabel(listed.name + ", " + s)
    }

    private func setButtons(_ actions: [DownloadAction]) {
        guard actions != shownButtons else { for b in buttons { b.colors = colors }; return }
        shownButtons = actions
        buttons.forEach { $0.removeFromSuperview() }
        buttons = actions.map { action in
            let b = SidebarGlyphButton(symbol: action.symbol, size: Design.Space.controlCompact, iconSize: Design.Icon.small, weight: .semibold,
                                       help: action.title, colors: colors) { [weak self] in
                guard let self, let listed = self.listed else { return }
                DownloadHistory.shared.perform(action, on: listed)
            }
            b.isHidden = !hovering
            addSubview(b)
            return b
        }
    }

    private func refreshHover() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.backgroundColor = (hovering ? colors.plate(.hover) : .clear).cgColor
        CATransaction.commit()
        for b in buttons { b.isHidden = !hovering }
        refreshAge()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = DownloadsTrayMetrics.self
        let t = m.thumbnail
        plate.frame = bounds.insetBy(dx: m.plateInset, dy: 0)
        thumb.frame = NSRect(x: 8, y: m.plateBleed, width: t, height: t)
        // Buttons sit at the plate's right; the text ends short of them, or of the plate's edge.
        var right = bounds.width - m.plateInset - m.plateTextInset
        let side = Design.Space.controlCompact
        var bx = bounds.width - m.plateInset - Design.Space.s
        for b in buttons.reversed() {
            bx -= side
            b.frame = NSRect(x: bx, y: (bounds.height - side) / 2, width: side, height: side)
            bx -= Design.Space.xxs
        }
        if hovering, let first = buttons.first { right = first.frame.minX - Design.Space.s }
        // HStack(spacing: 13); VStack(spacing: -1) of 17 + 15, centred on the thumbnail; with a bar
        // the two lines move up to leave it room under them.
        let x = 8 + t + 13, w = max(0, right - x)
        let bar = !progress.isHidden
        let top = m.plateBleed + (t - 32) / 2 + 1 - (bar ? m.progressHeight : 0)
        name.frame = NSRect(x: x - SidebarText.inset, y: top, width: w + 2 * SidebarText.inset, height: 17)
        age.frame = NSRect(x: x - SidebarText.inset, y: top + 16, width: w + 2 * SidebarText.inset, height: 15)
        progress.frame = NSRect(x: x, y: top + 16 + 15 + Design.Space.xs, width: w, height: m.progressHeight)
    }

    // MARK: Menu and VoiceOver

    override func menu(for event: NSEvent) -> NSMenu? { listed.map(DownloadMenu.make) }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let listed else { return nil }
        return DownloadAction.menu(for: listed.state, hasLink: listed.link != nil).joined().map { action in
            NSAccessibilityCustomAction(name: action.title) {
                DownloadHistory.shared.perform(action, on: listed)
                return true
            }
        }
    }

    // MARK: Click and drag

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let entry else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: entry.path) as NSURL)
        let image = DownloadHistory.shared.thumbnail(for: entry.path) ?? NSWorkspace.shared.icon(forFile: entry.path)
        item.setDraggingFrame(thumb.frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, let entry, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }
}

/// A download's row menu, in the tray and on Library ▸ Downloads: every action its state offers
/// (`DownloadAction.menu`), then Clear Downloads.
@MainActor
enum DownloadMenu {
    static func make(for listed: DownloadHistory.Listed) -> NSMenu {
        let menu = NSMenu()
        // Niche's own rows only: macOS adds its services ("Ask Siri") to a view's menu otherwise.
        menu.allowsContextMenuPlugIns = false
        fill(menu, for: listed)
        return menu
    }

    static func fill(_ menu: NSMenu, for listed: DownloadHistory.Listed) {
        for (i, group) in DownloadAction.menu(for: listed.state, hasLink: listed.link != nil).enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for action in group {
                MenuItems.add(menu, action.title) { DownloadHistory.shared.perform(action, on: listed) }
            }
        }
        menu.addItem(.separator())
        MenuItems.add(menu, "Clear Downloads", enabled: DownloadHistory.shared.canClear) { DownloadHistory.shared.clear() }
    }
}

/// The bar under a running download's two lines: the accent over a faint track, as far along as
/// the download is; a download with no size gets a short piece crossing the track (still, and
/// full, under Reduce motion); a paused one keeps its place in the ink's colour.
@MainActor
final class DownloadProgressBar: NSView {
    enum Shown: Equatable {
        case running(Double?)
        case paused(Double)
    }

    var colors = SidebarColors() { didSet { if colors != oldValue { paint() } } }
    private let fill = CALayer()
    private var shown: Shown?
    /// The track's width the crossing piece was last set off on.
    private var sweptWidth: CGFloat?
    private static let sweepKey = "sweep"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        fill.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(fill)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ next: Shown?) {
        guard next != shown else { return }
        shown = next
        isHidden = next == nil
        paint()
        needsLayout = true
    }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = colors.ink(.primary).withAlphaComponent(DownloadsTrayMetrics.trackAlpha).cgColor
        if case .paused = shown { fill.backgroundColor = colors.ink(.secondary).cgColor } else { fill.backgroundColor = Design.accentNS.cgColor }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        layer?.cornerRadius = Design.Radius.pill(h)
        fill.cornerRadius = Design.Radius.pill(h)
        var fraction: CGFloat = 0
        var sweeps = false
        switch shown {
        case .running(let f?): fraction = CGFloat(f)
        case .paused(let f): fraction = CGFloat(f)
        case .running(nil): sweeps = true
        case nil: break
        }
        guard sweeps else {
            fill.removeAnimation(forKey: Self.sweepKey)
            sweptWidth = nil
            // At least a dot, so a download that has just begun shows.
            fill.frame = NSRect(x: 0, y: 0, width: max(h, bounds.width * fraction), height: h)
            return
        }
        guard !Design.Motion.reduced else {
            fill.removeAnimation(forKey: Self.sweepKey)
            sweptWidth = nil
            fill.frame = bounds
            return
        }
        // Every progress report lays the row out again: the piece keeps crossing, it doesn't start over.
        guard sweptWidth != bounds.width || fill.animation(forKey: Self.sweepKey) == nil else { return }
        sweptWidth = bounds.width
        fill.removeAnimation(forKey: Self.sweepKey)
        let w = bounds.width * DownloadsTrayMetrics.sweepShare
        fill.frame = NSRect(x: 0, y: 0, width: w, height: h)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -w / 2
        move.toValue = bounds.width + w / 2
        move.duration = DownloadsTrayMetrics.sweep
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fill.add(move, forKey: Self.sweepKey)
    }
}
