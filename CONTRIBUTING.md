# Contributing to Niche

Bug reports with steps to repeat them are the most useful thing you can send. Code is welcome
too, within the rules below.

## What fits

- **Sleek and native.** AppKit and SwiftUI, Chromium through CEF. Every surface should feel
  like it belongs on the Mac: quiet, fast, precise. Arc's behaviour is the baseline where Niche
  has the same feature; change it when the change is better, and show why.
- **Local first.** No account, no server, no telemetry. Anything that would send a page or a
  prompt off the Mac needs the user's explicit choice.
- **English only, for now.** The interface isn't translated yet. Web pages and Chromium's own
  dialogs already follow the system language.

For anything bigger than a bug fix, open an issue first so the shape is agreed before the work.

## Getting set up

```sh
scripts/dev.sh            # dev loop: debug NicheDev.app, rebuilds + relaunches on save
scripts/build.sh          # release build at build/Niche.app
```

You need macOS 14+ on Apple silicon, Xcode 16+ and CMake (`brew install cmake`).
[docs/development.md](docs/development.md) has the layout, the `niche://` scripting hooks and
how to run a test instance next to your daily Niche.

## Sending a change

1. Branch from `main` and keep the change to one thing.
2. Match the code around you. Doc comments say *why*, not what.
3. Run `scripts/test.sh`. Say in the PR how you tested it, with a before and after screenshot
   for anything visible. A bug fix comes with the test that would have caught it.
4. Leave the release pipeline, signing and the CEF pin alone unless that is the point of the PR.

[docs/reviewing.md](docs/reviewing.md) lists what a review checks.

## Chromium and CEF

The CEF version is pinned in `scripts/fetch-cef.sh`. Patches to CEF live in
`scripts/cef-patches` and are built with `scripts/build-cef.sh`. A fix that needs a new patch
should say so in the issue first: every patch has to be carried through each Chromium update.

## Security

Please don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md).

## Licence

By contributing you agree that your contribution is licensed under the [MIT licence](LICENSE).
