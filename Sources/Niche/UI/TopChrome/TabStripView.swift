import AppKit

/// Sizes and motions of the tab strip that are its own.
enum TabStripMetrics {
    /// The strip's row: the window's title row, so the traffic lights sit on the tabs' centre line.
    static let height: CGFloat = 40
    /// A tab's pill in that row.
    static let pill: CGFloat = 30
    /// Where the first item starts beside the traffic lights (they end at 67 pt), and without them.
    static let lightsInset: CGFloat = 80
    static let plainInset: CGFloat = Design.Space.m
    /// After the last trailing button.
    static let trailingInset: CGFloat = Design.Space.m
    /// A tab's inner padding: before its icon, and after its title or close button.
    static let padLeading: CGFloat = 9
    static let padTrailing: CGFloat = 6
    static let iconGap: CGFloat = 7
    /// The close and sound buttons inside a tab.
    static let innerButton: CGFloat = 20
    /// The rule between the favorites and the tabs.
    static let ruleHeight: CGFloat = 16
    /// A tab arriving or leaving: it grows from, or shrinks to, this much of its size.
    static let arrivalScale: CGFloat = 0.9
    /// The selection's plate travelling to another tab: a spring with a trace of bounce.
    static let selectionBounce: CGFloat = 0.12
    /// How far the pointer moves before a press on a tab is a drag.
    static let dragSlop: CGFloat = 4
    /// How far above or below the strip a carried tab goes before it leaves the strip as a drag
    /// that other places can take (the bookmarks bar, another window, the desktop).
    static let tearDistance: CGFloat = 28
    /// A carried tab's shadow.
    static let carriedShadowOpacity: Float = 0.22
    static let carriedShadowRadius: CGFloat = 10
    /// Fingers' travel up or down over the strip that changes space, and the rest before the same
    /// hand can change it again.
    static let spaceSwipeTravel: CGFloat = 26
    static let spaceSwipeRest: TimeInterval = 0.4
    /// How far a space's tabs travel as they give way to the next space's.
    static let spaceSlide: CGFloat = 14
    /// A run too long for the window fades out over this much at an edge it scrolls past.
    static let scrollFade: CGFloat = 18
    /// The loading ring: its stroke, the share of the circle it covers, and one turn.
    static let ringStroke: CGFloat = 1.6
    static let ringArc: CGFloat = 0.72
    static let ringTurn: TimeInterval = 0.85
    /// A space's emoji in its chip.
    static let chipEmoji: CGFloat = 15
    /// A carried tab held near an end of a run that scrolls brings more of the run in: within
    /// this much of the end, at up to this many points a second.
    static let autoscrollEdge: CGFloat = 36
    static let autoscrollSpeed: CGFloat = 700
    /// With no favorites yet, a tab carried this far past the start of the tabs becomes the first.
    static let favoriteReach: CGFloat = Design.Space.s
    /// The line that shows where a dragged tab would land.
    static let dropLineWidth: CGFloat = 2
}

/// The tabs across the top of a window (`WindowLayout.top`): the space's chip, its favorites as
/// icons, its tabs with their group names and splits, the New Tab button, and Downloads at the
/// far end. `TabStripLayout` (NicheCore) says where each goes; this draws them and moves them.
///
/// The selection is one plate that travels from tab to tab. A tab keeps its width whatever its
/// title, and none widens while the pointer is still in the strip after a close. A pressed tab is
/// carried along the strip, its neighbours stepping aside at their middles. Carried in among the
/// favorites it becomes one, as a tab dropped on the sidebar's favorites does, and a favorite
/// carried out among the tabs is a tab again; favorites change places the same way. Carried off
/// the strip it becomes a drag the bookmarks bar, the sidebar or another window can take, and let
/// go over the desktop it opens in a window of its own.
@MainActor
final class TabStripView: NSView, TabMenuHost, NSDraggingSource {
    let store: SidebarStore
    let ui: SidebarUIState
    let actions: SidebarActions
    let favicons: FaviconCache

    /// Where the first item starts: past the traffic lights when the window shows them here.
    var leadingInset: CGFloat = TabStripMetrics.plainInset { didSet { if leadingInset != oldValue { needsLayout = true } } }

    private struct Model: Equatable {
        var spaceID = UUID()
        var spaceIcon = SpaceIcon.none
        var spaceTitle = ""
        var showsSpace = false
        /// An incognito window: its chip says so and opens nothing.
        var incognito = false
        var entries: [StripEntry] = []
        var colors = SidebarColors()
        var downloads = false
        var downloading = false
        /// The Library is open on Downloads: the button holds its plate, and a click closes it.
        var downloadsOpen = false
        /// The space keeps favorites (a Blank Window and an incognito one keep none).
        var allowsFavorites = true
        var drop: DropSpot?
    }

    /// Where a drag from elsewhere would land: among the favorites or among the tabs.
    private struct DropSpot: Equatable {
        var favorite: Bool
        var index: Int
    }

    private var model = Model()
    private var layoutResult = TabStripLayout.Result()
    private let spaceChip = StripSpaceChip()
    private let rule = CALayer()
    private let runClip = FlippedView()
    private let runContent = FlippedView()
    private let selection = CALayer()
    /// Fades the run's edges where more tabs lie past them.
    private let runFade = CAGradientLayer()
    private let dropLine = CALayer()
    private var views: [UUID: StripItemView] = [:]
    private var leaving: [StripItemView] = []
    private lazy var plus = SidebarGlyphButton(symbol: "plus", size: CGFloat(TabStripLayout.Metrics().square), iconSize: Design.Icon.bar,
                                               help: "New Tab (⌘T)", colors: SidebarColors()) { [weak self] in
        self?.actions.openCommandBar(.newTab)
    }
    private lazy var downloads = SidebarGlyphButton(symbol: "arrow.down.circle", size: CGFloat(TabStripLayout.Metrics().square),
                                                    iconSize: Design.Icon.bar, help: "Downloads", colors: SidebarColors()) { [weak self] in
        guard let self else { return }
        // The same button puts the Library away again, as the sidebar's own does.
        if self.ui.libraryPage == .downloads { self.actions.toggleLibrary() } else { self.actions.showLibrary(.downloads) }
    }
    private var scrollOffset: CGFloat = 0
    /// The tab width kept while the pointer stays in the strip after a close.
    private var heldTabWidth: CGFloat?
    private var pointerInside = false
    private var hoverArea: NSTrackingArea?
    private var selectedShown: UUID?
    private var press = WindowDragGesture()
    private var carry: Carry?
    private var swipeTravel: CGFloat = 0
    private var lastSpaceSwipe: TimeInterval = 0
    private var shownSpace: UUID?

