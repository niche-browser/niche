import Foundation

/// The ring round the sidebar's Library button while files download: how far along they are,
/// taken together. The Dock's icon showed progress, but the window gave no sign that a download
/// was under way until its thumbnail dropped in at the end (13 Nov 2026).
public enum DownloadProgressRing: Equatable, Sendable {
    /// Nothing is downloading.
    case hidden
    /// Downloading, but a server gave no size: the ring turns instead of filling.
    case turning
    /// The share received of everything running, 0…1.
    case filled(Double)

    /// The ring for the downloads Chromium reports. Failed and cancelled ones don't count.
    public static func ring(for live: [DownloadList.Live]) -> DownloadProgressRing {
        let running = live.filter(\.running)
        guard !running.isEmpty else { return .hidden }
        guard running.allSatisfy({ $0.total > 0 }) else { return .turning }
        let total = running.reduce(Int64(0)) { $0 + $1.total }
        let received = running.reduce(Int64(0)) { $0 + min(max($1.received, 0), $1.total) }
        return .filled(Double(received) / Double(total))
    }

    /// What VoiceOver says of it, and the Library button's tooltip while it shows.
    public var spoken: String? {
        switch self {
        case .hidden: return nil
        case .turning: return "Downloading"
        case .filled(let share): return "Downloading, \(Int((share * 100).rounded())) %"
        }
    }
}
