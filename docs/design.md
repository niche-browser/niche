# Design

Niche should feel like the quietest app on the Mac: graphite surfaces, one colour (the
signal orange), generous space, nothing that shouts. The tokens live in
`Sources/Niche/UI/Design.swift`; every view takes its colours, type, radii, icon sizes and
timings from them. `scripts/lint.py` (`design-literal`) fails a view that gains a literal one. A
value that is one component's own (an illustration's colour, a measured timing) is a named
`static let` beside a comment saying what it is, never a number at the use site.

## Colour

| Token | Use |
|---|---|
| `Design.accent` | The signal orange from the logo (`#f45120` dark, `#ef4f1f` light). Primary buttons, switches (through `.tint`), the selected settings icon. Nothing decorative. |
| `Design.graphite` | `#16181b`, the logo's ground. |
| `Design.surface` | A grouped card on a window background. |
| `Design.hairline` | Dividers between rows and panel outlines. |
| `Design.rowHover`, `Design.rowSelected` | Neutral plates for hovered and selected rows. Selection is never a saturated fill. |

| `Design.ink(_:)`, `inkColor(_:)` | Text and glyphs by emphasis (primary, secondary, tertiary, quaternary), following the window's appearance. |
| `Design.onDark(_:)`, `onLight(_:)` | The same four steps as white or black ink, for a surface that is dark (or light) in both appearances. |
| `Design.fill(_:)`, `fillNS`, `fillOnDark` | Neutral plates: subtle, hover, selected, pressed, strong. |
| `Design.barInk`, `barInkDim`, `barFill(_:onLight:)` | Ink and plates on a bar that takes its page's colour: dark on a light page, light on a dark one, so a hover plate shows on both. |
| `Design.danger`, `positive`, `warning` | What a state means, in the system's colours. |
| `Design.panelDark`, `panelDarkRaised`, `scrim` | A dialog's ground, a field on it, and the dim behind a panel. |

A space's own theme colour still tints the sidebar and the command bar's selected row: the space
is the user's colour, the orange is Niche's.

## Shape

`Design.Radius`: small 4 (badges), inset 6 (keycaps, glyph plates), row 8, control 10, card 12,
panel 16 (command bar, dialogs), and `pill(height)` for capsules. Always `.continuous` corners.

## Space

`Design.Space`: every gap is a step of the scale (1, 2, 4, 6, 8, 12, 16, 20, 24). Card rows are at
least 44 pt tall with 16 pt text insets; 24 pt between one card group and the next header; panes
sit 28 pt from the window's edges. Controls are 28 pt tall (24 in a dense bar, 32 for a primary
action).

## Type

SF Pro only; no serif. `Design.TextSize` is the whole scale: micro 10, caption 11, detail 12,
body 13, title 15, headline 17, pane 20, large 28, display 42; `Design.Font.ui` and `.ns` make
SwiftUI and AppKit fonts from it. Everything read in a window is 13 pt: rows, buttons, fields,
tab titles. Pane titles 20 semibold, section headers 13 semibold, details 12 secondary.
Onboarding headlines are semibold with tight tracking (−1.4 at 42 pt).

## Icons

