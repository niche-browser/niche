import SwiftUI

/// Arc's Filter panel on Library ▸ Archived Tabs and Downloads (Arc 1.172.1, 8 Nov 2026, 2x stills):
/// it takes the search row's place: the title ("Filter Archived Tabs", 15 pt semibold, 12 pt in) and
/// a Done pill (59 × 36 pt); then each question (12 pt semibold, faded) over a wrapping row of
/// 33 pt chips, 6 pt apart, light until picked, dark with white text once picked.
struct LibraryFilterPanel: View {
    struct Chip: Identifiable {
        var id: String
        var label: String
        var icon: String? = nil
        var on: Bool
    }

    struct Section: Identifiable {
        var id: String { title }
        var title: String
        var chips: [Chip]
    }

    let title: String
    let sections: [Section]
    /// The list's width: the chips wrap within it.
    var width: CGFloat = 300
    let dark: Bool
    let toggle: (String) -> Void
    let done: () -> Void

    /// Arc's Done pill and chip height.
    private static let donePill = CGSize(width: 59, height: 36)
    private static let chipHeight: CGFloat = 33

    /// Neutral ink and plates over the space's colour: white on a dark sidebar, black on a light one.
    private func ink(_ emphasis: Design.Emphasis) -> Color { dark ? Design.onDarkColor(emphasis) : Design.onLightColor(emphasis) }
    private func plate(_ fill: Design.Fill) -> Color { (dark ? Color.white : .black).opacity(fill.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Design.Font.title).foregroundStyle(ink(.secondary))
                Spacer()
                Button(action: done) {
                    Text("Done").font(Design.Font.control).foregroundStyle(ink(.secondary))
                        .frame(width: Self.donePill.width, height: Self.donePill.height)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(plate(.hover)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .frame(height: Self.donePill.height)
            .padding(.top, 10)
            ForEach(sections) { s in
                Text(s.title).font(Design.Font.ui(.detail, .semibold)).foregroundStyle(ink(.secondary))
                    .padding(.top, Design.Space.xl).padding(.bottom, Design.Space.s)
                FlowRow(spacing: Design.Space.s) {
                    ForEach(s.chips) { c in
                        Button { toggle(c.id) } label: {
                            HStack(spacing: Design.Space.xs) {
                                if let icon = c.icon { Text(icon).font(.system(size: Design.Icon.regular)) }
                                Text(c.label).font(Design.Font.ui(.body, c.on ? .semibold : .regular))
                            }
                            .foregroundStyle(c.on ? (dark ? Color.black : .white) : ink(.secondary))
                            .padding(.horizontal, Design.Space.l).frame(height: Self.chipHeight)
                            .background(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                                .fill(c.on ? ink(dark ? .primary : .secondary) : plate(.hover)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(c.on ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .padding(.leading, Design.Space.l).padding(.trailing, Design.Space.m).padding(.bottom, Design.Space.xs)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Chips left to right, onto the next line when the row is full.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, s.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