    /// A tab or a favorite being carried along the strip.
    private struct Carry {
        var id: UUID
        /// The pointer's offset from the item's leading edge.
        var grab: CGFloat
        var start: NSPoint
        /// Where the pointer was last, in the window.
        var here: NSPoint
        var moved = false
        /// The favorites and the run in the order the hand gave them (it applies on release). The
        /// carried item is in one of them, in that one's form.
        var favorites: [StripEntry]
        var run: [StripEntry]

        var asFavorite: Bool { favorites.contains { $0.id == id } }
    }
    private var autoscroll: Timer?

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        rule.actions = ["backgroundColor": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(rule)
        runClip.wantsLayer = true
        runClip.layer?.masksToBounds = true
        runFade.startPoint = CGPoint(x: 0, y: 0.5)
        runFade.endPoint = CGPoint(x: 1, y: 0.5)
        runFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        runFade.actions = ["bounds": NSNull(), "position": NSNull(), "locations": NSNull()]
        runContent.wantsLayer = true
        selection.cornerRadius = Design.Radius.row
        selection.cornerCurve = .continuous
        selection.actions = ["backgroundColor": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        selection.isHidden = true
        runContent.layer?.addSublayer(selection)
        dropLine.actions = ["backgroundColor": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull()]
        dropLine.cornerRadius = Design.Space.hair
        dropLine.isHidden = true
        dropLine.zPosition = 1
        runClip.addSubview(runContent)
        addSubview(runClip)
        layer?.addSublayer(dropLine)
        spaceChip.onClick = { [weak self] in self?.openSpaceMenu() }
        let chipGuard = UUID()
        spaceChip.onHover = { [weak ui] over in ui?.hoverTitleRowItem(chipGuard, over) }
        addSubview(spaceChip)
        addSubview(plus)
        addSubview(downloads)
        registerForDraggedTypes([.nicheSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")
        observeChanges(of: { [weak self] in self?.build() }) { [weak self] built in
            guard let self, let built else { return }
            self.apply(built)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    /// The strip's empty parts move the window themselves (mouseDown), so a double-click there
    /// can zoom it as a title bar's does.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Model

    private func icon(_ key: String?, dark: Bool) -> StripIcon {
        guard let image = favicons.image(forKey: key) else { return StripIcon(image: nil, flip: false) }
        return StripIcon(image: image, flip: favicons.glyphIsDark(forKey: key) == dark)
    }

    private func tabEntry(_ item: SidebarItem, kind: StripEntry.Kind, parent: UUID, dark: Bool) -> StripEntry? {
        guard let tab = item.tab else { return nil }
        let easel = Easel.id(fromURL: tab.url) != nil && tab.customIconKey == nil
        let glyph = easel ? StripIcon(image: NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "Easel"), flip: true)
                          : icon(tab.iconKey, dark: dark)
        let title = item.title == nil ? TidyTitleRules.arc.tidy(item.displayTitle, url: tab.url) : item.displayTitle
        return StripEntry(id: item.id, kind: kind, parent: parent, panes: [], title: title.isEmpty ? "New Tab" : title, icons: [glyph],
                          selected: store.isSelected(item.id, window: ui.windowID), audible: ui.audibleTabIDs.contains(item.id),
                          muted: tab.muted, loading: ui.loadingTabIDs.contains(item.id),
                          editing: ui.renamingID == item.id && ui.renamesInTopChrome)
    }

    private func build() -> Model? {
        let window = ui.windowID
        let space = store.focusedSpace(window: window)
        let palette = space.theme.palette
        var m = Model()
        m.spaceID = space.id
        m.spaceIcon = SpaceIcon(emoji: space.emoji, symbol: space.symbol)
        m.spaceTitle = space.title
        // A window of one space of its own (incognito, Blank) has nowhere to switch to; an incognito
        // one keeps its chip, which is what says the window is incognito once the sidebar is away.
        m.incognito = store.isIncognito(space: space.id)
        m.showsSpace = m.incognito || (!store.isStandalone(space: space.id) && !store.hidesSpaceHeader(space.id))
        m.colors = SidebarColors(palette)
        let dark = palette.isDark
        var out: [StripEntry] = []
        func splitEntry(_ item: SidebarItem, favorite: Bool, parent: UUID) -> StripEntry? {
            let panes = store.children(of: item.id).filter(\.isTab)
            guard !panes.isEmpty else { return nil }
            let selected = panes.contains { store.isSelected($0.id, window: window) }
            let focused = panes.first { store.isSelected($0.id, window: window) } ?? panes[0]
            let title = item.title ?? focused.tab.map { TidyTitleRules.arc.tidy(focused.displayTitle, url: $0.url) } ?? focused.displayTitle
            return StripEntry(id: item.id, kind: favorite ? .favorite : .split(panes.map(\.id)), parent: parent, panes: panes.map(\.id), title: title,
                              icons: panes.map { icon($0.tab?.iconKey, dark: dark) }, selected: selected,
                              audible: panes.contains { ui.audibleTabIDs.contains($0.id) }, muted: panes.allSatisfy { $0.tab?.muted == true },
                              loading: panes.contains { ui.loadingTabIDs.contains($0.id) },
                              editing: ui.renamingID == item.id && ui.renamesInTopChrome)
        }
        m.allowsFavorites = !store.isBlank(space: space.id) && !m.incognito
        if !store.isBlank(space: space.id) {
            // A favorite split is one tile, as in the sidebar.
            for item in store.children(of: space.favoritesContainerID) {
                let e = item.isSplit ? splitEntry(item, favorite: true, parent: space.favoritesContainerID)
                                     : tabEntry(item, kind: .favorite, parent: space.favoritesContainerID, dark: dark)
                if let e { out.append(e) }
            }
        }
        func add(_ item: SidebarItem, parent: UUID) {
            if item.isTabGroup {
                out.append(StripEntry(id: item.id, kind: .group, parent: parent, panes: [], title: item.title ?? "Untitled", icons: [], selected: false,
                                      audible: false, muted: false, loading: false, editing: false))
                for child in store.children(of: item.id).reversed() { add(child, parent: item.id) }
            } else if item.isSplit {
                if let e = splitEntry(item, favorite: false, parent: parent) { out.append(e) }
            } else if let e = tabEntry(item, kind: .tab, parent: parent, dark: dark) {
                out.append(e)
            }
        }
        // The sidebar lists the newest tab first, at the top; a strip reads the other way, as in
        // Chrome and Safari: the oldest at the start and a new tab at the end, beside New Tab.
        for item in store.children(of: space.todayContainerID).reversed() { add(item, parent: space.todayContainerID) }
        m.entries = out
        let history = DownloadHistory.shared
        m.downloading = history.hasRunningDownloads
        m.downloads = m.downloading || !history.entries.isEmpty || ui.recentDownload != nil
        m.downloadsOpen = ui.libraryPage == .downloads
        return m
    }

    private func apply(_ new: Model) {
        let old = model
        model = new
        // While a tab is carried the run keeps the order the hand gave it.
        if var c = carry {
            // What each item shows may have changed under the hand; where it stands has not.
            let fresh = Dictionary(new.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            c.favorites = c.favorites.compactMap { fresh[$0.id].map { Self.form($0, favorite: true, parent: $0.parent) } }
            c.run = c.run.compactMap { old in fresh[old.id].map { Self.form($0, favorite: false, parent: old.parent) } }
            carry = c
            if fresh[c.id] == nil { endCarry() }
        }
        if old.colors != new.colors { applyColors() }
        spaceChip.show(icon: new.spaceIcon, title: new.spaceTitle, colors: new.colors,
                       help: new.incognito ? "Incognito: nothing from this window is kept" : "\(new.spaceTitle): switch space")
        downloads.tint = new.downloading ? Design.accentNS : new.colors.textSecondary
        downloads.highlighted = new.downloadsOpen
        let spaceChanged = shownSpace != nil && shownSpace != new.spaceID
        let direction = spaceChanged ? spaceDirection(from: shownSpace, to: new.spaceID) : 0
        shownSpace = new.spaceID
        // A close with the pointer in the strip: the tabs keep their width until it leaves.
        let removed = Set(old.entries.map(\.id)).subtracting(new.entries.map(\.id))
        if !removed.isEmpty, pointerInside, !spaceChanged, heldTabWidth == nil, layoutResult.tabWidth > 0 {
            heldTabWidth = CGFloat(layoutResult.tabWidth)
        }
        if spaceChanged { heldTabWidth = nil; scrollOffset = 0 }
        syncViews(animated: window != nil && !spaceChanged, slide: direction)
    }

    private func applyColors() {
        let c = model.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rule.backgroundColor = c.rule.cgColor
        selection.backgroundColor = c.plate(.selected).cgColor
        dropLine.backgroundColor = Design.accentNS.cgColor
        CATransaction.commit()
        plus.colors = c
        downloads.colors = c
        // The sidebar's faint glyph tone is for its own quiet corners; these two are the strip's controls.
        plus.tint = c.textSecondary
        downloads.tint = model.downloading ? Design.accentNS : c.textSecondary
        for v in views.values { v.colors = c }
    }

    /// +1 when the new space comes after the old one in the window's order, −1 before.
    private func spaceDirection(from old: UUID?, to new: UUID) -> Int {
        let order = store.pagedSpaces(window: ui.windowID).map(\.id)
        guard let old, let a = order.firstIndex(of: old), let b = order.firstIndex(of: new) else { return 0 }
        return b > a ? 1 : -1
    }

    // MARK: Views

    private var shownEntries: [StripEntry] {
        guard let carry else { return model.entries }
        return carry.favorites + carry.run
    }

    /// An entry as a favorite's tile, or as the tab or split it is among the tabs.
    private static func form(_ e: StripEntry, favorite: Bool, parent: UUID) -> StripEntry {
        var e = e
        // A group's name is neither: it stays what it is.
        if e.kind != .group { e.kind = favorite ? .favorite : e.panes.isEmpty ? .tab : .split(e.panes) }
        e.parent = parent
        return e
    }

    /// The carried item is lifted out of the run onto the strip itself, so it can cross to the
    /// favorites and back.
    private func isLifted(_ id: UUID) -> Bool { carry?.id == id && carry?.moved == true }

    private func items(for entries: [StripEntry]) -> [TabStripLayout.Item] {
        var items: [TabStripLayout.Item] = model.showsSpace ? [.space] : []
        let favorites = entries.filter { $0.kind == .favorite }
        items += favorites.map { .favorite($0.id) }
        let run = entries.filter { $0.kind != .favorite }
        if !favorites.isEmpty { items.append(.rule) }
        for e in run {
            switch e.kind {
            case .group: items.append(.group(e.id, width: Double(StripItemView.groupWidth(e.title))))
            case .split(let panes): items.append(.split(e.id, panes: panes.count))
            default: items.append(.tab(e.id))
            }
        }
        return items
    }

    private var trailingWidth: CGFloat {
        let square = CGFloat(TabStripLayout.Metrics().square)
        return TabStripMetrics.trailingInset + (model.downloads ? square + Design.Space.xs : 0)
    }

    /// Creates, updates and removes the item views, then lays them out.
    private func syncViews(animated: Bool, slide: Int = 0) {
        let entries = shownEntries
        let ids = Set(entries.map(\.id))
        for (id, view) in views where !ids.contains(id) {
            views[id] = nil
            // It shrinks away where it stood while the others close the gap.
            if animated, !Design.Motion.reduced, slide == 0 {
                leaving.append(view)
                view.leave { [weak self, weak view] in
                    guard let view else { return }
                    view.removeFromSuperview()
                    self?.leaving.removeAll { $0 === view }
                }
            } else {
                view.removeFromSuperview()
            }
        }
        var arrived: [StripItemView] = []
        for e in entries {
            // A favorite stands with the fixed items, a tab in the run that scrolls. A tab made a
            // favorite (or back) is the same item: its view moves across.
            let host: NSView = e.kind == .favorite || isLifted(e.id) ? self : runContent
            if let view = views[e.id] {
                // It goes across from where it is, and changes shape on the way.
                if view.superview !== host, let from = view.superview {
                    let frame = from.convert(view.frame, to: host)
                    host.addSubview(view)
                    view.frame = frame
                }
                continue
            }
            let view = StripItemView(strip: self)
            view.colors = model.colors
            views[e.id] = view
            host.addSubview(view)
            arrived.append(view)
        }
        relayout(animated: animated, arrived: arrived)
        if slide != 0, !Design.Motion.reduced { playSpaceSlide(slide) }
    }

    override func layout() {
        super.layout()
        relayout(animated: false, arrived: [])
    }

    private func relayout(animated: Bool, arrived: [StripItemView]) {
        let entries = shownEntries
        let square = CGFloat(TabStripLayout.Metrics().square)
        let room = max(0, bounds.width - leadingInset - trailingWidth)
        let result = TabStripLayout.layout(items(for: entries), width: Double(room), heldTabWidth: heldTabWidth.map(Double.init))
        layoutResult = result
        let h = bounds.height
        let pillY = ((h - TabStripMetrics.pill) / 2).rounded()
        let squareY = ((h - square) / 2).rounded()
        let move = animated && !Design.Motion.reduced

        spaceChip.isHidden = !model.showsSpace
        rule.isHidden = true
        for f in result.fixed {
            let x = leadingInset + CGFloat(f.x)
            switch f.item {
            case .space:
                spaceChip.frame = NSRect(x: x, y: squareY, width: square, height: square)
            case .rule:
                rule.isHidden = false
                rule.frame = NSRect(x: (x + CGFloat(f.width) / 2).rounded(), y: ((h - TabStripMetrics.ruleHeight) / 2).rounded(),
                                    width: 1, height: TabStripMetrics.ruleHeight)
            case .favorite(let id):
                guard let view = views[id], let e = entries.first(where: { $0.id == id }) else { continue }
                if !isLifted(id) {
                    place(view, NSRect(x: x, y: squareY, width: square, height: square), animated: move && !arrived.contains { $0 === view })
                }
                view.show(e, titled: false)
            default: break
            }
        }

        scrollOffset = min(max(0, scrollOffset), CGFloat(result.maxScroll))
        if let selected = entries.first(where: { $0.selected && $0.kind != .favorite })?.id, selected != selectedShown || arrived.contains(where: { $0 === views[selected] }) {
            scrollOffset = CGFloat(TabStripLayout.scroll(toShow: selected, in: result, offset: Double(scrollOffset)))
        }
        runClip.frame = NSRect(x: leadingInset + CGFloat(result.runX), y: 0, width: CGFloat(result.runVisibleWidth), height: h)
        let content = NSRect(x: -scrollOffset, y: 0, width: max(CGFloat(result.runContentWidth), 1), height: h)
        if move { runContent.animator().frame = content } else { runContent.frame = content }

        var selectedFrame: NSRect?
        var selectedID: UUID?
        for f in result.run {
            guard let id = f.item.id, let view = views[id], let e = entries.first(where: { $0.id == id }) else { continue }
            let frame = NSRect(x: CGFloat(f.x), y: pillY, width: CGFloat(f.width), height: TabStripMetrics.pill)
            // The carried tab stays under the hand; only its slot is kept for it.
            if !isLifted(id) { place(view, frame, animated: move && !arrived.contains { $0 === view }) }
            view.show(e, titled: result.titled)
            if e.selected, e.kind != .group { selectedFrame = frame; selectedID = id }
        }
        if carry?.moved == true {
            placeCarried(animated: move)
            if let id = carry?.id, id == selectedID, let view = views[id] { selectedFrame = runContent.convert(view.frame, from: self) }
        }
        for view in arrived where view.superview != nil { view.arrive(animated: move) }
        moveSelection(to: selectedFrame, id: selectedID, animated: move)

        let plusFrame = NSRect(x: leadingInset + CGFloat(result.plusX), y: squareY, width: square, height: square)
        if move { plus.animator().frame = plusFrame } else { plus.frame = plusFrame }
        downloads.isHidden = !model.downloads
        downloads.frame = NSRect(x: bounds.width - TabStripMetrics.trailingInset - square, y: squareY, width: square, height: square)
        showDropLine()
        fadeRunEdges()
    }

    /// A run that scrolls fades out at the edge more tabs lie past, so a tab cut by the edge
    /// reads as going on, not as cut off.
    private func fadeRunEdges() {
        let w = runClip.bounds.width
        guard layoutResult.scrolls, w > 2 * TabStripMetrics.scrollFade else {
            if runClip.layer?.mask != nil { runClip.layer?.mask = nil }
            return
        }
        let fade = Double(TabStripMetrics.scrollFade / w)
        let leading = scrollOffset > 0.5 ? fade : 0
        let trailing = scrollOffset < CGFloat(layoutResult.maxScroll) - 0.5 ? fade : 0
        runFade.frame = runClip.bounds
        runFade.locations = [0, NSNumber(value: leading), NSNumber(value: 1 - trailing), 1]
        if runClip.layer?.mask !== runFade { runClip.layer?.mask = runFade }
    }

    private func place(_ view: NSView, _ frame: NSRect, animated: Bool) {
        guard view.frame != frame else { return }
        if animated, view.frame.width > 0 { view.animator().frame = frame } else { view.frame = frame }
    }

    /// The selection's plate goes to the selected tab: on a spring from where it is, or fading in
    /// when nothing in the run was selected before (a favorite, a pinned tab, a new window).
    private func moveSelection(to frame: NSRect?, id: UUID?, animated: Bool) {
        defer { selectedShown = id }
        guard let frame else {
            selection.isHidden = true
            return
        }
        let wasShown = !selection.isHidden
        let from = selection.presentation()?.frame ?? selection.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selection.isHidden = false
        selection.frame = frame
        CATransaction.commit()
        guard animated, from != frame else { return }
        if wasShown, id != selectedShown || selection.animation(forKey: "travel") != nil {
            let spring = CASpringAnimation(perceptualDuration: Design.Motion.slow, bounce: TabStripMetrics.selectionBounce)
            spring.keyPath = "position"
            spring.fromValue = NSValue(point: NSPoint(x: from.midX, y: from.midY))
            spring.toValue = NSValue(point: NSPoint(x: frame.midX, y: frame.midY))
            spring.duration = spring.settlingDuration
            selection.add(spring, forKey: "travel")
            let size = CASpringAnimation(perceptualDuration: Design.Motion.slow, bounce: 0)
            size.keyPath = "bounds.size"
            size.fromValue = NSValue(size: from.size)
            size.toValue = NSValue(size: frame.size)
            size.duration = size.settlingDuration
            selection.add(size, forKey: "resize")
        } else if !wasShown {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Design.Motion.fast
            selection.add(fade, forKey: "arrive")
        } else {
            // Its own tab moved or changed width: it goes with the tab.
            let follow = CABasicAnimation(keyPath: "position")
            follow.fromValue = NSValue(point: NSPoint(x: from.midX, y: from.midY))
            follow.duration = Design.Motion.standard
            follow.timingFunction = Design.Motion.curve
            selection.add(follow, forKey: "travel")
            let size = CABasicAnimation(keyPath: "bounds.size")
            size.fromValue = NSValue(size: from.size)
            size.duration = Design.Motion.standard
            size.timingFunction = Design.Motion.curve
            selection.add(size, forKey: "resize")
        }
    }

    /// Another space's tabs come in from the side the space is on, over a short distance, as the
    /// old ones were cut away: the strip says which way the space went without a whole slide.
    private func playSpaceSlide(_ direction: Int) {
        for view in [runClip, spaceChip] as [NSView] + views.values.filter({ $0.superview === self }) {
            guard let layer = view.layer else { continue }
            let move = CABasicAnimation(keyPath: "transform.translation.x")
            move.fromValue = CGFloat(direction) * TabStripMetrics.spaceSlide
            move.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = Design.Motion.standard
            group.timingFunction = Design.Motion.curve
            layer.add(group, forKey: "spaceSlide")
        }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        lookUnderPointer()
    }

    /// The strip follows the pointer itself and asks each item where it is. An item's own
    /// tracking lags after it has moved (a close, a reorder, a carry), and a press on a tab that
    /// hadn't heard the pointer was on it took the window instead of the tab (17 Nov 2026).
    override func mouseMoved(with event: NSEvent) { lookUnderPointer() }

    private func lookUnderPointer() {
        for view in views.values { view.syncHover() }
        spaceChip.syncHover()
    }

    /// Every item looks again where the pointer is, now and once the strip has settled.
    private func syncHovers() {
        for delay in [0, Design.Motion.standard + Design.Motion.fast] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.lookUnderPointer()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        syncHovers()
        guard heldTabWidth != nil, carry == nil else { return }
        heldTabWidth = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Design.Motion.duration(Design.Motion.standard)
            ctx.timingFunction = Design.Motion.curve
            ctx.allowsImplicitAnimation = true
            relayout(animated: true, arrived: [])
        }
    }

    // The strip's empty parts are the window's title bar: a drag moves it, a double-click zooms it.
    override func mouseDown(with event: NSEvent) { press.begin(event) }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) {
        if press.finish(), event.clickCount == 2 { actions.titleBarDoubleClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        MenuItems.add(menu, action: "newTab", title: "New Tab") { [actions] in actions.openCommandBar(.newTab) }
        MenuItems.add(menu, action: "reopenClosedTab") { [actions] in actions.performAction("reopenClosedTab") }
        menu.addItem(.separator())
        MenuItems.add(menu, action: "toggleBookmarksBar", title: store.settings.showBookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar") { [actions] in
            actions.performAction("toggleBookmarksBar")
        }
        MenuItems.add(menu, "Show Tabs in the Sidebar") { [store] in store.settings.windowLayout = .sidebar }
        return menu
    }

    /// Two fingers up or down over the strip change space, as a sideways swipe does in the
    /// sidebar; sideways they scroll a run too long for the window.
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if abs(dx) >= abs(dy) || !model.showsSpace || model.incognito {
            let d = abs(dx) >= abs(dy) ? dx : dy
            guard layoutResult.scrolls, d != 0 else { return }
            scrollOffset = min(max(0, scrollOffset - d), CGFloat(layoutResult.maxScroll))
            runContent.frame.origin.x = -scrollOffset
            fadeRunEdges()
            return
        }
        if event.phase == .began || event.phase == .mayBegin { swipeTravel = 0 }
        guard event.momentumPhase == [] else { return }
        swipeTravel += event.hasPreciseScrollingDeltas ? dy : dy * Design.Space.m
        let now = event.timestamp
        guard abs(swipeTravel) >= TabStripMetrics.spaceSwipeTravel, now - lastSpaceSwipe > TabStripMetrics.spaceSwipeRest else { return }
        lastSpaceSwipe = now
        // Fingers going up bring the next space, as a page scrolls on.
        let offset = swipeTravel < 0 ? 1 : -1
        swipeTravel = 0
        let order = store.pagedSpaces(window: ui.windowID).map(\.id)
        guard let i = order.firstIndex(of: model.spaceID), order.indices.contains(i + offset) else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }
        store.focusSpace(order[i + offset], window: ui.windowID)
    }

    private func openSpaceMenu() {
        guard !model.incognito else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let focused = model.spaceID
        for space in store.pagedSpaces(window: ui.windowID) {
            MenuItems.add(menu, space.labeled, on: space.id == focused) { [store, ui] in
                if space.id != focused { store.focusSpace(space.id, window: ui.windowID) }
            }
        }
        menu.addItem(.separator())
        MenuItems.add(menu, "New Space…") { [actions] in actions.editSpace(nil) }
        if let space = store.space(focused) {
            MenuItems.add(menu, "Edit Theme Color…") { [actions] in actions.editSpaceTheme(space) }
        }
        MenuItems.add(menu, "Manage Spaces…") { [actions] in actions.manageSpaces() }
        menu.popUp(positioning: nil, at: NSPoint(x: spaceChip.frame.minX, y: spaceChip.frame.maxY + Design.Space.xs), in: self)
    }

    // MARK: Tabs

    func entry(_ id: UUID) -> StripEntry? { model.entries.first { $0.id == id } }

    func closeGroup(for id: UUID) -> [UUID] { [id] }

    func closeTabs(_ ids: [UUID]) {
        let open = store.selectedTabID(window: ui.windowID)
        for id in ids.filter({ $0 != open }) + ids.filter({ $0 == open }) { actions.closeTab(id) }
    }

    /// The tab's close button, or a middle click on it.
    func close(_ e: StripEntry) {
        switch e.kind {
        case .split(let panes): closeTabs(panes)
        case .group: store.removeGroupHeader(e.id)
        default: actions.closeTab(e.id)
        }
    }

    func toggleMute(_ e: StripEntry) {
        let ids: [UUID] = { if case .split(let panes) = e.kind { return panes } else { return [e.id] } }()
        for id in ids {
            store.setMuted(id, !e.muted)
            actions.performAction("muteTab:\(id)")
        }
    }

    func select(_ e: StripEntry) {
        switch e.kind {
        case .split, .favorite where !e.panes.isEmpty:
            guard !e.selected, let first = e.panes.first else { return }
            let focus = store.item(e.id)?.split?.focusTabID
            store.selectTab(focus.flatMap { e.panes.contains($0) ? $0 : nil } ?? first, window: ui.windowID)
        case .group:
            break
        default:
            if ui.keyboardFocusID != nil { ui.keyboardFocusID = nil }
            store.selectTab(e.id, window: ui.windowID)
        }
    }

    func rename(_ e: StripEntry, to text: String?) {
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed != e.title { store.rename(e.id, to: trimmed.isEmpty ? nil : trimmed) }
        }
        if ui.renamingID == e.id { ui.renamingID = nil }
    }

    func menu(for e: StripEntry) -> NSMenu? {
        switch e.kind {
        case .group:
            return SidebarMenus.tabGroup(e.id, list: self)
        case .split(let panes):
            let titles = panes.map { id in (id: id, title: store.item(id)?.displayTitle ?? "Tab") }
            return SidebarMenus.split(e.id, panes: titles, open: e.selected, store: store, ui: ui, actions: actions)
        case .favorite where !e.panes.isEmpty:
            let titles = e.panes.map { id in (id: id, title: store.item(id)?.displayTitle ?? "Tab") }
            return SidebarMenus.split(e.id, panes: titles, open: e.selected, store: store, ui: ui, actions: actions)
        case .favorite:
            let tab = store.item(e.id)?.tab
            let away = tab.map { $0.url != $0.savedURL && !$0.savedURL.isEmpty } ?? false
            return SidebarMenus.tab(e.id, pinned: true, navigatedAway: away, list: self)
        case .tab:
            return SidebarMenus.tab(e.id, pinned: false, navigatedAway: false, list: self)
        }
    }

    // MARK: Carrying a tab

    private var favoriteSlots: [TabStripLayout.Frame] { layoutResult.favorites }

    /// The run's leading edge in the strip.
    private var runOrigin: CGFloat { leadingInset + CGFloat(layoutResult.runX) }

    /// Left of this the pointer is among the favorites: the rule between them and the tabs, or
    /// with no favorite yet, just past the start of the tabs.
    private var favoritesEdge: CGFloat {
        leadingInset + CGFloat(layoutResult.favoritesEdge(reach: Double(TabStripMetrics.favoriteReach)))
    }

    func itemPressed(_ view: StripItemView, _ e: StripEntry, event: NSEvent) {
        if e.kind != .group { select(e) }
        let p = (view.superview ?? self).convert(event.locationInWindow, from: nil)
        carry = Carry(id: e.id, grab: p.x - view.frame.minX, start: event.locationInWindow, here: event.locationInWindow,
                      favorites: model.entries.filter { $0.kind == .favorite }, run: model.entries.filter { $0.kind != .favorite })
    }

    func itemDragged(_ view: StripItemView, _ e: StripEntry, event: NSEvent) {
        guard var c = carry, c.id == e.id else { return }
        c.here = event.locationInWindow
        // A group's name stays where it is; pulled away it becomes a drag.
        if !c.moved {
            guard hypot(c.here.x - c.start.x, c.here.y - c.start.y) > TabStripMetrics.dragSlop else { return }
            if e.kind == .group { carry = nil; beginSystemDrag(view, e, event: event); return }
            c.moved = true
            carry = c
            // Out of the run and onto the strip, above everything, where it can cross to the favorites.
            if let from = view.superview, from !== self {
                let frame = from.convert(view.frame, to: self)
                addSubview(view)
                view.frame = frame
            } else {
                addSubview(view)
            }
            view.setPressedLook(false)
            view.setCarried(true)
            startAutoscroll()
            if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        carry = c
        let local = convert(c.here, from: nil)
        if local.y < -TabStripMetrics.tearDistance || local.y > bounds.height + TabStripMetrics.tearDistance {
            // Off the strip: other places can take it now. It goes back to where it was meanwhile.
            endCarry()
            animate { self.syncViews(animated: true) }
            beginSystemDrag(view, e, event: event)
            return
        }
        updateCarry()
    }

    private func animate(_ body: () -> Void) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Design.Motion.duration(Design.Motion.standard)
            ctx.timingFunction = Design.Motion.curve
            ctx.allowsImplicitAnimation = true
            body()
        }
    }

