import AppKit
import NicheCEF
import SwiftUI

private enum Metrics {
    /// A profile's round monogram plate.
    static let monogram: CGFloat = 28
    /// Where the dividers start under the profile rows: at their text, past the monogram.
    static let monogramDividerInset = Design.Space.rowInset + monogram + Design.Space.l
    /// The download location menu: every profile's is the same width.
    static let downloadMenuWidth: CGFloat = 220
}

/// The profiles and the spaces using each, then each profile's downloads, website languages and
/// Chromium pages. A space picks its profile in Edit Space. Only a profile no space uses can be
/// deleted, and never Default.
struct ProfilesPane: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        SettingsCardPane {
            SettingsSection(title: "Profiles",
                            footnote: "Each profile keeps its own logins, cookies and site data. Assign one to a space from the space’s menu.") {
                row(name: "Default", profileID: nil) { EmptyView() }
                ForEach(store.profiles) { p in
                    SettingsCardDivider(inset: Metrics.monogramDividerInset)
                    row(name: p.name, profileID: p.id) {
                        Button("Rename…") { rename(p) }
                        Button("Delete…") { delete(p) }
                            .disabled(!store.spaces(usingProfile: p.id).isEmpty)
                    }
                }
                SettingsCardDivider(inset: 0)
                SettingsCardRow {
                    Button { actions.newProfile() } label: {
                        Label("New Profile…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(Design.Font.control)
                    .foregroundStyle(Design.accent)
                } trailing: {
                    // Spaces an Arc import left on Default, back on their Arc profiles (#131).
                    if ArcProfileRebuilder.isAvailable {
                        Button("Rebuild from Arc…") { actions.rebuildArcProfiles() }
                            .help("Put spaces imported from Arc back on the profiles they use in Arc, with their sign-ins and extensions.")
                    }
                }
            }
            // Per-profile download location, GitHub #190.
            SettingsSection(title: "Downloads", footnote: "Where each profile saves downloads.") {
                downloadRow(name: "Default", profileID: nil)
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    downloadRow(name: p.name, profileID: p.id)
                }
            }
            // Chromium's per-profile website languages (#209).
            SettingsSection(title: "Languages", footnote: "The languages websites use for each profile, most wanted first.") {
                languageRow(name: "Default", profileID: nil)
                ForEach(store.profiles) { p in
                    SettingsCardDivider()
                    languageRow(name: p.name, profileID: p.id)
                }
            }
            .id(nav.shown)  // read again each time Settings comes up: Chromium's page may have changed them
            SettingsSection(title: "Your data and settings") {
                ForEach(Array(Self.dataPages.enumerated()), id: \.offset) { i, page in
                    if i > 0 { SettingsCardDivider(inset: SettingsMetrics.glyphDividerInset) }
                    dataRow(page)
                }
            }
        }
    }

    /// Chromium's pages for the profile, each with its plate colour.
    static let dataPages: [(title: String, symbol: String, url: String)] = [
        ("Privacy and security", "lock.fill", "chrome://settings/privacy"),
        ("Passwords", "key.fill", "chrome://password-manager/passwords"),
        ("Payment methods", "creditcard.fill", "chrome://settings/payments"),
        ("Notifications", "bell.fill", "chrome://settings/content/notifications"),
    ]

    private func dataRow(_ page: (title: String, symbol: String, url: String)) -> some View {
        SettingsCardRow {
            SettingsIconLabel(title: page.title, symbol: page.symbol, color: Self.plate(page.symbol))
        } trailing: {
            if store.profiles.isEmpty {
                Button("Open") { actions.openProfilePage(page.url, nil) }
            } else {
                // One set of pages per Profile: pick whose.
                Menu("Open") {
                    Button("Default") { actions.openProfilePage(page.url, nil) }
                    ForEach(store.profiles) { p in Button(p.name) { actions.openProfilePage(page.url, p.id) } }
                }
                .menuStyle(.button)
                .controlSize(.regular)
                .fixedSize()
            }
        }
    }

    private static func plate(_ symbol: String) -> Color {
        switch symbol {
        case "lock.fill": return .blue
        case "key.fill": return .gray
        case "creditcard.fill": return .green
        default: return .red
        }
    }

    private enum DownloadChoice: Hashable { case folder, ask, other }

    private func downloadRow(name: String, profileID: UUID?) -> some View {
        let location = store.settings.downloadLocation(profileID: profileID)
        let folder = DownloadDestinations.folder(profileID: profileID)
        let choice = Binding<DownloadChoice>(
            get: { location.askWhereToSave ? .ask : .folder },
            set: { picked in
                var l = store.settings.downloadLocation(profileID: profileID)
                switch picked {
                case .folder: l.askWhereToSave = false
                case .ask: l.askWhereToSave = true
                case .other:
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = folder
                    panel.prompt = "Select"
                    panel.message = "Choose where \(name) saves downloaded files."
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    l.folder = url.standardizedFileURL.path == DownloadDestinations.downloadsFolder.standardizedFileURL.path ? nil : url.path
                    l.askWhereToSave = false
                }
                store.settings.setDownloadLocation(l, profileID: profileID)
            })
        return SettingsCardRow {
            SettingsLabel(title: name)
        } trailing: {
            Picker("Download location", selection: choice) {
                Label(FileManager.default.displayName(atPath: folder.path), systemImage: "folder").tag(DownloadChoice.folder)
                Text("Ask Where to Save Each File").tag(DownloadChoice.ask)
                Divider()
                Text("Other…").tag(DownloadChoice.other)
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.regular)
            .frame(width: Metrics.downloadMenuWidth)
            .help(folder.path)
        }
    }

    private func languageRow(name: String, profileID: UUID?) -> some View {
        let summary = BrowserLanguages.summary(languages(profileID: profileID))
        let hasSpace = !store.spaces(usingProfile: profileID).isEmpty
        return SettingsCardRow {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(name).font(Design.Font.body)
                Text(summary.isEmpty ? "The browser’s default languages" : summary)
                    .font(Design.Font.detail).foregroundStyle(.secondary).lineLimit(1)
                    .help(summary)
            }
        } trailing: {
            Button("Change…") { actions.openProfilePage(BrowserLanguages.settingsPage, profileID) }
                .disabled(!hasSpace)
                .help(hasSpace ? "Open the language settings for \(name)." : "Set \(name) on a space first.")
        }
    }

    /// What Chromium holds for the profile now, else what its Preferences file saved (a profile no
    /// page has loaded in since launch).
    private func languages(profileID: UUID?) -> [String] {
        let path = store.profilePath(profile: profileID)
        if let json = NicheCEFRuntime.preference(BrowserLanguages.pref, forProfile: path) {
            return BrowserLanguages.codes(json)
        }
        let folder = path.map { URL(fileURLWithPath: $0) } ?? AppPaths.chromiumCache.appendingPathComponent("Default")
        return (try? Data(contentsOf: folder.appendingPathComponent("Preferences")))
            .flatMap(BrowserLanguages.codes(preferencesFile:)) ?? []
    }

    private func rename(_ profile: BrowserProfile) {
        guard let window = AppDialog.parentWindow else { return }
        let dialog = AppDialog(title: "Rename your Profile",
                               message: "This won’t affect the names of any of the Spaces associated with this Profile.",
                               actions: [DialogAction("Save"), .cancel], input: profile.name, placeholder: "Profile name", requiresInput: true,
                               icon: .none, width: 496)
        dialog.present(over: window) { response in
            guard response == .alertFirstButtonReturn, let name = dialog.input else { return }
            store.renameProfile(profile.id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func delete(_ profile: BrowserProfile) {
        guard let window = AppDialog.parentWindow else { return }
        let dialog = AppDialog(title: "Delete “\(profile.name)”?",
                               message: "Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.",
                               actions: [DialogAction("Delete Profile", role: .destructive), .cancel])
        dialog.present(over: window) { response in
            if response == .alertFirstButtonReturn { store.deleteProfile(profile.id) }
        }
    }

    private func row<Trailing: View>(name: String, profileID: UUID?, @ViewBuilder trailing: () -> Trailing) -> some View {
        let spaces = store.spaces(usingProfile: profileID)
        return SettingsCardRow {
            HStack(spacing: Design.Space.l) {
                ProfileMonogram(name: name)
                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                    Text(name).font(Design.Font.body)
                    Text(spaces.isEmpty ? "No spaces use it" : "Used by " + spaces.map(\.labeled).joined(separator: ", "))
                        .font(Design.Font.detail).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } trailing: {
            trailing()
        }
    }
}

/// A profile's first letter on a soft round plate.
private struct ProfileMonogram: View {
    let name: String
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Design.Font.ui(.body, .semibold))
            .foregroundStyle(.secondary)
            .frame(width: Metrics.monogram, height: Metrics.monogram)
            .background(Circle().fill(Design.fill(.selected)))
            .accessibilityHidden(true)
    }
}
