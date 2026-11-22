import AppKit

/// Whether the pointer is on a view is asked of the part of it that shows (ShownPart.swift). A view
/// that doesn't clip, AppKit's default since macOS 14, reports a visible rect as large as the window:
/// the downloads list asked that, took a pointer on the page for its own and never closed (22 Nov 2026).
@main
enum ShownPartTests {
    private static var checks = 0

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 880), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 880))
        window.contentView = root
        let column = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 880))
        root.addSubview(column)
        let list = NSView(frame: NSRect(x: 0, y: 100, width: 280, height: 128))
        column.addSubview(list)

        // The page, far right of the list, is in the list's visible rect but not in its shown part.
        let onPage = NSPoint(x: 600, y: 400)
        expect(!list.clipsToBounds, "views don't clip by default (the case this guards)")
        expect(list.shownPart == list.bounds, "an unclipped list shows its bounds")
        expect(!list.shownPartContains(onPage), "a point on the page is not on the list")
        expect(list.shownPartContains(NSPoint(x: 140, y: 64)), "a point on the list is")

        // A clipping ancestor cuts it as before.
        column.clipsToBounds = true
        list.frame = NSRect(x: 200, y: 100, width: 280, height: 128)
        expect(list.shownPart == NSRect(x: 0, y: 0, width: 80, height: 128), "a clipping column cuts the list at its edge")
        expect(!list.shownPartContains(NSPoint(x: 100, y: 64)), "the cut-off part is not under the pointer")

        // Hidden, nothing of it shows.
        column.isHidden = true
        expect(list.shownPart.isEmpty, "a view under a hidden ancestor shows nothing")
        expect(!list.shownPartContains(NSPoint(x: 10, y: 10)), "and the pointer is never on it")
        print("Shown part: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ what: String) {
        checks += 1
        guard condition else {
            print("FAILED: \(what)")
            exit(1)
        }
    }
}
