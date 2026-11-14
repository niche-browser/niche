import AppKit
import SwiftUI

private enum Metrics {
    /// The window, Arc's.
    static let size = NSSize(width: 475, height: 462)
    /// The heading's top, under the traffic lights.
    static let headerTop: CGFloat = 37.5
    /// One shortcut's row; with its hairline the rows are 73 pt apart.
    static let row: CGFloat = 72
    static let viewAllWidth: CGFloat = 96
    /// A key cap: its face stands this tall on a lip as tall as a control; a word ("TAB") gets the wide cap.
    static let capFace: CGFloat = 26
    static let capWide: CGFloat = 34
    /// The rim of a key cap's face.
    static let capRim: CGFloat = 0.75
}

private extension Color {
    /// The hairline between rows and around plates on this always-dark window.
    static let shortcutsHairline = Color(nsColor: Design.hairlineOnDark)
}

/// Arc's Help ▸ Essential Keyboard Shortcuts (KeyboardShortcutsEDUWindowController, Arc 1.172.1,
/// captured 7 Nov 2026 at 2x): a 475 × 462 pt floating window, #161C2F, traffic lights only,
/// opening at the top right of the screen. "Essential Keyboard Shortcuts" in heavy 20.5 pt at 30 pt
/// in, a "View All ↗" button (96 × 28, #282D3F, 6 pt corners, a faint rim) level with it, then
/// five rows 73 pt apart: a 15 pt title, a 12 pt grey line under it, the shortcut's key caps on
/// the right, and a hairline between rows. Niche draws it on its own graphite with neutral key
/// caps (Arc's was navy with blue caps), and its rows show the user's own bindings.
@MainActor
final class EssentialShortcutsWindow {
    static let shared = EssentialShortcutsWindow()
    private var panel: NSPanel?

    /// The rows: Arc's five, with Niche's action for each.
    static let rows: [(action: String, title: String, detail: String)] = [
        ("newTab", "Open a New Tab", "Open the Command Bar to create a new tab"),
        ("recentTab", "Switch to a Recent Tab", "Hold this to quickly switch between recent tabs"),
        ("copyURL", "Copy Page URL", "Copy the current tab's URL without trackers"),
        ("addSplitView", "Add Split View", "View multiple websites side-by-side"),
        ("newLittleWindow", "Open Little Window", "Use a smaller browser window for quick searches"),
    ]

    func show(bindings: KeyBindingRegistry, viewAll: @escaping () -> Void) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let size = Metrics.size
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.title = "Essential Keyboard Shortcuts"
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.appearance = NSAppearance(named: .darkAqua)
        p.backgroundColor = NSColor(Design.graphite)
        p.standardWindowButton(.zoomButton)?.isEnabled = false
        let host = NSHostingView(rootView: EssentialShortcutsView(bindings: bindings, viewAll: { [weak p] in
            p?.close()
            viewAll()
        }))
        host.sizingOptions = []  // the title bar sits inside Arc's 462 pt, so the view doesn't size the window
        p.contentView = host
        p.setFrame(NSRect(origin: .zero, size: size), display: false)
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - size.width - Design.Space.l, y: v.maxY - size.height - Design.Space.l))
        }
        panel = p
        p.makeKeyAndOrderFront(nil)
    }
}

private struct EssentialShortcutsView: View {
    let bindings: KeyBindingRegistry
    let viewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Essential Keyboard Shortcuts")
                    .font(Design.Font.ui(.pane, .semibold))
                    .kerning(-0.4)
                    .foregroundStyle(Design.onDarkColor(.primary))
                Spacer(minLength: Design.Space.m)
                ViewAllButton(action: viewAll)
            }
            .frame(height: Design.Space.control)
            .padding(.top, Metrics.headerTop)
            .padding(.bottom, Design.Space.xxs)
            ForEach(Array(EssentialShortcutsWindow.rows.enumerated()), id: \.offset) { i, row in
                if i > 0 {
                    Rectangle().fill(Color.shortcutsHairline).frame(height: Design.Space.hair)
                }
                HStack(alignment: .center, spacing: Design.Space.l) {
                    VStack(alignment: .leading, spacing: Design.Space.xxs) {
                        Text(row.title).font(Design.Font.ui(.title)).foregroundStyle(Design.onDarkColor(.primary))
                        Text(row.detail).font(Design.Font.ui(.detail)).foregroundStyle(Design.onDarkColor(.secondary)).lineLimit(1)
                    }
                    Spacer(minLength: Design.Space.m)
                    HStack(spacing: Design.Space.xxs) {
                        ForEach(Array((bindings.action(row.action)?.primary?.caps ?? []).enumerated()), id: \.offset) { _, cap in
                            KeyCap(text: cap == "⇥" ? "TAB" : cap)
                        }
                    }
                }
                .frame(height: Metrics.row)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Space.pane)
        .frame(width: Metrics.size.width, height: Metrics.size.height, alignment: .topLeading)
    }
}

private struct ViewAllButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.m) {
                Text("View All").font(Design.Font.ui(.body))
                Image(systemName: "arrow.up.right").font(.system(size: Design.Icon.small, weight: .medium))
            }
            .foregroundStyle(Design.onDarkColor(.primary))
            .frame(width: Metrics.viewAllWidth, height: Design.Space.control)
            .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .fill(Design.fillOnDarkColor(hover ? .pressed : .selected)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(Color.shortcutsHairline, lineWidth: Design.Space.hair))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// One key cap: a graphite face on a darker lip, the glyph in white.
private struct KeyCap: View {
    let text: String

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(Design.fillOnDarkColor(.hover))
            RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .fill(Design.fillOnDarkColor(.pressed))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(Color.shortcutsHairline, lineWidth: Metrics.capRim))
                .frame(height: Metrics.capFace)
            Text(text)
                .font(Design.Font.ui(text.count > 1 ? .micro : .body, .semibold, design: .rounded))
                .foregroundStyle(Design.onDarkColor(.primary))
                .frame(height: Metrics.capFace)
        }
        .frame(width: text.count > 1 ? Metrics.capWide : Design.Space.control, height: Design.Space.control)
    }
}
