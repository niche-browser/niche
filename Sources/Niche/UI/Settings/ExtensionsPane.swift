import AppKit
import SwiftUI

private enum Metrics {
    /// The plate behind an extension's icon.
    static let iconPlate: CGFloat = 28
    /// Where the dividers start: at the rows' text, past the icon.
    static let dividerInset = Design.Space.rowInset + iconPlate + Design.Space.l
}

/// Installed extensions, each with its icon, version and description, and the ways to add and
/// manage them at the foot of the card.
struct ExtensionsPane: View {
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    @State private var extensions = ExtensionStore()
    @State private var error: String?

    var body: some View {
        SettingsCardPane {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader("Installed")
                SettingsCard {
                    if extensions.entries.isEmpty {
                        SettingsCardRow {
                            SettingsIconLabel(title: "No extensions yet",
                                              detail: "Add one from the Chrome Web Store, or an unpacked extension folder.",
                                              symbol: "puzzlepiece.extension.fill", color: .gray)
                        } trailing: { EmptyView() }
                    }
                    ForEach(Array(extensions.entries.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { SettingsCardDivider(inset: Metrics.dividerInset) }
                        SettingsCardRow {
                            HStack(spacing: Design.Space.l) {
                                ExtensionRowIcon(image: e.icon)
                                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                                    HStack(spacing: Design.Space.s) {
                                        Text(e.name).font(Design.Font.body).lineLimit(1)
                                        Text(e.version).font(Design.Font.detail).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    if !e.description.isEmpty {
                                        Text(e.description).font(Design.Font.detail).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                        } trailing: {
                            if e.managedByChrome {
                                Button("Remove…") { actions.openURL("chrome://extensions/?id=\(e.extensionID)") }
                            } else {
                                Button("Remove") { extensions.remove(e) }
                            }
                        }
                    }
                    SettingsCardDivider(inset: 0)
                    SettingsCardRow {
                        Button { addExtension() } label: { Label("Add Unpacked Extension…", systemImage: "plus") }
                            .buttonStyle(.plain)
                            .font(Design.Font.control)
                            .foregroundStyle(Design.accent)
                    } trailing: {
                        Button("Manage…") { actions.openURL("chrome://extensions") }
                            .disabled(!store.settings.chromeEngine)
                            .help("All extensions, their permissions and site access.")
                    }
                }
                if let error { SettingsFootnote(error).foregroundStyle(Design.danger) }
                SettingsFootnote(store.settings.chromeEngine
                                 ? (extensions.needsRestart ? "Restart Niche to apply the change." : "Extensions load when Niche starts.")
                                 : "Extensions need the Chrome engine, in Advanced.")
            }
        }
    }

    private func addExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose an unpacked extension folder (it holds manifest.json)."
        if panel.runModal() == .OK, let url = panel.url {
            do { try extensions.add(folder: url); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}

/// An extension's own icon on a soft plate, or a puzzle piece when it has none.
private struct ExtensionRowIcon: View {
    let image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(Design.Space.xs)
            } else {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: Design.Icon.bar)).foregroundStyle(.secondary)
            }
        }
        .frame(width: Metrics.iconPlate, height: Metrics.iconPlate)
        .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(Design.fill(.hover)))
        .accessibilityHidden(true)
    }
}
