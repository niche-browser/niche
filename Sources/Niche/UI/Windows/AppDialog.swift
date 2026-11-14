import AppKit
import Observation
import SwiftUI

private enum Metrics {
    /// The mark as a dialog's icon, and the frame it sits in.
    static let mark: CGFloat = 56
    static let markFrame: CGFloat = 61
    /// The application icon's frame: its artwork stops short of its canvas, so it is a point larger
    /// and sits a point higher than the mark.
    static let appIconFrame: CGFloat = 62
    static let appIconDrop: CGFloat = 0.75
    static let appIconLift: CGFloat = -1
    /// A long message scrolls: never shorter than this, and this much of the screen stays free.
    static let scrollMinimum: CGFloat = 140
    static let screenMargin: CGFloat = 250
    /// The screen's height when there is no screen to ask.
    static let screenFallback: CGFloat = 800
}

@MainActor
@Observable
final class AppDialog {
    enum Icon { case mark, application, none }

    let title: String
    let message: String
    let actions: DialogActions
    let icon: Icon
    let width: CGFloat
    let buttonSpacing: CGFloat
    let buttonOutset: CGFloat
    var input: String?
    let placeholder: String
    let requiresInput: Bool
    let suppressionTitle: String?
    var isSuppressed = false
    private var presentedWindow: DialogPanel?
    private var completion: ((NSApplication.ModalResponse) -> Void)?
    private var runningModal = false
    private var result = NSApplication.ModalResponse.abort

    init(title: String, message: String = "", actions: [DialogAction] = [DialogAction("OK")],
         input: String? = nil, placeholder: String = "", requiresInput: Bool = false, suppressionTitle: String? = nil,
         icon: Icon = .mark, width: CGFloat = 450, buttonSpacing: CGFloat = Design.Space.xxxl, buttonOutset: CGFloat = 0) {
        self.title = title
        self.message = message
        self.actions = DialogActions(actions)
        self.icon = icon
        self.width = width
        self.buttonSpacing = buttonSpacing
        self.buttonOutset = buttonOutset
        self.input = input
        self.placeholder = placeholder
        self.requiresInput = requiresInput
        self.suppressionTitle = suppressionTitle
    }

    convenience init(error: Error) {
        let error = error as NSError
        self.init(title: error.localizedDescription, message: error.localizedRecoverySuggestion ?? error.localizedFailureReason ?? "")
    }

    static var parentWindow: NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.orderedWindows
        for candidate in candidates {
            var window = candidate
            while let parent = window.parent { window = parent }
            if window.isVisible && window.canBecomeMain { return window }
        }
        return nil
    }

    @discardableResult
    func runModal() -> NSApplication.ModalResponse {
        runModal(over: Self.parentWindow)
    }

    @discardableResult
    func runModal(over parent: NSWindow?) -> NSApplication.ModalResponse {
        if let parent, parent.attachedSheet != nil { return .abort }
        let window = prepareWindow(over: parent)
        runningModal = true
        window.show()
        let response = NSApp.runModal(for: window)
        runningModal = false
        window.close()
        return response
    }

    func present(over parent: NSWindow, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard parent.attachedSheet == nil else {
            completion(.abort)
            return
        }
        self.completion = completion
        prepareWindow(over: parent).show()
    }

    func prepareWindow(over parent: NSWindow? = nil) -> DialogPanel {
        if let window = presentedWindow { return window }
        result = .abort
        let window = DialogPanel(over: parent, content: AppDialogView(dialog: self))
        window.title = title
        window.onDismiss = { [self] in
            presentedWindow = nil
            let done = completion
            completion = nil
            if runningModal { NSApp.stopModal(withCode: result) }
            done?(result)
        }
        window.handleKey = { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
            if event.keyCode == 53 {
                if let index = actions.cancelIndex { select(index) }
                return true
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                if let index = actions.defaultIndex { select(index) }
                return true
            }
            return false
        }
        presentedWindow = window
        return window
    }

    func select(_ index: Int) {
        guard let window = presentedWindow, !window.isDismissing, actions.buttons.indices.contains(index),
              actions.isEnabled(at: index, input: input, requiresInput: requiresInput) else { return }
        result = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
        window.close()
    }
}

