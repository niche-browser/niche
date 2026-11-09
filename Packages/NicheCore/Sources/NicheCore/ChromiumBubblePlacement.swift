import CoreGraphics

/// Where a Chromium bubble that hangs off the screen goes. Chromium anchors some bubbles (the
/// "extension added" one after a Web Store install) to the page's hidden toolbar, whose screen
/// position is the screen's corner: the bubble sat half off the left edge. Chromium fits the
/// bubbles it places itself on a screen, so one that is not fully on any screen is moved inside
/// its Niche window; every other bubble (menus, autofill, tooltips) stays where Chromium put it.
public enum ChromiumBubblePlacement {
    /// The bubble's new frame, or nil to leave it. All rects in the same (screen) coordinates.
    public static func frame(for bubble: CGRect, window: CGRect, screens: [CGRect], inset: CGFloat = 8) -> CGRect? {
        guard !bubble.isEmpty, !screens.contains(where: { $0.contains(bubble) }) else { return nil }
        var r = bubble
        r.origin.x = max(window.minX + inset, min(r.minX, window.maxX - inset - r.width))
        r.origin.y = max(window.minY + inset, min(r.minY, window.maxY - inset - r.height))
        return r == bubble ? nil : r
    }
}
