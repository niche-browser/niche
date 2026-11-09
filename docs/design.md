# Design

Niche should feel like the quietest app on the Mac: graphite surfaces, one colour (the
signal orange), generous space, nothing that shouts. The tokens live in
`Sources/Niche/UI/Design.swift`; use them instead of literal colours, radii and font sizes.

## Colour

| Token | Use |
|---|---|
| `Design.accent` | The signal orange from the logo (`#f45120` dark, `#ef4f1f` light). Primary buttons, switches (through `.tint`), the selected settings icon. Nothing decorative. |
| `Design.graphite` | `#16181b`, the logo's ground. |
| `Design.surface` | A grouped card on a window background. |
| `Design.hairline` | Dividers between rows and panel outlines. |
| `Design.rowHover`, `Design.rowSelected` | Neutral plates for hovered and selected rows. Selection is never a saturated fill. |

A space's own theme colour still tints the sidebar and the command bar's selected row: the space
is the user's colour, the orange is Niche's.

## Shape

`Design.Radius`: inset 6 (keycaps, glyph plates), row 8, control 10, card 12, panel 16 (command
bar). Always `.continuous` corners.

## Space

Card rows are at least 44 pt tall with 14 pt text insets. 26 pt between one card group and the
next header; panes sit 28 pt from the window's edges.

## Type

SF Pro only; no serif. Pane titles 20 semibold, section headers 13 semibold, body 13, details
11.5 secondary. Onboarding headlines are semibold with tight tracking (−1.4 at 42 pt).

## Settings

Every pane is built from `SettingsKit.swift`: `SettingsSection` (header, card, optional
footnote), rows from `SettingsToggleRow`, `SettingsPickerRow` or `SettingsCardRow`, separated by
`SettingsCardDivider`. Explain a switch in its row's `detail`, not in a paragraph under the card;
a footnote is one or two lines. Switches are small (`.controlSize(.small)`). No right-aligned
"Label:" forms.

## Command bar

`CommandBarView`: a glass panel (HUD material under a graphite tint), 58 pt search field at
19 pt, 44 pt rows with 14 pt medium titles and tertiary details, and a footer of keyboard hints.
Rows are reused AppKit views; keep a keystroke to a few label updates.

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

## Boost editor

A 248 pt glass panel (`NSVisualEffectView`, popover material, 16 pt corners) at the window's right
edge under the toolbar, in the window's own appearance. Labelled buttons, the selected font and
active tools in the accent; Code widens it to 480 pt.
