import SwiftUI

/// How the window looks and sounds: the toolbar and page edges, the space header, the app icon,
/// and feedback.
struct AppearancePane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader("Tabs")
                WindowLayoutPicker(layout: store.settings.windowLayout) { store.settings.windowLayout = $0 }
                SettingsFootnote(store.settings.tabsOnTop
                                 ? "The sidebar still comes with ⌘S, with the Library, your spaces and your folders in it."
                                 : "Tabs on top puts a tab strip, the address and your bookmarks across the top of the window.")
            }
            .padding(.bottom, Design.Space.section)
            SettingsSection(title: "Window") {
                if store.settings.tabsOnTop {
                    SettingsToggleRow(title: "Show the bookmarks bar",
                                      detail: "The space’s pinned tabs and folders in a bar under the address.",
                                      isOn: $store.settings.showBookmarksBar)
                } else {
                    SettingsToggleRow(title: "Show the toolbar above the page", isOn: $store.settings.showToolbar)
                }
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

/// Where the tabs go, as two cards: a small drawing of the window, the layout's name and what
/// it is. Onboarding's personalization step offers the same choice with a live preview.
struct WindowLayoutPicker: View {
    let layout: WindowLayout
    let choose: (WindowLayout) -> Void

    var body: some View {
        HStack(spacing: Design.Space.l) {
            ForEach(WindowLayout.allCases, id: \.self) { option in
                let selected = option == layout
                Button { choose(option) } label: {
                    VStack(alignment: .leading, spacing: Design.Space.s) {
                        WindowLayoutGlyph(layout: option, selected: selected)
                            .padding(.bottom, Design.Space.xs)
                        Text(option.title).font(Design.Font.section)
                        Text(option.detail).font(Design.Font.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(Design.Space.l)
                    .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .fill(selected ? Design.accentWash : Design.fill(.subtle)))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                        .strokeBorder(selected ? Design.accentRing : Design.hairline, lineWidth: selected ? Design.Space.xxs : Design.Space.hair))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title): \(option.detail)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// A layout's card: the drawing, the name and a two-line description.
    static let cardHeight: CGFloat = 156
}

/// A window in miniature: its traffic lights, where the tabs are, and the page.
private struct WindowLayoutGlyph: View {
    let layout: WindowLayout
    let selected: Bool

    /// The drawing's own measures.
    private enum Art {
        static let size = CGSize(width: 104, height: 68)
        static let light: CGFloat = 4
        static let lightPitch: CGFloat = 7
        static let lightOrigin = CGPoint(x: 7, y: 7)
        static let row = CGSize(width: 24, height: 6)
        static let rowPitch: CGFloat = 10
        static let rowOrigin = CGPoint(x: 6, y: 18)
        static let sidePage = CGRect(x: 36, y: 5, width: 63, height: 58)
        static let tab = CGSize(width: 18, height: 6)
        static let tabPitch: CGFloat = 21
        static let tabOrigin = CGPoint(x: 32, y: 6)
        static let address = CGRect(x: 6, y: 17, width: 92, height: 6)
        static let topPage = CGRect(x: 5, y: 28, width: 94, height: 35)
    }

    var body: some View {
        let mark = selected ? Design.accent : Design.inkColor(.tertiary)
        let rest = Design.inkColor(.quaternary)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(Design.fill(.hover))
            ForEach(0..<3) { i in
                Circle().fill(rest).frame(width: Art.light, height: Art.light)
                    .offset(x: Art.lightOrigin.x + CGFloat(i) * Art.lightPitch, y: Art.lightOrigin.y)
            }
            switch layout {
            case .sidebar:
                ForEach(0..<4) { i in
                    Capsule().fill(i == 0 ? mark : rest)
                        .frame(width: Art.row.width, height: Art.row.height)
                        .offset(x: Art.rowOrigin.x, y: Art.rowOrigin.y + CGFloat(i) * Art.rowPitch)
                }
                page(Art.sidePage)
            case .top:
                ForEach(0..<3) { i in
                    Capsule().fill(i == 0 ? mark : rest)
                        .frame(width: Art.tab.width, height: Art.tab.height)
                        .offset(x: Art.tabOrigin.x + CGFloat(i) * Art.tabPitch, y: Art.tabOrigin.y)
                }
                Capsule().fill(rest)
                    .frame(width: Art.address.width, height: Art.address.height)
                    .offset(x: Art.address.minX, y: Art.address.minY)
                page(Art.topPage)
            }
        }
        .frame(width: Art.size.width, height: Art.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func page(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.surface)
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.hairline, lineWidth: Design.Space.hair))
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
    }
}
