import Foundation

/// A row in the downloads list. Arc 1.171 shows downloads that are still running, failed or were
/// cancelled there, with the finished ones, and has no download toast (its strings: "Failed to
/// Download", a download speed "e.g. 3 MB/s", subtitles for paused and cancelled downloads).
/// Niche's bottom-right download cards were the only other toast design and are gone (#85 follow-up).
public enum DownloadRow {
    public enum State: Equatable {
        case downloading(received: Int64, total: Int64, bytesPerSecond: Double?)
        case paused(received: Int64, total: Int64)
        case failed
        case cancelled
        /// Chromium holds it until Keep or Delete (DownloadDanger).
        case held(DownloadDanger)
        /// Chromium blocked the file outright, for this reason when it said one.
        case blocked(DownloadDanger?)
        case finished(at: Date)

        /// Said in the danger colour: it failed, or Chromium held or blocked the file.
        public var isWarning: Bool {
            switch self {
            case .failed, .held, .blocked: true
            default: false
            }
        }

        /// The state in a word, for the log.
        public var word: String {
            switch self {
            case .downloading: "running"
            case .paused: "paused"
            case .failed: "failed"
            case .cancelled: "cancelled"
            case .held: "held"
            case .blocked: "blocked"
            case .finished: "finished"
            }
        }
    }

    /// How much a running download's line says: everything (the Library), without the speed once
    /// the time left is known (the tray), or the one thing that matters most (a tray row whose
    /// buttons are showing).
    public enum Detail: Sendable { case full, compact, brief }

    /// The line under the file name: progress and speed while it runs, Arc's failure text, or
    /// how long ago it finished ("54 seconds ago").
    ///
    /// A running download says how long it still takes once that can be told (a size and a speed).
    /// How much of the rest fits depends on the room (`Detail`).
    public static func subtitle(_ state: State, now: Date, detail: Detail = .full) -> String {
        switch state {
        case let .downloading(received, total, speed):
            let left = timeLeft(received: received, total: total, bytesPerSecond: speed)
            if detail == .brief, let left { return left }
            var s = bytes(received)
            if total > 0 { s += " of " + bytes(total) }
            if let speed, speed > 0, detail == .full || left == nil { s += " — " + bytes(Int64(speed)) + "/s" }
            if let left { s += " — " + left }
            return s
        case let .paused(received, total):
            if detail == .brief { return "Paused" }
            return "Paused — " + bytes(received) + (total > 0 ? " of " + bytes(total) : "")
        case .failed: return "Failed to Download"
        case .cancelled: return "Cancelled"
        case let .held(danger): return detail == .brief ? danger.brief : danger.subtitle
        case .blocked(.insecure?): return "Insecure download blocked"
        case .blocked: return "Blocked"
        // At least a second: a row read just as it finished said "in 0 seconds".
        case let .finished(at): return age.localizedString(fromTimeInterval: -max(1, now.timeIntervalSince(at)))
        }
    }

    /// "38 s left", "4 min left", "2 h 10 min left": the bytes still to come at the speed measured,
    /// rounded up so it never says 0. nil without a size, a speed, or anything left.
    public static func timeLeft(received: Int64, total: Int64, bytesPerSecond: Double?) -> String? {
        guard let speed = bytesPerSecond, speed > 0, total > received, received >= 0 else { return nil }
        let seconds = Int((Double(total - received) / speed).rounded(.up))
        if seconds < 60 { return "\(max(1, seconds)) s left" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) min left" }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? "\(h) h left" : "\(h) h \(m) min left"
    }

    /// Bytes per second from two progress reports; nil until there is a span to measure.
    public static func speed(fromBytes a: Int64, at t0: Date, toBytes b: Int64, at t1: Date) -> Double? {
        let dt = t1.timeIntervalSince(t0)
        guard dt >= 0.25, b >= a else { return nil }
        return Double(b - a) / dt
    }

    /// Finder's sizes (1000-based: "980 bytes", "12 KB", "3 MB", "1.5 GB"), always in English like the
    /// rest of Niche; ByteCountFormatter follows the system's locale.
    public static func bytes(_ n: Int64) -> String {
        if n < 1000 { return "\(n) bytes" }
        let units = ["KB", "MB", "GB", "TB"]
        var v = Double(n) / 1000, i = 0
        while v >= 999.95, i < units.count - 1 { v /= 1000; i += 1 }
        if i == 0 { return "\(Int(v.rounded())) KB" }
        let r = (v * 10).rounded() / 10
        return (r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), r)) + " " + units[i]
    }

    private static let age: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .full
        return f
    }()
}
