import AppKit

extension NSView {
    /// The part of the view that shows: its visible rect, kept within its bounds. A view that
    /// doesn't clip (AppKit's default since macOS 14) reports a visible rect as large as the window,
    /// so asking that whether the pointer is on the view answers yes anywhere in the window
    /// (`unbounded-visible-rect` in scripts/lint.py).
    /// Nothing shows of a hidden view, or one under a hidden ancestor (the Library page over the tab list).
    var shownPart: NSRect { isHiddenOrHasHiddenAncestor ? .zero : visibleRect.intersection(bounds) }

    /// Whether the pointer is on the part of the view that shows, in this view's coordinates.
    func shownPartContains(_ point: NSPoint) -> Bool { shownPart.contains(point) }

    /// Whether the pointer is on the part of the view that shows now (false outside a window).
    var pointerIsOnShownPart: Bool {
        guard let window, window.isVisible else { return false }
        return shownPartContains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}
