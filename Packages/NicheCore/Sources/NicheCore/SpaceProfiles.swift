import Foundation

/// Which profile a space is on. Spaces on the same profile share their sign-ins, cookies and
/// site data; a space on its own profile shares nothing.
///
/// Arc (1.171, watched in a fresh copy, 3 Nov 2026) puts every new space on the profile of the
/// space it was made from, so a new space opened Google signed in to the first space's account.
/// Niche did the same until 13 Nov 2026, when the owner decided a space must not carry anything
/// over unasked: a new space now starts on a profile of its own, and sharing one is picked in
/// the New Space sheet.
public enum SpaceProfiles {
    /// What the New Space sheet starts on.
    public enum NewSpace: Equatable, Sendable {
        /// A new profile made with the space, named by `newProfileName`.
        case ownProfile
    }

    /// The same for every space it is made from, a space on another profile included.
    public static func forNewSpace(from focused: Space?, profiles: [BrowserProfile]) -> NewSpace {
        .ownProfile
    }

    /// The new profile's name: the space's, with a number when a profile has it already
    /// ("Default" counts: it is the profile spaces were on before).
    public static func newProfileName(spaceTitle: String, taken: [String]) -> String {
        let name = spaceTitle.trimmingCharacters(in: .whitespaces)
        let base = name.isEmpty ? "Space" : name
        let used = Set((taken + ["Default"]).map { $0.lowercased() })
        guard used.contains(base.lowercased()) else { return base }
        var n = 2
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