    /// The carried item follows the pointer: it takes the favorites' form or the tabs' as it
    /// crosses the rule, and the others step aside at their middles.
    private func updateCarry() {
        guard var c = carry, c.moved, let view = views[c.id] else { return }
        let local = convert(c.here, from: nil)
        let wantsFavorite = model.allowsFavorites && local.x < favoritesEdge
        if wantsFavorite != c.asFavorite, let e = (c.favorites + c.run).first(where: { $0.id == c.id }) {
            let space = store.focusedSpace(window: ui.windowID)
            c.favorites.removeAll { $0.id == c.id }
            c.run.removeAll { $0.id == c.id }
            if wantsFavorite {
                c.favorites.append(Self.form(e, favorite: true, parent: space.favoritesContainerID))
                c.grab = CGFloat(TabStripLayout.Metrics().square) / 2
            } else {
                c.run.insert(Self.form(e, favorite: false, parent: space.todayContainerID), at: 0)
            }
            carry = c
            if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            animate { self.relayout(animated: true, arrived: []) }
            // Held by its middle in its new shape.
            if !wantsFavorite, var held = carry {
                held.grab = view.frame.width / 2
                carry = held
                c = held
            }
        }
        placeCarried(animated: false)
        // Its middle where the hand has it, not where the strip's ends stop it: held against an
        // end, it still passes the last neighbour there.
        let mid = local.x - c.grab + view.frame.width / 2
        var favorites = c.favorites, run = c.run
        if c.asFavorite, let e = favorites.first(where: { $0.id == c.id }) {
            let index = layoutResult.favoriteIndex(x: Double(mid - leadingInset), moving: c.id)
            favorites.removeAll { $0.id == c.id }
            favorites.insert(e, at: min(index, favorites.count))
        } else if let e = run.first(where: { $0.id == c.id }) {
            let index = TabStripLayout.insertionIndex(x: Double(mid - runOrigin + scrollOffset), among: layoutResult.run, moving: c.id)
            run.removeAll { $0.id == c.id }
            run.insert(e, at: min(index, run.count))
        }
        guard favorites.map(\.id) != c.favorites.map(\.id) || run.map(\.id) != c.run.map(\.id) else { return }
        c.favorites = favorites
        c.run = run
        carry = c
        if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        animate { self.relayout(animated: true, arrived: []) }
    }

