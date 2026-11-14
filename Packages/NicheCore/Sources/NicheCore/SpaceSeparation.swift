import Foundation

/// A space keeps to itself, and a profile keeps what it browsed. The command bar in a space offers
/// that space's open tabs (`SidebarStore.commandBarTabs`), the tabs archived from it, and the
/// history of its profile: picking a row never takes the window to another space, and a profile
/// never sees what another one visited. Reported 13 Nov 2026: in a new space, picking Google
/// went to the Google tab of the first space.
public enum SpaceSeparation {
    /// The key a visit is kept under. The Default profile's is the address alone, as history.json
    /// had it before visits knew their profile; a page visited on two profiles is two entries.
    public static func historyKey(url: String, profileID: UUID?) -> String {
        profileID.map { "\($0.uuidString)|\(url)" } ?? url
    }

    /// Whether a space on `spaceProfile` lists a visit made on `visitProfile` (nil is Default).
    public static func listsVisit(on visitProfile: UUID?, inSpaceOn spaceProfile: UUID?) -> Bool {
        visitProfile == spaceProfile
    }

    /// Whether a space lists an archived tab: one closed from it, or one whose space is gone
    /// (restoring that one opens it here; `sourceSpace` is nil for it).
    public static func listsArchived(from sourceSpace: UUID?, in space: UUID) -> Bool {
        sourceSpace == nil || sourceSpace == space
    }
}
