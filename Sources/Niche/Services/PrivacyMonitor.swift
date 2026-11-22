import AppKit
import NicheCEF
import Observation

/// What every page has done that concerns the visitor's privacy, for the toolbar's count and the
/// privacy panel: a `PrivacyLedger` per browser, fed by the engine (NicheCEFRuntime's privacy
/// events), the user's own rules for each profile (privacy.json; AppDelegate gives each profile's to
/// the engine with the rest of its Shields) and how much was
/// blocked in all (privacy-stats.json). Every page is recorded from the moment it is asked for,
/// whether a panel is open or not. Nothing here is sent anywhere, and no ledger is saved: what a
/// page did is forgotten when its tab closes, and a tab keeps its last few pages only.
@MainActor
@Observable
final class PrivacyMonitor {
    static let shared = PrivacyMonitor()

    /// Counts up when a ledger changed, a few times a second at most: what the views follow.
    private(set) var revision = 0
    /// The rules in force, each profile's: the saved ones, and what incognito windows chose on top
    /// of the Default profile's, which incognito follows.
    private(set) var book: PrivacyRuleBook
    /// What privacy.json holds.
    @ObservationIgnored private var saved: PrivacyRuleBook
    private(set) var stats: PrivacyStats

    @ObservationIgnored private var pages: [Int: PrivacyPages] = [:]
    /// The engine's number for each tab's browser, told by each window as its pages change.
    @ObservationIgnored private var browsers: [UUID: Int] = [:]
    @ObservationIgnored private var bound: [ObjectIdentifier: [UUID: Int]] = [:]
    /// Browsers whose pages leave nothing behind (incognito windows): not counted in the total.
    @ObservationIgnored private var unrecorded: Set<Int> = []
    @ObservationIgnored private var offRecordWindows: Set<ObjectIdentifier> = []
    @ObservationIgnored private var publishPending = false
    @ObservationIgnored private let rulesFile = JSONStore<PrivacyRuleBook>("privacy.json")
    @ObservationIgnored private let statsFile = JSONStore<PrivacyStats>("privacy-stats.json")

    /// How often the views hear of changes while a page loads.
    private static let publishEvery: TimeInterval = 0.2

    private init() {
        let loaded = rulesFile.load(or: { PrivacyRuleBook() })
        book = loaded
        saved = loaded
        stats = statsFile.load(or: { PrivacyStats() })
    }

    /// Hooks the engine up; once, after CEF is initialised. From then on every page is recorded,
    /// panel or no panel, so a panel opened later has the whole of what its page did.
    func install() {
        NicheCEFRuntime.setPrivacyEventHandler { [weak self] events in
            MainActor.assumeIsolated { self?.take(events) }
        }
    }

    // MARK: Reading

    /// A window's live tabs and the browser each one's page is in. What a closed tab's page did
    /// is forgotten here. `leavesNoTrace` for an incognito window.
    func bind(window: ObjectIdentifier, tabs: [UUID: Int], leavesNoTrace: Bool = false) {
        if leavesNoTrace, !tabs.isEmpty { offRecordWindows.insert(window) }
        guard bound[window] != tabs else { return }
        let gone = Set((bound[window] ?? [:]).values).subtracting(tabs.values)
        bound[window] = tabs.isEmpty ? nil : tabs
        browsers = bound.values.reduce(into: [:]) { $0.merge($1) { _, new in new } }
        let live = Set(browsers.values)
        for b in gone where !live.contains(b) {
            pages[b] = nil
            unrecorded.remove(b)
        }
        if leavesNoTrace { unrecorded.formUnion(tabs.values) }
    }

    /// A window closed. With the last incognito window go the choices made in them.
    func unbind(window: ObjectIdentifier) {
        bind(window: window, tabs: [:])
        guard offRecordWindows.remove(window) != nil, offRecordWindows.isEmpty, book != saved else { return }
        book = saved
    }

    /// The ledger for a tab's page; nil for an address that is no website's.
    func ledger(tab: UUID, pageURL: String) -> PrivacyLedger? {
        guard let site = PrivacySite.site(ofURL: pageURL) else { return nil }
        guard let b = browsers[tab], let pages = pages[b] else { return PrivacyLedger(pageSite: site) }
        return pages.ledger(pageKey: NicheCEFRuntime.privacyPageKey(forURL: pageURL), site: site)
    }

    /// Requests blocked on a tab's page: the toolbar's count.
    func blocked(tab: UUID, pageURL: String) -> Int {
        _ = revision
        return ledger(tab: tab, pageURL: pageURL)?.summary.blockedRequests ?? 0
    }

    // MARK: The engine's events

