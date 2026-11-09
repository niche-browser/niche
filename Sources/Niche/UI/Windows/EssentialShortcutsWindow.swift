import AppKit
import SwiftUI

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
        let size = NSSize(width: 475, height: 462)
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
            p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 10, y: v.maxY - size.height - 10))
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
                    .font(.system(size: 20, weight: .semibold))
                    .kerning(-0.4)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                ViewAllButton(action: viewAll)
            }
            .frame(height: 28)
            .padding(.top, 37.5)
            .padding(.bottom, 3)
            ForEach(Array(EssentialShortcutsWindow.rows.enumerated()), id: \.offset) { i, row in
                if i > 0 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(row.title).font(.system(size: 15)).foregroundStyle(.white)
                        Text(row.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        ForEach(Array((bindings.action(row.action)?.primary?.caps ?? []).enumerated()), id: \.offset) { _, cap in
                            KeyCap(text: cap == "⇥" ? "TAB" : cap)
                        }
                    }
                }
                .frame(height: 72)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .frame(width: 475, height: 462, alignment: .topLeading)
    }
}

private struct ViewAllButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("View All").font(.system(size: 14))
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 96, height: 28)
            .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.12 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
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
            RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                .fill(Color.white.opacity(0.13))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
                .frame(height: 26)
            Text(text)
                .font(.system(size: text.count > 1 ? 10 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .frame(height: 26)
        }
        .frame(width: text.count > 1 ? 34 : 28, height: 28)
    }
}
