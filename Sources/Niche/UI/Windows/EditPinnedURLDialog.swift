import SwiftUI

private enum Metrics {
    /// The card's width, Arc's.
    static let width: CGFloat = 393
    /// The key badges beside Cancel and Save.
    static let cancelKey = CGSize(width: 35, height: 20)
    static let saveKey = CGSize(width: 27, height: 20)
}

/// Arc 1.171's "Edit Pinned URL" dialog (a pinned tab's or favorite's Edit Pinned URL…),
/// as wide as Arc's in a 2x capture (1 Nov, #54): a 393 pt card over the dimmed window, the
/// saved URL selected in its field. Arc enables Save for any text; Niche only for an address
/// (TypedURL.pinnedDestination), so a search or a script can't become the pinned page.
struct EditPinnedURLDialog: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(url: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: url)
    }

    private var destination: String? { TypedURL.pinnedDestination(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Pinned URL")
                .font(Design.Font.ui(.title, .semibold))
                .foregroundStyle(DialogTheme.title)
            Text("This is what opens first when you click this tab or its favicon.")
                .font(Design.Font.ui(.body))
                .lineSpacing(Design.Space.hair)
                .foregroundStyle(DialogTheme.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Design.Space.m)
            TextField("", text: $text, prompt: Text("Enter a URL…").foregroundStyle(DialogTheme.faint))
                .textFieldStyle(.plain)
                .font(Design.Font.ui(.body))
                .foregroundStyle(DialogTheme.title)
                .focused($focused)
                .onSubmit { if let destination { onSave(destination) } }
                .padding(.horizontal, Design.Space.m)
                .frame(height: Design.Space.control)
                .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(Design.panelDarkRaisedColor))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).strokeBorder(DialogTheme.outline, lineWidth: 1))
                .padding(.top, Design.Space.xl)
            HStack(spacing: Design.Space.m) {
                Spacer()
                DialogButton(title: "Cancel", key: "ESC", enabled: true, style: .secondary, badge: Metrics.cancelKey, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                DialogButton(title: "Save", key: "↩", enabled: destination != nil, style: .accent, badge: Metrics.saveKey) {
                    if let destination { onSave(destination) }
                }
            }
            .padding(.top, Design.Space.xxxl)
        }
        .padding(Design.Space.xxxl)
        .frame(width: Metrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DialogSurface())
        .onAppear { focused = true }
    }
}
