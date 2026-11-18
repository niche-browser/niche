import AppKit

/// Sizes of the bookmarks bar that are its own.
enum BookmarksBarMetrics {
    static let height: CGFloat = 28
    /// An item's plate in that row.
    static let item: CGFloat = 24
    static let pad: CGFloat = 7
    static let iconGap: CGFloat = 6
    /// The longest a name runs before it is cut.
    static let maxText: CGFloat = 150
    static let gap: CGFloat = Design.Space.xxs
    /// The chevron that holds what doesn't fit.
    static let chevron: CGFloat = 24
    /// The bar's inset from the window's edges, the toolbar's.
    static let inset: CGFloat = Design.Space.m
    /// A dragged tab over the middle of a folder goes into it; over its edges, beside it.
    static let folderDropShare: CGFloat = 0.5
}

/// The bookmarks bar under the toolbar when the tabs are across the top: the space's pinned tabs
/// and folders, which are what Niche keeps where other browsers keep bookmarks. A pinned tab opens
/// in place (it is a tab, not a link to one); a folder opens as a menu of what is in it; what
/// doesn't fit goes behind a chevron. Tabs are dragged here to pin them and out to unpin them.
@MainActor
final class BookmarksBarView: NSView, TabMenuHost, NSDraggingSource {
    let store: SidebarStore
    let ui: SidebarUIState
    let actions: SidebarActions
    let favicons: FaviconCache
    /// The bar gained its first item or lost its last: the window gives it room or takes it back.
    var onHasItemsChange: (() -> Void)?
    private(set) var hasItems = false

    struct Entry: Equatable {
        enum Kind: Equatable { case tab, folder, split([UUID]) }
        var id: UUID
        var kind: Kind
        var title: String
        var icon: StripIcon
        var selected: Bool
        var loaded: Bool
        var editing: Bool
        var navigatedAway: Bool
    }

    private struct Model: Equatable {
        var pinned = UUID()
        var entries: [Entry] = []
        var colors = SidebarColors()
    }

    private var model = Model()
    private var views: [UUID: BookmarkItemView] = [:]
    private var shownCount = 0
    private lazy var chevron = SidebarGlyphButton(symbol: "chevron.right.2", size: BookmarksBarMetrics.chevron, height: BookmarksBarMetrics.item,
                                                  iconSize: Design.Icon.small, help: "More Bookmarks", colors: SidebarColors()) { [weak self] in
        self?.openOverflow()
    }
    private let dropLine = CALayer()
    private var drop: Drop?
    private var press = WindowDragGesture()

