import AppKit
import SwiftUI

/// The Shortcuts pane's own geometry.
private enum Metrics {
    /// The action list's column.
    static let listWidth: CGFloat = 300
    /// The plate behind the empty detail's symbol.
    static let emptyPlate: CGFloat = 44
    /// The recorder field: tall enough for full-size key caps.
    static let recorderHeight: CGFloat = 40
    /// The dot that pulses while a shortcut is recorded: its size, how far it dims, and one beat.
    static let recordingDot: CGFloat = 7
    static let pulseDim: CGFloat = 0.35
    static let pulse: TimeInterval = 0.7
    /// A key cap's side: in a list row, and in the recorder.
    static let capCompact: CGFloat = 18
    static let cap: CGFloat = 26
}

/// Every menu action and its keyboard shortcut: a searchable list grouped under the menus, and a
/// detail column to record a new shortcut for the selected action.
struct ShortcutsPane: View {
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var query = ""
    @State private var selectedID: String?
    @State private var customizedOnly = false
    @State private var conflictingOnly = false
    /// The search field has the keyboard only while the user is typing in it: picking an action
    /// or clicking elsewhere takes it away, and the pane never opens with it focused.
    @FocusState private var searchFocused: Bool

    private static let sections: [(MenuSection, String)] = [
        (.app, "Niche"), (.file, "File"), (.edit, "Edit"), (.view, "View"), (.spaces, "Spaces"),
        (.tabs, "Tabs"), (.archive, "Archive"), (.window, "Window"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            HStack(spacing: Design.Space.m) {
                SettingsSearchField(text: $query, focused: $searchFocused)
                iconMenu("line.3.horizontal.decrease", help: "Filter", active: customizedOnly || conflictingOnly) {
                    Toggle("Customized Shortcuts", isOn: $customizedOnly)
                    Toggle("Conflicting Shortcuts", isOn: $conflictingOnly)
                }
                iconMenu("ellipsis", help: "More", active: false) {
                    Button("Reset All Shortcuts") { bindings.resetOverrides() }
                }
            }
            HStack(alignment: .top, spacing: Design.Space.xxl) {
                list
                detail
            }
        }
        .frame(maxWidth: SettingsMetrics.contentWidth)
        .padding(.horizontal, Design.Space.pane)
        .padding(.top, Design.Space.xs)
        .padding(.bottom, Design.Space.pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = false }
        .onAppear {
            // AppKit hands the window's first text field the keyboard when the pane appears.
            DispatchQueue.main.async { searchFocused = false }
        }
    }

