import CoreGraphics
import Foundation

/// The bottom of the sidebar's column, over the Library button: the end of the tab list, the
/// sidebar player's cards (they rest where the list ends and grow over it on hover) and the
/// downloads list that hovering the Library button opens. Heights count from the top of the
/// column, as the sidebar lays out (flipped).
public struct SidebarBottom: Equatable, Sendable {
    /// Where the tab list ends: the player's resting cards take the room under it.
    public var listBottom: CGFloat
    /// The downloads list's frame, top to bottom (empty when there are no rows).
    public var trayTop: CGFloat
    public var trayBottom: CGFloat
    /// How far down the list keeps the pointer: to the Library button's top, so the gap between
    /// the button and the list is the list's (a slow move took longer to cross it than the list
    /// waits before closing, 22 Nov 2026).
    public var trayHoverBottom: CGFloat
    /// The player gives way to the open list: its cards fade with the tab list and don't open.
    public var playerGivesWay: Bool

    /// - Parameters:
    ///   - areaBottom: the bottom of the room the list and player share (above the update banner and the dock).
    ///   - playerRest: the room the player's resting cards take (0 with none).
    ///   - trayHeight: the downloads list's height with its rows (0 with none).
    ///   - trayOpen: whether the downloads list is open, or opening.
    ///   - buttonTop: the top of the Library button, under the list.
    public init(areaBottom: CGFloat, playerRest: CGFloat, trayHeight: CGFloat, trayOpen: Bool, buttonTop: CGFloat) {
        listBottom = areaBottom - playerRest
        // Right over the Library button, where the player rests: from the button to a row the
        // pointer never crosses the player (21 Nov 2026 it did, and its cards opened under the list).
        trayBottom = areaBottom
        trayTop = trayBottom - trayHeight
        trayHoverBottom = max(trayBottom, buttonTop)
        // While the list is open it owns the bottom: the player fades with the tab list behind it. A
        // list whose last row went (Clear, Remove) shows nothing, and the player comes back.
        playerGivesWay = trayOpen && trayHeight > 0
    }
}
