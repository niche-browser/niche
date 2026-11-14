import AppKit
import SwiftUI

struct FolderIconPicker: View {
    let current: FolderSymbol?
    let onPick: (FolderSymbol?) -> Void
    @State private var hovered: FolderSymbol?

    /// The popover, a grid cell and the plate drawn inside it.
    private static let size = CGSize(width: 272, height: 144)
    private static let cell: CGFloat = 31
    private static let plate: CGFloat = 29

    private static let removeIcon: NSImage = {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>"#
        guard let image = NSImage(data: Data(svg.utf8)) else {
            preconditionFailure("Invalid folder icon removal artwork")
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Icon").font(Design.Font.ui(.body, .bold))
                if current != nil {
                    Button { onPick(nil) } label: {
                        Image(nsImage: Self.removeIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Design.Icon.image, height: Design.Icon.image)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove Icon")
                    .help("Remove Icon")
                }
            }
            .frame(height: 18)
            .padding(.top, 13.5)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 0), count: 8), spacing: 0) {
                ForEach(FolderSymbol.allCases, id: \.self) { symbol in
                    Button { onPick(symbol) } label: {
                        Image(nsImage: symbol.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Design.Icon.bar, height: Design.Icon.bar)
                            .frame(width: Self.cell, height: Self.cell)
                            .background(
                                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                                    .fill(symbol == current ? Design.fill(.strong) : hovered == symbol ? Design.fill(.selected) : Color.clear)
                                    .frame(width: Self.plate, height: Self.plate)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? symbol : (hovered == symbol ? nil : hovered) }
                    .accessibilityLabel(symbol.title)
                    .accessibilityAddTraits(symbol == current ? .isSelected : [])
                    .help(symbol.title)
                }
            }
            .padding(.horizontal, Design.Space.l)
            .padding(.top, Design.Space.l)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @MainActor
    static func show(current: FolderSymbol?, anchor: NSView, rect: NSRect, onPick: @escaping (FolderSymbol?) -> Void) {
        guard let content = anchor.window?.contentView else { return }
        let popover = NSPopover()
        popover.animates = false   // no system pop (SiteControlCenter.show)
        popover.behavior = .transient
        let picker = FolderIconPicker(current: current) { [weak popover] symbol in
            onPick(symbol)
            popover?.performClose(nil)
        }
        let host = NSHostingController(rootView: picker)
        host.sizingOptions = []
        host.preferredContentSize = size
        popover.contentViewController = host
        popover.contentSize = host.preferredContentSize
        popover.show(relativeTo: anchor.convert(rect, to: content), of: content,
                     preferredEdge: content.isFlipped ? .maxY : .minY)
    }
}
