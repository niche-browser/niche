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

    /// Chromium's extension dialogs ("Add …?", "… has been added", "Remove …?") hang from the
    /// page's hidden toolbar, whose buttons all sit at the page's top-left corner: some went off the
    /// screen's left edge, others dropped over the page's top left. A dialog hanging there (its top
    /// within `band` of the page's top, its left edge left of `page.minX + reach`: Chrome's toolbar
    /// puts back, forward, reload and home before the extensions area, so "Remove …?" sat 172 pt in) opens at the
    /// page's top right instead, where Chrome's extensions button is. Nil leaves it.
    public static func toolbarDialogFrame(for bubble: CGRect, page: CGRect, inset: CGFloat = 10,
                                          band: CGFloat = 72, reach: CGFloat = 240) -> CGRect? {
        guard !bubble.isEmpty, !page.isEmpty,
              bubble.maxY <= page.maxY + 4, bubble.maxY >= page.maxY - band,
              bubble.minX < page.minX + reach,
              // A site's alert() hangs from the page's top too, but centred on it.
              abs(bubble.midX - page.midX) > 24 else { return nil }
        let x = max(page.minX, page.maxX - inset - bubble.width)
        let r = CGRect(x: x, y: page.maxY - inset - bubble.height, width: bubble.width, height: bubble.height)
        return r == bubble ? nil : r
    }
}
