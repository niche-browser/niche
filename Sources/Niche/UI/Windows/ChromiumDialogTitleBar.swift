import AppKit

/// Applies `ChromiumDialogFrame` to every window as it appears: Chromium's buttonless dialogs
/// get a full-size, transparent title bar so nothing covers their top edge. Bubbles Chromium
/// left off the screen are moved into their window (`ChromiumBubblePlacement`).
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

    private static func placeBubble(_ w: NSWindow) {
        // Extension popups wait transparent until ExtensionActions frames them.
        // A framed extension popup moves with its frame, which the user may drag partly off screen.
        guard w.isVisible, w.alphaValue > 0, !w.styleMask.contains(.titled), !(w is NSPanel),
              !(w.parent is ExtensionPopupWindow), NSStringFromClass(type(of: w)) == "NativeWidgetMacNSWindow" else { return }
        var owner = w.parent
        while let up = owner?.parent { owner = up }
        guard let owner = owner ?? NSApp.mainWindow,
              let frame = ChromiumBubblePlacement.frame(for: w.frame, window: owner.frame,
                                                        screens: NSScreen.screens.map(\.frame)) else { return }
        NicheLog.note("bubble \(w.windowNumber) moved into its window: \(Int(w.frame.width))x\(Int(w.frame.height)) at \(Int(w.frame.minX)),\(Int(w.frame.minY)) parent=\(w.parent?.windowNumber ?? -1) key=\(w.isKeyWindow)")
        w.setFrame(frame, display: true)
    }
}
