import NicheCore
import Testing

/// Chromium's own dialogs (the extension install prompt) open as titled windows with no
/// window buttons; their title bar strip covered the top of the dialog (its icon and title).
struct ChromiumDialogFrameTests {
    func window(_ cls: String = "NativeWidgetMacNSWindow", titled: Bool = true, buttons: Bool = false,
                transparent: Bool = false, fullSize: Bool = false) -> ChromiumDialogFrame.Window {
        .init(className: cls, titled: titled, hasWindowButtons: buttons, titlebarTransparent: transparent, fullSizeContent: fullSize)
    }

    @Test func aButtonlessTitledChromiumWindowLosesItsTitleBarStrip() {
        #expect(ChromiumDialogFrame.needsFix(window()))
    }

    @Test func windowsThatShowTheirTitleBarOnPurposeKeepIt() {
        // An extension's popup window (windows.create type "popup") has a real title bar.
        #expect(!ChromiumDialogFrame.needsFix(window(buttons: true)))
        // Borderless bubbles and menus have no title bar to hide.
        #expect(!ChromiumDialogFrame.needsFix(window(titled: false)))
        // Already fixed, or a tabbed window Chrome made full-size itself.
        #expect(!ChromiumDialogFrame.needsFix(window(transparent: true, fullSize: true)))
        // Niche's own windows are not Chromium's to fix.
        #expect(!ChromiumDialogFrame.needsFix(window("NSWindow")))
    }
}