`Design.Icon`: one size and weight per place, so buttons side by side match. Bar buttons (the
toolbar, the sidebar's header and dock) draw 14 pt regular glyphs on a 28 pt plate with a 6 pt
radius; rows 13 pt; inside a field 11 pt; favicons and extension icons 16 pt. Back and forward
are chevrons. A custom control says what it is to VoiceOver (a label and the button role).

## Motion

`Design.Motion`: `fast` (0.12 s) for what the pointer causes, `standard` (0.22 s) on `curve` for a
view arriving or a list changing, `slow` (0.35 s) for something window-sized, `exit` (0.09 s) for
a panel leaving. A hover or selection fill shows at once and fades out in `fast`
(`CALayer.fadeOutFill`); a pressed row or tile sinks to 97.5 % and comes back on release
(`NSView.setPressedLook`); the command bar fades in over `fast` while it settles from 98 %, and
fades out in 0.09 s after the page has the keys back. Check `Design.Motion.reduced` (Reduce
motion) before anything travels: the change still happens, it doesn't move. Motions measured from
Arc (the sidebar slide, a row's bounce, the Library's 0.05 s) keep their numbers beside the
measurement.

## Settings

Every pane is built from `SettingsKit.swift`: `SettingsSection` (header, card, optional
footnote), rows from `SettingsToggleRow`, `SettingsPickerRow` or `SettingsCardRow`, separated by
`SettingsCardDivider`. Explain a switch in its row's `detail`, not in a paragraph under the card;
a footnote is one or two lines. Switches are small (`.controlSize(.small)`). No right-aligned
"Label:" forms.

## Command bar

`CommandBarView`: a glass panel (HUD material under a graphite tint), 52 pt search field at
17 pt, 40 pt rows with 13 pt medium titles and tertiary details, and a footer of keyboard hints.
Rows are reused AppKit views; keep a keystroke to a few label updates.

Opened by Add Split View, the bar fills the empty pane: an open tab's row reads "Open in Split"
and puts that tab in the pane instead of switching to it. A Today tab of the space moves in; a
favorite, a pinned tab, a tab of another space and a pane already in the split stay where they
are and the pane opens their address (`SplitPaneFill`, `SidebarStore.fillEmptyPane`).

## Home

A window with no tab open shows its home (`HomeView`, content from `HomeScreen`): the logo's
glyph, a 44 pt field that opens the command bar with New Tab's keys on it, and up to four pages
last closed in that space, each a 36 pt row that reopens it. It sits on the space's own colours
and nothing in it moves. An incognito window keeps its empty page.

## Onboarding

The left column carries the words, the right panel (`ImportFlowArt`) a scene. Primary actions
use `PrimaryButton`, filled with the accent. The cover shows the logo's arch with a glowing dot
behind a glass command bar.

## Logo

`brand/README.md` has the construction. In SwiftUI, draw it with `BrandGlyph` (vector, ink plus
orange dot) or `BrandMark` (the rendered app tile).

## Cards and empty states

No decorative gradients: a card is one flat fill (`Color.primary` at 4–7 %, or the banner's white
over the space) with a hairline, and its one action is `Design.accent`. Empty states and opt-ins
sit inside their column, never over a neighbour, and follow the sidebar's light or dark look.
Numbers that count (download progress) keep a fixed format and monospaced digits so they don't
change width, and redraw in steps, not per event.

## Library

A 74 pt rail of 64 × 56 buttons stacked under the traffic lights, a 32 pt search field. Opening
it widens the sidebar by 40 pt over the page, or as far as its edge was last dragged
(`LibraryWidth`, never narrower than the tab sidebar): pages keep the size they have beside the plain
sidebar (`ShellView.pageSidebarWidth`), so the Library never makes Chromium lay a page out again.

## The bar's colour

The bar above a page takes the colour the page shows along its top edge, so the two read as one
surface. `PageTopColor` decides it from a row of pixels across the page's top: one colour over
nearly all of the edge is the bar's; a glow, gradient or picture gives the ground it sits on,
which the page's script finds under it (the body and root last: their colour is the canvas
behind everything). While the page loads the bar has the ground the page has drawn so far, or
the canvas, never white over a dark page, and `BarLoadingSheen` crosses it: a soft band of the
bar's ink with a thin accent beam along its lower edge, which fade when the page has loaded.
Still under Reduce motion.

## Downloads

A download shows in the sidebar while it runs (`DownloadProgressRing`): the file's thumbnail over
the Library button is faint and fills from the bottom as the bytes arrive, breathing when the
server gives no size; a download with no thumbnail in this window draws an accent ring round the
Library glyph instead, which closes to a full circle before it fades. Under Reduce motion the
thumbnail and ring show their state without moving.

