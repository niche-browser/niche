import Foundation

/// Where everything in the tab strip goes (the tabs across the top of a window, `WindowLayout.top`).
///
/// From the leading edge: the space's chip, the favorites as small squares, a rule, then the run:
/// the space's tabs with their group names and splits, and the New Tab button after the last one.
/// The run is what gives when the window is narrow: tabs share the room evenly, lose their titles,
/// and at their narrowest scroll inside the run's own edges while the New Tab button stays put.
///
/// A tab keeps one width however long its title is, so the next tab's close button is under the
/// pointer after a close. For the same reason the tabs don't widen while the pointer is still in
/// the strip (`heldTabWidth`): several can be closed in a row without moving the mouse.
public enum TabStripLayout {
    public enum Item: Equatable, Sendable {
        /// The space's icon; opens the space list.
        case space
        case favorite(UUID)
        /// The rule between the favorites and the run.
        case rule
        /// A tab group's name, as wide as its text (`width`).
        case group(UUID, width: Double)
        case tab(UUID)
        /// A split view of `panes` pages: one item, wider than a tab.
        case split(UUID, panes: Int)

        public var id: UUID? {
            switch self {
            case .space, .rule: nil
            case .favorite(let id), .group(let id, _), .tab(let id), .split(let id, _): id
            }
        }

        /// Part of the run: it scrolls and shares the room. The chip, favorites and rule are fixed.
        public var isInRun: Bool {
            switch self {
            case .group, .tab, .split: true
            case .space, .favorite, .rule: false
            }
        }

        /// How many tab widths it takes: a split is one and a half, and 0.4 more for each page past two.
        var units: Double {
            switch self {
            case .tab: 1
            case .split(_, let panes): 1.5 + 0.4 * Double(max(0, panes - 2))
            default: 0
            }
        }
    }

    public struct Metrics: Equatable, Sendable {
        /// A tab with room to spare: wide enough for a page's name, the same for every tab.
        public var tabMax: Double = 200
        /// Under this a tab shows its icon alone.
        public var tabTitled: Double = 76
        /// The narrowest a tab gets before the run scrolls: its icon with air around it.
        public var tabMin: Double = 40
        /// Between two items.
        public var gap: Double = 2
        /// The space chip, a favorite and the New Tab button: squares of one size.
        public var square: Double = 28
        /// The rule and the air on both sides of it.
        public var rule: Double = 13
        /// Between the last item and the New Tab button.
        public var plusGap: Double = 4

        public init() {}
    }

    public struct Frame: Equatable, Sendable {
        public var item: Item
        /// From the strip's leading edge for a fixed item; from the run's own origin for a run item.
        public var x: Double
        public var width: Double
        public var midX: Double { x + width / 2 }
        public var maxX: Double { x + width }
    }

    public struct Result: Equatable, Sendable {
        /// The chip, favorites and rule, in strip coordinates.
        public var fixed: [Frame] = []
        /// Groups, tabs and splits, in the run's coordinates (0 is the run's leading edge).
        public var run: [Frame] = []
        /// Where the run starts in the strip, and how much of it shows.
        public var runX: Double = 0
        public var runVisibleWidth: Double = 0
        /// The run's whole length; more than `runVisibleWidth` when it scrolls.
        public var runContentWidth: Double = 0
        /// The New Tab button's leading edge, in strip coordinates.
        public var plusX: Double = 0
        /// One tab's width.
        public var tabWidth: Double = 0
        /// Tabs show their titles (false: icons alone).
        public var titled: Bool = true
        public init() {}
        public var scrolls: Bool { runContentWidth > runVisibleWidth + 0.5 }
        /// The furthest the run scrolls.
        public var maxScroll: Double { max(0, runContentWidth - runVisibleWidth) }

        /// The favorites' slots, in strip coordinates.
        public var favorites: [Frame] {
            fixed.filter { if case .favorite = $0.item { true } else { false } }
        }

        /// Left of this (strip coordinates) a carried or dragged tab is among the favorites: the
        /// rule between them and the tabs. With no favorite yet there is no rule, and it is
        /// `reach` past the start of the tabs, so a tab taken to the very start becomes the first.
        public func favoritesEdge(reach: Double) -> Double {
            if let rule = fixed.first(where: { $0.item == .rule }) { return rule.midX }
            return runX + reach
        }

        /// Where an item lands among the favorites when its middle is at `x` (strip coordinates):
        /// its index among the others. It passes a neighbour at that neighbour's middle.
        public func favoriteIndex(x: Double, moving: UUID?) -> Int {
            favorites.filter { $0.item.id != moving && $0.midX < x }.count
        }
    }

