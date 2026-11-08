# Niche

A native macOS browser: an AppKit and SwiftUI app on Chromium through CEF. Sidebar, spaces,
command bar; no account, no server, nothing leaves the Mac. Write code, comments and docs in
English.

- Build and run: `scripts/dev.sh` (debug NicheDev.app, relaunched on save), `scripts/build.sh`.
  `just` lists every script.
- Layout: `Packages/NicheCore` (decisions, no AppKit), `Sources/Niche` (the app),
  `Sources/NicheCEF` (Objective-C++ bridge to CEF), `Sources/NicheHelper` (Chromium subprocess),
  `brand/` (logo sources), `scripts/` (build, test, CEF).

## Rules

- Put a decision that needs no window or page (model, file format, layout rule, policy) in
  NicheCore, with a test. Before adding a type or moving logic, read docs/architecture.md.
- Strings shared with the prebuilt engine (`Cra.*` DevTools methods and process messages,
  `cra-load-extension-profiles`, `Niche Safe Store`) keep their spelling: see
  docs/architecture.md, "The engine contract".
- A bug fix comes with a test written first and seen failing. A test locked in
  `Tests/promises.lock` changes only when the product owner decides the behaviour changes.
  Before writing or changing a test, read docs/testing.md.
- Run `scripts/test.sh` before calling work done or opening a PR.
- Before changing a window, panel, sheet, menu or colour, read docs/design.md.
- AppKit over SwiftUI where the two compete; SwiftUI for settings panes and static content.

## When you need more

- Code layout, test instances, `niche://` scripting hooks: docs/development.md.
- Reviewing a PR: docs/reviewing.md.
- Speed, hangs and the perf budgets: docs/performance.md.
- Arc behaviour Niche follows, and how it was measured: docs/arc-parity.md,
  docs/arc-reverse-engineering.md.
- Releases, signing, the CEF pin: docs/release.md and docs/release-checklist.md.
- Logo and icons: brand/README.md; regenerate with `swift scripts/make-brand.swift`.
