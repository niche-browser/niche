import Foundation

/// `Perf/session.open`: made once Chromium has started, removed when Niche quits normally. Found
/// at the next launch, it means that session ended without quitting: a crash, a force quit,
/// `kill -9` or the Mac losing power.
public struct PerfSessionMarker: Codable, Equatable, Sendable {
    public var id: String
    public var launch: Int
    public var startedAt: Date
    public var pid: Int32
    public var nicheVersion: String

    public init(id: String, launch: Int, startedAt: Date, pid: Int32, nicheVersion: String) {
        self.id = id
        self.launch = launch
        self.startedAt = startedAt
        self.pid = pid
        self.nicheVersion = nicheVersion
    }
}

/// The session before this one, as this launch found it.
public struct PerfPreviousSession: Codable, Equatable, Sendable {
    public var id: String
    public var launch: Int
    public var startedAt: Date
    public var nicheVersion: String
    /// Ended without quitting (its marker was still there).
    public var abnormal: Bool
    /// When it quit; nil after an abnormal end.
    public var endedAt: Date?

    public init(id: String, launch: Int, startedAt: Date, nicheVersion: String, abnormal: Bool, endedAt: Date?) {
        self.id = id
        self.launch = launch
        self.startedAt = startedAt
        self.nicheVersion = nicheVersion
        self.abnormal = abnormal
        self.endedAt = endedAt
    }
}

/// When Niche records and when it writes (GitHub #91).
public enum PerfSessionRules {
    /// Settings ▸ Performance ▸ "Record performance", unless `NICHE_PERF=0` turns it off for a
    /// development run.
    public static func recording(setting: Bool, environment: [String: String]) -> Bool {
        environment["NICHE_PERF"] != "0" && setting
    }

    /// Only the Niche that owns the data folder writes, like NicheLog's rotation: a second launch
    /// that hands its URLs over and quits must not replace the running one's files.
    public static func writesFiles(owner: Bool, recording: Bool) -> Bool { owner && recording }

    /// The session before this one: the marker it left (abnormal), else the one history recorded
    /// as quitting normally, else none (the first launch, or recording was off).
    public static func previous(marker: PerfSessionMarker?, history: PerfHistory) -> PerfPreviousSession? {
        if let m = marker {
            return PerfPreviousSession(id: m.id, launch: m.launch, startedAt: m.startedAt, nicheVersion: m.nicheVersion, abnormal: true, endedAt: nil)
        }
        return history.lastSession
    }
}