    /// `width` is the strip's room for all of it, from its leading inset to where the trailing
    /// buttons begin. `heldTabWidth` is the tab width to keep (never widen past) while the pointer
    /// is in the strip after a close.
    public static func layout(_ items: [Item], width: Double, heldTabWidth: Double? = nil, metrics m: Metrics = Metrics()) -> Result {
        var result = Result()
        var x = 0.0
        for item in items where !item.isInRun {
            let w = item == .rule ? m.rule : m.square
            result.fixed.append(Frame(item: item, x: x, width: w))
            x += w + (item == .rule ? 0 : m.gap)
        }
        // A rule already carries its air; the last square's gap stands before the run.
        result.runX = x
        let run = items.filter(\.isInRun)
        let plus = m.plusGap + m.square
        let room = max(0, width - x - plus)
        let units = run.reduce(0) { $0 + $1.units }
        let named = run.reduce(0.0) { total, item in
            if case .group(_, let w) = item { return total + w }
            return total
        }
        let gaps = m.gap * Double(max(0, run.count - 1))
        var tab = units > 0 ? (room - named - gaps) / units : m.tabMax
        tab = min(m.tabMax, max(m.tabMin, tab))
        if let heldTabWidth { tab = min(tab, max(m.tabMin, heldTabWidth)) }
        tab = tab.rounded(.down)
        result.tabWidth = tab
        result.titled = tab >= m.tabTitled
        var rx = 0.0
        for item in run {
            let w: Double
            switch item {
            case .group(_, let width): w = width
            default: w = (tab * item.units).rounded(.down)
            }
            result.run.append(Frame(item: item, x: rx, width: w))
            rx += w + m.gap
        }
        result.runContentWidth = run.isEmpty ? 0 : rx - m.gap
        result.runVisibleWidth = min(result.runContentWidth, room)
        result.plusX = result.runX + result.runVisibleWidth + (run.isEmpty ? 0 : m.plusGap)
        return result
    }

    /// The scroll offset that brings `id` into view, from `offset`: unchanged when it already
    /// shows whole, else the least movement that does, with a tab's worth of what comes next.
    public static func scroll(toShow id: UUID, in result: Result, offset: Double, peek: Double = 24) -> Double {
        guard result.scrolls, let f = result.run.first(where: { $0.item.id == id }) else { return min(max(0, offset), result.maxScroll) }
        var o = offset
        if f.x - peek < o { o = f.x - peek }
        if f.maxX + peek > o + result.runVisibleWidth { o = f.maxX + peek - result.runVisibleWidth }
        return min(max(0, o), result.maxScroll)
    }

    /// Where a dragged item lands among `frames` (run coordinates) when its middle is at `x`: the
    /// index it would have in the list without it. It passes a neighbour at that neighbour's middle.
    public static func insertionIndex(x: Double, among frames: [Frame], moving: UUID?) -> Int {
        let others = frames.filter { $0.item.id != moving }
        return others.filter { $0.midX < x }.count
    }
}

/// How many of the bookmarks bar's items fit, and whether the rest go behind a chevron.
public enum BookmarksBarLayout {
    /// `widths` are the items' own widths, in order. All of them show when they fit; when they
    /// don't, as many as fit beside the chevron.
    public static func visibleCount(widths: [Double], gap: Double, available: Double, chevron: Double) -> Int {
        let total = widths.reduce(0, +) + gap * Double(max(0, widths.count - 1))
        if total <= available { return widths.count }
        var used = chevron
        var count = 0
        for w in widths {
            let next = used + w + gap
            if next > available { break }
            used = next
            count += 1
        }
        return count
    }

    /// Where a dragged item lands among the shown items whose leading edges and widths are given:
    /// before the first one whose middle is past `x`.
    public static func insertionIndex(x: Double, frames: [(x: Double, width: Double)]) -> Int {
        frames.filter { $0.x + $0.width / 2 < x }.count
    }
}

/// Which items in the window's title row say the pointer is on them (a tab in the strip, a
/// bookmark under it). While any does the window stays put, so a press carries the item and not
/// the window.
public struct TitleRowHold: Equatable, Sendable {
    /// Every item that says so, not the last alone: a neighbour stepping aside under a carried
    /// tab says so and takes it back, and the tab in the hand still counts.
    private var items: Set<UUID> = []

    public init() {}

    public var holdsWindow: Bool { !items.isEmpty }

    public mutating func set(_ id: UUID, inside: Bool) {
        if inside { items.insert(id) } else { items.remove(id) }
    }
}
