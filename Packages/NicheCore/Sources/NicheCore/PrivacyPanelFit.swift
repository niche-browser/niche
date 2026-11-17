import Foundation

/// Whether the privacy panel fits beside the page, and what a window lacks when it doesn't. The
/// panel is opened to be read, so a window too narrow for it grows by what is missing (as far as
/// the screen allows) instead of opening a panel nobody can see (17 Nov 2026: a 1010 pt window
/// showed the shield lit and no panel).
public enum PrivacyPanelFit {
    /// The narrowest a single page gets beside the panel: a phone's width, which pages lay out for.
    public static let minimumPageWidth: Double = 320

    /// What the panes need beside the panel: one page its minimum, split panes each theirs.
    public static func pageMinimum(panes: Int, paneMinimum: Double, gap: Double, sideBySide: Bool) -> Double {
        guard sideBySide, panes > 1 else { return minimumPageWidth }
        return max(minimumPageWidth, Double(panes) * paneMinimum + Double(panes - 1) * gap)
    }

    /// Whether a content area `content` wide has room for the panel and its gap beside the pages.
    public static func fits(content: Double, panel: Double, gap: Double, pages: Double) -> Bool {
        shortfall(content: content, panel: panel, gap: gap, pages: pages) == 0
    }

    /// How much wider the content area must be for the panel to fit; 0 when it does.
    public static func shortfall(content: Double, panel: Double, gap: Double, pages: Double) -> Double {
        max(0, (panel + gap + pages - content).rounded(.up))
    }

    /// The window's frame (x and width) grown by `shortfall` inside the screen's `visible` span:
    /// to the right while there is room, then to the left, never past the screen.
    public static func grown(x: Double, width: Double, by shortfall: Double, visibleMinX: Double, visibleMaxX: Double) -> (x: Double, width: Double) {
        guard shortfall > 0 else { return (x, width) }
        let wanted = min(width + shortfall, visibleMaxX - visibleMinX)
        let left = max(visibleMinX, min(x, visibleMaxX - wanted))
        return (left, wanted)
    }
}
