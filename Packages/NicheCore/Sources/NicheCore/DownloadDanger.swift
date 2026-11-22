import Foundation

/// What Chromium found unsafe about a download, as Chrome checks one (safe-downloads.patch): it holds
/// the file, under a temporary name, until Keep or Delete, as Chrome's download bubble does.
public enum DownloadDanger: String, CaseIterable, Equatable, Sendable {
    /// A kind of file that can run code or change the Mac (Chrome's file type policies).
    case file
    /// Safe Browsing knows the address, the file, or the site that serves it to be malicious.
    case url, content, host
    /// Safe Browsing rarely sees this file downloaded.
    case uncommon
    /// Safe Browsing knows it to make unwanted changes (to settings, the browser).
    case unwanted
    /// Downloaded over http.
    case insecure
    /// Held by a policy or for a scan that Chrome offers no Keep for.
    case policy
    /// A danger this version of Niche has no words of its own for.
    case other

    /// The engine's word ("" for nothing); one Niche doesn't know is still a danger.
    public init?(engine word: String) {
        guard !word.isEmpty else { return nil }
        self = DownloadDanger(rawValue: word) ?? .other
    }

    /// Known to be bad, not only possibly: the row offers Delete alone and Keep asks first.
    public var isKnownBad: Bool { self == .url || self == .content || self == .host }

    /// Whether Keep is offered at all (Chrome offers none for a file held by policy).
    public var canKeep: Bool { self != .policy }

    /// The line under the file's name.
    public var subtitle: String {
        switch self {
        case .file: "This kind of file can harm your Mac"
        case .url, .content, .host: "Known to be dangerous"
        case .uncommon: "Not commonly downloaded"
        case .unwanted: "May make unwanted changes"
        case .insecure: "Insecure download"
        case .policy: "Blocked by your settings"
        case .other: "May be dangerous"
        }
    }

    /// The same, short, for a row whose buttons are showing.
    public var brief: String {
        switch self {
        case .file: "Can harm your Mac"
        case .url, .content, .host: "Dangerous"
        case .uncommon: "Uncommon file"
        case .unwanted: "Unwanted changes"
        case .insecure: "Insecure download"
        case .policy: "Blocked"
        case .other: "May be dangerous"
        }
    }
}
