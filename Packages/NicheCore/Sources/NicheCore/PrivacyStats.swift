import Foundation

/// How much Niche has blocked since it began counting (privacy-stats.json): the foot of the
/// privacy panel. A total, the date counting began and a count per day for the last two weeks;
/// never which sites.
public struct PrivacyStats: Codable, Equatable, Sendable {
    public var blocked = 0
    /// When counting began; nil until the first block.
    public var since: Date?
    /// Blocked per day ("2026-11-17"), the last `daysKept` days that had any.
    public var days: [String: Int] = [:]
    public static let daysKept = 14

    public init(blocked: Int = 0, since: Date? = nil, days: [String: Int] = [:]) {
        self.blocked = blocked
        self.since = since
        self.days = days
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocked = try c.decodeIfPresent(Int.self, forKey: .blocked) ?? 0
        since = try c.decodeIfPresent(Date.self, forKey: .since)
        days = try c.decodeIfPresent([String: Int].self, forKey: .days) ?? [:]
    }

    public mutating func add(_ n: Int, at now: Date, calendar: Calendar = .current) {
        guard n > 0 else { return }
        if since == nil { since = now }
        blocked += n
        days[Self.day(now, calendar: calendar), default: 0] += n
        if days.count > Self.daysKept {
            for old in days.keys.sorted().dropLast(Self.daysKept) { days[old] = nil }
        }
    }

    /// The last `count` days ending today, oldest first, with what was blocked on each.
    public func recent(_ count: Int = 7, now: Date, calendar: Calendar = .current) -> [(day: Date, blocked: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { ($0, days[Self.day($0, calendar: calendar)] ?? 0) }
        }
    }

    /// Blocked today.
    public func today(now: Date, calendar: Calendar = .current) -> Int { days[Self.day(now, calendar: calendar)] ?? 0 }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "12,480": the total as it is written.
    public var total: String {
        let number = NumberFormatter()
        number.numberStyle = .decimal
        number.locale = Locale(identifier: "en_US")
        return number.string(from: NSNumber(value: blocked)) ?? "\(blocked)"
    }

    /// "12,480 trackers blocked since 14 Nov 2026"; nil before anything was blocked.
    public func line(calendar: Calendar = .current) -> String? {
        guard blocked > 0, let since else { return nil }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_GB")
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.dateFormat = "d MMM yyyy"
        return "\(total) tracker\(blocked == 1 ? "" : "s") blocked since \(date.string(from: since))"
    }
}
