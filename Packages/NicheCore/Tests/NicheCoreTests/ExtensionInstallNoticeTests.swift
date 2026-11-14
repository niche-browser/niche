import NicheCore
import Testing

/// An installed extension is announced, once (13 Nov 2026: nothing changed after an install).
struct ExtensionInstallNoticeTests {
    @Test func aNewExtensionIsAnnounced() {
        #expect(ExtensionInstallNotice.added(before: ["a", "b"], after: ["a", "c", "b"], firstRead: false) == ["c"])
        #expect(ExtensionInstallNotice.added(before: [], after: ["a", "b"], firstRead: false) == ["a", "b"])
    }

    @Test func theOnesThereAtLaunchAreNot() {
        #expect(ExtensionInstallNotice.added(before: [], after: ["a", "b"], firstRead: true) == [])
    }

    @Test func removingOrKeepingAnnouncesNothing() {
        #expect(ExtensionInstallNotice.added(before: ["a", "b"], after: ["a"], firstRead: false) == [])
        #expect(ExtensionInstallNotice.added(before: ["a", "b"], after: ["b", "a"], firstRead: false) == [])
    }

    @Test func words() {
        #expect(ExtensionInstallNotice.message(name: "Dark Reader") == "Added Dark Reader")
    }
}
