# Niche brand

The mark is a lowercase **n** drawn as a niche's vault on one stem, with the signal dot
standing in for the other stem: a space carved out, and something of yours in it.

## Construction

On a 32 grid, stroke 6, butt caps:

- **Arch:** `M7 17.5V15a9 9 0 0 1 18 0v14`, a half circle of radius 9 centred on 16,15, the
  right stem down to the baseline (y 29), the left side stopping 2.5 above the dot.
- **Dot:** radius 4.5 at 7,24.5, centred under the left side, its bottom on the baseline.
- Nothing else is ever added to it. No gradient, outline, glow or shadow on the mark.

## Colours

| Role | Dark | Light |
|---|---|---|
| Ground (tile) | `#16181b` graphite | `#f4f5f7` |
| Ink (arch) | `#f0f2f4` | `#16181b` |
| Signal (dot) | `#f45120` signal orange | `#ef4f1f` |

The dot is the only colour in the logo. In one colour (`niche-icon-mono`, the menu bar) the
whole mark goes ink.

## Files

| File | Use |
|---|---|
| `niche-icon.svg` | App icon: the mark on a graphite squircle, 824 wide on the 1024 canvas, with the standard shadow. Source of `resources/AppIcon.icns` and the default App Icon choice. |
| `niche-icon-light.svg` | Light tile (Settings ▸ General ▸ App Icon). |
| `niche-icon-mono.svg` | One colour. |
| `niche-mark.svg` | The tile alone, edge to edge, for in-app branding (`BrandMark`). |
| `niche-mark-mono.svg` | The bare mark in `currentColor`; `MenuBarItem.icon` draws the same geometry. |

## Regenerating

    swift scripts/make-brand.swift
