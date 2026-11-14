import AppKit
import SwiftUI

/// Callbacks the panes hand back to the app.
struct SettingsActions {
    var importData: () -> Void = {}
    var rebuildArcProfiles: () -> Void = {}
    var openURL: (String) -> Void = { _ in }
    /// A page in a space on that profile (nil is Default), e.g. its chrome://settings/languages.
    var openProfilePage: (String, UUID?) -> Void = { _, _ in }
    var exportDiagnostics: () -> Void = {}
    var newProfile: () -> Void = {}
}

/// The Settings panes, in sidebar order. Intelligence holds the features that run on the Mac's
/// own Apple Intelligence model (the raw value stays `max` so saved links keep working).
/// Performance is reached from Advanced ▸ Troubleshooting, not the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, tabs, shortcuts, privacy, profiles, extensions, max, advanced, performance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .tabs: return "Tabs & Spaces"
        case .max: return "Intelligence"
        case .privacy: return "Privacy & Security"
        case .profiles: return "Profiles"
        case .extensions: return "Extensions"
        case .shortcuts: return "Shortcuts"
        case .performance: return "Performance"
        case .advanced: return "Advanced"
        }
    }

    /// The sidebar's groups: the browser itself, what it does with pages, and the machinery.
    var group: Group? {
        switch self {
        case .general, .appearance, .tabs, .shortcuts: return .browser
        case .privacy, .profiles, .extensions: return .browsing
        case .max, .advanced: return .system
        case .performance: return nil
        }
    }

    /// The pane a page outside the sidebar belongs under, highlighted while it shows.
    var parent: SettingsPane? { self == .performance ? .advanced : nil }

    enum Group: String, CaseIterable {
        case browser = "Browser", browsing = "Browsing", system = "System"
        var panes: [SettingsPane] { SettingsPane.allCases.filter { $0.group == self } }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .tabs: return "square.on.square"
        // macOS 15.1 added Apple's mark; before it, sparkles.
        case .max: return NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) != nil ? "apple.intelligence" : "sparkles"
        case .privacy: return "hand.raised"
        case .profiles: return "person.crop.circle"
        case .extensions: return "puzzlepiece.extension"
        case .shortcuts: return "command"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

/// The selected pane.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var pane: SettingsPane = .general
    /// The window is on screen: panes that refresh (Performance) stop while it is closed or covered.
    var isOpen = false
    /// Counts each time Settings is brought up: panes showing what changed elsewhere (a profile's
    /// languages, set on Chromium's page) read it again.
    private(set) var shown = 0
    func didShow() { shown += 1 }

    func show(_ p: SettingsPane) { pane = p }
}

/// The Settings window: a full-height source-list sidebar in an NSSplitViewController and the
/// pane's title drawn by the content under an empty, transparent toolbar (macOS 26 would wrap
/// toolbar items in a glass capsule).
@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let nav = SettingsNavigation()

    func show(_ pane: SettingsPane) { nav.show(pane) }
    func didShow() {
        nav.didShow()
        // No field starts with the keyboard: a search field holding it looked stuck in focus.
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }

    init(store: SidebarStore, bindings: KeyBindingRegistry, actions: SettingsActions) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsMetrics.windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // The content view draws the title under the toolbar: no blur, no separator line.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false

        window.contentMinSize = SettingsMetrics.minimumSize

        let split = NSSplitViewController()
        let sidebarHost = NSHostingController(rootView: SettingsSidebar(nav: nav))
        // The window keeps its size: a pane's content (the long shortcut list) never resizes it.
        sidebarHost.sizingOptions = []
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        // macOS 26 insets the sidebar panel 8 pt.
        sidebar.minimumThickness = SettingsMetrics.sidebarWidth - 8
        sidebar.maximumThickness = SettingsMetrics.sidebarWidth - 8
        sidebar.canCollapse = false
        let content = NSHostingController(rootView: SettingsContent(nav: nav, actions: actions)
            .environment(store).environment(bindings))
        content.sizingOptions = []
        let contentItem = NSSplitViewItem(viewController: content)
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(contentItem)
        split.splitView.dividerStyle = .thin
        window.contentViewController = split

        let toolbar = NSToolbar(identifier: "niche.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        // Size last: the toolbar and full-size content change how the frame is derived. A size
        // the user chose comes back from the autosaved frame.
        if !window.setFrameUsingName(Self.frameName) {
            window.setFrame(NSRect(origin: .zero, size: SettingsMetrics.windowSize), display: false)
            window.center()
        }
        // Saved only from here on: setting the content above shrinks the window to its minimum.
        window.setFrameAutosaveName(Self.frameName)
        // On screen: shown and not entirely covered (the window needn't be key).
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [nav] note in
                MainActor.assumeIsolated {
                    guard let w = note.object as? NSWindow else { return }
                    let open = note.name != NSWindow.willCloseNotification && w.occlusionState.contains(.visible)
                    if nav.isOpen != open { nav.isOpen = open }
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static let frameName = "NicheSettingsWindow"

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        nil
    }
}

/// The title over the pane, aligned with the cards below it. A page reached from another pane
/// (Performance, from Advanced) gets a way back.
struct SettingsToolbarRow: View {
    let nav: SettingsNavigation
    var body: some View {
        HStack(spacing: Design.Space.m) {
            if let parent = nav.pane.parent {
                Button { nav.show(parent) } label: {
                    Image(systemName: "chevron.left").font(.system(size: Design.Icon.bar, weight: .semibold))
                        .frame(width: Design.Icon.plate, height: Design.Icon.plate)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to \(parent.title)")
                .accessibilityLabel("Back to \(parent.title)")
            }
            Text(nav.pane.title).font(Design.Font.paneTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.leading, nav.pane.parent == nil ? Design.Space.rowInset : 0)
        .frame(maxWidth: SettingsMetrics.contentWidth, alignment: .leading)
        .padding(.horizontal, Design.Space.pane)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.toolbarHeight)
    }
}

/// The source list: panes in three quiet groups. The selected row is a soft neutral plate,
/// not a saturated fill, so the pane's content stays the loudest thing in the window.
struct SettingsSidebar: View {
    let nav: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(SettingsPane.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                    Text(group.rawValue)
                        .font(Design.Font.ui(.caption, .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, SettingsMetrics.fieldInset)
                        .padding(.bottom, Design.Space.xs)
                    ForEach(group.panes) { row($0) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ p: SettingsPane) -> some View {
        SettingsSidebarRow(pane: p, selected: nav.pane == p || nav.pane.parent == p) { nav.show(p) }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: Design.Icon.regular, weight: .medium))
                    .frame(width: Design.Icon.large, height: Design.Icon.large)
                    .foregroundStyle(selected ? Design.accent : Color.secondary)
                Text(pane.title)
                    .font(Design.Font.ui(.body, selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                .fill(selected ? Design.rowSelected : (hovered ? Design.rowHover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsContent: View {
    let nav: SettingsNavigation
    let actions: SettingsActions

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbarRow(nav: nav)
            Group {
                switch nav.pane {
                case .general: GeneralPane(actions: actions)
                case .appearance: AppearancePane()
                case .tabs: TabsPane()
                case .max: MaxPane()
                case .privacy: PrivacyPane(actions: actions)
                case .profiles: ProfilesPane(nav: nav, actions: actions)
                case .extensions: ExtensionsPane(actions: actions)
                case .shortcuts: ShortcutsPane()
                case .performance: PerformancePane(nav: nav, actions: actions)
                case .advanced: AdvancedPane(nav: nav, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.container, edges: .top)
        .buttonStyle(.settings)
        .tint(Design.accent)
    }
}
