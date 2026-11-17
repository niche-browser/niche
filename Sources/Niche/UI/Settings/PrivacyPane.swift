import SwiftUI

/// Content blocking, connections (HTTPS-only and secure DNS) and the profile's browsing data.
struct PrivacyPane: View {
    @Environment(SidebarStore.self) private var store
    let actions: SettingsActions

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader("Protection")
                PrivacyLevelPicker(level: PrivacyLevel.level(of: store.settings)) { level in
                    level.apply(to: &store.settings)
                }
                SettingsFootnote(PrivacyLevel.level(of: store.settings) == nil
                                 ? "Custom: the switches below were changed by hand. Pick a level to go back to it."
                                 : "A level sets the switches below. Change any of them to make it your own.")
            }
            .padding(.bottom, Design.Space.section)
            SettingsSection(title: "Shields", footnote: shieldsLine) {
                shieldsRow(.ads, color: .red, isOn: $store.settings.blockAds)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                shieldsRow(.trackers, color: .orange, isOn: $store.settings.blockTrackers)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                shieldsRow(.cookies, color: .yellow, isOn: $store.settings.blockCookieNotices)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                shieldsRow(.annoyances, color: .indigo, isOn: $store.settings.blockAnnoyances)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                shieldsRow(.malware, color: .green, isOn: $store.settings.blockMaliciousSites)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                shieldsRow(.regional, color: .blue, isOn: $store.settings.useRegionalLists)
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                SettingsCardRow {
                    SettingsIconLabel(title: "Filter lists",
                                      detail: "Niche looks for newer lists once a day. They are the community’s: EasyList, uBlock Origin’s, AdGuard’s and others.",
                                      symbol: "arrow.triangle.2.circlepath", color: .gray)
                } trailing: {
                    HStack(spacing: Design.Space.m) {
                        Button("Credits") { showingCredits = true }
                            .disabled(ShieldsService.shared.credits.isEmpty)
                        Button(ShieldsService.shared.checking ? "Updating…" : "Update Now") { ShieldsService.shared.look() }
                            .disabled(ShieldsService.shared.checking || store.settings.shieldsGroups.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingCredits) { ShieldsCredits(credits: ShieldsService.shared.credits) { showingCredits = false } }
            SettingsSection(title: "Tracking") {
                SettingsCardRow {
                    SettingsIconLabel(title: "Block third-party cookies",
                                      detail: "A company embedded in another site’s page can’t use cookies to recognise you there.",
                                      symbol: "person.crop.circle.badge.xmark", color: .purple)
                } trailing: {
                    SettingsSwitch(title: "Block third-party cookies", isOn: $store.settings.blockThirdPartyCookies)
                }
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                SettingsCardRow {
                    SettingsIconLabel(title: "Remove tracking codes from links",
                                      detail: "Codes that say which ad or email you clicked are taken off a page’s address before it opens.",
                                      symbol: "link.badge.plus", color: .teal)
                } trailing: {
                    SettingsSwitch(title: "Remove tracking codes from links", isOn: $store.settings.removeTrackingParameters)
                }
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                SettingsCardRow {
                    SettingsIconLabel(title: "Tell websites not to sell or share my data",
                                      detail: "Sends the Global Privacy Control signal, which some laws require sites to honour.",
                                      symbol: "megaphone.fill", color: .blue)
                } trailing: {
                    SettingsSwitch(title: "Tell websites not to sell or share my data", isOn: $store.settings.sendGlobalPrivacyControl)
                }
                SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                SettingsCardRow {
                    SettingsIconLabel(title: "Notice fingerprinting",
                                      detail: "The privacy panel names scripts that read your Mac’s details to recognise it without a cookie.",
                                      symbol: "touchid", color: .pink)
                } trailing: {
                    SettingsSwitch(title: "Notice fingerprinting", isOn: $store.settings.noticeFingerprinting)
                }
            }
            SettingsSection(title: "Privacy panel",
                            footnote: PrivacyMonitor.shared.stats.line()) {
                SettingsCardRow {
                    SettingsIconLabel(title: "See who a page talks to",
                                      detail: "View ▸ Show Privacy Panel, or the shield beside a page’s address: every company on the page, what it learned, and a way to block it.",
                                      symbol: "shield.lefthalf.filled", color: .green)
                } trailing: {
                    Button("Show") { actions.showPrivacyPanel() }
                }
                if !PrivacyMonitor.shared.rules.isEmpty {
                    SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                    SettingsCardRow {
                        SettingsIconLabel(title: "Your own blocks and exceptions",
                                          detail: "What you blocked, allowed or switched off in the panel.",
                                          symbol: "slider.horizontal.3", color: .gray)
                    } trailing: {
                        Button("Reset…") { confirmingReset = true }
                    }
                }
            }
            .confirmationDialog("Forget what you blocked and allowed in the privacy panel?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive) { PrivacyMonitor.shared.resetRules() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Niche goes back to its own list on every site.")
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
                    SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
                    SecureDNSRows(error: $dnsError)
                }
                if let line = dnsFootnote { SettingsFootnote(line) }
                if let dnsError { SettingsFootnote(dnsError).foregroundStyle(Design.danger) }
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
    @State private var confirmingReset = false
    @State private var showingCredits = false

    /// One switch of Shields: what a group of filter lists is for.
    private func shieldsRow(_ group: ShieldsGroup, color: Color, isOn: Binding<Bool>) -> some View {
        SettingsCardRow {
            SettingsIconLabel(title: group.title, detail: group.detail, symbol: group.symbol, color: color)
        } trailing: {
            SettingsSwitch(title: group.title, isOn: isOn)
        }
    }

    /// Under the switches: how much is loaded and how fresh it is.
    private var shieldsLine: String {
        switch ShieldsService.shared.status {
        case .off: return "Shields are off: nothing is blocked or hidden."
        case .waiting: return "Getting the filter lists. Nothing is blocked until they arrive."
        case .ready(let rules):
            let number = NumberFormatter()
            number.numberStyle = .decimal
            var line = "\(number.string(from: NSNumber(value: rules)) ?? "\(rules)") rules from \(PrivacyWords.count(ShieldsService.shared.credits.count, "list"))"
            if let built = ShieldsService.shared.built {
                let date = RelativeDateTimeFormatter()
                date.unitsStyle = .full
                line += ", put together \(date.localizedString(for: built, relativeTo: Date()))"
            }
            return line + "."
        }
    }

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
            SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset)
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

/// The three privacy levels as cards: a shield that fills with the level, its name and what it
/// is for. Settings ▸ Privacy shows it; onboarding has its own, larger (OnboardingPrivacy).
struct PrivacyLevelPicker: View {
    let level: PrivacyLevel?
    let choose: (PrivacyLevel) -> Void

    var body: some View {
        HStack(spacing: Design.Space.l) {
            ForEach(PrivacyLevel.allCases, id: \.self) { option in
                let selected = option == level
                Button { choose(option) } label: {
                    VStack(alignment: .leading, spacing: Design.Space.s) {
                        HStack {
                            Image(systemName: option.symbol)
                                .font(.system(size: Design.Icon.large, weight: .medium))
                                .foregroundStyle(selected ? Design.accent : Design.inkColor(.secondary))
                            Spacer()
                            if option == PrivacyLevel.recommended {
                                Text("Recommended").font(Design.Font.ui(.micro, .medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xxs)
                                    .background(Capsule().fill(Design.fill(.subtle)))
                            }
                        }
                        Text(option.title).font(Design.Font.section)
                        Text(option.tagline).font(Design.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(Design.Space.l)
                    .frame(maxWidth: .infinity, minHeight: PrivacyLevelPicker.cardHeight, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .fill(selected ? Design.accentWash : Design.fill(.subtle)))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .strokeBorder(selected ? Design.accentRing : Design.hairline, lineWidth: selected ? Design.Space.xxs : Design.Space.hair))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title): \(option.tagline)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// A level's card: room for a two-line tagline.
    static let cardHeight: CGFloat = 112
}

/// Who wrote the filter lists in use, with each list's licence and a link to it.
private struct ShieldsCredits: View {
    let credits: [ShieldsService.Credit]
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            Text("Filter lists").font(Design.Font.title)
            Text("Shields runs on lists written and kept up by volunteers. Niche downloads them as they are; each stays under its own licence.")
                .font(Design.Font.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(credits.enumerated()), id: \.element.id) { i, credit in
                        if i > 0 { Rectangle().fill(Design.hairline).frame(height: Design.Space.hair) }
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                            VStack(alignment: .leading, spacing: Design.Space.hair) {
                                Text(credit.title).font(Design.Font.body)
                                Text("\(credit.group.title) · \(credit.licence)").font(Design.Font.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Design.Space.m)
                            if let url = URL(string: credit.homepage) {
                                Link("Website", destination: url).font(Design.Font.caption)
                            }
                        }
                        .padding(.vertical, Design.Space.m)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: done).buttonStyle(.settingsProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Design.Space.xxl)
        .frame(width: ShieldsCredits.width, height: ShieldsCredits.height)
    }

    static let width: CGFloat = 460
    static let height: CGFloat = 480
}