    private func iconMenu<Items: View>(_ symbol: String, help: String, active: Bool, @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: {
            SettingsIconTile(symbol: symbol, active: active)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: List

    private var visible: [(title: String, actions: [KeyAction])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.sections.compactMap { section, title in
            let acts = bindings.actions(in: section).filter { a in
                (q.isEmpty || a.name.lowercased().contains(q))
                    && (!customizedOnly || bindings.isOverridden(a.id))
                    && (!conflictingOnly || !conflicts(of: a).isEmpty)
            }
            return acts.isEmpty ? nil : (title, acts)
        }
    }

    private func conflicts(of a: KeyAction) -> [KeyAction] {
        guard let s = a.primary else { return [] }
        return bindings.actions.filter { $0.id != a.id && $0.shortcuts.contains(s) }
    }

    private var list: some View {
        SettingsCard {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Design.Space.hair) {
                    ForEach(visible, id: \.title) { group in
                        Text(group.title)
                            .font(Design.Font.ui(.caption, .semibold)).foregroundStyle(.tertiary)
                            .padding(.leading, SettingsMetrics.fieldInset)
                            .padding(.top, Design.Space.l)
                            .padding(.bottom, Design.Space.xs)
                        ForEach(group.actions) { a in row(a) }
                    }
                    if visible.isEmpty {
                        Text("No matching actions").font(Design.Font.detail).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, Design.Space.xxxl)
                    }
                }
                .padding(Design.Space.s)
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .frame(width: Metrics.listWidth)
    }

    private func row(_ a: KeyAction) -> some View {
        ShortcutListRow(action: a, selected: a.id == selectedID) {
            selectedID = a.id
            searchFocused = false
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let a = selectedID.flatMap({ bindings.action($0) }) {
            VStack(alignment: .leading, spacing: Design.Space.m) {
                HStack(alignment: .center) {
                    Text(a.name).font(Design.Font.ui(.headline, .semibold))
                    Spacer()
                    Menu {
                        Button("Reset to Default") { bindings.resetShortcuts(for: a.id) }.disabled(!bindings.isOverridden(a.id))
                        Button("Remove Shortcut") { bindings.setShortcuts([], for: a.id) }.disabled(a.shortcuts.isEmpty)
                    } label: {
                        SettingsIconTile(symbol: "ellipsis", active: false, size: Design.Space.controlCompact)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("Shortcut options")
                    .accessibilityLabel("Shortcut options")
                }
                Text(ShortcutDescriptions.text(for: a))
                    .font(Design.Font.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ShortcutRecorder(action: a)
                    .padding(.top, Design.Space.s)
                Text("Click the field, then press the new keys. Esc cancels, ⌫ removes the shortcut.")
                    .font(Design.Font.detail).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                let c = conflicts(of: a)
                if !c.isEmpty {
                    Label((c.count == 1 ? "Also used by " : "Also used by ") + c.map(\.name).joined(separator: ", "),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Design.Font.detail).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Design.Space.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: Design.Space.m) {
                Image(systemName: "command")
                    .font(.system(size: Design.Icon.large, weight: .medium)).foregroundStyle(.tertiary)
                    .frame(width: Metrics.emptyPlate, height: Metrics.emptyPlate)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(Design.fill(.hover)))
                Text("Perform common actions faster, from anywhere in Niche.")
                    .font(Design.Font.body)
                Text("Select an action to change its keyboard shortcut.")
                    .font(Design.Font.body).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Design.Space.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// A square icon button: the symbol centred on a soft plate that fills the whole hit area,
/// darker on hover and tinted while its filter is on.
struct SettingsIconTile: View {
    let symbol: String
    let active: Bool
    var size: CGFloat = Design.Space.control
    @State private var hovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: Design.Icon.regular, weight: .semibold))
            .foregroundStyle(active ? Design.accent : Color.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                .fill(active ? Design.accent.opacity(0.14) : Design.fill(hovered ? .pressed : .hover)))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Design.Motion.fast), value: hovered)
    }
}

/// One action in the list: name, its keys as caps, a soft plate when hovered or selected.
private struct ShortcutListRow: View {
    let action: KeyAction
    let selected: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Design.Space.m) {
                Text(action.name).font(Design.Font.body).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: Design.Space.m)
                if let s = action.primary { KeyCaps(caps: s.caps, compact: true) }
            }
            .padding(.horizontal, SettingsMetrics.fieldInset)
            .frame(height: Design.Space.control)
            .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .fill(selected ? Design.accent.opacity(0.16) : (hovered ? Design.rowHover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .strokeBorder(selected ? Design.accent.opacity(0.35) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A shortcut as one cap per key.
struct KeyCaps: View {
    let caps: [String]
    var compact = false

    var body: some View {
        let side = compact ? Metrics.capCompact : Metrics.cap
        HStack(spacing: compact ? Design.Space.xxs : Design.Space.xs) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Design.Font.ui(compact ? .caption : .body, .medium, design: .rounded))
                    .foregroundStyle(compact ? .secondary : .primary)
                    .frame(minWidth: side, minHeight: side)
                    .padding(.horizontal, cap.count > 1 ? Design.Space.xs : 0)
                    .background(RoundedRectangle(cornerRadius: compact ? Design.Radius.small : Design.Radius.inset, style: .continuous)
                        .fill(Design.fill(compact ? .hover : .selected)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined())
    }
}

/// The shortcut field: the keys as caps, or a prompt. Click it, then press the new keys; Esc
/// cancels, ⌫ removes the shortcut. While it records, an accent ring pulses.
struct ShortcutRecorder: View {
    let action: KeyAction
    @Environment(KeyBindingRegistry.self) private var bindings
    @State private var recording = false
    @State private var pulse = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Design.Space.m) {
            Button {
                recording ? stop() : start()
            } label: {
                HStack {
                    if recording {
                        Circle().fill(Design.accent).frame(width: Metrics.recordingDot, height: Metrics.recordingDot)
                            .opacity(pulse ? Metrics.pulseDim : 1)
                        Text("Press the new shortcut…").font(Design.Font.body).foregroundStyle(Design.accent)
                    } else if action.shortcuts.isEmpty {
                        Text("Record Shortcut").font(Design.Font.body).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(action.shortcuts.enumerated()), id: \.offset) { _, s in KeyCaps(caps: s.caps) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SettingsMetrics.fieldInset)
                .frame(height: Metrics.recorderHeight)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(Design.surface))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .strokeBorder(recording ? Design.accent : Design.hairline,
                                  lineWidth: recording ? SettingsMetrics.focusRing : Design.Space.hair))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recording ? "Recording shortcut" : "Shortcut")
            .accessibilityValue(action.shortcuts.map(\.display).joined(separator: ", "))
            if !action.shortcuts.isEmpty && !recording {
                Button { bindings.setShortcuts([], for: action.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: Design.Icon.bar)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
            }
        }
        .onChange(of: action.id) { _, _ in stop() }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        withAnimation(.easeInOut(duration: Metrics.pulse).repeatForever(autoreverses: true)) { pulse = true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e)
            return nil
        }
    }

    private func stop() {
        recording = false
        pulse = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ e: NSEvent) {
        if e.keyCode == 53 { stop(); return }                               // esc
        if e.keyCode == 51 || e.keyCode == 117 { bindings.setShortcuts([], for: action.id); stop(); return }  // ⌫ / ⌦
        guard let s = Shortcut.from(event: e) else { return }
        bindings.setShortcuts([s], for: action.id)
        stop()
    }
}

/// A search field at the row controls' height: glass, the query, and a clear button.
struct SettingsSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: "magnifyingglass").font(.system(size: Design.Icon.regular, weight: .medium)).foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(Design.Font.body)
                .focused(focused)
                .onExitCommand { focused.wrappedValue = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SettingsMetrics.fieldInset)
        .frame(height: Design.Space.control)
        .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(Design.fill(.hover)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
            .strokeBorder(focused.wrappedValue ? Design.accent.opacity(0.7) : Design.hairline,
                          lineWidth: focused.wrappedValue ? SettingsMetrics.focusRing : Design.Space.hair))
    }
}

