import AppKit
import SwiftUI

/// What a window shows while no tab is open (HomeScreen): Niche's mark, a field that opens the
/// command bar, and the pages last closed in this space. It sits on the space's own colours, as
/// the sidebar does, and is still: nothing here moves.
struct HomeView: View {
    struct Model: Equatable {
        var theme: SpaceTheme
        var recents: [HomeScreen.Recent]
        /// New Tab's shortcut as keycaps ("⌘", "T"), empty when it has none.
        var newTabKeys: [String]
    }

    let model: Model
    var favicon: (String) -> NSImage? = { _ in nil }
    var openCommandBar: () -> Void = {}
    var restore: (UUID) -> Void = { _ in }

    private enum Metrics {
        /// The column the field and the list share.
        static let column: CGFloat = 480
        /// The mark over the field.
        static let mark: CGFloat = 44
        /// The field: a little taller than a control, as the place the eye lands.
        static let field: CGFloat = 44
        static let row: CGFloat = 36
    }

    private var palette: SpacePalette { model.theme.palette }

    var body: some View {
        VStack(spacing: Design.Space.section) {
            BrandGlyph(size: Metrics.mark, ink: palette.textPrimary)
                .accessibilityHidden(true)
            field
            if !model.recents.isEmpty { recents }
        }
        .frame(maxWidth: Metrics.column)
        .padding(Design.Space.pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A little above the middle, where a page's first line would be read.
        .offset(y: -Design.Space.pane)
    }

    private var field: some View {
        Button(action: openCommandBar) {
            HStack(spacing: Design.Space.m) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: Design.Icon.bar))
                    .foregroundStyle(palette.textTertiary)
                Text("Search or enter address")
                    .font(Design.Font.ui(.title))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Design.Space.m)
                HStack(spacing: Design.Space.xxs) {
                    ForEach(model.newTabKeys, id: \.self) { key in
                        Text(key)
                            .font(Design.Font.ui(.caption, .medium))
                            .foregroundStyle(palette.textSecondary)
                            .frame(minWidth: Design.Space.xxl, minHeight: Design.Space.xxl)
                            .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(palette.pillFill))
                    }
                }
            }
            .padding(.horizontal, Design.Space.xl)
            .frame(height: Metrics.field)
            .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(palette.pillFill))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(palette.separator, lineWidth: Design.Space.hair))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel("Search or enter address")
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text("Recently closed")
                .font(Design.Font.ui(.caption, .medium))
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Design.Space.l)
            VStack(spacing: Design.Space.hair) {
                ForEach(model.recents) { recent in
                    HomeRecentRow(recent: recent, icon: favicon(recent.url), palette: palette) { restore(recent.id) }
                }
            }
        }
    }
}

/// A recently closed page: its icon, title and address on a plate that shows under the pointer.
private struct HomeRecentRow: View {
    let recent: HomeScreen.Recent
    let icon: NSImage?
    let palette: SpacePalette
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Design.Space.l) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "globe").font(.system(size: Design.Icon.regular)).foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(width: Design.Icon.image, height: Design.Icon.image)
                Text(recent.title)
                    .font(Design.Font.ui(.body))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Design.Space.m)
                Text(recent.address)
                    .font(Design.Font.ui(.detail))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            .padding(.horizontal, Design.Space.l)
            .frame(height: NicheMetrics.rowHeight)
            .background(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous).fill(hovering ? palette.hoverFill : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous))
        }
        .buttonStyle(HomePressStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel("Reopen \(recent.title)")
    }
}

/// A pressed control sinks a little, as the sidebar's rows do.
private struct HomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Design.Motion.reduced ? Design.Motion.pressScale : 1)
            .animation(.easeOut(duration: Design.Motion.fast), value: configuration.isPressed)
    }
}
