import NicheCore
import Testing

/// Help ▸ Export Diagnostics: what a zip attached to a public issue keeps.
struct DiagnosticsRedactionTests {
    let home = "/Users/someone"

    @Test(arguments: [
        ("loaded https://mail.example.com/inbox/123?q=secret", "loaded https://mail.example.com/…"),
        ("ws wss://live.example.com:8443/socket#x", "ws wss://live.example.com:8443/…"),
        ("\"url\":\"chrome-extension://abcdef/options.html\"", "\"url\":\"chrome-extension://abcdef/…\""),
        ("https://example.com", "https://example.com"),
    ])
    func addressesKeepOnlyTheirSite(line: String, kept: String) {
        #expect(DiagnosticsRedaction.redact(line, home: home) == kept)
    }

    @Test(arguments: [
        ("https://user:pass@intranet.example.com/a", "https://intranet.example.com/…"),
        ("ftp://me@files.example.com", "ftp://files.example.com"),
    ])
    func credentialsAreDropped(line: String, kept: String) {
        #expect(DiagnosticsRedaction.redact(line, home: home) == kept)
    }

    @Test func homeFolderBecomesTilde() {
        let report = #"{"path":"\/Users\/someone\/Applications\/Niche.app"} /Users/someone/Library/Logs"#
        #expect(DiagnosticsRedaction.redact(report, home: home) == #"{"path":"~\/Applications\/Niche.app"} ~/Library/Logs"#)
    }

    @Test func singleSignOnHostsAreHidden() {
        let line = #"--flag --auth-server-allowlist=*.corp.example.com,sso.example.com --other"#
        #expect(DiagnosticsRedaction.redact(line, home: home) == "--flag --auth-server-allowlist=(set by IT) --other")
    }

    @Test(arguments: [
        ("Niche-2026-11-01-120000.ips", true),
        ("Niche Helper (Renderer)-2026-11-01-120000.ips", true),
        ("Craft-2026-11-01-120000.ips", false),
        ("NicheClip-2026-11-01-120000.ips", false),
        ("Safari-2026-11-01-120000.ips", false),
    ])
    func onlyNichesOwnCrashReports(name: String, isNiche: Bool) {
        #expect(DiagnosticsRedaction.isNicheCrashReport(name) == isNiche)
    }
}
