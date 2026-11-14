import CoreGraphics
import NicheCore
import Testing

/// The favorites grid: Arc's rule for how many columns (docs/arc-reverse-engineering.md, "Favorites
/// grid columns and Peek") at Dia's tile size, 40 pt tall and up to six across (the owner, 13 Nov
/// 2026: Arc's 47 pt tiles read as bulk). Widths are the sidebar's; the grid is 16 pt narrower.
struct FavoritesLayoutTests {
    /// Four favorites, sidebar width → columns and the tile's width in whole points: four across
    /// while a tile stays at least 40 pt wide (down to a 200 pt sidebar), then two.
    @Test(.bug("https://github.com/niche-browser/niche/issues/12"), arguments: [
        (347, 4, 76), (300, 4, 65), (280, 4, 60), (260, 4, 55), (230, 4, 47),
        (205, 4, 41), (200, 4, 40),
        (170, 2, 73), (140, 2, 58), (100, 1, 84),
    ] as [(Int, Int, Int?)])
    func fourFavoritesMatchArc(sidebarWidth: Int, columns: Int, tileWidth: Int?) {
        let grid = FavoritesLayout(count: 4, width: CGFloat(sidebarWidth - 16))
        #expect(grid.columns == columns)
        if let tileWidth { #expect(Int(grid.tileWidth) == tileWidth) }
    }

    /// 1–9 favorites at six sidebar widths. The widest grid keeps tiles at least 40 pt wide, six
    /// at most (6 at 347, 5 at 280, 4 at 230 and 200, 2 at 140, 1 at 100), then takes the fewest
    /// columns that need no more rows: at 280 pt five go in one row, 6 → 3 × 2, 7 → 4 + 3, 9 → 5 + 4.
    @Test(.bug("https://github.com/niche-browser/niche/issues/29"), arguments: [
        (347, [1, 2, 3, 4, 5, 6, 4, 4, 5]),
        (280, [1, 2, 3, 4, 5, 3, 4, 4, 5]),
        (230, [1, 2, 3, 4, 3, 3, 4, 4, 3]),
        (200, [1, 2, 3, 4, 3, 3, 4, 4, 3]),
        (140, [1, 2, 2, 2, 2, 2, 2, 2, 2]),
        (100, [1, 1, 1, 1, 1, 1, 1, 1, 1]),
    ])
    func columnsByCountMatchArc(sidebarWidth: Int, columnsByCount: [Int]) {
        for (i, expected) in columnsByCount.enumerated() {
            let grid = FavoritesLayout(count: i + 1, width: CGFloat(sidebarWidth - 16))
            #expect(grid.columns == expected, "\(i + 1) favorites at \(sidebarWidth) pt")
        }
    }

    @Test func tilesSitOnHalfPoints() {
        // At 347 pt: 84.75 → 85, 254.25 → 254.5 (Arc's half points). Widths are not rounded.
        let grid = FavoritesLayout(count: 4, width: 331)
        #expect(grid.frame(at: 1).minX == 85)
        #expect(grid.frame(at: 3).minX == 254.5)
        #expect(grid.frame(at: 3).width == 76.75)
    }

    @Test func shortLastRowKeepsTileWidthFromTheLeft() {
        let grid = FavoritesLayout(count: 7, width: 331)
        #expect(grid.columns == 4 && grid.rows == 2)
        #expect(grid.frame(at: 4).minX == 0 && grid.frame(at: 4).minY == 48)
        #expect(grid.frame(at: 6).minX == grid.frame(at: 2).minX)
        #expect(grid.frame(at: 6).width == grid.frame(at: 0).width)
        #expect(grid.frame(at: 0).height == 40)
    }

    @Test func heightCountsRowsAndGaps() {
        #expect(FavoritesLayout(count: 0, width: 331).gridHeight == 0)
        #expect(FavoritesLayout(count: 0, width: 331).rows == 0)
        #expect(FavoritesLayout(count: 4, width: 331).gridHeight == 40)
        #expect(FavoritesLayout(count: 13, width: 331).gridHeight == 136, "3 rows of 40 and 2 gaps of 8")
    }

    /// #176: the slot under the pointer, across rows, with gaps going to the nearer tile.
    @Test(.bug("https://github.com/niche-browser/niche/issues/176"))
    func slotUnderThePointer() {
        let grid = FavoritesLayout(count: 7, width: 331)  // 4 + 3, tiles 76.75 wide, 48 pt row pitch
        #expect(grid.slot(at: CGPoint(x: 10, y: 10)) == 0)
        #expect(grid.slot(at: CGPoint(x: 100, y: 10)) == 1)
        #expect(grid.slot(at: CGPoint(x: 81, y: 10)) == 1, "a gap's right half goes to the tile after it")
        #expect(grid.slot(at: CGPoint(x: 80, y: 10)) == 0, "its left half to the tile before")
        #expect(grid.slot(at: CGPoint(x: 330, y: 10)) == 3)
        #expect(grid.slot(at: CGPoint(x: 10, y: 50)) == 4)
        #expect(grid.slot(at: CGPoint(x: 100, y: 50)) == 5)
        #expect(grid.slot(at: CGPoint(x: 300, y: 50)) == 6, "past the short last row: the last slot")
        #expect(grid.slot(at: CGPoint(x: -20, y: -20)) == 0)
        #expect(grid.slot(at: CGPoint(x: 400, y: 400)) == 6)
        #expect(FavoritesLayout(count: 0, width: 331).slot(at: .zero) == 0)
    }

    @Test(.bug("https://github.com/niche-browser/niche/issues/176"))
    func tilesMoveAlongPastTheOpenSlot() {
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: nil) } == [0, 1, 2, 3])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 0) } == [1, 2, 3, 4])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 2) } == [0, 1, 3, 4])
        #expect((0..<4).map { FavoritesLayout.slot(ofTile: $0, opening: 4) } == [0, 1, 2, 3])
    }
}