    private func take(_ events: [NichePrivacyEvent]) {
        let now = Date()
        var blocked = 0
        for e in events {
            let kind: PrivacyEvent.Kind
            switch e.kind {
            case .navigation: kind = .navigation
            case .request: kind = .request
            case .cookieSent: kind = .cookieSent
            case .cookieSaved: kind = .cookieSaved
            case .cleanedAddress: kind = .cleanedAddress
            @unknown default: continue
            }
            var event = PrivacyEvent(kind: kind, host: e.host, site: e.site, at: now)
            event.resource = e.resource
            event.verdict = PrivacyEvent.Verdict(rawValue: e.verdict) ?? .allowed
            event.listed = e.listed
            event.sendsSite = e.sendsSite
            event.sendsPage = e.sendsPage
            event.bytesSent = e.bytesSent
            event.detail = e.detail
            event.cookieDays = e.cookieDays
            event.key = e.key
            event.group = ShieldsGroup(number: e.group)
            // What the ledger counted, so the total and the page's count agree (a repeat counts once).
            let counted = pages[e.browser, default: PrivacyPages()].record(event, pageKey: e.pageKey, pageSite: e.pageSite)
            if !unrecorded.contains(e.browser) { blocked += counted }
        }
        if blocked > 0 {
            stats.add(blocked, at: now)
            statsFile.save(stats, delay: 5)
        }
        // Browsers no window has named (a popup on its way to a tab, an extension's page).
        if pages.count > Self.pagesLimit {
            let keep = Set(browsers.values)
            for key in pages.keys where !keep.contains(key) { pages[key] = nil }
        }
        publish()
    }

    /// Past this many browsers, the ones no tab belongs to are dropped.
    private static let pagesLimit = 300

    /// What the page's own scripts were seen reading (`PrivacyProbeScript`), read from the page by
    /// the window that shows the panel.
    func record(probes: [String], tab: UUID, pageURL: String) {
        guard let b = browsers[tab], let pageHost = URLComponents(string: pageURL)?.host?.lowercased(), !probes.isEmpty else { return }
        let pageSite = PrivacySite.site(ofHost: pageHost)
        let key = NicheCEFRuntime.privacyPageKey(forURL: pageURL)
        for report in probes {
            guard let hit = PrivacyProbeScript.parse(report) else { continue }
            // No address in the stack: an inline script, the page's own.
            let host = hit.host.isEmpty ? pageHost : hit.host
            pages[b, default: PrivacyPages()].record(PrivacyEvent(kind: .probe(hit.probe), host: host, site: PrivacySite.site(ofHost: host), at: Date()),
                                                     pageKey: key, pageSite: pageSite)
        }
        publish()
    }

    private func publish() {
        guard !publishPending else { return }
        publishPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.publishEvery) { [weak self] in
            guard let self else { return }
            self.publishPending = false
            self.revision += 1
        }
    }

    // MARK: The user's rules

    /// A profile's rules in force (`PrivacyProfile.key`; incognito windows use Default's).
    func rules(for profile: String) -> PrivacyRules { book[profile] }

    /// The profiles there are besides Default: one from a file from before per-profile choices
    /// gets that file's, one that is gone loses its own. At launch and when a profile comes or goes.
    func adopt(profiles: Set<String>) {
        var next = saved
        next.adopt(profiles: profiles)
        guard next != saved || saved.sharedByEveryProfile else { return }
        saved = next
        var live = book
        live.adopt(profiles: profiles)
        book = live
        rulesFile.save(saved)
    }

    /// `remembered` false in an incognito window: the choice holds until the last incognito
    /// window closes and is never written down (it would name a site visited there).
    func setChoice(_ choice: PrivacyRules.Choice, for party: String, on site: String, profile: String, remembered: Bool = true) {
        book[profile].set(choice, for: party, on: site)
        if remembered { saved[profile].set(choice, for: party, on: site) }
        NicheLog.note("Privacy rule: \(choice.rawValue)")
        rulesChanged()
    }

    func setProtection(off: Bool, on site: String, profile: String, remembered: Bool = true) {
        book[profile].setOff(off, on: site)
        if remembered { saved[profile].setOff(off, on: site) }
        NicheLog.note("Privacy protection \(off ? "off" : "on") for a site")
        rulesChanged()
    }

    /// The privacy panel's filtering slider for one site (`FilteringMode`). `standard` is the
    /// profile's mode for every site: picking it gives the site back to the setting.
    func setMode(_ mode: FilteringMode, on site: String, standard: FilteringMode, profile: String, remembered: Bool = true) {
        book[profile].setMode(mode, on: site, standard: standard)
        if remembered { saved[profile].setMode(mode, on: site, standard: standard) }
        NicheLog.note("Privacy filtering \(mode.title.lowercased()) for a site")
        rulesChanged()
    }

    /// Settings ▸ Privacy "Reset…": every block, exception and site switch of the profile goes.
    func resetRules(profile: String) {
        book[profile] = PrivacyRules()
        saved[profile] = PrivacyRules()
        NicheLog.note("Privacy rules reset")
        rulesChanged()
    }

    private func rulesChanged() {
        rulesFile.save(saved)
    }
}
