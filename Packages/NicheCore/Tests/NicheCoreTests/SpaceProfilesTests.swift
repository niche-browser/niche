import NicheCore
import Foundation
import Testing

/// A new space starts on a profile of its own (owner, 13 Nov 2026: a new space opened Google
/// signed in to the first space's account). Sharing a profile is a choice made in the sheet.
struct SpaceProfilesTests {
    private func space(profile: UUID?) -> Space {
        Space(id: UUID(), title: "S", emoji: "🌱", theme: SpaceTheme.presets[0], favoritesContainerID: UUID(),
              pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: Date(), profileID: profile)
    }

    @Test func aNewSpaceGetsItsOwnProfileWhateverSpaceItIsMadeFrom() {
        let work = BrowserProfile(id: UUID(), name: "Work")
        #expect(SpaceProfiles.forNewSpace(from: space(profile: nil), profiles: [work]) == .ownProfile)
        #expect(SpaceProfiles.forNewSpace(from: space(profile: work.id), profiles: [work]) == .ownProfile)
        #expect(SpaceProfiles.forNewSpace(from: nil, profiles: []) == .ownProfile)
    }

    @Test func theProfileIsNamedAfterTheSpace() {
        #expect(SpaceProfiles.newProfileName(spaceTitle: "Work", taken: []) == "Work")
        #expect(SpaceProfiles.newProfileName(spaceTitle: "  Music ", taken: ["Work"]) == "Music")
        // Before the space has a name.
        #expect(SpaceProfiles.newProfileName(spaceTitle: "", taken: []) == "Space")
    }

    @Test func aTakenNameGetsANumber() {
        #expect(SpaceProfiles.newProfileName(spaceTitle: "Work", taken: ["Work"]) == "Work 2")
        #expect(SpaceProfiles.newProfileName(spaceTitle: "work", taken: ["Work", "Work 2"]) == "work 3")
        // "Default" is the profile every space was on.
        #expect(SpaceProfiles.newProfileName(spaceTitle: "Default", taken: []) == "Default 2")
    }
}
