/// Which Chromium windows get their title bar made transparent. Chromium opens some of its own
/// dialogs (the extension install prompt, shown with no tab to hang a sheet on) as titled
/// windows without window buttons, laid out as if frameless: the title bar strip then covered
/// the dialog's icon and title. Such a window is given a full-size, transparent title bar.
public enum ChromiumDialogFrame {
    public struct Window: Equatable, Sendable {
        public var className: String
        public var titled: Bool
        /// Close, minimise or zoom: a window that shows them means its title bar.
        public var hasWindowButtons: Bool
        public var titlebarTransparent: Bool
        public var fullSizeContent: Bool

        public init(className: String, titled: Bool, hasWindowButtons: Bool, titlebarTransparent: Bool, fullSizeContent: Bool) {
            self.className = className
            self.titled = titled
            self.hasWindowButtons = hasWindowButtons
            self.titlebarTransparent = titlebarTransparent
            self.fullSizeContent = fullSizeContent
        }
    }

    public static func needsFix(_ w: Window) -> Bool {
        w.className == "NativeWidgetMacNSWindow" && w.titled && !w.hasWindowButtons
            && !(w.titlebarTransparent && w.fullSizeContent)
    }
}
