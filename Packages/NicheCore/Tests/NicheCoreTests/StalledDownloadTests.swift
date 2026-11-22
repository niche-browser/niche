import Foundation
import NicheCore
import Testing

/// Chromium stops reporting a download once the tab that started it is gone, so a row that hears
/// nothing for a while reads the disk. It read `<name>.crdownload` and `<name>`; a .dmg, .zip or .pkg
/// runs as Chromium's "Unconfirmed <n>.crdownload" while Safe Browsing checks it, so the row was
/// called cancelled mid-download, and Remove then trashed the finished file (review, 22 Nov 2026).
struct StalledDownloadTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func live(part: String, received: Int64 = 5, total: Int64 = 10) -> DownloadList.Live {
        var l = DownloadList.Live(id: 1, name: "setup.dmg", path: "/d/setup.dmg", started: now, received: received,
                                  total: total, percent: 50, updated: now)
        l.partPath = part
        return l
    }

    @Test func aPartUnderItsOwnNameIsStillComing() {
        let l = live(part: "/d/Unconfirmed 123.crdownload")
        #expect(StalledDownload.outcome(l, exists: { $0 == "/d/Unconfirmed 123.crdownload" }, size: { _ in nil }) == .running)
        let named = live(part: "/d/setup.dmg.crdownload")
        #expect(StalledDownload.outcome(named, exists: { $0 == "/d/setup.dmg.crdownload" }, size: { _ in nil }) == .running)
    }

    @Test func theWholeFileWithNoPartIsDone() {
        let l = live(part: "/d/Unconfirmed 123.crdownload")
        #expect(StalledDownload.outcome(l, exists: { $0 == "/d/setup.dmg" }, size: { _ in 10 }) == .complete)
    }

    /// Chromium's quiet spell while macOS marks a finished file took over 5 s on a busy Mac.
    @Test func waitsLongerThanChromiumsQuietSpells() {
        #expect(StalledDownload.quietFor >= 15)
    }

    @Test func nothingOnDiskMeansItEnded() {
        let l = live(part: "/d/Unconfirmed 123.crdownload")
        #expect(StalledDownload.outcome(l, exists: { _ in false }, size: { _ in nil }) == .cancelled)
    }

    /// A short file where it was going, and no part: not proof of anything, so it waits.
    @Test func aShortFileWaits() {
        let l = live(part: "/d/Unconfirmed 123.crdownload")
        #expect(StalledDownload.outcome(l, exists: { $0 == "/d/setup.dmg" }, size: { _ in 4 }) == .running)
    }

    /// Before Chromium says where the bytes are, the old rule: the target's own .crdownload.
    @Test func withoutAPartPathItLooksBesideTheFile() {
        let l = live(part: "")
        #expect(StalledDownload.outcome(l, exists: { $0 == "/d/setup.dmg.crdownload" }, size: { _ in nil }) == .running)
    }
}
