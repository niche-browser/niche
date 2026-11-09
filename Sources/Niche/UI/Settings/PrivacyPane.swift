import SwiftUI

/// Content blocking, connections (HTTPS-only and secure DNS) and the profile's browsing data.
struct PrivacyPane: View {
    @Environment(SidebarStore.self) private var store
    let actions: SettingsActions

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            SettingsSection(title: "Content blocking") {
                SettingsCardRow {
                    SettingsIconLabel(title: "Block ads and trackers",
                                      detail: "Known ad and tracker requests are cancelled unless they come from the page’s own site.",
                                      symbol: "hand.raised.fill", color: .red)
                } trailing: {
                    SettingsSwitch(title: "Block ads and trackers", isOn: $store.settings.blockAdsAndTrackers)
                }
                SettingsCardDivider(inset: 54)
                SettingsCardRow {
                    SettingsIconLabel(title: "Block cookie banners", symbol: "eye.slash.fill", color: .orange)
                } trailing: {
                    SettingsSwitch(title: "Block cookie banners", isOn: $store.settings.blockCookieBanners)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader("Connections")
                SettingsCard {
                    SettingsCardRow {
                        SettingsIconLabel(title: "Always use secure connections",
                                          detail: "Niche warns you before opening a site that doesn’t support HTTPS.",
                                          symbol: "lock.fill", color: .green)
                    } trailing: {
                        SettingsSwitch(title: "Always use secure connections", isOn: $store.settings.httpsOnly)
                    }
                    SettingsCardDivider(inset: 54)
                    SecureDNSRows(error: $dnsError)
                }
                if let line = dnsFootnote { SettingsFootnote(line) }
                if let dnsError { SettingsFootnote(dnsError).foregroundStyle(.red) }
            }
            .padding(.bottom, Design.Space.section)
            SettingsSection(title: "Data") {
                SettingsCardRow {
                    SettingsIconLabel(title: "Browsing data", detail: "History, cookies and cached files for the current space’s profile.",
                                      symbol: "trash.fill", color: .gray)
                } trailing: {
                    Button("Clear…") { actions.openURL(BrowsingDataClear.pageURL) }
                }
            }
        }
    }

    @State private var dnsError: String?

    private var dnsFootnote: String? {
        let dns = SecureDNSSetting.shared
        guard let summary = dns.inEffect?.summary, !summary.isEmpty else { return nil }
        return dns.isManaged ? "Your organization sets secure DNS. " + summary : summary
    }
}

/// Chromium's secure DNS setting (chrome://settings/security) as a menu, under "Always use
/// secure connections": the lookup before the page (#133). Custom adds a row for the template.
private struct SecureDNSRows: View {
    @Binding var error: String?
    private let dns = SecureDNSSetting.shared
    @State private var editingCustom = false
    @State private var customText = ""

    var body: some View {
        SettingsCardRow {
            SettingsIconLabel(title: "Secure DNS", symbol: "network.badge.shield.half.filled", color: .blue)
        } trailing: {
            Picker("Secure DNS", selection: choice) {
                Text("Automatic").tag(SecureDNSChoice.automatic)
                Text("Off").tag(SecureDNSChoice.off)
                Divider()
                ForEach(SecureDNSProvider.all) { Text($0.name).tag(SecureDNSChoice.provider($0)) }
                Divider()
                Text("Custom…").tag(SecureDNSChoice.custom)
            }
            .settingsMenu()
            .disabled(dns.prefs == nil || dns.isManaged)
            .onAppear { dns.refresh() }
            .onChange(of: liveCustom, initial: true) { if let liveCustom { customText = liveCustom } }
        }
        if showsCustom {
            SettingsCardDivider(inset: 54)
            SettingsCardRow {
                SettingsTextField(placeholder: "https://dns.example/dns-query{?dns}", text: $customText, onSubmit: saveCustom)
                    .disabled(dns.isManaged)
            } trailing: {
                Button("Use", action: saveCustom)
                    .disabled(dns.isManaged || customText.trimmingCharacters(in: .whitespacesAndNewlines) == liveCustom)
            }
        }
    }

    private var current: SecureDNSChoice { dns.prefs?.choice ?? .automatic }
    private var liveCustom: String? { current == .custom ? dns.prefs?.templates : nil }
    private var showsCustom: Bool { editingCustom || current == .custom }

    private var choice: Binding<SecureDNSChoice> {
        Binding(get: { editingCustom ? .custom : current }, set: { new in
            error = nil
            if new == .custom {
                if !showsCustom { customText = "" }
                editingCustom = true
                return
            }
            editingCustom = false
            if let prefs = SecureDNSPrefs(new), !dns.apply(prefs) { error = "Niche couldn’t change secure DNS." }
        })
    }

    private func saveCustom() {
        guard let prefs = SecureDNSPrefs(.custom, custom: customText) else {
            error = "Enter one or more https:// templates, like https://dns.example/dns-query{?dns}."
            return
        }
        error = nil
        if dns.apply(prefs) {
            editingCustom = false
            customText = prefs.templates
        } else {
            error = "Niche couldn’t change secure DNS."
        }
    }
}
