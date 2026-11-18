import SwiftUI

/// The filtering slider (`FilteringMode`, uBlock Origin Lite's modes): a track with a stop per
/// mode and each mode's name under its stop. Settings ▸ Privacy shows the three a mode for every
/// site can be; the privacy panel shows all four for the site on screen, Off first.
///
/// The thumb follows the hand and settles on the nearest stop; a click on the track or on a name
/// goes there. The track fills in the accent up to the thumb, so more filtering reads as more.
struct FilteringSlider: View {
    let modes: [FilteringMode]
    let mode: FilteringMode
    let choose: (FilteringMode) -> Void

    /// Where the hand has the thumb, while it is dragged.
    @State private var dragX: CGFloat?
    @State private var hovering = false

    /// The thumb, the track under it, a stop's dot, and the row the names stand in.
    private static let thumb: CGFloat = 18
    private static let track: CGFloat = 4
    private static let dot: CGFloat = 6
    private static let trackRow: CGFloat = 22
    private static let nameRow: CGFloat = 16
    /// The thumb under the pointer or the hand grows by this much.
    private static let lift: CGFloat = 1.12

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let index = modes.firstIndex(of: mode) ?? 0
            let x = dragX.map { min(max($0, stop(0, width)), stop(modes.count - 1, width)) } ?? stop(index, width)
            let near = dragX.map { nearest($0, width) } ?? index
            ZStack(alignment: .topLeading) {
                Capsule().fill(Design.fill(.selected))
                    .frame(width: max(0, width - Self.thumb), height: Self.track)
                    .position(x: width / 2, y: Self.trackRow / 2)
                Capsule().fill(Design.accent)
                    .frame(width: max(0, x - stop(0, width)), height: Self.track)
                    .position(x: (stop(0, width) + x) / 2, y: Self.trackRow / 2)
                ForEach(modes.indices, id: \.self) { i in
                    Circle().fill(stop(i, width) <= x ? Design.accent : Design.inkColor(.quaternary))
                        .frame(width: Self.dot, height: Self.dot)
                        .position(x: stop(i, width), y: Self.trackRow / 2)
                    Text(modes[i].title)
                        .font(Design.Font.ui(.caption, i == near ? .semibold : .regular))
                        .foregroundStyle(i == near ? Design.inkColor(.primary) : Design.inkColor(.secondary))
                        .fixedSize()
                        .position(x: nameX(i, width), y: Self.trackRow + Self.nameRow / 2)
                }
                Circle().fill(.white)
                    .overlay(Circle().strokeBorder(Design.hairline, lineWidth: Design.Space.hair))
                    .shadow(color: Color(nsColor: Design.Shadow.cardColor), radius: Design.Shadow.cardRadius / 2, y: Design.Space.hair)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .scaleEffect(dragX != nil || hovering ? Self.lift : 1)
                    .position(x: x, y: Self.trackRow / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragX = $0.location.x }
                .onEnded { value in
                    let picked = modes[nearest(value.location.x, width)]
                    dragX = nil
                    if picked != mode { choose(picked) }
                })
            .onHover { hovering = $0 }
            .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.fast), value: dragX == nil)
            .animation(Design.Motion.reduced ? nil : .spring(duration: Design.Motion.standard), value: mode)
            .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.fast), value: hovering)
        }
        .frame(height: Self.trackRow + Self.nameRow)
        .accessibilityElement()
        .accessibilityLabel("Filtering")
        .accessibilityValue(mode.title)
        .accessibilityAdjustableAction { direction in
            guard let i = modes.firstIndex(of: mode) else { return }
            let next = direction == .increment ? i + 1 : i - 1
            if modes.indices.contains(next) { choose(modes[next]) }
        }
    }

    /// A stop's place on the track: the first and last half a thumb in from the ends.
    private func stop(_ i: Int, _ width: CGFloat) -> CGFloat {
        guard modes.count > 1 else { return width / 2 }
        return Self.thumb / 2 + CGFloat(i) * (width - Self.thumb) / CGFloat(modes.count - 1)
    }

    /// A name is centred under its stop; the first and last are kept inside the slider's edges.
    private func nameX(_ i: Int, _ width: CGFloat) -> CGFloat {
        let half = (modes[i].title as NSString).size(withAttributes: [.font: Design.Font.ns(.caption, .semibold)]).width / 2
        return min(max(stop(i, width), half), width - half)
    }

    private func nearest(_ x: CGFloat, _ width: CGFloat) -> Int {
        modes.indices.min { abs(stop($0, width) - x) < abs(stop($1, width) - x) } ?? 0
    }
}