/// One-line descriptions for the detail column ("Create a new tab.").
enum ShortcutDescriptions {
    static func text(for a: KeyAction) -> String {
        if let t = table[a.id] { return t }
        if a.id.hasPrefix("item"), let n = a.id.dropFirst(4).first { return "Switch to the \(n). tab in the sidebar." }
        if a.id.hasPrefix("space"), let n = a.id.dropFirst(5).first { return "Switch to the \(n). space." }
        if a.id.hasPrefix("moveTabToSpace"), let n = a.id.dropFirst(14).first { return "Move the current tab, or a Little Window's page, to the \(n). space and switch to it." }
        return a.name + "."
    }

    private static let table: [String: String] = [
        "newTab": "Create a new tab.",
        "newWindow": "Open a new window.",
        "newIncognitoWindow": "Open a window that keeps no history, cookies or tabs once closed.",
        "newLittleWindow": "Open a small, disposable window for a quick look.",
        "reopenClosedTab": "Bring back the tab you closed last.",
        "editURL": "Open the command bar to search or enter a URL.",
        "newFolder": "Create a folder in the sidebar.",
        "newGitHubLiveFolder": "Add a folder that fills itself with your open pull requests and review requests.",
        "newSpace": "Create a new space.",
        "closeWindow": "Close the current window.",
        "closeTab": "Close the current tab.",
        "capturePage": "Take a screenshot of the page.",
        "print": "Print the page.",
        "copyURL": "Copy the page’s URL.",
        "copyURLMarkdown": "Copy the page’s title and URL as a Markdown link.",
        "find": "Search for text on the page.",
        "findNext": "Jump to the next match.",
        "findPrevious": "Jump to the previous match.",
        "toggleSidebar": "Show or hide the sidebar.",
        "toggleToolbar": "Show or hide the toolbar above the page.",
        "stop": "Stop loading the page.",
        "reload": "Reload the page.",
        "hardReload": "Reload the page, ignoring cached content.",
        "clearCache": "Clear the browser cache and reload the page.",
        "clearCookies": "Clear this site’s cookies and reload the page.",
        "toggleDeveloperMode": "Show the full URL and developer tools for this site.",
        "resetZoom": "Return the page to its actual size.",
        "zoomIn": "Make the page larger.",
        "zoomOut": "Make the page smaller.",
        "viewSource": "Show the page’s source.",
        "devTools": "Open the developer tools.",
        "inspectElement": "Open the developer tools on the Elements panel.",
        "jsConsole": "Open the developer tools on the Console panel.",
        "pictureInPicture": "Pop the playing video out into a floating window.",
        "addSplitView": "Open another page beside this one.",
        "closeSplitPane": "Close the focused split pane.",
        "separateFromSplit": "Move the page out of the split view into its own tab.",
        "flipSplitOrientation": "Switch the split view between side by side and stacked.",
        "nextSplitPane": "Focus the next split pane.",
        "previousSplitPane": "Focus the previous split pane.",
        "nextSpace": "Switch to the next space.",
        "previousSpace": "Switch to the previous space.",
        "editSpace": "Change the space’s name, emoji and theme.",
        "changeProfile": "Pick the profile the space’s sign-ins, cookies and extensions come from.",
        "deleteSpace": "Delete the current space.",
        "manageSpaces": "Open the Library’s Spaces page: every space side by side, to reorder or edit them.",
        "pinTab": "Pin the tab or unpin it.",
        "nextTab": "Switch to the next tab.",
        "previousTab": "Switch to the previous tab.",
        "recentTab": "Open the tab switcher and cycle through recent tabs, like ⌘Tab for apps.",
        "recentTabBackward": "Cycle backwards through recent tabs in the tab switcher.",
        "clearToday": "Archive all of today’s tabs.",
        "favoriteTab": "Add the tab to the favorites grid.",
        "renameTab": "Give the tab a name of your own.",
        "duplicateTab": "Open a copy of the tab.",
        "resetTab": "Return a pinned tab to its original URL.",
        "muteTab": "Mute or unmute the tab.",
        "goBack": "Go back a page.",
        "goForward": "Go forward a page.",
        "viewArchive": "Open the archive of closed tabs.",
        "openLibrary": "Open the Library.",
        "viewDownloads": "Show your downloads.",
        "promoteLittleWindow": "Move the Little Window’s page into a space.",
        "closeLittleWindows": "Close all Little Windows.",
        "settings": "Open Settings.",
        "setDefaultBrowser": "Make Niche the default browser.",
        "importData": "Bring tabs, spaces and extensions over from another browser.",
        "rebuildArcProfiles": "Put spaces imported from Arc back on their Arc profiles, with their sign-ins and extensions.",
        "clearBrowsingData": "Delete history, cookies and cached files.",
        "languageSettings": "Choose the languages websites show their pages in, for this space’s profile.",
        "checkForUpdates": "Look for a newer version of Niche.",
    ]
}