    /// Puts the carried item under the pointer, inside the favorites or the part of the run that
    /// shows. A change of shape (a tab to a tile, or back) is animated; following the hand is not.
    private func placeCarried(animated: Bool) {
        guard let c = carry, c.moved, let view = views[c.id] else { return }
        let local = convert(c.here, from: nil)
        let h = bounds.height
        var frame: NSRect
        if c.asFavorite {
            let square = CGFloat(TabStripLayout.Metrics().square)
            let slots = favoriteSlots
            guard let first = slots.first, let last = slots.last else { return }
            let x = min(max(leadingInset + CGFloat(first.x), local.x - c.grab), leadingInset + CGFloat(last.x))
            frame = NSRect(x: x, y: ((h - square) / 2).rounded(), width: square, height: square)
        } else {
            guard let slot = layoutResult.run.first(where: { $0.item.id == c.id }) else { return }
            let w = CGFloat(slot.width)
            let x = min(max(runOrigin, local.x - c.grab), runOrigin + max(0, CGFloat(layoutResult.runVisibleWidth) - w))
            frame = NSRect(x: x, y: ((h - TabStripMetrics.pill) / 2).rounded(), width: w, height: TabStripMetrics.pill)
        }
        frame.origin.x = frame.origin.x.rounded()
        let from = view.frame.size
        guard view.frame != frame else { return }
        view.frame = frame
        if from != frame.size, from.width > 0, animated || carry != nil, !Design.Motion.reduced, let layer = view.layer {
            let size = CABasicAnimation(keyPath: "bounds.size")
            size.fromValue = NSValue(size: layer.presentation()?.bounds.size ?? from)
            size.duration = Design.Motion.fast
            size.timingFunction = Design.Motion.curve
            layer.add(size, forKey: "reshape")
        }
        if view.entry?.selected == true, !c.asFavorite {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selection.removeAllAnimations()
            selection.frame = runContent.convert(frame, from: self)
            CATransaction.commit()
        }
    }