    private enum Drop: Equatable {
        case at(Int)
        case into(UUID)
    }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        dropLine.actions = ["backgroundColor": NSNull(), "hidden": NSNull(), "position": NSNull(), "bounds": NSNull()]
        dropLine.cornerRadius = Design.Space.hair
        dropLine.isHidden = true
        layer?.addSublayer(dropLine)
        chevron.isHidden = true
        addSubview(chevron)
        registerForDraggedTypes([.nicheSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Bookmarks")
        observeChanges(of: { [weak self] in self?.build() }) { [weak self] built in
            guard let self, let built else { return }
            self.apply(built)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Model

    private func build() -> Model? {
        let window = ui.windowID
        let space = store.focusedSpace(window: window)
        let palette = space.theme.palette
        var m = Model()
        m.pinned = space.pinnedContainerID
        m.colors = SidebarColors(palette)
        guard !store.isBlank(space: space.id) else { return m }
        func icon(_ key: String?) -> StripIcon {
            guard let image = favicons.image(forKey: key) else { return StripIcon(image: nil, flip: false) }
            return StripIcon(image: image, flip: favicons.glyphIsDark(forKey: key) == palette.isDark)
        }
        let selected = store.selectedTabID(window: window)
        for item in store.children(of: space.pinnedContainerID) {
            let editing = ui.renamingID == item.id && ui.renamesInTopChrome
            if item.isFolder {
                let inside = selected.map { id in store.tabs(under: item.id).contains { $0.id == id } } ?? false
                m.entries.append(Entry(id: item.id, kind: .folder, title: item.title ?? "Folder",
                                       icon: StripIcon(image: SidebarSymbols.image(item.isLiveFolder ? "folder.badge.gearshape" : "folder", size: Design.Icon.bar), flip: true),
                                       selected: inside, loaded: true, editing: editing, navigatedAway: false))
            } else if item.isSplit {
                let panes = store.children(of: item.id).filter(\.isTab)
                guard let first = panes.first else { continue }
                m.entries.append(Entry(id: item.id, kind: .split(panes.map(\.id)), title: item.title ?? first.displayTitle,
                                       icon: icon(first.tab?.iconKey), selected: panes.contains { $0.id == selected },
                                       loaded: panes.contains { ui.loadedTabIDs.contains($0.id) }, editing: editing, navigatedAway: false))
            } else if let tab = item.tab {
                let away = tab.url != tab.savedURL && !tab.savedURL.isEmpty
                let title = item.title ?? tab.homeTitle.flatMap { $0.isEmpty ? nil : $0 } ?? TidyTitleRules.arc.tidy(item.displayTitle, url: tab.url)
                m.entries.append(Entry(id: item.id, kind: .tab, title: title.isEmpty ? "Untitled" : title,
                                       icon: icon(away ? tab.customIconKey ?? FaviconKey.key(for: tab.savedURL) : tab.iconKey),
                                       selected: item.id == selected, loaded: ui.loadedTabIDs.contains(item.id), editing: editing, navigatedAway: away))
            }
        }
        return m
    }

    private func apply(_ new: Model) {
        model = new
        let ids = Set(new.entries.map(\.id))
        for (id, view) in views where !ids.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
        }
        for e in new.entries {
            let view = views[e.id] ?? {
                let v = BookmarkItemView(bar: self)
                views[e.id] = v
                addSubview(v)
                return v
            }()
            view.colors = new.colors
            view.show(e)
        }
        chevron.colors = new.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropLine.backgroundColor = Design.accentNS.cgColor
        CATransaction.commit()
        needsLayout = true
        let has = !new.entries.isEmpty
        if has != hasItems {
            hasItems = has
            onHasItemsChange?()
        }
    }

    override func layout() {
        super.layout()
        let inset = BookmarksBarMetrics.inset
        let widths = model.entries.map { Double(views[$0.id]?.fittingWidth ?? 0) }
        let available = Double(max(0, bounds.width - 2 * inset))
        shownCount = BookmarksBarLayout.visibleCount(widths: widths, gap: Double(BookmarksBarMetrics.gap), available: available,
                                                     chevron: Double(BookmarksBarMetrics.chevron))
        let y = ((bounds.height - BookmarksBarMetrics.item) / 2).rounded()
        var x = inset
        for (i, e) in model.entries.enumerated() {
            guard let view = views[e.id] else { continue }
            view.isHidden = i >= shownCount
            guard i < shownCount else { continue }
            view.frame = NSRect(x: x, y: y, width: CGFloat(widths[i]), height: BookmarksBarMetrics.item)
            x += CGFloat(widths[i]) + BookmarksBarMetrics.gap
        }
        chevron.isHidden = shownCount >= model.entries.count
        chevron.frame = NSRect(x: bounds.width - inset - BookmarksBarMetrics.chevron, y: y, width: BookmarksBarMetrics.chevron, height: BookmarksBarMetrics.item)
        showDrop()
    }

    // MARK: Items

    func closeGroup(for id: UUID) -> [UUID] { [id] }
    func closeTabs(_ ids: [UUID]) { for id in ids { actions.closeTab(id) } }

    func open(_ e: Entry, from view: NSView) {
        switch e.kind {
        case .tab:
            if ui.keyboardFocusID != nil { ui.keyboardFocusID = nil }
            store.selectTab(e.id, window: ui.windowID)
        case .split(let panes):
            guard !e.selected else { return }
            let focus = store.item(e.id)?.split?.focusTabID
            store.selectTab(focus.flatMap { panes.contains($0) ? $0 : nil } ?? panes.first, window: ui.windowID)
        case .folder:
            let menu = folderMenu(e.id)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + Design.Space.xs), in: view)
        }
    }

