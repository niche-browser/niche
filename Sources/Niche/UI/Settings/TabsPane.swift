import SwiftUI

/// How tabs, spaces and links behave: four card groups of switches and choices.
struct TabsPane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let littleWindowKey = KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N"
        SettingsCardPane {
            SettingsSection(title: "Tabs") {
                SettingsToggleRow(title: "Add new tabs to the top", isOn: $store.settings.newTabsAtTop)
                SettingsCardDivider()
                SettingsToggleRow(title: "Show the New Tab button above tabs", isOn: $store.settings.newTabButtonAtTop)
                SettingsCardDivider()
                SettingsToggleRow(title: "Haptic feedback when reordering", isOn: $store.settings.hapticFeedbackOnReorder)
                SettingsCardDivider()
                SettingsToggleRow(title: "Preview a folder’s tabs on hover", isOn: $store.settings.folderPreviews)
                SettingsCardDivider()
                // Arc: Settings ▸ General ▸ Previews (Gmail's unread mail on its favorite).
                SettingsToggleRow(title: "Preview unread Gmail on its favorite", isOn: $store.settings.favoritePreviews)
                SettingsCardDivider()
                SettingsToggleRow(title: "Picture in Picture when you leave a video", isOn: $store.settings.autoPictureInPicture)
            }
            SettingsSection(title: "Window") {
                SettingsToggleRow(title: "Show the toolbar above the page", isOn: $store.settings.showToolbar)
                SettingsCardDivider()
                SettingsToggleRow(title: "Pages fill the window edge to edge", isOn: $store.settings.edgeToEdgeContent)
            }
            // Arc's single-space mode ("Hide Space Header" on the space's menu), for people who
            // don't use spaces.
            SettingsSection(title: "Spaces") {
                SettingsToggleRow(title: "Show the space header with one space",
                                  detail: "Off hides the space’s name and icon while you have a single space.",
                                  isOn: $store.settings.showSpaceHeaderOnSingleSpace)
                SettingsCardDivider()
                // #154: Arc's favorites, one set per profile.
                SettingsToggleRow(title: "Share Favorites across a profile’s spaces",
                                  detail: "Turning it on combines their Favorites; off gives each space its own copy.",
                                  isOn: Binding(get: { store.settings.sharedFavorites }, set: { store.setFavoritesShared($0) }))
            }
            // Arc's Links pane: the Little Arc switch and Air Traffic Control.
            SettingsSection(title: "Links") {
                SettingsToggleRow(title: "Links from other apps open in a Little Window", isOn: $store.settings.openExternalLinksInLittleWindow)
                SettingsCardDivider()
                // Arc's "Open Little Arc when I press ⌥⌘N" (#195): New Little Window's shortcut from any app.
                SettingsToggleRow(title: "\(littleWindowKey) opens a Little Window from any app", isOn: $store.settings.littleWindowShortcutEverywhere)
                SettingsCardDivider()
                // Arc: "Archive Little Arcs after:" 1 hour, 6 hours (default), 12 hours.
                SettingsPickerRow(title: "Archive Little Windows after", selection: $store.settings.littleWindowArchiveAfter) {
                    ForEach(LittleWindowArchive.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                SettingsCardDivider()
                SettingsToggleRow(title: "Peek links to other sites", isOn: $store.settings.peekLinksToOtherSites)
                SettingsCardDivider()
                SettingsToggleRow(title: "Peek in every tab", detail: "Not only Favorites and pinned tabs.", isOn: $store.settings.peekInEveryTab)
                    .disabled(!store.settings.peekLinksToOtherSites)
                SettingsCardDivider()
                SettingsToggleRow(title: "Peek links clicked with Shift held", isOn: $store.settings.peekOnShiftClick)
                SettingsCardDivider()
                // GitHub #183, Chrome's way and not Arc's: the page stays in front.
                SettingsToggleRow(title: "Open new tabs in the background",
                                  detail: "The page you’re reading stays in front. ⇧⌘-click still switches.",
                                  isOn: $store.settings.openLinksInBackground)
                SettingsCardDivider()
                SettingsCardRow {
                    SettingsLabel(title: "Air Traffic Control", detail: "Choose which space links from other apps open in.")
                } trailing: {
                    if !routesSummary.isEmpty { Text(routesSummary).foregroundStyle(.secondary) }
                    Button("Edit Routes…") { showsAirTrafficControl = true }
                }
            }
            SettingsSection(title: "Tab cleanup", footnote: tabSleepNote) {
                SettingsToggleRow(title: "Archive tabs you haven’t used", isOn: $store.settings.autoArchiveEnabled)
                SettingsCardDivider()
                SettingsPickerRow(title: "Archive after", selection: $store.settings.autoArchive) {
                    ForEach(AutoArchiveThreshold.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!store.settings.autoArchiveEnabled)
                SettingsCardDivider()
                // Tab sleeping (GitHub #153): Arc's 4 hours and nothing more unless you ask.
                SettingsToggleRow(title: "Put idle tabs to sleep", isOn: $store.settings.tabSleepTimerEnabled)
                SettingsCardDivider()
                SettingsPickerRow(title: "Sleep after", selection: $store.settings.tabSleepAfter) {
                    ForEach(TabSleepThreshold.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!store.settings.tabSleepTimerEnabled)
                SettingsCardDivider()
                SettingsToggleRow(title: "Sleep tabs when the Mac is low on memory", isOn: $store.settings.tabSleepOnMemoryPressure)
            }
        }
        .sheet(isPresented: $showsAirTrafficControl) {
            AirTrafficControlView().environment(store)
        }
    }

    @State private var showsAirTrafficControl = false

    /// Says what a forced-out tab costs, and which tabs stay, before the user finds out.
    private var tabSleepNote: String {
        let s = store.settings
        let note = "A sleeping tab reloads when you open it. Tabs playing sound, recording or holding typed text stay awake."
        guard s.tabSleepTimerEnabled, TabSleepPolicy.timer(s.tabSleepAfter).keepsRecentTabs else { return note }
        return note + (s.tabSleepOnMemoryPressure ? " So do the 10 tabs you used last, unless the Mac is short of memory." : " So do the 10 tabs you used last.")
    }

    private var routesSummary: String {
        switch store.settings.linkRoutes.count {
        case 0: return ""
        case 1: return "1 route"
        case let n: return "\(n) routes"
        }
    }
}
