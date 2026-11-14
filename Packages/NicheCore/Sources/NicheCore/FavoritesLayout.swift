import CoreGraphics

/// Where a space's favorite tiles go in a grid `width` points wide (the sidebar less 8 pt each side).
///
/// Arc's rule (1.171, AX frames, 1–9 favorites at sidebar widths 100–347, 31 Oct) at Dia's tile
/// size: at most as many columns (up to six) as keep a tile at least as wide as it is tall
/// (40 pt), then the fewest that need no more rows: one favorite fills the row, five go in one
/// row at 280 pt, seven 4 + 3 (#29). A short last row keeps the tile width, from the left.
public struct FavoritesLayout: Equatable {
    /// Dia's tile, where Arc's was 47 pt: the same favorites in a quieter block (13 Nov 2026).
    public static let tileHeight: CGFloat = 40
    public static let gap: CGFloat = 8
    /// The most tiles in a row, however wide the sidebar.
    public static let maxColumns = 6

    public let count: Int
    public let width: CGFloat

    public init(count: Int, width: CGFloat) {
        self.count = count
        self.width = width
    }

    public var columns: Int {
        let widest = (1...Self.maxColumns).last { (width - CGFloat($0 - 1) * Self.gap) / CGFloat($0) >= Self.tileHeight } ?? 1
        guard count > 0 else { return widest }
        let rows = (count + widest - 1) / widest
        return (count + rows - 1) / rows
    }

    public var rows: Int { (count + columns - 1) / columns }

    public var tileWidth: CGFloat { (width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns) }

    /// The tiles' height, 0 with no favorites.
    public var gridHeight: CGFloat {
        rows == 0 ? 0 : CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.gap
    }

    public func frame(at index: Int) -> CGRect {
        let n = columns, cw = tileWidth
        let r = index / n, c = index % n
        // Arc puts each tile on a half point (84.75 → 85 at 347 pt).
        let x = (CGFloat(c) * (cw + Self.gap) * 2).rounded() / 2
        return CGRect(x: x, y: CGFloat(r) * (Self.tileHeight + Self.gap), width: cw, height: Self.tileHeight)
    }

    /// The slot a tile dragged over the grid would land in: the one under `point`, a gap going to
    /// the nearer side, a point past the last tile to the last slot (#176). This grid counts the
    /// open slot among its tiles.
    public func slot(at point: CGPoint) -> Int {
        guard count > 0 else { return 0 }
        let row = min(max(Int(((point.y + Self.gap / 2) / (Self.tileHeight + Self.gap)).rounded(.down)), 0), rows - 1)
        let column = min(max(Int(((point.x + Self.gap / 2) / (tileWidth + Self.gap)).rounded(.down)), 0), columns - 1)
        return min(row * columns + column, count - 1)
    }

    /// Where the tile at `index` goes while slot `open` is held for a drop: the tiles from the
    /// open slot on move one slot along, so the grid reads as if the dragged tile were in it.
    public static func slot(ofTile index: Int, opening open: Int?) -> Int {
        guard let open, index >= open else { return index }
        return index + 1
    }
}