The tray over the Library button (`DownloadsTrayView`) starts with a line: "Downloads", which
opens Library ▸ Downloads, and Clear when there is something to clear. A row is the thumbnail,
the name (truncated in the middle, never to the sidebar's edge) over one line of state: "5 MB of
20 MB — 38 s left", "Paused — 5 MB of 20 MB", "Failed to Download" in the danger colour, or how
long ago it finished. A running or paused download has a 3 pt bar under its two lines: the
accent over a faint track, the ink's colour while paused, a piece crossing the track when the
server gave no size. Under the pointer a row gets a plate and the two buttons its state calls
for (`DownloadAction.buttons`: pause or resume and cancel; try again and remove; show in Finder
and remove), 24 pt with 11 pt glyphs, and its line shortens to the one thing that matters ("38 s
left"). A right-click has every action (`DownloadAction.menu`) and Clear Downloads; VoiceOver
gets them as the row's actions. The file's thumbnail over the Library button steps aside while
the tray is open. Library ▸ Downloads rows carry the same bar, buttons and menu.

## Privacy panel

A 360 pt card at the right of the panes (`PrivacyPanelCard`), rounded and shadowed like a page's
card, in the window's appearance; it fades in over `Design.Motion.standard` while the page makes
room at once. A page keeps at least a phone's width beside it, and a window too narrow grows
(`PrivacyPanelFit`). Everything in it is a row, a word or a count; no tables, no addresses unless
a company's row is opened. Blocked is `Design.positive`, a tracker that sees the visit
`Design.danger`, everything else neutral ink; the accent is only on the shield glyph, the switch
and the one primary button.

Top to bottom: the hero (a `Design.Radius.panel` card washed top to bottom in its state's colour:
green protected, red when a tracker sees the visit, grey with protection off) holds the diagram,
the site, the standing in `.headline` semibold with one line under it, and the three counts
divided by hairlines; then cards of rows (`privacyCard()`: `Fill.subtle` and a hairline), each
under a caption-size header: "On this page" (a tinted glyph plate, a title, the result at the
right in its tone), the site's switch, "Who is here" (one bar split by kind, a colour per kind
that tracks, grey for what makes the page work), the companies, "Happening now" with how long
ago, and the totals with a seven-day bar chart.

The diagram (`PrivacyOrbit`): the page's icon on a disc, a ring as the shield (a sweep of green
with a soft glow; dashed and grey with protection off), parties that got through as lettered
chips inside it joined to the page, blocked ones as chips outside it whose dashed line stops at
the shield. A new block sends one ring out from the shield. Chips arrive scaled in over
`Design.Motion.standard`; the "Live" dot breathes; nothing moves under Reduce motion. Counts keep
monospaced digits. The wording is in NicheCore (`PrivacyReport`, `PrivacyLedger`, `PrivacyWords`,
`TrackerCategory`) with tests: plain sentences a non-technical reader understands, and never a
claim about what wasn't seen ([privacy.md](privacy.md)).

The shield (`ToolbarPrivacyChip`): a half-filled shield, with the page's blocked count when there
is one, at the end of the sidebar's address field and before the toolbar's right-hand buttons.
It is there on every website, so the way into the panel is always in the same place; its plate
is lit while the panel is open.

## Privacy level

Onboarding's privacy step and the top of Settings ▸ Privacy offer the same three levels
(`PrivacyLevel`) as cards: a shield that fills with the level (`shield`, `shield.lefthalf.filled`,
`shield.fill`), the name, one line, and "Recommended" on Balanced. The picked card takes the
accent wash and ring; nothing else on the step uses the accent but the primary button. Beside
the cards in onboarding, the scene (`PrivacyArt`) shows the shield glowing in its ring with six
chips round it for what the web throws at a page: the ones the level stops are struck out and
held off beyond the ring, the others come in to it, and three promises sit under it. A change
of level moves the chips on a spring; they bob slowly otherwise; nothing moves under Reduce
motion. Settings shows "Custom" in the footnote when the switches match no level.

## Boost editor

A 248 pt glass panel (`NSVisualEffectView`, popover material, 16 pt corners) at the window's right
edge under the toolbar, in the window's own appearance. Labelled buttons, the selected font and
active tools in the accent; Code widens it to 480 pt.
