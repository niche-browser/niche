import Foundation

/// Which profile a space is on. Spaces on the same profile share their logins, cookies,
/// passwords, extensions and history; a space on its own profile shares nothing.
///
/// A new space follows Dia's Create Profile (Dia 1.57.1, looked at on 13 Nov 2026): it keeps its
/// own data unless "Share data with current space" is turned on, which is off to start with.
/// Arc (1.171) and Niche until then put every new space on the profile of the space it was made
/// from, so a new space opened Google signed in to the first space's account.
public enum SpaceProfiles {
    /// Whether the New Space sheet starts with "Share data with current space" on.
    public static let newSpaceSharesData = false

    /// The profile a new space is made on.
    public enum NewSpace: Equatable, Sendable {
        /// A new profile made with the space, named by `newProfileName`.
        case ownProfile
        /// An existing profile; nil is Default.
        case profile(UUID?)
    }

    /// - Parameters:
    ///   - sharing: the sheet's "Share data with current space".
    ///   - focused: the space the sheet was opened from, the one to share with.
    public static func forNewSpace(sharing: Bool, from focused: Space?, profiles: [BrowserProfile]) -> NewSpace {
        guard sharing else { return .ownProfile }
        // A profile that is gone is Default.
        guard let id = focused?.profileID, profiles.contains(where: { $0.id == id }) else { return .profile(nil) }
        return .profile(id)
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