private struct AppDialogView: View {
    @Bindable var dialog: AppDialog
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogScrollContent(width: dialog.width - 2 * Design.Space.xxxl,
                                maximumHeight: max(Metrics.scrollMinimum, (NSScreen.main?.visibleFrame.height ?? Metrics.screenFallback) - Metrics.screenMargin)) {
                details
            }
            // Arc's extra choice ("Quit, and don’t ask again") sits at the card's left edge, the rest at its right.
            HStack(spacing: Design.Space.m) {
                buttons(dialog.actions.leadingOrder)
                Spacer(minLength: 0)
                buttons(dialog.actions.trailingOrder)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -dialog.buttonOutset)
            .padding(.top, dialog.buttonSpacing)
        }
        .padding(Design.Space.xxxl)
        .frame(width: dialog.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DialogSurface())
        .onAppear { inputFocused = dialog.input != nil }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dialog.icon != .none {
                ZStack {
                    if dialog.icon == .application {
                        Image(nsImage: NSApp.applicationIconImage).resizable()
                    } else {
                        BrandMark(size: Metrics.mark)
                    }
                }
                // The icon keeps the size of Arc 1.172.1's Quit and Delete Space sheets (7 Nov 2026): the app icon
                // shows 50.5 pt across.
                .frame(width: dialog.icon == .mark ? Metrics.markFrame : Metrics.appIconFrame,
                       height: dialog.icon == .mark ? Metrics.markFrame : Metrics.appIconFrame)
                .offset(y: dialog.icon == .application ? Metrics.appIconDrop : 0)
                .padding(.top, dialog.icon == .application ? Metrics.appIconLift : 0)
                .accessibilityHidden(true)
            }
            Text(dialog.title)
                .font(Design.Font.ui(.title, .semibold))
                .foregroundStyle(DialogTheme.title)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, dialog.icon == .none ? 0 : Design.Space.xl)
            if !dialog.message.isEmpty {
                Text(dialog.message)
                    .font(Design.Font.ui(.body))
                    .lineSpacing(Design.Space.hair)
                    .foregroundStyle(DialogTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Design.Space.m)
            }
            if dialog.input != nil {
                TextField(dialog.placeholder, text: Binding(get: { dialog.input ?? "" }, set: { dialog.input = $0 }))
                    .textFieldStyle(.plain)
                    .font(Design.Font.ui(.body))
                    .foregroundStyle(DialogTheme.title)
                    .focused($inputFocused)
                    .padding(.horizontal, Design.Space.m)
                    .frame(height: Design.Space.control)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(Design.panelDarkRaisedColor))
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(DialogTheme.outline, lineWidth: 1))
                    .padding(.top, Design.Space.xl)
            }
            if let title = dialog.suppressionTitle {
                Toggle(title, isOn: $dialog.isSuppressed)
                    .toggleStyle(.checkbox)
                    .font(Design.Font.ui(.body))
                    .foregroundStyle(DialogTheme.body)
                    .padding(.top, Design.Space.xl)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func buttons(_ order: [Int]) -> some View {
        ForEach(order, id: \.self) { index in
            let action = dialog.actions.buttons[index]
            DialogButton(title: action.title, key: dialog.actions.key(at: index),
                         enabled: dialog.actions.isEnabled(at: index, input: dialog.input, requiresInput: dialog.requiresInput),
                         style: style(action.role)) { dialog.select(index) }
        }
    }

    private func style(_ role: DialogAction.Role) -> DialogButton.Style {
        switch role {
        case .primary: return .accent
        case .destructive: return .destructive
        case .secondary, .cancel: return .secondary
        }
    }
}
