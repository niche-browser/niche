import Foundation
import NicheCore
import Testing

/// Chromium checks a download as Chrome does (safe-downloads.patch): a file it finds unsafe is held
/// until Keep or Delete. Before, Niche chose every download's path itself and Chromium's checks never
/// ran: no dangerous file, Safe Browsing hit or insecure download was ever held (21 Nov 2026).
struct DownloadDangerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func live(danger: DownloadDanger? = nil, blocked: Bool = false, failed: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: 1, name: "setup.dmg", path: "/d/setup.dmg", started: now, received: 9, total: 9,
                                  percent: 100, updated: now)
        l.danger = danger
        l.blocked = blocked
        l.failed = failed
        return l
    }

    /// The engine's words: "" for nothing, the rest one kind each.
    @Test func readsTheEnginesWords() {
        #expect(DownloadDanger(engine: "") == nil)
        #expect(DownloadDanger(engine: "file") == .file)
        #expect(DownloadDanger(engine: "insecure") == .insecure)
        #expect(DownloadDanger(engine: "url") == .url)
        // A kind the app doesn't know yet still holds the download.
        #expect(DownloadDanger(engine: "something-new") == .other)
    }

    @Test func aHeldDownloadWaitsForTheUser() {
        #expect(live(danger: .uncommon).row == .held(.uncommon))
        #expect(live(danger: .uncommon).awaitingDecision)
        #expect(!live().awaitingDecision)
        // Still Chromium's to finish or end: Clear keeps it.
        #expect(live(danger: .uncommon).running)
        // Ended, it is what ended it that the row says.
        #expect(live(danger: .file, failed: true).row == .failed)
    }

    @Test func aBlockedFileSaysSo() {
        #expect(live(blocked: true, failed: true).row == .blocked)
        #expect(DownloadRow.subtitle(.blocked, now: now) == "Blocked")
    }

    /// A file known to be bad offers only Delete on its row; Keep is in its menu, and asks first.
    @Test func keepIsAtHandUnlessTheFileIsKnownBad() {
        #expect(DownloadAction.buttons(for: .held(.uncommon)) == [.keep, .discard])
        #expect(DownloadAction.buttons(for: .held(.insecure)) == [.keep, .discard])
        #expect(DownloadAction.buttons(for: .held(.content)) == [.discard])
        #expect(DownloadAction.menu(for: .held(.content), hasLink: true) == [[.discard], [.keep], [.copyLink]])
        #expect(DownloadAction.menu(for: .held(.file), hasLink: false) == [[.keep, .discard]])
        #expect(DownloadAction.buttons(for: .blocked) == [.remove])
        // Held by policy: Chrome has no Keep for it, nor does Niche.
        #expect(DownloadAction.buttons(for: .held(.policy)) == [.discard])
        #expect(DownloadAction.menu(for: .held(.policy), hasLink: true) == [[.discard], [.copyLink]])
        #expect(DownloadDanger(engine: "policy") == .policy && !DownloadDanger.policy.canKeep)
        #expect(DownloadAction.menu(for: .blocked, hasLink: true) == [[.copyLink], [.remove]])
        #expect(DownloadDanger.content.isKnownBad && DownloadDanger.url.isKnownBad && DownloadDanger.host.isKnownBad)
        #expect(!DownloadDanger.file.isKnownBad && !DownloadDanger.insecure.isKnownBad)
    }

    @Test func everyDangerHasWords() {
        for d in DownloadDanger.allCases {
            #expect(!DownloadRow.subtitle(.held(d), now: now).isEmpty)
            #expect(!DownloadRow.subtitle(.held(d), now: now, detail: .brief).isEmpty)
        }
        #expect(DownloadRow.subtitle(.held(.insecure), now: now) == "Insecure download")
        #expect(DownloadRow.State.held(.file).word == "held")
        #expect(DownloadRow.State.held(.uncommon).isWarning && DownloadRow.State.blocked.isWarning && DownloadRow.State.failed.isWarning)
        #expect(!DownloadRow.State.cancelled.isWarning && !DownloadRow.State.finished(at: now).isWarning)
        #expect(DownloadAction.keep.title == "Keep")
        #expect(DownloadAction.discard.title == "Delete")
    }

    /// A held download isn't progress: the ring round the Library button leaves it out.
    @Test func theRingLeavesHeldDownloadsOut() {
        var running = DownloadList.Live(id: 2, name: "a.zip", path: "/d/a.zip", started: now, received: 5, total: 10,
                                        percent: 50, updated: now)
        running.url = "https://example.com/a.zip"
        #expect(DownloadProgressRing.ring(for: [live(danger: .file)]) == .hidden)
        #expect(DownloadProgressRing.ring(for: [live(danger: .file), running]) == .filled(0.5))
    }

    /// Chromium's report carries the safety; a kept download carries on as any other.
    @Test func takesTheSafetyFromEachReport() {
        var l = live()
        l.take(name: "setup.dmg", path: "/d/setup.dmg", url: "", received: 9, total: 9, percent: 100, failed: false,
               cancelled: false, paused: false, now: now, danger: .file, blocked: false, partPath: "/d/Unconfirmed 1.crdownload")
        #expect(l.row == .held(.file))
        #expect(l.partPath == "/d/Unconfirmed 1.crdownload")
        l.take(name: "setup.dmg", path: "/d/setup.dmg", url: "", received: 9, total: 9, percent: 100, failed: false,
               cancelled: false, paused: false, now: now, danger: nil, blocked: false, partPath: "/d/setup.dmg.crdownload")
        #expect(l.row == .downloading(received: 9, total: 9, bytesPerSecond: nil))
    }
}
