import Foundation
import NicheCore
import Testing

/// The sidebar shows a download's progress as a ring round the Library button (13 Nov 2026).
struct DownloadProgressRingTests {
    private func live(_ id: UInt32, _ received: Int64, of total: Int64, failed: Bool = false, cancelled: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: id, name: "file", path: "", started: Date(timeIntervalSince1970: 0), received: received,
                                  total: total, percent: 0, updated: Date(timeIntervalSince1970: 0))
        l.failed = failed
        l.cancelled = cancelled
        return l
    }

    @Test func nothingRunningNoRing() {
        #expect(DownloadProgressRing.ring(for: []) == .hidden)
        #expect(DownloadProgressRing.ring(for: [live(1, 10, of: 100, failed: true), live(2, 10, of: 100, cancelled: true)]) == .hidden)
    }

    @Test func oneDownloadFillsWithIt() {
        #expect(DownloadProgressRing.ring(for: [live(1, 25, of: 100)]) == .filled(0.25))
        #expect(DownloadProgressRing.ring(for: [live(1, 0, of: 100)]) == .filled(0))
    }

    /// Two files are one job: 30 of 300 bytes and 150 of 300 are 180 of 600.
    @Test func severalAreTakenTogether() {
        #expect(DownloadProgressRing.ring(for: [live(1, 30, of: 300), live(2, 150, of: 300), live(3, 5, of: 50, failed: true)]) == .filled(0.3))
    }

    /// A server that sends no size: the ring turns, also when another download has one.
    @Test func withoutASizeItTurns() {
        #expect(DownloadProgressRing.ring(for: [live(1, 4096, of: 0)]) == .turning)
        #expect(DownloadProgressRing.ring(for: [live(1, 4096, of: 0), live(2, 10, of: 100)]) == .turning)
    }

    @Test func neverPastFull() {
        #expect(DownloadProgressRing.ring(for: [live(1, 120, of: 100)]) == .filled(1))
    }

    @Test func words() {
        #expect(DownloadProgressRing.hidden.spoken == nil)
        #expect(DownloadProgressRing.turning.spoken == "Downloading")
        #expect(DownloadProgressRing.filled(0.256).spoken == "Downloading, 26 %")
    }
}
