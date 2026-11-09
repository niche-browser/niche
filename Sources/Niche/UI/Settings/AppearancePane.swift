import SwiftUI

/// How the window looks and sounds: the toolbar and page edges, the space header, the app icon,
/// and feedback.
struct AppearancePane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            SettingsSection(title: "Window") {
                SettingsToggleRow(title: "Show the toolbar above the page", isOn: $store.settings.showToolbar)
                SettingsCardDivider()
                SettingsToggleRow(title: "Pages fill the window edge to edge", isOn: $store.settings.edgeToEdgeContent)
                SettingsCardDivider()
                SettingsToggleRow(title: "Show the space header with one space",
                                  detail: "Off hides the space’s name and icon while you have a single space.",
                                  isOn: $store.settings.showSpaceHeaderOnSingleSpace)
            }
            AppIconSection().padding(.bottom, Design.Space.section)
            SettingsSection(title: "Feedback") {
                SettingsToggleRow(title: "Sound effects", isOn: $store.settings.soundEffects)
                SettingsCardDivider()
                SettingsToggleRow(title: "Haptic feedback when reordering", isOn: $store.settings.hapticFeedbackOnReorder)
            }
        }
    }
}
