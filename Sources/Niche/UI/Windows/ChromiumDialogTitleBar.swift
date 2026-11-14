import AppKit
import NicheCEF

/// Applies `ChromiumDialogFrame` to every window as it appears: Chromium's buttonless dialogs
/// get a full-size, transparent title bar so nothing covers their top edge. Dialogs hung from the
/// page's hidden toolbar open at the page's top right, and other bubbles Chromium left off the
/// screen move into their window (`ChromiumBubblePlacement`). Chromium's "… has been added"
/// bubble is closed: Niche says it (`ChromiumAddedBubble`).
@MainActor
enum ChromiumDialogTitleBar {
    static func install() {
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { (note.object as? NSWindow).map(fix) }
            }
        }
        // Chromium re-anchors a bubble to its hidden toolbar whenever the bubble resizes (its icon
        // and text lay out after it shows) or the page's window moves (Niche lays the page out
        // again when the extension lands in the toolbar). Placed only when it first showed, the
        // "extension added" bubble went back off the screen's left edge a moment later.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { (note.object as? NSWindow).map(placeBubble) }
            }
        }
    }

    static func fix(_ w: NSWindow) {
        placeBubble(w)
        let mask = w.styleMask
        let window = ChromiumDialogFrame.Window(
            className: NSStringFromClass(type(of: w)), titled: mask.contains(.titled),
            hasWindowButtons: !mask.intersection([.closable, .miniaturizable]).isEmpty,
            titlebarTransparent: w.titlebarAppearsTransparent, fullSizeContent: mask.contains(.fullSizeContentView))
        guard ChromiumDialogFrame.needsFix(window) else { return }
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(type)?.isHidden = true }
    }

    /// Closes Chromium's "<name> has been added to Chromium" bubble (`ChromiumAddedBubble`): it
    /// opens half off the screen's top-left corner and stays there, and Niche's own "Added <name>"
    /// toast says it. True when `w` is that bubble.
    @discardableResult
    private static func closeAddedBubble(_ w: NSWindow) -> Bool {
        guard w.isVisible, NSStringFromClass(type(of: w)) == "NativeWidgetMacNSWindow",
              ChromiumAddedBubble.matches(title: w.title, titled: w.styleMask.contains(.titled), hasParent: w.parent != nil,
                                          extensionNames: ExtensionStore.shared.entries.map(\.name)) else { return false }
        // Out of sight now; closed after this notification, which may be about the window itself.
        w.alphaValue = 0
        DispatchQueue.main.async { [weak w] in
            guard let w, w.isVisible else { return }
            NicheLog.note("bubble \(w.windowNumber) closed: Chromium's extension added bubble")
            w.close()
        }
        return true
    }

    /// The bubble can show before Niche has read the new extension's name: look again once it has.
    static func closeAddedBubbles() {
        for w in NSApp.windows { closeAddedBubble(w) }
    }

    private static func placeBubble(_ w: NSWindow) {
        if closeAddedBubble(w) { return }
        // Extension popups wait transparent until ExtensionActions frames them; a framed one moves
        // with its frame, which the user may drag partly off screen.
        guard w.isVisible, w.alphaValue > 0, !(w is NSPanel), !(w.parent is ExtensionPopupWindow),
              NSStringFromClass(type(of: w)) == "NativeWidgetMacNSWindow" else { return }
        // Chromium's "… has been added" is a titled window with no parent (shown centred, then
        // moved off the screen's left edge); "Remove …?" a child of the page's window.
        let host = w.parent.flatMap { NicheCEFRuntime.isPageWindow($0) ? $0 : nil }
        guard host != nil || w.parent == nil || !w.styleMask.contains(.titled) else { return }
        var owner = w.parent
        while let up = owner?.parent { owner = up }
        guard let owner = owner ?? frontBrowserWindow() else { return }
        // A dialog hung from the page's hidden toolbar (it takes keys; select lists and autofill
        // don't) opens at the page's top right; any other bubble off every screen moves into the
        // window.
        var frame: NSRect?
        if w.canBecomeKey, let page = (host ?? focusedPageWindow(in: owner))?.frame.intersection(owner.frame), !page.isEmpty {
            frame = ChromiumBubblePlacement.toolbarDialogFrame(for: w.frame, page: page)
        }
        if frame == nil, !w.styleMask.contains(.titled) {
            frame = ChromiumBubblePlacement.frame(for: w.frame, window: owner.frame, screens: NSScreen.screens.map(\.frame))
        }
        guard let frame else { return }
        NicheLog.note("bubble \(w.windowNumber) placed: \(Int(w.frame.width))x\(Int(w.frame.height)) from \(Int(w.frame.minX)),\(Int(w.frame.minY)) to \(Int(frame.minX)),\(Int(frame.minY))")
        w.setFrame(frame, display: true)
    }

    /// The browser window in front (a parentless dialog is the key window itself).
    private static func frontBrowserWindow() -> NSWindow? {
        NSApp.orderedWindows.first { $0.windowController is MainWindowController }
    }

    /// The visible page window over the browser window's focused page.
    private static func focusedPageWindow(in owner: NSWindow) -> NSWindow? {
        (owner.windowController as? MainWindowController)?.browsers.visibleRuntime?.hostWindow
            ?? owner.childWindows?.first { $0.isVisible && NicheCEFRuntime.isPageWindow($0) }
    }
}
