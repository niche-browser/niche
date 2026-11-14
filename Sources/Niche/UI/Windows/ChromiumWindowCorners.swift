import AppKit
import ObjectiveC

/// Chromium's page and DevTools windows use a frame view derived from NSThemeFrame, so
/// macOS clips them to its window corner radius (about 18 pt on macOS 26) even when they
/// are borderless. Docked inside Niche's card they must be square; the card's own rounded
/// bottom corners come from the content layer's mask. This overrides the frame view's
/// corner queries for windows registered here only; every other window keeps the system
/// behaviour.
@MainActor
enum ChromiumWindowCorners {
    private static let squared = NSHashTable<NSWindow>.weakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()
    /// The frame view each squared window had when its corners were last refreshed. Chromium
    /// swaps a window's frame view when it restores its own style mask (as a page first shows, on
    /// fullscreen and display changes), and the new one comes with macOS's rounded corners until
    /// the mask is asked for again: a Little Window's page kept round top corners (13 Nov 2026).
    private static let squaredFrames = NSMapTable<NSWindow, NSView>.weakToWeakObjects()

    static func setSquare(_ square: Bool, for window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        patch(type(of: frameView))
        var changed = squared.contains(window) != square
        if square {
            squared.add(window)
            if squaredFrames.object(forKey: window) !== frameView { changed = true }
            squaredFrames.setObject(frameView, forKey: window)
        } else {
            squared.remove(window)
            squaredFrames.removeObject(forKey: window)
        }
        guard changed else { return }
        let refresh = NSSelectorFromString("_cornerMaskChanged")
        if window.responds(to: refresh) { window.perform(refresh) }
        frameView.needsDisplay = true
        window.invalidateShadow()
    }

    static func isSquare(_ view: AnyObject) -> Bool {
        guard let v = view as? NSView, let w = v.window else { return false }
        return squared.contains(w)
    }

    private static func patch(_ cls: AnyClass) {
        let id = ObjectIdentifier(cls)
        guard !patchedClasses.contains(id) else { return }
        patchedClasses.insert(id)
        overrideBool(cls, "_shouldRoundCornersForSurface", squareValue: false)
        overrideBool(cls, "topCornerRounded", squareValue: false)
        overrideBool(cls, "bottomCornerRounded", squareValue: false)
        overrideFloat(cls, "_cornerRadius", squareValue: 0)
        overrideFloat(cls, "_getCachedWindowCornerRadius", squareValue: 0)
        // Linked against a pre-26 SDK (release builds on GitHub's macos-15 runners), macOS 26
        // ignores the queries above and masks the window with a 12 pt corner image of its own,
        // which rounded the page's top corners under the toolbar. No mask means square.
        overrideObject(cls, "_cornerMask", squareValue: nil)
        // macOS 27 shapes a window from its frame view's radii, not from the answers above: with
        // only those, Chromium's page window kept round corners on all four sides, and a Little
        // Window's page was round at the top, under its bar (13 Nov 2026).
        overrideFloat(cls, "_getCachedDefaultWindowCornerRadius", squareValue: 0)
        // Its radii are an object there (NSViewCornerRadii, 16 pt on each corner of a theme frame
        // whatever the style mask): a square window's are that class's `zero`.
        if let zero = zeroRadii {
            overrideObject(cls, "_cornerRadii", squareValue: zero)
            overrideObject(cls, "_getCachedWindowCornerRadii", squareValue: zero)
        }
    }

    /// `NSViewCornerRadii.zero`, where AppKit has the class (macOS 27).
    private static let zeroRadii: AnyObject? = {
        guard let cls = NSClassFromString("NSViewCornerRadii") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("zero")
        guard cls.responds(to: sel) else { return nil }
        return cls.perform(sel)?.takeUnretainedValue()
    }()

    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
    private typealias FloatIMP = @convention(c) (AnyObject, Selector) -> CGFloat
    private typealias ObjectIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private static func overrideBool(_ cls: AnyClass, _ name: String, squareValue: Bool) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
        let block: @convention(block) (AnyObject) -> Bool = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        // Add on the subclass when it only inherits the method, else replace its own.
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    private static func overrideFloat(_ cls: AnyClass, _ name: String, squareValue: CGFloat) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: FloatIMP.self)
        let block: @convention(block) (AnyObject) -> CGFloat = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    private static func overrideObject(_ cls: AnyClass, _ name: String, squareValue: AnyObject?) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ObjectIMP.self)
        let block: @convention(block) (AnyObject) -> Unmanaged<AnyObject>? = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue.map { Unmanaged.passUnretained($0) } : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
