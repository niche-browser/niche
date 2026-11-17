import NicheCore
import Foundation
import Testing

/// Downloads show their progress and failures in the downloads list, as in Arc (#85 follow-up).
struct DownloadRowTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func runningShowsProgressAndSpeed() {
        let s = DownloadRow.subtitle(.downloading(received: 3_000_000, total: 10_000_000, bytesPerSecond: 1_500_000), now: now)
        #expect(s == "3 MB of 10 MB — 1.5 MB/s — 5 s left")
        #expect(DownloadRow.subtitle(.downloading(received: 3_000_000, total: -1, bytesPerSecond: nil), now: now) == "3 MB")
    }

    /// The tray is narrow: once it can say how long is left it drops the speed.
    @Test func theTrayLeavesTheSpeedOutWhenItKnowsTheTimeLeft() {
        let running = DownloadRow.State.downloading(received: 3_000_000, total: 10_000_000, bytesPerSecond: 1_500_000)
        #expect(DownloadRow.subtitle(running, now: now, detail: .compact) == "3 MB of 10 MB — 5 s left")
        // No size, so no time left: the speed is all there is to tell.
        let unsized = DownloadRow.State.downloading(received: 3_000_000, total: -1, bytesPerSecond: 1_500_000)
        #expect(DownloadRow.subtitle(unsized, now: now, detail: .compact) == "3 MB — 1.5 MB/s")
        // Beside the row's buttons there is room for one thing.
        #expect(DownloadRow.subtitle(running, now: now, detail: .brief) == "5 s left")
        #expect(DownloadRow.subtitle(unsized, now: now, detail: .brief) == "3 MB — 1.5 MB/s")
        #expect(DownloadRow.subtitle(.paused(received: 3_000_000, total: 10_000_000), now: now, detail: .brief) == "Paused")
        #expect(DownloadRow.subtitle(.failed, now: now, detail: .brief) == "Failed to Download")
    }

    @Test func eachStateHasAWordForTheLog() {
        #expect(DownloadRow.State.downloading(received: 1, total: 2, bytesPerSecond: nil).word == "running")
        #expect(DownloadRow.State.paused(received: 1, total: 2).word == "paused")
        #expect(DownloadRow.State.failed.word == "failed")
        #expect(DownloadRow.State.cancelled.word == "cancelled")
        #expect(DownloadRow.State.finished(at: now).word == "finished")
    }

    @Test func pausedSaysHowFarItGot() {
        #expect(DownloadRow.subtitle(.paused(received: 3_000_000, total: 10_000_000), now: now) == "Paused — 3 MB of 10 MB")
        #expect(DownloadRow.subtitle(.paused(received: 3_000_000, total: -1), now: now) == "Paused — 3 MB")
    }

    @Test(arguments: [(Int64(9_000_000), 1_000_000.0, "1 s left"), (0, 250_000.0, "40 s left"), (0, 100_000.0, "2 min left"),
                      (0, 40_000.0, "5 min left"), (0, 2_000.0, "1 h 24 min left"), (0, 2_800.0, "1 h left"), (9_999_999, 1_000_000.0, "1 s left")])
    func timeLeftRoundsUp(received: Int64, speed: Double, text: String) {
        #expect(DownloadRow.timeLeft(received: received, total: 10_000_000, bytesPerSecond: speed) == text)
    }

    @Test func timeLeftNeedsASizeASpeedAndSomethingLeft() {
        #expect(DownloadRow.timeLeft(received: 1, total: -1, bytesPerSecond: 100) == nil)
        #expect(DownloadRow.timeLeft(received: 1, total: 10, bytesPerSecond: nil) == nil)
        #expect(DownloadRow.timeLeft(received: 1, total: 10, bytesPerSecond: 0) == nil)
        #expect(DownloadRow.timeLeft(received: 10, total: 10, bytesPerSecond: 100) == nil)
    }

    @Test func failedAndCancelled() {
        #expect(DownloadRow.subtitle(.failed, now: now) == "Failed to Download")
        #expect(DownloadRow.subtitle(.cancelled, now: now) == "Cancelled")
    }

    @Test func finishedShowsItsAge() {
        #expect(DownloadRow.subtitle(.finished(at: now.addingTimeInterval(-54)), now: now) == "54 seconds ago")
        // Just finished, or a clock that ran backwards: never "in 0 seconds".
        #expect(DownloadRow.subtitle(.finished(at: now), now: now) == "1 second ago")
        #expect(DownloadRow.subtitle(.finished(at: now.addingTimeInterval(2)), now: now) == "1 second ago")
    }

    @Test(arguments: [(Int64(980), "980 bytes"), (12_400, "12 KB"), (3_000_000, "3 MB"), (1_540_000_000, "1.5 GB"), (999_960, "1 MB")])
    func sizesInEnglish(n: Int64, text: String) {
        #expect(DownloadRow.bytes(n) == text)
    }

    @Test func speedNeedsASpanAndGrowth() {
        #expect(DownloadRow.speed(fromBytes: 0, at: now, toBytes: 1_000, at: now.addingTimeInterval(0.1)) == nil)
        #expect(DownloadRow.speed(fromBytes: 1_000, at: now, toBytes: 500, at: now.addingTimeInterval(1)) == nil)
        #expect(DownloadRow.speed(fromBytes: 0, at: now, toBytes: 2_000, at: now.addingTimeInterval(2)) == 1_000)
    }
}
