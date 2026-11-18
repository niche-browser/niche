import AppKit

/// What stands above the page when the tabs are across the top of the window (`WindowLayout.top`):
/// the tab strip in the title row, the toolbar with the address under it, and the bookmarks bar
/// under that. It sits on the window's own ground, the space's colour, so the three read as the
/// window's frame and the page as a card below them.
@MainActor
final class TopChromeView: NSView {
    let strip: TabStripView
    let toolbar: PaneToolbarView
    let bookmarks: BookmarksBarView
    private let store: SidebarStore
    /// The rows it shows changed height: the shell lays the window out again.
    var onHeightChange: (() -> Void)?

    /// Above the strip, so its centre is the title row's (`NicheMetrics.titleRowCenter`).
    static let topPad: CGFloat = NicheMetrics.titleRowCenter - TabStripMetrics.height / 2
    /// Under the last row, before the page's card.
    static let bottomPad: CGFloat = Design.Space.s
    /// The toolbar's inset from the window's edges.
    static let toolbarInset: CGFloat = Design.Space.s

    /// The traffic lights stand at the start of the strip: the window shows them and the sidebar
    /// doesn't (it carries them when it is out).
    var lightsInStrip = true {
        didSet { strip.leadingInset = lightsInStrip ? TabStripMetrics.lightsInset : TabStripMetrics.plainInset }
    }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        strip = TabStripView(store: store, ui: ui, actions: actions, favicons: favicons)
        toolbar = PaneToolbarView(paneTabID: nil, store: store, ui: ui, actions: actions)
        bookmarks = BookmarksBarView(store: store, ui: ui, actions: actions, favicons: favicons)
        super.init(frame: .zero)
        wantsLayer = true
        toolbar.onChrome = true
        toolbar.layer?.cornerRadius = Design.Radius.row
        toolbar.layer?.cornerCurve = .continuous
        toolbar.layer?.masksToBounds = true
        toolbar.onHeightChange = { [weak self] in self?.heightChanged() }
        bookmarks.onHasItemsChange = { [weak self] in self?.heightChanged() }
        strip.leadingInset = TabStripMetrics.lightsInset
        addSubview(strip)
        addSubview(toolbar)
        addSubview(bookmarks)
        observeChanges(of: { [weak store] in store?.settings.showBookmarksBar ?? true }) { [weak self] _ in self?.heightChanged() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    /// The gaps between the rows are the window's: a drag there moves it.
    override var mouseDownCanMoveWindow: Bool { true }

    private var showsBookmarks: Bool { store.settings.showBookmarksBar && bookmarks.hasItems }

    /// What the rows take, top padding to the page's card.
    var preferredHeight: CGFloat {
        Self.topPad + TabStripMetrics.height + toolbar.barHeight + (showsBookmarks ? Design.Space.xxs + BookmarksBarMetrics.height : 0) + Self.bottomPad
    }

    private func heightChanged() {
        needsLayout = true
        onHeightChange?()
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        var y = Self.topPad
        strip.frame = NSRect(x: 0, y: y, width: w, height: TabStripMetrics.height)
        y += TabStripMetrics.height
        toolbar.frame = NSRect(x: Self.toolbarInset, y: y, width: max(0, w - 2 * Self.toolbarInset), height: toolbar.barHeight)
        y += toolbar.barHeight
        bookmarks.isHidden = !showsBookmarks
        bookmarks.frame = NSRect(x: 0, y: y + Design.Space.xxs, width: w, height: BookmarksBarMetrics.height)
    }
}
