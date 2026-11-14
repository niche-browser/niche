import Foundation

/// Chromium's "<name> has been added to Chromium" bubble, shown after a Web Store install. It
/// hangs from a toolbar Niche doesn't show, so it opened half off the screen's top-left corner and
/// stayed there (13 Nov 2026), and it sends people to a Window menu item Niche doesn't have.
/// Niche says "Added <name>" itself (`ExtensionInstallNotice`), so this bubble is closed.
public enum ChromiumAddedBubble {
    /// The engine's name, which Chromium puts in the bubble's title in every language.
    public static let engineName = "Chromium"

    /// Whether a Chromium window is that bubble: a titled window with no parent whose title names
    /// an installed extension and, outside that name, the engine. The install prompt ("Add …?")
    /// names the extension only; dialogs hung from a page have a parent.
    public static func matches(title: String, titled: Bool, hasParent: Bool, extensionNames: [String]) -> Bool {
        guard titled, !hasParent, !title.isEmpty else { return false }
        return extensionNames.contains { name in
            !name.isEmpty && title.contains(name) && title.replacingOccurrences(of: name, with: "").contains(engineName)
        }
    }
}
