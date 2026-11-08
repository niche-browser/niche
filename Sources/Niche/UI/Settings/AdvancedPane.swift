import NicheCEF
import SwiftUI

/// Updates, the engine, search, quitting, import and export, and the version.
struct AdvancedPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = SoftwareUpdater.shared
        let littleWindowKey = KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N"
        SettingsCardPane {
            SettingsSection(title: "Updates") {
                SettingsToggleRow(title: "Update Niche automatically", isOn: $updater.automaticallyUpdates)
                    .disabled(!updater.isAvailable)
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Software update", detail: updater.lastCheckSummary)
                } trailing: {
                    Button("Check Now") { updater.checkForUpdates(nil) }
                        .disabled(!updater.isAvailable)
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
            SettingsSection(title: "Websites") {
                SettingsToggleRow(title: "Chrome engine for pages",
                                  detail: "Extensions and Chrome DevTools. Takes effect after a restart.",
                                  isOn: $store.settings.chromeEngine)
                SettingsCardDivider()
                // Arc: "Allow websites to get your theme data" (--arc-palette-* variables).
                SettingsToggleRow(title: "Let websites read your theme colours", isOn: $store.settings.shareThemeWithWebsites)
                SettingsCardDivider()
                // Arc: "Allow window dragging from the top of webpages" (with the toolbar hidden).
                SettingsToggleRow(title: "Drag the window from the top of pages", isOn: $store.settings.pageTopWindowDrag)
                SettingsCardDivider()
                SettingsToggleRow(title: "Boosts on websites you visit", isOn: $store.settings.boostsEnabled)
                SettingsCardDivider()
                // Arc: Settings ▸ Advanced "Play Arc sound effects".
                SettingsToggleRow(title: "Sound effects", isOn: $store.settings.soundEffects)
            }
            SettingsSection(title: "Quitting") {
                SettingsToggleRow(title: "Warn before quitting", isOn: $store.settings.warnBeforeQuitting)
                    .disabled(store.settings.keepInMenuBar)
                SettingsCardDivider()
                // GitHub #231: ⌘Q puts Niche in the menu bar instead of quitting.
                SettingsToggleRow(title: "Keep Niche in the menu bar",
                                  detail: "⌘Q closes windows but Niche keeps running, so \(littleWindowKey) opens a Little Window at once.",
                                  isOn: $store.settings.keepInMenuBar)
                SettingsCardDivider()
                // Arc: "When opening Arc, restore windows from previous session".
                SettingsToggleRow(title: "Restore windows when Niche opens", isOn: $store.settings.restoreWindows)
            }
            SettingsSection(title: "Your data") {
                SettingsCardRow {
                    SettingsLabel(title: "Import", detail: "Spaces, tabs, passwords and extensions from \(importSources).")
                } trailing: {
                    Button("Import…") { actions.importData() }
                }
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Export", detail: "Favorites, pinned tabs and folders as a bookmarks file.")
                } trailing: {
                    Button("Export…") { SidebarExport.run(store, in: NSApp.keyWindow) }
                }
            }
            SettingsSection(title: "About") {
                SettingsCardRow {
                    SettingsLabel(title: "Niche \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")",
                                  detail: "Chromium \(NicheCEFRuntime.chromiumVersion()) · CEF \(NicheCEFRuntime.cefVersion())")
                } trailing: {
                    EmptyView()
                }
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Data folder", detail: AppPaths.supportDir.path)
                        .textSelection(.enabled)
                } trailing: {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDir]) }
                }
            }
        }
    }

    private var importSources: String {
        let names = ImportSource.allCases.filter { $0.kind != .safari && $0.isAvailable }.map(\.name)
        return names.isEmpty ? "Safari" : (names.prefix(3) + ["Safari"]).joined(separator: ", ")
    }
}

/// Chromium's default search engine, the one chrome://settings/searchEngines sets (Arc: Settings ▸
/// Profiles ▸ Default Search Engine, beside "Search Settings"): its built-in engines and whichever is
/// the default. The page adds, edits and removes the rest.
private struct SearchEnginePicker: View {
    let store: SidebarStore
    let openURL: (String) -> Void
    @State private var engines: [ChromiumSearchEngine] = []
    @State private var selected = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { selected }, set: pick)) {
                ForEach(engines, id: \.keyword) { Text($0.name).tag($0.keyword) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Manage…") { openURL(SearchEngines.settingsPage) }
        }
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
