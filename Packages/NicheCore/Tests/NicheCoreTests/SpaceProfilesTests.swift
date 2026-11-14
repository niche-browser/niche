import NicheCore
import Foundation
import Testing

/// A new space keeps its own data unless it is told to share the current space's, as Dia's
/// Create Profile does ("Share data with current profile", off by default; Dia 1.57.1, 13 Nov
/// 2026). Before, a new space opened Google signed in to the first space's account.
struct SpaceProfilesTests {
    private func space(profile: UUID?) -> Space {
        Space(id: UUID(), title: "S", emoji: "🌱", theme: SpaceTheme.presets[0], favoritesContainerID: UUID(),
              pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: Date(), profileID: profile)
    }

    @Test func sharingIsOffUntilAsked() {
        #expect(!SpaceProfiles.newSpaceSharesData)
    }

    @Test func aNewSpaceGetsItsOwnProfileWhateverSpaceItIsMadeFrom() {
        let work = BrowserProfile(id: UUID(), name: "Work")
        #expect(SpaceProfiles.forNewSpace(sharing: false, from: space(profile: nil), profiles: [work]) == .ownProfile)
        #expect(SpaceProfiles.forNewSpace(sharing: false, from: space(profile: work.id), profiles: [work]) == .ownProfile)
        #expect(SpaceProfiles.forNewSpace(sharing: false, from: nil, profiles: []) == .ownProfile)
    }

    @Test func aSharingSpaceJoinsTheCurrentSpacesProfile() {
        let work = BrowserProfile(id: UUID(), name: "Work")
        #expect(SpaceProfiles.forNewSpace(sharing: true, from: space(profile: work.id), profiles: [work]) == .profile(work.id))
        #expect(SpaceProfiles.forNewSpace(sharing: true, from: space(profile: nil), profiles: [work]) == .profile(nil), "Default stays Default")
        // A profile that is gone is Default, and so is no space to share with.
        #expect(SpaceProfiles.forNewSpace(sharing: true, from: space(profile: UUID()), profiles: []) == .profile(nil))
        #expect(SpaceProfiles.forNewSpace(sharing: true, from: nil, profiles: [work]) == .profile(nil))
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
