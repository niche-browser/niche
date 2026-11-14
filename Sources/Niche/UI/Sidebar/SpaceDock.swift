import AppKit
import SwiftUI

/// The Library button's glyph: a tray of saved things, in the dock's quiet ink, drawn once per
/// theme brightness into an image so it matches the space icons and + beside it.
struct LibraryGlyph: View {
    let dark: Bool

    var body: some View {
        Image(systemName: "tray.full.fill")
            .font(.system(size: Design.Icon.regular))
            .foregroundStyle(dark ? Design.onDarkColor(.secondary) : Design.onLightColor(.tertiary))
            .frame(width: 28, height: 28)
    }

    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor static func image(dark: Bool) -> NSImage? {
        if let img = cache[dark] { return img }
        let r = ImageRenderer(content: LibraryGlyph(dark: dark))
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage
        cache[dark] = img
        return img
    }
}