    private func endCarry() {
        autoscroll?.invalidate()
        autoscroll = nil
        guard let c = carry else { return }
        carry = nil
        views[c.id]?.setCarried(false)
    }

    func itemReleased(_ view: StripItemView, _ e: StripEntry, event: NSEvent) {
        guard let c = carry, c.id == e.id else { return }
        guard c.moved else { carry = nil; return }
        let space = store.focusedSpace(window: ui.windowID)
        let wasFavorite = model.entries.first { $0.id == c.id }?.kind == .favorite
        if c.asFavorite {
            if c.favorites.map(\.id) != model.entries.filter({ $0.kind == .favorite }).map(\.id), let slot = c.favorites.firstIndex(where: { $0.id == c.id }) {
                moveToFavorites(c.id, slot: slot, resting: c.favorites.filter { $0.id != c.id }.map(\.id), in: space, wasFavorite: wasFavorite)
            }
        } else if let i = c.run.firstIndex(where: { $0.id == c.id }), c.run.map(\.id) != model.entries.filter({ $0.kind != .favorite }).map(\.id) {
            let target = dropTarget(after: i > 0 ? c.run[i - 1] : nil)
            store.moveItem(c.id, to: target.parent, index: target.index)
        }
        endCarry()
        syncHovers()
        // The new order lands as the item settles into its slot, from where the hand left it.
        animate {
            if let built = self.build() { self.apply(built) } else { self.syncViews(animated: true) }
        }
    }

