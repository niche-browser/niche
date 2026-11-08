# Architecture

## Layers

| Layer | Where | Imports |
|---|---|---|
| Core | `Packages/NicheCore` | Foundation, CoreGraphics, Observation |
| App | `Sources/Niche` | NicheCore, AppKit, SwiftUI, NicheCEF |
| Bridge | `Sources/NicheCEF` | CEF (Objective-C++, seen by Swift through `include/`) |
| Helper | `Sources/NicheHelper` | CEF (the Chromium subprocess) |
| Dock tile | `Sources/NicheDockTile` | AppKit (the Dock icon plug-in) |

NicheCore never imports AppKit, Cocoa, SwiftUI, UIKit or NicheCEF; `scripts/lint.py`
(`core-platform-import`) fails the build when it does. NicheCore is a package of its own, so
`swift test --package-path Packages/NicheCore` runs without `vendor/cef`. Every app file sees it
through `Sources/Niche/App/NicheCoreExports.swift`.

## Rules

1. **Decisions go in NicheCore.** Code that decides something without a window or a page (a
   model, a file format, a layout rule, a policy) goes in NicheCore, with a test. Its API is
   `public` because the app is another package.
2. **Split a type that needs AppKit for part of its job.** The value goes in NicheCore and the
   AppKit side becomes an extension in the app: `KeyChord` and `Shortcut`, `FaviconKey` and
   `FaviconCache`.
3. **A decoder reads only its own file.** A one-time migration that needs anything else
   (another app's preferences, the disk) takes it as an argument and runs where the file is
   loaded. Example: `AppSettings.migrateToolbarDefault(arcShowsToolbar:)`, called by
   `SidebarStore`.
4. **Data-folder formats don't change by accident.**
   `Packages/NicheCore/Tests/NicheCoreTests/Fixtures/Model` holds current and older
   `sidebar.json`, `settings.json`, `windows.json`, `keybindings.json` and the others, each with
   what Niche saved after loading it. If a change makes a file load differently, record the new
   expectation and say why in the PR.

## The engine contract

The CEF build in `vendor/cef` is downloaded prebuilt (`scripts/fetch-cef.sh`), with Niche's
patches from `scripts/cef-patches` compiled in. Strings both sides must agree on are compiled
into that binary, so they keep their upstream spelling until the engine is rebuilt with
`scripts/build-cef.sh`:

- DevTools methods sent by `BrowserManager`, `ExtensionStore` and `WebKitBrowser`:
  `Cra.discard`, `Cra.load`, `Cra.getFreezingState`, `Cra.setFreezingVote`,
  `Cra.mediaSession`, `Cra.autoPictureInPicture`, `Cra.installFromWebStore`.
- Process messages handled in `NicheCEF.mm`: `Cra.audible`, `Cra.capture`, `Cra.activate`.
- The command-line switch `cra-load-extension-profiles`.

Renaming any of them in Swift alone breaks tab sleeping, media keys, Picture in Picture,
Web Store installs or per-profile extensions. Rename them in the patches and the app in one
change, together with a rebuilt engine.

The Keychain item is `Niche Safe Store`. It has the upstream name's 16-byte length so
`fetch-cef.sh` swaps it into the binary in place; a longer name needs a rebuilt engine.

## Known exceptions

This logic is pure enough for NicheCore but still lives in the app. Move a piece when a change
touches it anyway, not as a side errand. Paths are under `Sources/Niche/`.

- `Services/SuggestionEngine.swift`: the command bar's ranking. It holds `SidebarStore`,
  `KeyBindingRegistry` and `SearchSuggestions`.
- `Services/SidebarStore.swift` and `SidebarIntegrity.swift`: tree edits and repair, on
  `JSONStore` files, the app's clock and `ArcImporter`. Tested by `scripts/test-store.sh`.
- `App/KeyBindings.swift`: `KeyAction`, `MenuSection` and the default bindings, in a file that
  imports AppKit for `Shortcut`'s event matching.
- `Services/Import/`: the parsers for other browsers' files. Tested on `Tests/Fixtures` by
  `scripts/test-store.sh`.
- `UI/Windows/ExtensionLaunch.swift`, `Services/DevToolsToggle.swift` and
  `UI/Windows/FloatingSidebarGeometry.swift`: policies, tested by `scripts/test-policies.sh`
  and `scripts/test-floating-sidebar.sh`.
