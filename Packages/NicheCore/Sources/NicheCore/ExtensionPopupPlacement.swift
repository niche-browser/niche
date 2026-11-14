import CoreGraphics

/// Where an extension's popup opens. It hangs from its button: right edge on the button's right
/// edge, as Chrome anchors popups. A button in the sidebar (a pinned extension with the toolbar
/// hidden) sits near the window's left edge, and a popup wider than what is left of it went out of
/// the window, over the desktop or off the screen (13 Nov 2026: "the popup goes to the left and
/// is cropped"). It then slides right until it is inside the window, still under its button's
/// row; a popup wider than the window, or dragged, only has to stay on the screen.
public enum ExtensionPopupPlacement {
    /// Clear space kept between the popup and the window's or screen's edge.
    public static let margin: CGFloat = 8

    /// The popup's left edge. `anchorX` is the button's right edge, `dragged` how far the user
    /// moved this popup; `window` and `screen` are x ranges in the same (screen) coordinates.
    public static func minX(anchorX: CGFloat, width: CGFloat, dragged: CGFloat = 0,
                            window: ClosedRange<CGFloat>?, screen: ClosedRange<CGFloat>?) -> CGFloat {
        var x = anchorX - width + dragged
        // Inside the window, when it was not dragged and the window has room for it.
        if dragged == 0, let window, window.upperBound - window.lowerBound >= width + 2 * margin {
            x = min(max(x, window.lowerBound + margin), window.upperBound - margin - width)
        }
        if let screen {
            x = max(min(x, screen.upperBound - margin - width), screen.lowerBound + margin)
        }
        return x
    }
}
