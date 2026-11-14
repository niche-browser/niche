import NicheCore
import Testing

struct ToolbarColorTests {
    /// A tab's toolbar colour: its page's report, else the colour the tab saved, else white, so a page
    /// coming back never flashes a white bar it didn't have (#84).
    @Test(.bug("https://github.com/niche-browser/niche/issues/84"), arguments: [
        // The page's own report wins over what the tab remembers.
        ("#602040", "#205060", "#602040" as String?),
        // Not reported yet (no live page, or a page still loading): the remembered colour.
        ("", "#205060", "#205060"),
        (nil, "#205060", "#205060"),
        ("none", "#205060", "#205060"),
        // Nothing known: white, never the canvas.
        ("", nil, nil),
        (nil, nil, nil),
        (nil, "", nil),
        ("rgb(1, 2, 3)", "#12345", nil),
    ] as [(String?, String?, String?)])
    func reportedThenRememberedThenWhite(reported: String?, remembered: String?, bar: String?) {
        #expect(ToolbarColor.hex(reported: reported, remembered: remembered) == bar)
    }

    /// A page that is still loading has drawn its ground before it has a top edge to read: the
    /// bar takes that, so bar and page are one surface from the first frame (13 Nov 2026: a
    /// white bar over a dark page until the load ended).
    @Test(arguments: [
        ("#602040", "#205060", "#000000", "#602040" as String?),
        ("", "#205060", "#000000", "#205060"),
        ("", nil, "#000000", "#000000"),
        (nil, "", "#0F0F0F", "#0F0F0F"),
        // A page of Niche's own that lets the window through has no colour to give.
        ("", nil, "clear", nil),
        ("", nil, "", nil),
        (nil, nil, nil, nil),
    ] as [(String?, String?, String?, String?)])
    func thenThePagesGround(reported: String?, remembered: String?, ground: String?, bar: String?) {
        #expect(ToolbarColor.hex(reported: reported, remembered: remembered, ground: ground) == bar)
    }
}
