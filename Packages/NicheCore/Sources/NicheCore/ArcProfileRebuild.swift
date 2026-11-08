import Foundation

/// Settings ▸ Profiles ▸ Rebuild from Arc (GitHub #131): an import from before Niche kept Arc's
/// profiles left every space on Default. This finds the spaces to move back onto the profile
/// their Arc space is on, matched by name, since ids differ between the browsers.
public enum ArcProfileRebuild {
    public struct NicheSpace: Equatable, Sendable {
        public var id: UUID
        public var title: String
        /// On Default and not incognito: the only spaces a rebuild moves. One already on a
        /// profile was put there by hand.
        public var movable: Bool

        public init(id: UUID, title: String, movable: Bool) {
            self.id = id
            self.title = title
            self.movable = movable
        }
    }

    public struct ArcSpace: Equatable, Sendable {
        public var title: String
        /// Arc's profile folder ("Profile 2"); nil for Default.
        public var folder: String?
        /// The profile's name in Arc.
        public var name: String

        public init(title: String, folder: String?, name: String) {
            self.title = title
            self.folder = folder
            self.name = name
        }
    }

    public struct Move: Equatable, Sendable {
        public var spaceID: UUID
        public var spaceTitle: String
        public var folder: String
        public var profileName: String
    }

    /// The Niche spaces to put on an Arc profile: a movable space whose name (any case) is one Arc
    /// space's, when that space is on a profile other than Default. A name Arc uses on more than
    /// one profile, or Niche on more than one space, says nothing about which is which: skipped.
    public static func moves(niche: [NicheSpace], arc: [ArcSpace]) -> [Move] {
        let arcByTitle = Dictionary(grouping: arc) { $0.title.lowercased() }
        let nicheCount = Dictionary(grouping: niche) { $0.title.lowercased() }.mapValues(\.count)
        return niche.compactMap { space in
            let key = space.title.lowercased()
            guard space.movable, nicheCount[key] == 1, let matches = arcByTitle[key],
                  Set(matches.map(\.folder)).count == 1, let match = matches.first, let folder = match.folder else { return nil }
            return Move(spaceID: space.id, spaceTitle: space.title, folder: folder, profileName: match.name)
        }
    }
}
