import NicheCEF
import SwiftUI

/// The engine and websites, moving data in and out, and troubleshooting.
struct AdvancedPane: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            SettingsSection(title: "Websites") {
                SettingsToggleRow(title: "Chrome engine for pages",
                                  detail: "Extensions and Chrome DevTools. Takes effect after a restart.",
                                  isOn: $store.settings.chromeEngine)
                SettingsCardDivider()
                SettingsToggleRow(title: "Let websites read your theme colors", isOn: $store.settings.shareThemeWithWebsites)
                SettingsCardDivider()
                SettingsToggleRow(title: "Drag the window from the top of pages", isOn: $store.settings.pageTopWindowDrag)
                SettingsCardDivider()
                SettingsToggleRow(title: "Boosts on websites you visit", isOn: $store.settings.boostsEnabled)
            }
            SettingsSection(title: "Your data") {
                SettingsCardRow {
                    SettingsIconLabel(title: "Import", detail: "Spaces, tabs, passwords and extensions from \(importSources).",
                                      symbol: "square.and.arrow.down", color: .blue)
                } trailing: {
                    Button("Import…") { actions.importData() }
                }
                SettingsCardDivider(inset: 54)
                SettingsCardRow {
                    SettingsIconLabel(title: "Export", detail: "Favorites, pinned tabs and folders as a bookmarks file.",
                                      symbol: "square.and.arrow.up", color: .indigo)
                } trailing: {
                    Button("Export…") { SidebarExport.run(store, in: NSApp.keyWindow) }
                }
            }
            SettingsSection(title: "Troubleshooting") {
                SettingsCardRow {
                    SettingsIconLabel(title: "Performance", detail: "Freezes, CPU and memory, measured on this Mac.",
                                      symbol: "gauge.with.dots.needle.67percent", color: .orange)
                } trailing: {
                    Button("Open") { nav.show(.performance) }
                }
                SettingsCardDivider(inset: 54)
                SettingsCardRow {
                    SettingsIconLabel(title: "Data folder", detail: "Profiles, settings and logs.", symbol: "folder.fill", color: .gray)
                        .help(AppPaths.supportDir.path)
                } trailing: {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDir]) }
                }
                SettingsCardDivider(inset: 54)
                SettingsCardRow {
                    SettingsIconLabel(title: "Browser engine", detail: "Chromium \(NicheCEFRuntime.chromiumVersion())",
                                      symbol: "cpu", color: .teal)
                        .textSelection(.enabled)
                } trailing: {
                    EmptyView()
                }
            }
        }
    }

    private var importSources: String {
        let names = ImportSource.allCases.filter { $0.kind != .safari && $0.isAvailable }.map(\.name)
        return names.isEmpty ? "Safari" : (names.prefix(3) + ["Safari"]).joined(separator: ", ")
    }
}