    /// The middle button on a pinned tab closes its page and keeps it pinned.
    func close(_ e: Entry) {
        if e.kind == .tab, e.loaded { actions.closeTab(e.id) }
    }

    func rename(_ e: Entry, to text: String?) {
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed != e.title { store.rename(e.id, to: trimmed.isEmpty ? nil : trimmed) }
        }
        if ui.renamingID == e.id { ui.renamingID = nil }
    }

    /// What a folder holds, as a menu: its tabs open in place, its folders are submenus.
    private func folderMenu(_ id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let selected = store.selectedTabID(window: ui.windowID)
        let kids = store.children(of: id)
        for item in kids {
            if item.isFolder {
                let sub = NSMenuItem(title: item.title ?? "Folder", action: nil, keyEquivalent: "")
                sub.image = menuImage(SidebarSymbols.image("folder", size: Design.Icon.regular))
                sub.submenu = folderMenu(item.id)
                menu.addItem(sub)
            } else if item.isSplit {
                let panes = store.children(of: item.id).filter(\.isTab)
                guard let first = panes.first else { continue }
                let row = MenuItems.add(menu, item.title ?? first.displayTitle, on: panes.contains { $0.id == selected } ? true : nil,
                                        image: menuImage(favicons.image(forKey: first.tab?.iconKey))) { [store, ui] in
                    store.selectTab(first.id, window: ui.windowID)
                }
                row.toolTip = panes.map(\.displayTitle).joined(separator: " + ")
            } else if let tab = item.tab {
                let title = item.title ?? TidyTitleRules.arc.tidy(item.displayTitle, url: tab.url)
                MenuItems.add(menu, title.isEmpty ? "Untitled" : title, on: item.id == selected ? true : nil,
                              image: menuImage(favicons.image(forKey: tab.iconKey))) { [store, ui] in
                    store.selectTab(item.id, window: ui.windowID)
                }
            }
        }
        if kids.isEmpty {
            let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }

    private func menuImage(_ image: NSImage?) -> NSImage? {
        guard let copy = image?.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: NicheMetrics.favicon, height: NicheMetrics.favicon)
        return copy
    }

    private func openOverflow() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for e in model.entries.dropFirst(shownCount) {
            switch e.kind {
            case .folder:
                let sub = NSMenuItem(title: e.title, action: nil, keyEquivalent: "")
                sub.image = menuImage(SidebarSymbols.image("folder", size: Design.Icon.regular))
                sub.submenu = folderMenu(e.id)
                menu.addItem(sub)
            default:
                MenuItems.add(menu, e.title, on: e.selected ? true : nil, image: menuImage(e.icon.image)) { [weak self] in
                    guard let self else { return }
                    self.open(e, from: self.chevron)
                }
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: chevron.bounds.height + Design.Space.xs), in: chevron)
    }

    func menu(for e: Entry) -> NSMenu? {
        switch e.kind {
        case .tab:
            return SidebarMenus.tab(e.id, pinned: true, navigatedAway: e.navigatedAway, list: self)
        case .split(let panes):
            let titles = panes.map { id in (id: id, title: store.item(id)?.displayTitle ?? "Tab") }
            return SidebarMenus.split(e.id, panes: titles, open: e.selected, store: store, ui: ui, actions: actions)
        case .folder:
            let menu = NSMenu()
            menu.autoenablesItems = false
            let id = e.id
            let live = store.item(id)?.isLiveFolder == true
            MenuItems.add(menu, "Rename…") { [ui] in ui.renamingID = id }
            if !live {
                MenuItems.add(menu, "New Folder Inside") { [store] in _ = store.createFolder(named: "New Folder", in: id, index: 0) }
            }
            menu.addItem(.separator())
            if live, let item = store.item(id) {
                MenuItems.add(menu, "Delete Live Folder…") { [store, weak self] in
                    SidebarMenus.confirmDeleteLiveFolder(item, store: store, in: self?.window)
                }
            } else {
                MenuItems.add(menu, "Delete Folder (archives tabs)") { [store] in store.deleteFolder(id) }
            }
            return menu
        }
    }

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    // The bar follows the pointer itself and asks each item where it is. An item's own tracking
    // lags after it has moved, and a press on one that hadn't heard yet took the window
    // (TabStripView.mouseMoved).
    override func mouseEntered(with event: NSEvent) { for view in views.values { view.syncHover() } }
    override func mouseMoved(with event: NSEvent) { for view in views.values { view.syncHover() } }

    /// The pointer left the bar: every item looks again, so a hover (and the hold on the window
    /// that comes with it) never outlives the pointer (StripItemView.syncHover).
    override func mouseExited(with event: NSEvent) { syncHovers() }

    private func syncHovers() {
        for delay in [0, Design.Motion.standard] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for view in self.views.values { view.syncHover() }
            }
        }
    }

    // The bar's empty parts are the window's: a drag moves it.
    override func mouseDown(with event: NSEvent) { press.begin(event) }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) {
        if press.finish(), event.clickCount == 2 { actions.titleBarDoubleClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        MenuItems.add(menu, action: "newFolder") { [actions] in actions.performAction("newFolder") }
        menu.addItem(.separator())
        MenuItems.add(menu, action: "toggleBookmarksBar", title: "Hide Bookmarks Bar") { [actions] in actions.performAction("toggleBookmarksBar") }
        return menu
    }

    // MARK: Drag source

    func beginDrag(_ view: BookmarkItemView, _ e: Entry, event: NSEvent) {
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

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ui.draggingID = nil
        syncHovers()
    }

    // MARK: Drop target

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        if let id = ui.draggingID { return id }
        guard let data = info.draggingPasteboard.data(forType: .nicheSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data) else { return nil }
        return d.id
    }

    private func resolve(_ info: NSDraggingInfo) -> Drop? {
        guard let id = draggedID(info), let item = store.item(id), item.isTab || item.isSplit || item.isFolder else { return nil }
        let p = convert(info.draggingLocation, from: nil)
        let shown = model.entries.prefix(shownCount).filter { $0.id != id }
        // Over the middle of a folder a tab goes into it.
        if !item.isFolder {
            for e in shown where e.kind == .folder && store.item(e.id)?.isLiveFolder != true {
                guard let f = views[e.id]?.frame else { continue }
                let band = f.insetBy(dx: f.width * (1 - BookmarksBarMetrics.folderDropShare) / 2, dy: 0)
                if band.contains(NSPoint(x: p.x, y: band.midY)) { return .into(e.id) }
            }
        }
        let frames = shown.compactMap { views[$0.id]?.frame }.map { (x: Double($0.minX), width: Double($0.width)) }
        return .at(BookmarksBarLayout.insertionIndex(x: Double(p.x), frames: frames))
    }

    private func setDrop(_ new: Drop?) {
        guard new != drop else { return }
        if case .into(let id)? = drop { views[id]?.setDropTarget(false) }
        drop = new
        if case .into(let id)? = new {
            views[id]?.setDropTarget(true)
            if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        showDrop()
    }

    private func showDrop() {
        guard case .at(let index)? = drop else { dropLine.isHidden = true; return }
        let shown = model.entries.prefix(shownCount).filter { $0.id != ui.draggingID }.compactMap { views[$0.id]?.frame }
        let x: CGFloat = index < shown.count ? shown[index].minX - BookmarksBarMetrics.gap : (shown.last?.maxX ?? BookmarksBarMetrics.inset) + 1
        let h = BookmarksBarMetrics.item - 2 * Design.Space.xs
        dropLine.isHidden = false
        dropLine.frame = NSRect(x: max(Design.Space.xxs, x), y: ((bounds.height - h) / 2).rounded(), width: 2, height: h)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let d = resolve(sender)
        setDrop(d)
        return d == nil ? [] : .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDrop(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setDrop(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDrop(nil) }
        guard let id = draggedID(sender), let d = resolve(sender) else { return false }
        switch d {
        case .into(let folder):
            store.moveItem(id, to: folder, index: nil)
        case .at(let index):
            // The store takes the index in the list as it is now, the moved item still in it: right
            // after the item the drop follows, or the start.
            let others = model.entries.filter { $0.id != id }
            let kids = store.item(model.pinned)?.children ?? []
            let after = index > 0 && index <= others.count ? kids.firstIndex(of: others[index - 1].id) : nil
            store.moveItem(id, to: model.pinned, index: after.map { $0 + 1 } ?? 0)
        }
        if store.item(id)?.isTab == true { store.tookTab(id, into: ui.windowID) }
        if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted) }
        return true
    }

    /// `niche://debug?bookmarksBar=<label>`: what the bar shows, for scenarios.
    var readout: String {
        let folders = model.entries.filter { $0.kind == .folder }.count
        let selected = model.entries.firstIndex { $0.selected }.map(String.init) ?? "-"
        return "items=\(model.entries.count) folders=\(folders) shown=\(shownCount) selected=\(selected) hidden=\(isHidden ? 1 : 0)"
    }
}

