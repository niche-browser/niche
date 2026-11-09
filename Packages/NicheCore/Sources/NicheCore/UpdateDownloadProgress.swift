import Foundation

/// What the update window shows while an update downloads, and when it redraws.
public enum UpdateDownloadProgress {
    /// Steps the bar moves in: half a percent, about a pixel of its 170 pt.
    static let steps: UInt64 = 200

    /// "12.3 of 120.0 MB": always one decimal, so the centred line keeps its width as it counts.
    public static func label(received: UInt64, expected: UInt64) -> String {
        guard expected > 0 else { return "Downloading…" }
        let mb = { (n: UInt64) in String(format: "%.1f", Double(n) / 1_000_000) }
        return "\(mb(received)) of \(mb(expected)) MB"
    }

    /// Whether `received` bytes need a redraw after one at `drawn`: when the bar reaches its next
    /// step or the download completes, not on every network chunk. Unknown sizes show a spinner.
    public static func shouldPublish(drawn: UInt64, received: UInt64, expected: UInt64) -> Bool {
        guard expected > 0 else { return false }
        if received >= expected { return drawn < expected }
        return received * steps / expected != drawn * steps / expected
    }
}
