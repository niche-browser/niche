import NicheCore
import Testing

/// The update window's download line jittered: each network chunk (hundreds a second) redrew it,
/// and ByteCountFormatter switched between "8 MB" and "12.3 MB", so the centred label changed
/// width and jumped from one frame to the next.
struct UpdateDownloadProgressTests {
    let mb: UInt64 = 1_000_000

    @Test func theLabelKeepsOneDecimalSoItsWidthHoldsStill() {
        #expect(UpdateDownloadProgress.label(received: 8 * mb, expected: 120 * mb) == "8.0 of 120.0 MB")
        #expect(UpdateDownloadProgress.label(received: 12_340_000, expected: 120 * mb) == "12.3 of 120.0 MB")
        #expect(UpdateDownloadProgress.label(received: 120 * mb, expected: 120 * mb) == "120.0 of 120.0 MB")
        #expect(UpdateDownloadProgress.label(received: 0, expected: 0) == "Downloading…")
    }

    @Test func aChunkRedrawsOnlyWhenTheBarVisiblyMoves() {
        let total = 200 * mb
        // 64 KB more than the last drawn value: same half-percent step, nothing to redraw.
        #expect(!UpdateDownloadProgress.shouldPublish(drawn: 10 * mb, received: 10 * mb + 65_536, expected: total))
        // Into the next half percent.
        #expect(UpdateDownloadProgress.shouldPublish(drawn: 10 * mb, received: 11 * mb + 1, expected: total))
        // The last byte always shows, and so does a download of unknown size starting.
        #expect(UpdateDownloadProgress.shouldPublish(drawn: total - 10, received: total, expected: total))
        #expect(UpdateDownloadProgress.shouldPublish(drawn: 0, received: 10, expected: 0) == false)
    }

    @Test func aWholeDownloadRedrawsAboutTwoHundredTimes() {
        let total = 150 * mb
        var drawn: UInt64 = 0, received: UInt64 = 0, redraws = 0
        while received < total {
            received = min(total, received + 32_768)
            if UpdateDownloadProgress.shouldPublish(drawn: drawn, received: received, expected: total) { drawn = received; redraws += 1 }
        }
        #expect(drawn == total)
        #expect((190...201).contains(redraws))
    }
}
