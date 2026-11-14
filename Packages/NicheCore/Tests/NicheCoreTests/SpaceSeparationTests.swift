import Foundation
import NicheCore
import Testing

/// A space keeps to itself and a profile keeps what it browsed (13 Nov 2026).
struct SpaceSeparationTests {
    private let work = UUID(), personal = UUID(), client = UUID()

    @Test func aVisitBelongsToItsProfile() {
        #expect(SpaceSeparation.listsVisit(on: nil, inSpaceOn: nil))
        #expect(SpaceSeparation.listsVisit(on: client, inSpaceOn: client))
        #expect(!SpaceSeparation.listsVisit(on: nil, inSpaceOn: client))
        #expect(!SpaceSeparation.listsVisit(on: client, inSpaceOn: nil))
        #expect(!SpaceSeparation.listsVisit(on: client, inSpaceOn: work))
    }

    /// Default keeps the key history.json always had; another profile's visit to the same page is its own entry.
    @Test func historyKeys() {
        let url = "https://mail.google.com/"
        #expect(SpaceSeparation.historyKey(url: url, profileID: nil) == url)
        #expect(SpaceSeparation.historyKey(url: url, profileID: client) != url)
        #expect(SpaceSeparation.historyKey(url: url, profileID: client) != SpaceSeparation.historyKey(url: url, profileID: work))
        #expect(SpaceSeparation.historyKey(url: url, profileID: client) == SpaceSeparation.historyKey(url: url, profileID: client))
    }

    @Test func anArchivedTabIsOfferedWhereItWasClosed() {
        #expect(SpaceSeparation.listsArchived(from: work, in: work))
        #expect(!SpaceSeparation.listsArchived(from: personal, in: work))
        // Its space was deleted: restoring opens it in the space in use.
        #expect(SpaceSeparation.listsArchived(from: nil, in: work))
    }
}