    /// Puts an item among the favorites at `slot` of the tiles that stay (`resting`), as a drop on
    /// the sidebar's favorites does: a favorite changes places, anything else becomes one.
    private func moveToFavorites(_ id: UUID, slot: Int, resting: [UUID], in space: Space, wasFavorite: Bool) {
        let container = space.favoritesContainerID
        let children = store.item(container)?.children ?? []
        let index = slot < resting.count ? (children.firstIndex(of: resting[slot]) ?? children.count) : children.count
        if wasFavorite { store.moveItem(id, to: container, index: index) } else { store.addToFavorites(id, in: space.id, at: index) }
    }

    // MARK: Autoscroll

    private func startAutoscroll() {
        autoscroll?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoscrollTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoscroll = timer
    }

    /// A carried tab held at an end of a run that scrolls brings the tabs past that end in.
    private func autoscrollTick() {
        guard let c = carry, c.moved, !c.asFavorite, layoutResult.scrolls else { return }
        let x = convert(c.here, from: nil).x
        let lo = runOrigin, hi = runOrigin + CGFloat(layoutResult.runVisibleWidth)
        let edge = TabStripMetrics.autoscrollEdge
        var pull: CGFloat = 0
        if x < lo + edge { pull = -min(1, (lo + edge - x) / edge) } else if x > hi - edge { pull = min(1, (x - (hi - edge)) / edge) }
        let offset = min(max(0, scrollOffset + pull * TabStripMetrics.autoscrollSpeed / 60), CGFloat(layoutResult.maxScroll))
        guard offset != scrollOffset else { return }
        scrollOffset = offset
        runContent.frame.origin.x = -scrollOffset
        fadeRunEdges()
        updateCarry()
    }

