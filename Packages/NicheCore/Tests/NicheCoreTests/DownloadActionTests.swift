import NicheCore
import Foundation
import Testing

/// A download can be paused, resumed, cancelled, tried again and taken off the list from its row
/// (14 Nov 2026: rows had no controls at all).
struct DownloadActionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aRunningDownloadCanBeHeldOrStopped() {
        let state = DownloadRow.State.downloading(received: 1, total: 10, bytesPerSecond: nil)
        #expect(DownloadAction.buttons(for: state) == [.pause, .cancel])
        #expect(DownloadAction.menu(for: state, hasLink: true) == [[.pause, .cancel], [.copyLink]])
    }

    @Test func aPausedDownloadCanCarryOnOrStop() {
        let state = DownloadRow.State.paused(received: 1, total: 10)
        #expect(DownloadAction.buttons(for: state) == [.resume, .cancel])
        #expect(DownloadAction.menu(for: state, hasLink: false) == [[.resume, .cancel]])
    }

    @Test(arguments: [DownloadRow.State.failed, .cancelled])
    func aStoppedDownloadCanBeTriedAgainOrDismissed(state: DownloadRow.State) {
        #expect(DownloadAction.buttons(for: state) == [.retry, .remove])
        #expect(DownloadAction.menu(for: state, hasLink: true) == [[.retry], [.copyLink], [.remove]])
    }

    @Test func aFinishedFileCanBeFoundRemovedOrTrashed() {
        let state = DownloadRow.State.finished(at: now)
        #expect(DownloadAction.buttons(for: state) == [.showInFinder, .remove])
        #expect(DownloadAction.menu(for: state, hasLink: true) == [[.open, .showInFinder], [.copyFile, .copyLink], [.remove, .moveToTrash]])
        #expect(DownloadAction.menu(for: state, hasLink: false) == [[.open, .showInFinder], [.copyFile], [.remove, .moveToTrash]])
    }

    @Test func everyActionHasWordsAndASymbol() {
        for action in DownloadAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.symbol.isEmpty)
        }
        #expect(DownloadAction.cancel.title == "Cancel Download")
        #expect(DownloadAction.retry.title == "Try Again")
    }

    @Test func clearKeepsWhatIsStillComing() {
        var running = DownloadList.Live(id: 1, name: "a.zip", path: "/d/a.zip", started: now, received: 1, total: 9, percent: 11, updated: now)
        var paused = running, failed = running, cancelled = running
        running.url = "https://example.com/a.zip"
        paused = DownloadList.Live(id: 2, name: "b.zip", path: "/d/b.zip", started: now, received: 1, total: 9, percent: 11, updated: now)
        paused.paused = true
        failed = DownloadList.Live(id: 3, name: "c.zip", path: "/d/c.zip", started: now, received: 1, total: 9, percent: 11, updated: now)
        failed.failed = true
        cancelled = DownloadList.Live(id: 4, name: "d.zip", path: "", started: now, received: 0, total: 9, percent: 0, updated: now)
        cancelled.cancelled = true
        let entries = [DownloadList.Entry(id: UUID(), path: "/d/done.pdf", date: now)]
        let after = DownloadList.cleared(entries: entries, live: [running, paused, failed, cancelled])
        #expect(after.entries.isEmpty)
        #expect(after.live.map(\.id) == [1, 2])
    }

    @Test func clearIsOfferedOnlyWhenSomethingWouldGo() {
        var running = DownloadList.Live(id: 1, name: "a.zip", path: "/d/a.zip", started: now, received: 1, total: 9, percent: 11, updated: now)
        #expect(!DownloadList.canClear(entries: [], live: [running]) { _ in true })
        running.failed = true
        #expect(DownloadList.canClear(entries: [], live: [running]) { _ in true })
        let entry = DownloadList.Entry(id: UUID(), path: "/d/done.pdf", date: now)
        #expect(DownloadList.canClear(entries: [entry], live: []) { _ in true })
        // A file deleted since isn't listed, so there is nothing to clear.
        #expect(!DownloadList.canClear(entries: [entry], live: []) { _ in false })
    }

    /// 14 Nov 2026: Chromium's report of a cancelled download has no file name or path any more,
    /// and the row went blank.
    @Test func aCancelledDownloadKeepsItsName() {
        var live = DownloadList.Live(id: 1, name: "ubuntu.iso", path: "/d/ubuntu.iso", started: now, received: 5, total: 10, percent: 50, updated: now)
        live.take(name: "", path: "", url: "", received: 0, total: 0, percent: 0, failed: false, cancelled: true, paused: false,
                  now: now.addingTimeInterval(1))
        #expect(live.name == "ubuntu.iso")
        #expect(live.path == "/d/ubuntu.iso")
        #expect(live.row == .cancelled)
        // What it had reached stays too: a cancelled row can still say how far it got.
        #expect(live.received == 5)
        #expect(live.total == 10)
    }

    @Test func reportsMeasureTheSpeedAndAPauseForgetsIt() {
        var live = DownloadList.Live(id: 1, name: "a.zip", path: "", started: now, received: 0, total: 10_000, percent: 0, updated: now)
        live.take(name: "a.zip", path: "/d/a.zip", url: "https://example.com/a.zip", received: 0, total: 10_000, percent: 0,
                  failed: false, cancelled: false, paused: false, now: now)
        #expect(live.bytesPerSecond == nil)
        live.take(name: "a.zip", path: "", url: "", received: 2_000, total: 10_000, percent: 20,
                  failed: false, cancelled: false, paused: false, now: now.addingTimeInterval(2))
        #expect(live.bytesPerSecond == 1_000)
        #expect(live.path == "/d/a.zip")
        #expect(live.url == "https://example.com/a.zip")
        #expect(live.updated == now.addingTimeInterval(2))
        live.take(name: "a.zip", path: "", url: "", received: 2_000, total: 10_000, percent: 20,
                  failed: false, cancelled: false, paused: true, now: now.addingTimeInterval(3))
        #expect(live.bytesPerSecond == nil)
        #expect(live.row == .paused(received: 2_000, total: 10_000))
        // Resumed: the speed is measured afresh, not from before the pause.
        live.take(name: "a.zip", path: "", url: "", received: 2_000, total: 10_000, percent: 20,
                  failed: false, cancelled: false, paused: false, now: now.addingTimeInterval(60))
        #expect(live.bytesPerSecond == nil)
        live.take(name: "a.zip", path: "", url: "", received: 4_000, total: 10_000, percent: 40,
                  failed: false, cancelled: false, paused: false, now: now.addingTimeInterval(61))
        #expect(live.bytesPerSecond == 2_000)
    }

    /// 14 Nov 2026: a file downloaded again to the same place showed twice, the old row calling
    /// the half-written file finished "1 hour ago".
    @Test func aFileBeingDownloadedAgainHasOneRow() {
        let old = DownloadList.Entry(id: UUID(), path: "/d/a.iso", date: now.addingTimeInterval(-3600))
        let other = DownloadList.Entry(id: UUID(), path: "/d/b.pdf", date: now.addingTimeInterval(-60))
        let again = DownloadList.Live(id: 9, name: "a.iso", path: "/d/a.iso", started: now, received: 1, total: 9, percent: 11, updated: now)
        let tray = DownloadList.tray(entries: [old, other], live: [again], limit: 5) { _ in true }
        #expect(tray.map(\.id) == [other.id.uuidString, "live-9"])
        let library = DownloadList.library(entries: [old, other], live: [again], query: "") { _ in true }
        #expect(library.map(\.id) == ["live-9", other.id.uuidString])
        // One that failed or was cancelled wrote nothing worth hiding the old file for.
        var failed = again
        failed.failed = true
        #expect(DownloadList.tray(entries: [old], live: [failed], limit: 5) { _ in true }.count == 2)
        // Finished: the new entry takes the old one's place.
        let fresh = DownloadList.Entry(id: UUID(), path: "/d/a.iso", date: now)
        #expect(DownloadList.adding(fresh, to: [old, other]).map { $0.id } == [other.id, fresh.id])
        #expect(DownloadList.adding(fresh, to: []).map { $0.id } == [fresh.id])
    }

    @Test func aRowKnowsItsStateAndLink() {
        var live = DownloadList.Live(id: 1, name: "a.zip", path: "/d/a.zip", started: now, received: 5, total: 10, percent: 50, updated: now)
        #expect(DownloadList.Listed.live(live).link == nil)
        #expect(live.fraction == 0.5)
        live.url = "https://example.com/a.zip"
        live.paused = true
        #expect(DownloadList.Listed.live(live).link == "https://example.com/a.zip")
        #expect(DownloadList.Listed.live(live).state == .paused(received: 5, total: 10))
        live.total = -1
        #expect(live.fraction == nil)
        let entry = DownloadList.Entry(id: UUID(), path: "/d/done.pdf", date: now, url: "https://example.com/done.pdf")
        #expect(DownloadList.Listed.finished(entry).link == "https://example.com/done.pdf")
        #expect(DownloadList.Listed.finished(entry).state == .finished(at: now))
        #expect(DownloadList.Listed.finished(DownloadList.Entry(id: UUID(), path: "/d/x", date: now)).link == nil)
    }

    @Test func anOlderDownloadsFileStillLoadsAndSavesTheSame() throws {
        let old = #"[{"id":"8E4B8C4E-6F0B-4E53-9F0E-0E6B8A2C1D11","path":"/d/a.pdf","date":770000000,"profile":"Default"}]"#
        let entries = try JSONDecoder().decode([DownloadList.Entry].self, from: Data(old.utf8))
        #expect(entries.first?.url == nil)
        let saved = try JSONEncoder().encode(entries)
        #expect(!String(decoding: saved, as: UTF8.self).contains("url"))
    }
}