/// One item of the bookmarks bar: a pinned tab, a pinned split or a folder.
@MainActor
final class BookmarkItemView: NSView, NSTextFieldDelegate {
    private weak var bar: BookmarksBarView?
    private var entry: BookmarksBarView.Entry?
    var colors = SidebarColors() { didSet { if colors != oldValue { refresh() } } }
    private let icon = SidebarFaviconView()
    private let glyph = StripImage()
    private let title = StripLabel.make(.detail)
    private let chevron = StripImage()
    private var field: NSTextField?
    private var hovering = false {
        didSet {
            guard hovering != oldValue else { return }
            refresh()
            // The window stays put while the pointer is on an item, so a press drags the item (StripItemView).
            bar?.ui.hoverTitleRowItem(dragGuard, hovering)
        }
    }
    private let dragGuard = UUID()
    private var dropTarget = false
    private var pressAt: NSPoint?
    private var dragged = false

    init(bar: BookmarksBarView) {
        self.bar = bar
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Design.Radius.inset
        layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleNone
        chevron.imageScaling = .scaleNone
        chevron.image = SidebarSymbols.image("chevron.down", size: Design.Icon.tiny, weight: .semibold)
        for v in [icon, glyph, title, chevron] as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }

    /// The whole item takes a press, not its label (StripItemView.hitTest); its rename field stays its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let field, hit === field || hit.isDescendant(of: field) { return hit }
        return self
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { bar?.ui.hoverTitleRowItem(dragGuard, false) }
    }

    /// Its icon, its name up to the bar's longest, and a folder's chevron.
    var fittingWidth: CGFloat {
        guard let e = entry else { return 0 }
        // The cell's own width: the label's intrinsic size is a point short of it, which cut the last letter.
        let text = min(BookmarksBarMetrics.maxText, ceil(title.cell?.cellSize.width ?? title.intrinsicContentSize.width))
        let tail = e.kind == .folder ? Design.Space.xs + Design.Icon.tiny : 0
        return BookmarksBarMetrics.pad + NicheMetrics.favicon + BookmarksBarMetrics.iconGap + text + tail + BookmarksBarMetrics.pad
    }

    func show(_ e: BookmarksBarView.Entry) {
        let old = entry
        guard old != e else { return }
        entry = e
        title.stringValue = e.title
        setAccessibilityLabel(e.title)
        let folder = e.kind == .folder
        icon.isHidden = folder
        glyph.isHidden = !folder
        chevron.isHidden = !folder
        if folder { glyph.image = e.icon.image } else { icon.show(e.icon.image, flip: e.icon.flip, colors: colors) }
        if e.editing != (old?.editing ?? false) { e.editing ? beginEditing() : endEditing() }
        refresh()
        needsLayout = true
        if old?.title != e.title { superview?.needsLayout = true }
    }

    func setDropTarget(_ on: Bool) {
        dropTarget = on
        refresh()
    }

    private func refresh() {
        guard let e = entry else { return }
        // A pinned tab whose page is open reads at full strength; one that is asleep, a step back.
        let ink = e.selected || hovering || e.loaded ? colors.textPrimary : colors.textSecondary
        title.textColor = ink
        glyph.contentTintColor = colors.textSecondary
        chevron.contentTintColor = colors.textTertiary
        if e.kind != .folder { icon.show(e.icon.image, flip: e.icon.flip, colors: colors) }
        let fill: NSColor = dropTarget ? Design.accentNS.withAlphaComponent(Design.Fill.strong.rawValue) : e.selected ? colors.plate(.selected) : hovering ? colors.plate(.hover) : .clear
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
        let h = bounds.height, side = NicheMetrics.favicon
        let iconFrame = NSRect(x: BookmarksBarMetrics.pad, y: ((h - side) / 2).rounded(), width: side, height: side)
        icon.frame = iconFrame
        glyph.frame = iconFrame
        let x = iconFrame.maxX + BookmarksBarMetrics.iconGap
        var right = bounds.width - BookmarksBarMetrics.pad
        if e.kind == .folder {
            right -= Design.Icon.tiny
            chevron.frame = NSRect(x: right, y: 0, width: Design.Icon.tiny, height: h)
            right -= Design.Space.xs
        }
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: x, y: ((h - th) / 2).rounded(), width: max(0, right - x), height: th)
        title.fadeTail()
        field?.frame = title.frame.insetBy(dx: -Design.Space.xxs, dy: 0)
    }

    func dragImage() -> NSImage {
        let size = bounds.size
        let rep = bitmapImageRepForCachingDisplay(in: bounds)
        if let rep { cacheDisplay(in: bounds, to: rep) }
        let fill = colors.plate(.strong)
        return NSImage(size: size, flipped: false) { r in
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: Design.Radius.inset, yRadius: Design.Radius.inset).fill()
            rep?.draw(in: r)
            return true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        let inside = window.map { visibleRect.intersection(bounds).contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if inside { options.insert(.assumeInside) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil))
        if hovering != inside { hovering = inside }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// Looks where the pointer is (StripItemView.syncHover).
    func syncHover() {
        let inside = window.map { !isHiddenOrHasHiddenAncestor && bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if hovering != inside { hovering = inside }
    }

    override func mouseDown(with event: NSEvent) {
        guard field == nil else { return }
        pressAt = event.locationInWindow
        dragged = false
        setPressedLook(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressAt, !dragged, let e = entry else { return }
        let here = event.locationInWindow
        guard hypot(here.x - start.x, here.y - start.y) > TabStripMetrics.dragSlop else { return }
        dragged = true
        setPressedLook(false)
        bar?.beginDrag(self, e, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        setPressedLook(false)
        defer { pressAt = nil }
        guard pressAt != nil, !dragged, let e = entry, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        bar?.open(e, from: self)
        hovering = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let e = entry, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return super.otherMouseUp(with: event)
        }
        bar?.close(e)
    }

    override func menu(for event: NSEvent) -> NSMenu? { entry.flatMap { bar?.menu(for: $0) } }

    override func accessibilityPerformPress() -> Bool {
        guard let e = entry else { return false }
        bar?.open(e, from: self)
        return true
    }

    // MARK: Renaming

    private func beginEditing() {
        guard field == nil, let e = entry else { return }
        let f = NSTextField(string: e.title)
        f.font = Design.Font.ns(.detail)
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
        bar?.rename(e, to: text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), let f = field, let e = entry {
            let text = f.stringValue
            endEditing()
            bar?.rename(e, to: text)
            return true
        }
        guard selector == #selector(NSResponder.cancelOperation(_:)), let e = entry else { return false }
        endEditing()
        bar?.rename(e, to: nil)
        return true
    }
}
