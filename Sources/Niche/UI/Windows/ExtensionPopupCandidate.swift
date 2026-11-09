import AppKit

/// Restrict the native-window fallback to Chromium bubbles in the requesting page.
/// This is still a native ownership check, not a protocol target-to-window mapping.
enum ExtensionPopupCandidate {
    @MainActor
    static func matches(_ window: NSWindow, owner: NSWindow?, sourceHost: NSWindow?,
                        isPageHost: (NSWindow) -> Bool) -> Bool {
        guard let owner, owner.isVisible, window.isVisible, window.frame.width > 1,
              !window.styleMask.contains(.titled), !(window is NSPanel),
              NSStringFromClass(type(of: window)) == "NativeWidgetMacNSWindow",
              let host = window.parent, isPageHost(host), host.parent === owner else { return false }
        return sourceHost == nil || host === sourceHost
    }

    /// A window Chrome has created but not shown yet that can turn out to be the popup's bubble
    /// (kept transparent until it is framed). Its parent is only set once it is shown.
    @MainActor
    static func mayBecomePopup(_ window: NSWindow) -> Bool {
        !window.isVisible && !window.styleMask.contains(.titled) && !(window is NSPanel)
            && NSStringFromClass(type(of: window)) == "NativeWidgetMacNSWindow"
    }

    /// Whether the anchor belongs to this window. Edges count: with the toolbar hidden the popup
    /// hangs from the page's top edge, which is the window's own top edge, and NSRect.contains
    /// leaves that edge out (the popup then stayed unframed, without a way to close it).
    static func window(_ frame: NSRect, holds anchor: NSPoint) -> Bool {
        frame.insetBy(dx: -1, dy: -1).contains(anchor)
    }
}
