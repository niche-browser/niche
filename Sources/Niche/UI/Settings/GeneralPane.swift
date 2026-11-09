import SwiftUI

/// The browser's place on the Mac, search, starting and quitting, and updates with the version.
struct GeneralPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    private let system = SystemIntegration.shared
    @State private var error: String?

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = SoftwareUpdater.shared
        let littleWindowKey = KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N"
        SettingsCardPane {
            SettingsSection(title: "System", footnote: error) {
                SettingsCardRow {
                    SettingsLabel(title: "Default browser",
                                  detail: system.isDefaultBrowser ? "Links from other apps open in Niche."
                                      : system.defaultBrowserName.map { "Links from other apps open in \($0)." })
                } trailing: {
                    if system.isDefaultBrowser {
                        Label("Default", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button(system.isPromptingDefault ? "Confirm in the Dialog…" : "Make Default") {
                            Task { await system.makeDefaultBrowser() }
                        }
                        .buttonStyle(.settingsProminent)
                        .disabled(system.isPromptingDefault)
                    }
                }
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Keep Niche in the Dock")
                } trailing: {
                    if system.isInDock {
                        Label("In the Dock", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button("Add to Dock") { if !system.addToDock() { error = "Niche couldn’t be added to the Dock." } }
                    }
                }
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Open Niche at login")
                } trailing: {
                    SettingsSwitch(title: "Open Niche at login",
                                   isOn: Binding(get: { system.launchesAtLogin }, set: { error = system.setLaunchAtLogin($0) }))
                }
            }
            SettingsSection(title: "Search") {
                SettingsCardRow {
                    SettingsLabel(title: "Search engine")
                } trailing: {
                    SearchEnginePicker(store: store, openURL: actions.openURL)
                }
                SettingsCardDivider()
                SettingsToggleRow(title: "Show search suggestions", isOn: $store.settings.searchSuggestions)
            }
            SettingsSection(title: "Starting and quitting") {
                SettingsToggleRow(title: "Restore windows when Niche opens", isOn: $store.settings.restoreWindows)
                SettingsCardDivider()
                SettingsToggleRow(title: "Warn before quitting", isOn: $store.settings.warnBeforeQuitting)
                    .disabled(store.settings.keepInMenuBar)
                SettingsCardDivider()
                // GitHub #231: ⌘Q puts Niche in the menu bar instead of quitting.
                SettingsToggleRow(title: "Keep Niche in the menu bar",
                                  detail: "⌘Q closes windows but Niche keeps running, so \(littleWindowKey) opens a Little Window at once.",
                                  isOn: $store.settings.keepInMenuBar)
            }
            SettingsSection(title: "Updates") {
                SettingsCardRow {
                    HStack(spacing: 12) {
                        BrandTile()
                        SettingsLabel(title: "Niche \(Self.version)", detail: updater.lastCheckSummary)
                    }
                } trailing: {
                    Button("Check for Updates") { updater.checkForUpdates(nil) }
                        .disabled(!updater.isAvailable)
                }
                SettingsCardDivider()
                SettingsToggleRow(title: "Update Niche automatically", isOn: $updater.automaticallyUpdates)
                    .disabled(!updater.isAvailable)
            }
        }
        .onAppear { system.refresh() }
    }

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}

/// The app's own icon, small, in front of its version.
private struct BrandTile: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
    }
}

/// Chromium's default search engine, the one chrome://settings/searchEngines sets: its built-in
/// engines and whichever is the default. That page adds, edits and removes the rest.
private struct SearchEnginePicker: View {
    let store: SidebarStore
    let openURL: (String) -> Void
    @State private var engines: [ChromiumSearchEngine] = []
    @State private var selected = ""

    var body: some View {
        Picker("Search engine", selection: Binding(get: { selected }, set: pick)) {
            ForEach(engines, id: \.keyword) { Text($0.name).tag($0.keyword) }
        }
        .settingsMenu()
        Button("Manage…") { openURL(SearchEngines.settingsPage) }
            .onAppear(perform: reload)
    }

    private func reload() {
        let current = SearchEngines.shared.defaultEngine(profilePath: nil, legacy: store.settings.searchEngine)
        var list = SearchEngines.shared.keywords(profilePath: nil).filter(\.isBuiltIn)
        if !list.contains(where: { $0.keyword == current.keyword }) { list.insert(current, at: 0) }
        engines = list
        selected = current.keyword
    }

    private func pick(_ keyword: String) {
        guard let engine = engines.first(where: { $0.keyword == keyword }) else { return }
        SearchEngines.shared.setDefault(engine, store: store)
        selected = keyword
    }
}
