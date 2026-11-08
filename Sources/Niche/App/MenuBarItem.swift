import AppKit

/// The menu bar item of Settings ▸ Advanced ▸ "Keep Niche in the menu bar" (GitHub #231). Arc has
/// none, so it is a plain macOS status item: Niche's C mark as a template image, and a menu that
/// AppDelegate builds each time it opens (the shortcuts follow Settings ▸ Shortcuts).
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let build: (NSMenu) -> Void

    init(build: @escaping (NSMenu) -> Void) {
        self.build = build
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.icon
        item.button?.setAccessibilityLabel("Niche")
        item.button?.toolTip = "Niche"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        build(menu)
    }

    /// brand/niche-mark-mono.svg on its 32 grid: the arch (radius 9 about 16,15, stroke 6, left
    /// side down to 17.5, right stem to 29) and the dot (radius 4.5 at 7,24.5). 16 pt, like the
    /// system's own items.
    static let icon: NSImage = {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let s = rect.height / 32  // SVG units; y flips because the SVG's origin is top-left
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (32 - y) * s) }
            let arch = NSBezierPath()
            arch.move(to: p(7, 17.5))
            arch.line(to: p(7, 15))
            arch.appendArc(withCenter: p(16, 15), radius: 9 * s, startAngle: 180, endAngle: 0, clockwise: true)
            arch.line(to: p(25, 29))
            arch.lineWidth = 6 * s
            NSColor.black.set()
            arch.stroke()
            NSBezierPath(ovalIn: NSRect(x: 2.5 * s, y: (32 - 29) * s, width: 9 * s, height: 9 * s)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