    /// The container and index that put an item right after `before` in the strip (the start of
    /// the strip when nothing is before it). After a group's name is inside the group. The strip
    /// runs the other way from the store's list (newest last), so right after `before` on screen is
    /// right before it in the list, and the strip's start is the list's end. The store takes the
    /// index in the list as it is now, the moved item still in it, so the end is the list's count.
    private func dropTarget(after before: StripEntry?) -> (parent: UUID, index: Int) {
        let today = store.focusedSpace(window: ui.windowID).todayContainerID
        let count = { [store] (parent: UUID) in store.item(parent)?.children.count ?? 0 }
        guard let before else { return (today, count(today)) }
        if before.kind == .group { return (before.id, count(before.id)) }
        return (before.parent, store.item(before.parent)?.children.firstIndex(of: before.id) ?? count(before.parent))
    }

    // MARK: Drag source

    private func beginSystemDrag(_ view: StripItemView, _ e: StripEntry, event: NSEvent) {
        ui.draggingID = e.id
        let pb = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(SidebarDragItem(id: e.id)) { pb.setData(data, forType: .nicheSidebarItem) }
        let item = NSDraggingItem(pasteboardWriter: pb)
        item.setDraggingFrame(view.bounds, contents: view.dragImage())
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic, .private] : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let back = SpaceListView.isOverAppWindow(screenPoint)
        if session.animatesToStartingPositionsOnCancelOrFail != back { session.animatesToStartingPositionsOnCancelOrFail = back }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        syncHovers()
        // Let go over the desktop, where nothing took it: the tab opens in a window of its own.
        if let id = ui.draggingID, TabTearOff.tearsOff(isTab: store.item(id)?.isTab == true, incognito: store.isIncognito(item: id),
                                                       dropAccepted: !operation.isEmpty,
                                                       overAppWindow: SpaceListView.isOverAppWindow(screenPoint)) {
            actions.tearOffTab(id, screenPoint)
        }
        ui.draggingID = nil
    }

    // MARK: Drop target

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        if let id = ui.draggingID { return id }
        guard let data = info.draggingPasteboard.data(forType: .nicheSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data) else { return nil }
        return d.id
    }

    /// A tab, a split or a folder's tab from anywhere lands among the space's tabs, or left of
    /// the rule among its favorites.
    private func dropSpot(_ info: NSDraggingInfo) -> DropSpot? {
        guard let id = draggedID(info), let item = store.item(id), item.isTab || item.isSplit else { return nil }
        let local = convert(info.draggingLocation, from: nil)
        if model.allowsFavorites, local.x < favoritesEdge {
            return DropSpot(favorite: true, index: layoutResult.favoriteIndex(x: Double(local.x - leadingInset), moving: id))
        }
        let x = runContent.convert(info.draggingLocation, from: nil).x
        return DropSpot(favorite: false, index: TabStripLayout.insertionIndex(x: Double(x), among: layoutResult.run, moving: id))
    }

    private func setDrop(_ spot: DropSpot?) {
        guard model.drop != spot else { return }
        model.drop = spot
        showDropLine()
    }

    private func showDropLine() {
        guard let spot = model.drop else { dropLine.isHidden = true; return }
        let m = TabStripLayout.Metrics()
        let line = TabStripMetrics.dropLineWidth
        let x: CGFloat, height: CGFloat
        if spot.favorite {
            let slots = favoriteSlots.filter { $0.item.id != ui.draggingID }
            let gap = CGFloat(m.gap)
            if spot.index < slots.count { x = leadingInset + CGFloat(slots[spot.index].x) - (gap + line) / 2 }
            else if let last = slots.last { x = leadingInset + CGFloat(last.maxX) + (gap - line) / 2 }
            else { x = runOrigin - (gap + line) / 2 }
            height = CGFloat(m.square)
        } else {
            let frames = layoutResult.run.filter { $0.item.id != ui.draggingID }
            let inRun = spot.index < frames.count ? CGFloat(frames[spot.index].x) - line : CGFloat(frames.last?.maxX ?? 0)
            x = min(max(runOrigin, runOrigin - scrollOffset + inRun), runOrigin + CGFloat(layoutResult.runVisibleWidth))
            height = TabStripMetrics.pill
        }
        dropLine.isHidden = false
        dropLine.frame = NSRect(x: x.rounded(), y: ((bounds.height - height) / 2).rounded() + Design.Space.xs, width: line, height: height - 2 * Design.Space.xs)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let spot = dropSpot(sender)
        setDrop(spot)
        return spot == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDrop(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setDrop(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDrop(nil) }
        guard let id = draggedID(sender), let spot = dropSpot(sender) else { return false }
        let before = store.selectedTabID(window: ui.windowID)
        if spot.favorite {
            let favorites = model.entries.filter { $0.kind == .favorite }.map(\.id)
            moveToFavorites(id, slot: spot.index, resting: favorites.filter { $0 != id }, in: store.focusedSpace(window: ui.windowID),
                            wasFavorite: favorites.contains(id))
        } else {
            let run = model.entries.filter { $0.kind != .favorite && $0.id != id }
            let target = dropTarget(after: spot.index > 0 && spot.index <= run.count ? run[spot.index - 1] : nil)
            store.moveItem(id, to: target.parent, index: target.index)
            // From another window: it opens here.
            if store.item(id)?.isTab == true { store.tookTab(id, into: ui.windowID) }
        }
        if store.selectedTabID(window: ui.windowID) != before { window?.makeKeyAndOrderFront(nil) }
        if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted) }
        return true
    }

    // MARK: Readout

    /// `niche://debug?tabStrip=<label>`: what the strip shows, for scenarios.
    var readout: String {
        let run = model.entries.filter { $0.kind != .favorite }
        let selected = model.entries.firstIndex { $0.selected }.map(String.init) ?? "-"
        return "favorites=\(model.entries.count - run.count) items=\(run.count) selected=\(selected) tab-width=\(Int(layoutResult.tabWidth))"
            + " titled=\(layoutResult.titled ? 1 : 0) scrolls=\(layoutResult.scrolls ? 1 : 0) space=\(model.showsSpace ? 1 : 0)"
            + " hover=\(views.values.filter(\.showsHover).count) under=\(views.values.filter(\.isUnderPointer).count)"
            + " views=\(views.count) width=\(Int(bounds.width)) lead=\(Int(leadingInset))"
    }
}

/// One thing in the tab strip, as the strip's model has it.
struct StripEntry: Equatable {
    enum Kind: Equatable {
        case favorite, tab, group
        /// A split view, with its panes' tabs.
        case split([UUID])
    }

    var id: UUID
    var kind: Kind
    /// The container it sits in (the space's tabs, or a group).
    var parent: UUID
    /// A split view's panes, also when it is a favorite's tile; empty for a tab.
    var panes: [UUID]
    var title: String
    var icons: [StripIcon]
    var selected: Bool
    var audible: Bool
    var muted: Bool
    var loading: Bool
    var editing: Bool
}

struct StripIcon: Equatable {
    var image: NSImage?
    /// A one-colour glyph drawn in the strip's ink.
    var flip: Bool
}
