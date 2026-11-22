import Foundation

/// Which of Niche's protections are switched on (Settings ▸ Privacy), as the panel's report
/// needs them.
public struct PrivacyProtections: Equatable, Sendable {
    public var blocksTrackers = true
    public var withholdsCookies = true
    public var cleansAddresses = true
    public var sendsSignal = true
    public var noticesFingerprinting = true

    public init(blocksTrackers: Bool = true, withholdsCookies: Bool = true, cleansAddresses: Bool = true,
                sendsSignal: Bool = true, noticesFingerprinting: Bool = true) {
        self.blocksTrackers = blocksTrackers
        self.withholdsCookies = withholdsCookies
        self.cleansAddresses = cleansAddresses
        self.sendsSignal = sendsSignal
        self.noticesFingerprinting = noticesFingerprinting
    }

    /// The Default profile's (`AppSettings.privacy`).
    public init(_ settings: AppSettings) { self.init(settings.privacy) }

    /// A profile's.
    public init(_ settings: PrivacySettings) {
        self.init(blocksTrackers: settings.blockAdsAndTrackers, withholdsCookies: settings.blockThirdPartyCookies,
                  cleansAddresses: settings.removeTrackingParameters, sendsSignal: settings.sendGlobalPrivacyControl,
                  noticesFingerprinting: settings.noticeFingerprinting)
    }
}

/// The top of the privacy panel in words: where the page stands, and what each of Niche's
/// protections did on it. Short lines anyone can read; nothing is claimed that wasn't seen.
public enum PrivacyReport {
    public enum Tone: Equatable, Sendable {
        /// Niche did something for the visitor.
        case good
        /// Something got through that the visitor may mind.
        case bad
        /// On, with nothing to do on this page.
        case quiet
        /// Switched off.
        case off
    }

    public struct Standing: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var tone: Tone

        public init(title: String, detail: String, tone: Tone) {
            self.title = title
            self.detail = detail
            self.tone = tone
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable { case trackers, cookies, address, signal, fingerprinting, connection }
        public var kind: Kind
        public var title: String
        public var value: String
        public var tone: Tone
        public var id: Kind { kind }

        /// The SF Symbol beside it.
        public var symbol: String {
            switch kind {
            case .trackers: "hand.raised"
            case .cookies: "person.crop.circle.badge.xmark"
            case .address: "link"
            case .signal: "megaphone"
            case .fingerprinting: "touchid"
            case .connection: "lock"
            }
        }
    }

    /// The headline and the line under it.
    public static func standing(_ s: PrivacyLedger.Summary, siteOff: Bool) -> Standing {
        if siteOff {
            return Standing(title: "Protection is off here",
                            detail: s.sawYou == 0 ? "Nothing is blocked on this site." : "\(PrivacyWords.count(s.sawYou, "tracker")) can see this visit.",
                            tone: .off)
        }
        var did: [String] = []
        if s.blocked > 0 { did.append("\(PrivacyWords.count(s.blocked, "company", plural: "companies")) blocked") }
        if s.cookiesWithheld > 0 { did.append("\(PrivacyWords.count(s.cookiesWithheld, "cookie")) kept back") }
        if s.cleanedAddress { did.append("address cleaned") }
        let sentence = did.isEmpty ? "" : (did.joined(separator: ", ").prefix(1).uppercased() + did.joined(separator: ", ").dropFirst() + ".")
        if s.sawYou > 0 {
            return Standing(title: "\(PrivacyWords.count(s.sawYou, "tracker")) can see this visit",
                            detail: sentence.isEmpty ? "Open one below to block it." : sentence + " Open a tracker below to block it.",
                            tone: .bad)
        }
        if s.parties == 0 {
            return Standing(title: "This page keeps to itself", detail: sentence.isEmpty ? "It hasn’t contacted any other company." : sentence, tone: .good)
        }
        if s.blocked == 0 {
            return Standing(title: "No trackers here", detail: sentence.isEmpty ? "What this page loads from others makes it work." : sentence, tone: .good)
        }
        return Standing(title: "You’re protected", detail: sentence, tone: .good)
    }

    /// What each protection did on the page, in the panel's order. `secure` is whether the page
    /// came over an encrypted connection.
    public static func rows(_ s: PrivacyLedger.Summary, protections p: PrivacyProtections, siteOff: Bool, secure: Bool) -> [Row] {
        let offHere = "Off for this site"
        func row(_ kind: Row.Kind, _ title: String, on: Bool, sitewide: Bool = true, _ value: () -> (String, Tone)) -> Row {
            if !on { return Row(kind: kind, title: title, value: "Off", tone: .off) }
            if siteOff, sitewide { return Row(kind: kind, title: title, value: offHere, tone: .off) }
            let (text, tone) = value()
            return Row(kind: kind, title: title, value: text, tone: tone)
        }
        return [
            row(.trackers, "Trackers", on: p.blocksTrackers) {
                s.blockedRequests > 0 ? ("\(PrivacyWords.count(s.blockedRequests, "request")) stopped", .good) : ("None found", .quiet)
            },
            row(.cookies, "Cross-site cookies", on: p.withholdsCookies) {
                s.cookiesWithheld > 0 ? ("\(s.cookiesWithheld) kept back", .good) : ("None asked for", .quiet)
            },
            row(.address, "Tracking codes", on: p.cleansAddresses, sitewide: false) {
                s.cleanedAddress ? ("Removed", .good) : ("None found", .quiet)
            },
            row(.signal, "“Don’t sell my data” signal", on: p.sendsSignal, sitewide: false) { ("Sent", .good) },
            row(.fingerprinting, "Fingerprinting", on: p.noticesFingerprinting, sitewide: false) {
                s.fingerprinters > 0 ? ("\(PrivacyWords.count(s.fingerprinters, "company", plural: "companies")) tried", .bad) : ("None noticed", .quiet)
            },
            Row(kind: .connection, title: "Connection", value: secure ? "Encrypted" : "Not encrypted", tone: secure ? .good : .bad),
        ]
    }

    /// How long ago a feed line happened: "now", "12 s", "4 min", "2 h".
    public static func ago(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "now" }
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        return "\(s / 3600) h"
    }
}
