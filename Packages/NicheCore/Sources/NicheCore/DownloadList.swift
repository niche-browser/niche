import Foundation

/// The downloads Niche lists: finished files (kept in downloads.json) and downloads Chromium is still
/// reporting on, or that ended without a file (this session only). Two places show them: the tray
/// over the Library button and Library ▸ Downloads.
public enum DownloadList {
    /// A finished download, as saved in downloads.json.
    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var path: String
        public var date: Date
        /// The profile folder it was downloaded in ("Default", "Profile 2"; nil before 8 Nov 2026),
        /// for Arc's Filter ▸ Profiles on Library ▸ Downloads.
        public var profile: String?
        /// The address it was downloaded from (nil before 14 Nov 2026), for Copy Download Link.
        public var url: String?

        public init(id: UUID, path: String, date: Date, profile: String? = nil, url: String? = nil) {
            self.id = id
            self.path = path
            self.date = date
            self.profile = profile
            self.url = url
        }

        public var name: String { (path as NSString).lastPathComponent }
    }

    /// A download Chromium is still reporting on, or one that ended without a file.
    public struct Live: Identifiable, Equatable, Sendable {
        public let id: UInt32
        public var name: String
        public var path: String
        public var started: Date
        public var received: Int64
        public var total: Int64
        public var percent: Int
        public var bytesPerSecond: Double?
        /// The last point the speed was measured from.
        public var sampleBytes: Int64 = 0
        public var sampleAt = Date.distantPast
        public var failed = false
        public var cancelled = false
        /// Held by Pause: still in progress, nothing arriving.
        public var paused = false
        /// The address it is downloaded from ("" when Chromium gave none).
        public var url = ""
        /// When Chromium last reported on it.
        public var updated: Date
        /// What Chromium found unsafe about it: held until Keep or Delete.
        public var danger: DownloadDanger?
        /// Chromium blocked the file outright.
        public var blocked = false
        /// Where the bytes are while it runs (a .crdownload beside `path`, or Chromium's "Unconfirmed"
        /// name for a held one); "" when Chromium gave none.
        public var partPath = ""

        public init(id: UInt32, name: String, path: String, started: Date, received: Int64, total: Int64, percent: Int, updated: Date) {
            self.id = id
            self.name = name
            self.path = path
            self.started = started
            self.received = received
            self.total = total
            self.percent = percent
            self.updated = updated
        }

        /// Chromium's next report on this download. A report on one that was cancelled or has
        /// failed can come without its name, path or sizes: the row keeps what it knew.
        public mutating func take(name: String, path: String, url: String, received: Int64, total: Int64, percent: Int,
                                  failed: Bool, cancelled: Bool, paused: Bool, now: Date,
                                  danger: DownloadDanger? = nil, blocked: Bool = false, partPath: String = "") {
            self.danger = danger
            self.blocked = blocked
            if !partPath.isEmpty { self.partPath = partPath }
            if sampleAt == .distantPast {
                (sampleBytes, sampleAt) = (received, now)
            } else if let speed = DownloadRow.speed(fromBytes: sampleBytes, at: sampleAt, toBytes: received, at: now) {
                bytesPerSecond = speed
                (sampleBytes, sampleAt) = (received, now)
            }
            updated = now
            if !name.isEmpty { self.name = name }
            if !path.isEmpty { self.path = path }
            if !url.isEmpty { self.url = url }
            let ended = failed || cancelled
            if !(ended && received == 0 && total <= 0) {
                self.received = received
                self.total = total
                self.percent = percent
            }
            self.failed = failed
            self.cancelled = cancelled
            self.paused = paused && !ended
            if self.paused || ended { bytesPerSecond = nil; sampleAt = .distantPast }
        }

        public var running: Bool { !failed && !cancelled }
        /// Held for the user: no bytes are coming until Keep.
        public var awaitingDecision: Bool { running && danger != nil }
        public var row: DownloadRow.State {
            if blocked { return .blocked(danger) }
            if failed { return .failed }
            if cancelled { return .cancelled }
            if let danger { return .held(danger) }
            if paused { return .paused(received: received, total: total) }
            return .downloading(received: received, total: total, bytesPerSecond: bytesPerSecond)
        }
        /// How far along it is, 0…1; nil when the server gave no size.
        public var fraction: Double? {
            total > 0 ? min(1, max(0, Double(received) / Double(total))) : nil
        }
    }

    /// A row in either list.
    public enum Listed: Identifiable, Equatable, Sendable {
        case finished(Entry)
        case live(Live)

        public var id: String {
            switch self {
            case .finished(let e): return e.id.uuidString
            case .live(let l): return "live-\(l.id)"
            }
        }
        public var date: Date {
            switch self {
            case .finished(let e): return e.date
            case .live(let l): return l.started
            }
        }
        public var name: String {
            switch self {
            case .finished(let e): return e.name
            case .live(let l): return l.name
            }
        }
        public var state: DownloadRow.State {
            switch self {
            case .finished(let e): return .finished(at: e.date)
            case .live(let l): return l.row
            }
        }
        /// The address it came from, when known.
        public var link: String? {
            switch self {
            case .finished(let e): return e.url.flatMap { $0.isEmpty ? nil : $0 }
            case .live(let l): return l.url.isEmpty ? nil : l.url
            }
        }
    }

    /// The finished files to list: the ones still on disk, less a file that is being downloaded
    /// again to the same place (its row is the download's; what is on disk is half written).
    private static func shown(_ entries: [Entry], beside live: [Live], fileExists: (String) -> Bool) -> [Entry] {
        let arriving = Set(live.filter { $0.running && !$0.path.isEmpty }.map(\.path))
        return entries.filter { fileExists($0.path) && !arriving.contains($0.path) }
    }

    /// The saved list with a download that has just finished: it takes the place of an earlier
    /// download of the same file to the same place.
    public static func adding(_ entry: Entry, to entries: [Entry]) -> [Entry] {
        entries.filter { $0.path != entry.path } + [entry]
    }

    /// Clear Downloads: finished files leave the list (they stay on disk) and so do downloads that
    /// failed or were cancelled; one still running or paused stays.
    public static func cleared(entries: [Entry], live: [Live]) -> (entries: [Entry], live: [Live]) {
        ([], live.filter(\.running))
    }

    /// Whether Clear Downloads has anything to take away.
    public static func canClear(entries: [Entry], live: [Live], fileExists: (String) -> Bool) -> Bool {
        entries.contains { fileExists($0.path) } || live.contains { !$0.running }
    }

    /// The tray: the newest `limit` downloads, oldest first: files still on disk, and running,
    /// failed or cancelled ones.
    public static func tray(entries: [Entry], live: [Live], limit: Int, fileExists: (String) -> Bool) -> [Listed] {
        let finished = shown(entries, beside: live, fileExists: fileExists).map(Listed.finished)
        return Array((finished + live.map(Listed.live)).sorted { $0.date < $1.date }.suffix(limit))
    }

    /// Library ▸ Downloads, newest first, narrowed to names containing `query`: the same rows as the
    /// tray, without its limit. A running download is listed too, with its progress (#245); before,
    /// the page showed only finished files, so the one being downloaded was missing exactly where
    /// people go to look for it.
    public static func library(entries: [Entry], live: [Live], query: String, fileExists: (String) -> Bool) -> [Listed] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        let finished = shown(entries, beside: live, fileExists: fileExists).map(Listed.finished)
        let all = (finished + live.map(Listed.live)).sorted { $0.date > $1.date }
        return needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) }
    }
}
