import AppKit
import NicheCEF

/// What a window keeps for its privacy panel while it is open.
struct PrivacyPanelState {
    /// Reads the page's fingerprinting reports for the tab on screen.
    var poll: Timer?
    /// How often the page on screen is asked what it was seen reading.
    static let pollEvery: TimeInterval = 1.5
}

/// The privacy panel: the card at the right of the page (PrivacyPanelCard) that says who the
/// page talks to and lets the user block them. Opened from the toolbar's shield, the Site Control
/// Center, the View menu or the command bar. Every page is recorded all the time (PrivacyMonitor),
/// so the panel shows the whole of what a page did whenever it is opened; while it is open it
/// also asks the page on screen what its scripts were seen reading.
extension MainWindowController {
    var privacyPanelOpen: Bool { shell.privacyPanelWidth > 0 }

    func togglePrivacyPanel() {
        if privacyPanelOpen { hidePrivacyPanel() } else { showPrivacyPanel() }
    }

    func showPrivacyPanel() {
        guard !privacyPanelOpen else { return }
        let model = shell.privacyPanel.model
        model.remembersChoices = !isIncognito
        model.onClose = { [weak self] in self?.hidePrivacyPanel() }
        // Past the cache: a script the page already has is not asked for again, and a rule that
        // now blocks it would seem to do nothing.
        model.onReload = { [weak self] in self?.currentBrowser?.reloadIgnoringCache() }
        model.onSettings = { [weak self] in self?.app.showSettings(.privacy) }
        // A window too narrow for the panel grows by what is missing, as far as its screen allows.
        let shortfall = shell.privacyPanelShortfall(width: PrivacyPanelMetrics.width)
        if shortfall > 0, let window, let screen = window.screen, !window.styleMask.contains(.fullScreen) {
            let grown = PrivacyPanelFit.grown(x: Double(window.frame.minX), width: Double(window.frame.width), by: Double(shortfall),
                                              visibleMinX: Double(screen.visibleFrame.minX), visibleMaxX: Double(screen.visibleFrame.maxX))
            var frame = window.frame
            frame.origin.x = CGFloat(grown.x)
            frame.size.width = CGFloat(grown.width)
            window.setFrame(frame, display: true, animate: !Design.Motion.reduced)
        }
        shell.privacyPanelWidth = PrivacyPanelMetrics.width
        sidebarUI.privacyPanelOpen = true
        syncPrivacyPanel()
        // The page makes room at once; the panel arrives over it.
        if !Design.Motion.reduced {
            shell.privacyPanel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Design.Motion.standard
                context.timingFunction = Design.Motion.curve
                shell.privacyPanel.animator().alphaValue = 1
            }
        }
        readPrivacyProbes()
        privacy.poll = Timer.scheduledTimer(withTimeInterval: PrivacyPanelState.pollEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readPrivacyProbes() }
        }
        NicheLog.note("Privacy panel opened")
    }

    func hidePrivacyPanel() {
        guard privacyPanelOpen else { return }
        privacy.poll?.invalidate()
        privacy.poll = nil
        shell.privacyPanelWidth = 0
        sidebarUI.privacyPanelOpen = false
        NicheLog.note("Privacy panel closed")
    }

    /// Tells the monitor which browser each live tab's page is in, and the panel which tab is on
    /// screen. Called when a page changes and when the selection does.
    func syncPrivacyPanel() {
        var tabs: [UUID: Int] = [:]
        for (id, rt) in browsers.runtimes where !(rt.browser is WebKitBrowser) && rt.browser.browserIdentifier != 0 {
            tabs[id] = rt.browser.browserIdentifier
        }
        PrivacyMonitor.shared.bind(window: ObjectIdentifier(self), tabs: tabs, leavesNoTrace: isIncognito)
        guard privacyPanelOpen else { return }
        let model = shell.privacyPanel.model
        let tab = browsers.visibleTabID
        let url = tab.flatMap { store.item($0)?.tab?.url } ?? ""
        let reason: String?
        if tab == nil {
            reason = "Open a website to see who it talks to."
        } else if currentBrowser is WebKitBrowser {
            reason = "This page plays in Safari’s engine, which Niche can’t watch."
        } else if PrivacySite.site(ofURL: url) == nil {
            reason = "Privacy details show for websites. This is one of Niche’s own pages."
        } else {
            reason = nil
        }
        if model.tabID != tab { model.tabID = tab }
        if model.pageURL != url { model.pageURL = url }
        if model.unavailable != reason { model.unavailable = reason }
        let icon = reason == nil ? app.favicons.image(for: url) : nil
        if model.favicon !== icon { model.favicon = icon }
        let protections = PrivacyProtections(store.settings)
        if model.protections != protections { model.protections = protections }
        if model.standardMode != store.settings.filteringMode { model.standardMode = store.settings.filteringMode }
    }

    /// Asks the page on screen what its scripts were seen reading since the last time; `then` runs
    /// on the main thread once the answer is in the ledger (or there is nobody to ask).
    func readPrivacyProbes(then: @escaping () -> Void = {}) {
        guard let tab = browsers.visibleTabID, let browser = currentBrowser, !(browser is WebKitBrowser),
              browser.isCreated, !browser.isClosed, let url = store.item(tab)?.tab?.url, PrivacySite.site(ofURL: url) != nil,
              let body = try? JSONSerialization.data(withJSONObject: ["expression": PrivacyProbeScript.drain, "returnByValue": true]),
              let params = String(data: body, encoding: .utf8) else { return then() }
        browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, _ in
            let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { $0["result"] as? [String: Any] }?["value"] as? String
            let reports = value.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
            DispatchQueue.main.async {
                PrivacyMonitor.shared.record(probes: reports, tab: tab, pageURL: url)
                then()
            }
        }
    }

    /// `niche://debug?privacy=<label>`: what the panel has for the tab on screen, on one log line
    /// (scenarios and checks read it): the counts, then each company with where it stands.
    func debugPrivacy(label: String) {
        // What the page was seen reading is asked for first, so the line doesn't depend on when
        // the panel last asked.
        readPrivacyProbes { [weak self] in self?.logPrivacy(label: label) }
    }

    private func logPrivacy(label: String) {
        guard let tab = browsers.visibleTabID, let url = store.item(tab)?.tab?.url,
              let ledger = PrivacyMonitor.shared.ledger(tab: tab, pageURL: url) else {
            NicheLog.note("privacy[\(label)] nothing to watch")
            return
        }
        let s = ledger.summary
        let parties = ledger.sorted.map { p in
            "\(p.id)=\(PrivacyWords.status(p).lowercased().replacingOccurrences(of: " ", with: "-"))(\(p.blocked)/\(p.requests))"
                + (p.cookiesSent.isEmpty ? "" : " cookies-sent=\(p.cookiesSent.count)")
                + (p.cookiesSaved.isEmpty ? "" : " cookies-left=\(p.cookiesSaved.count)")
                + (p.cookiesWithheld.isEmpty ? "" : " cookies-kept-back=\(p.cookiesWithheld.count)")
                + (p.probes.isEmpty ? "" : " probes=" + p.probes.map(\.rawValue).sorted().joined(separator: "+"))
        }
        let mode = PrivacyMonitor.shared.rules.mode(on: ledger.pageSite, standard: store.settings.filteringMode)
        NicheLog.note("privacy[\(label)] open=\(privacyPanelOpen) site=\(ledger.pageSite) companies=\(s.parties) blocked=\(s.blocked) see-you=\(s.sawYou) "
                      + "other=\(s.others) requests-blocked=\(s.blockedRequests) cleaned=\(s.cleanedAddress) mode=\(mode.title.lowercased()) | " + parties.joined(separator: " "))
    }
}
