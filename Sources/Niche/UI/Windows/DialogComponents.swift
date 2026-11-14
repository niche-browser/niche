import AppKit
import SwiftUI

/// Niche's dialog card: graphite, the ground of the logo's tile, a step lighter so it lifts off a
/// dark page. Buttons are neutral plates and the one default action is the signal orange.
enum DialogTheme {
    static let card = Design.panelDarkColor
    static let body = Design.onDarkColor(.secondary)
    /// What is read first: a title, a field's text, a button's label.
    static let title = Design.onDarkColor(.primary)
    /// Placeholders and disabled labels.
    static let faint = Design.onDarkColor(.tertiary)
    /// The 1 pt rim of a button, a key badge or a field.
    static let outline = Color(nsColor: Design.hairlineOnDark)
    /// The lip under the default button: deep orange (dimmed while it is disabled), a dark red under Delete.
    static let accentLip = Color(hex: "#7A2A12")
    static let accentLipDisabled = Color(hex: "#3A2018")
    static let destructiveLip = Color(hex: "#41232A")
}

private enum Metrics {
    /// The smallest key badge beside a button's title.
    static let key = CGSize(width: 27, height: 19)
    /// How far the default button's lip shows below it.
    static let lip: CGFloat = 1.5
}

/// The card a dialog draws on. The sheet it sits in already has macOS's 1 pt light edge, as Arc's does,
/// so the card draws none of its own.
struct DialogSurface: ViewModifier {
    var cornerRadius: CGFloat = Design.Radius.panel

    func body(content: Content) -> some View {
        content
            .background(DialogTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

struct DialogButton: View {
    enum Style {
        case secondary, primary, accent, destructive

        /// Under the pointer: a white plate over the neutral buttons, a black one over the coloured ones.
        var hoverTint: Color { self == .secondary ? .white : .black }
    }
    let title: String
    let key: String
    let enabled: Bool
    let style: Style
    var badge: CGSize?
    let action: () -> Void
    @State private var hovered = false

    init(title: String, key: String, enabled: Bool, primary: Bool, action: @escaping () -> Void) {
        self.init(title: title, key: key, enabled: enabled, style: primary ? .primary : .secondary, action: action)
    }

    init(title: String, key: String, enabled: Bool, style: Style, badge: CGSize? = nil, action: @escaping () -> Void) {
        self.title = title
        self.key = key
        self.enabled = enabled
        self.style = style
        self.badge = badge
        self.action = action
    }

    // Destructive (Delete Space, Delete Live Folder): red fill, key badge a lighter red.
    private var accent: Bool { style == .accent && enabled }
    private var destructive: Bool { style == .destructive && enabled }
    private var primary: Bool { style != .secondary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.m) {
                Text(title).font(Design.Font.ui(.body, .medium))
                    .foregroundStyle(enabled ? DialogTheme.title : DialogTheme.faint)
                if !key.isEmpty {
                    Text(key).font(Design.Font.ui(key == "↩" ? .body : .caption, .bold))
                        .foregroundStyle(accent || destructive ? DialogTheme.title : enabled ? DialogTheme.body : DialogTheme.faint)
                        .frame(minWidth: badge?.width ?? Metrics.key.width, maxWidth: badge?.width,
                               minHeight: badge?.height ?? Metrics.key.height, maxHeight: badge?.height)
                        .padding(.horizontal, badge != nil || key == "↩" ? 0 : Design.Space.xxs)
                        .background(RoundedRectangle(cornerRadius: badge == nil ? Design.Radius.inset : Design.Radius.small, style: .continuous)
                            .fill(Design.fillOnDarkColor(accent || destructive ? .pressed : primary ? (enabled ? .selected : .subtle) : .hover)))
                        .overlay(RoundedRectangle(cornerRadius: badge == nil ? Design.Radius.inset : Design.Radius.small, style: .continuous)
                            .strokeBorder(accent || destructive ? DialogTheme.outline : .clear, lineWidth: 1))
                }
            }
            .padding(.horizontal, Design.Space.l)
            .frame(height: Design.Space.control)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    .fill(destructive ? Design.danger : accent ? Design.accent : primary ? Design.fillOnDarkColor(enabled ? .pressed : .subtle) : Design.panelDarkRaisedColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    .strokeBorder(destructive || (primary && !enabled) ? .clear : DialogTheme.outline, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    // The default button sits on a darker lip, ~1.5 pt below: deep orange for Quit and Save,
                    // a dark red for Delete.
                    .fill(style == .accent ? (enabled ? DialogTheme.accentLip : DialogTheme.accentLipDisabled) : destructive ? DialogTheme.destructiveLip : .clear)
                    .offset(y: Metrics.lip)
            )
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                .fill(style.hoverTint.opacity(hovered && enabled ? Design.Fill.selected.rawValue : 0))
                .allowsHitTesting(false))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Design.Motion.fast), value: hovered)
        .accessibilityLabel(title)
        .fixedSize()
    }
}

struct DialogScrollContent<Content: View>: NSViewRepresentable {
    let width: CGFloat
    let maximumHeight: CGFloat
    let content: () -> Content

    init(width: CGFloat, maximumHeight: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.maximumHeight = maximumHeight
        self.content = content
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = NSHostingView(rootView: AnyView(content().frame(width: width, alignment: .leading)))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(content().frame(width: width, alignment: .leading))
        resize(scroll)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        resize(scroll)
    }

    @discardableResult
    private func resize(_ scroll: NSScrollView) -> CGSize {
        guard let host = scroll.documentView else { return .zero }
        let height = host.fittingSize.height
        host.setFrameSize(NSSize(width: width, height: height))
        scroll.hasVerticalScroller = height > maximumHeight
        scroll.contentView.scroll(to: NSPoint(x: 0, y: host.isFlipped ? 0 : max(0, height - maximumHeight)))
        return CGSize(width: width, height: min(height, maximumHeight))
    }
}

final class DialogPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var handleKey: ((NSEvent) -> Bool)?
    private weak var owner: NSWindow?
    private var parentObserver: NSObjectProtocol?
    private(set) var isDismissing = false
    private var isClosed = false

    override var canBecomeKey: Bool { true }

    convenience init<Content: View>(over parent: NSWindow?, content: Content) {
        self.init(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        let host = NSHostingView(rootView: content)
        contentView = host
        setContentSize(host.fittingSize)
        owner = parent
        if let parent {
            parentObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        } else {
            center()
        }
    }

    func show() {
        if let owner {
            owner.beginSheet(self) { [weak self] _ in self?.finishClose() }
        } else {
            makeKeyAndOrderFront(nil)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }

    override func close() {
        guard !isClosed, !isDismissing else { return }
        isDismissing = true
        if let parent = sheetParent {
            parent.endSheet(self)
        } else {
            finishClose()
        }
    }

    private func finishClose() {
        guard !isClosed else { return }
        isClosed = true
        let dismissed = onDismiss
        onDismiss = nil
        handleKey = nil
        if let parentObserver { NotificationCenter.default.removeObserver(parentObserver) }
        parentObserver = nil
        orderOut(nil)
        super.close()
        dismissed?()
    }

    @discardableResult
    static func present<Content: View>(over parent: NSWindow, _ content: (@escaping () -> Void) -> Content) -> Bool {
        guard parent.attachedSheet == nil else { return false }
        var panel: DialogPanel?
        let window = DialogPanel(over: parent, content: content { panel?.close() })
        panel = window
        window.onDismiss = { panel = nil }
        window.show()
        return true
    }
}
