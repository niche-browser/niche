import Foundation

/// "Quit Niche?" is asked once per quit. A quit that arrives as an Apple Event (the Dock's Quit,
/// logout, a script) reaches the delegate twice: AppKit asks `applicationShouldTerminate` itself,
/// then calls `terminate:`, where Niche asks again before it closes Chromium's browsers. Reported
/// 13 Nov 2026: Quit had to be clicked twice.
public struct QuitConfirmation: Equatable, Sendable {
    /// The user picked Quit: this quit is under way and is not asked about again.
    public private(set) var agreed = false

    public init() {}

    /// Whether to show the dialog now. An update or engine relaunch never asks.
    public func asks(warnBeforeQuitting: Bool, relaunching: Bool) -> Bool {
        warnBeforeQuitting && !relaunching && !agreed
    }

    /// The dialog's answer. Cancel leaves the next quit to ask again.
    public mutating func answered(quit: Bool) {
        agreed = quit
    }
}
