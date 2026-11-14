import Foundation

/// What Niche says when an extension arrives. Chrome's own "… has been added" bubble hangs from a
/// toolbar Niche doesn't show, and with the toolbar hidden the new extension was nowhere to be
/// seen: nothing changed in the window after an install (13 Nov 2026). Niche answers with a toast
/// that offers to pin it.
public enum ExtensionInstallNotice {
    /// The extensions to announce: those in `after` that `before` didn't have, in `after`'s order.
    /// The first read of a launch announces nothing (they were there already), and neither does an
    /// extension that only changed (turned on or off, updated).
    public static func added(before: [String], after: [String], firstRead: Bool) -> [String] {
        guard !firstRead else { return [] }
        let had = Set(before)
        return after.filter { !had.contains($0) }
    }

    /// The toast's words.
    public static func message(name: String) -> String { "Added \(name)" }
}
