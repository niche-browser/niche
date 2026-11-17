# Shields

Niche's ad, tracker and cookie-notice blocking: one filter engine, the community's filter lists,
updated once a day. What the user sees of it is in [privacy.md](privacy.md); this is how it is
built and how to work on it.

## The pieces

| Piece | Where | What it does |
|---|---|---|
| Engine | `Sources/NicheShields` (Rust) | A C interface (`include/NicheShields.h`) over Brave's [adblock-rust](https://github.com/brave/adblock-rust) (MPL-2.0, pinned in `Cargo.toml`): build an engine from lists, check a request, say what to hide on a page, and pack the rules page processes need. `scripts/build-shields.sh` builds `vendor/shields/libniche_shields.a`; NicheCEF and NicheHelper link it. |
| Request path | `NicheCEF.mm` (`NicheDecide`, `NicheContentBlockingHandler`) | Every request a page makes: the user's say first (`NicheContentBlocker.h`: allowed, blocked, protection off for the site), then the engine's. A blocked request is cancelled, or answered with a harmless stand-in when the lists name one (`NicheStandInHandler`). A page's address loses its tracking codes (`removeparam` rules). |
| Page processes | `Sources/NicheHelper/main.cc` | The lists' scriptlets for a document (answer a cookie notice, defuse an ad-block wall) run when its script context is created, before the page's own scripts. The rules for it travel with each tab as a compressed blob (about 0.6 MB). |
| Hiding | `ShieldsPageScript` (NicheCore), `HideWhatTheListsSay` in `NicheCEF.mm` | The page's top document adopts one stylesheet of selectors to hide, reports its class and id names for the generic rules, and works out procedural rules (`:has-text()`, `:upward()` …). |
| Lists in the app | `ShieldsService` (app), `ShieldsPack` / `ShieldsGroup` / `ShieldsUpdate` (NicheCore) | Keeps the packs in Application Support/…/Shields, checks their signature, builds the engine off the main thread from the groups switched on, and looks for newer packs daily. |
| Packs | `scripts/shields-pack.mjs`, `resources/shields/lists.json`, `.github/workflows/shields.yml` | A daily job downloads the lists, exports uBlock Origin's scriptlets and stand-in resources, and publishes signed packs as assets of the repository's `shields` release. |
| Levels | `PrivacyLevel` (NicheCore) | Relaxed, Balanced, Strict: presets over the switches, for onboarding and Settings ▸ Privacy. |

## Lists and groups

`resources/shields/lists.json` names every list with what it is for. A group is one switch in
Settings ▸ Privacy:

| Group | Lists | Default |
|---|---|---|
| core | uBlock filters – Unbreak, Quick fixes | used whenever anything is |
| ads | uBlock filters – Ads, EasyList, AdGuard – Ads | on |
| trackers | uBlock filters – Privacy, EasyPrivacy, URL Tracking Protection, Peter Lowe's list | on |
| cookies | uBlock, EasyList and AdGuard cookie-notice lists | on |
| annoyances | uBlock annoyances, EasyList newsletters and notifications | off (on at Strict) |
| malware | uBlock badware, URLhaus | on |
| regional | 37 lists by language, one small pack each | on: a Mac fetches the ones for its languages |

Only uBlock Origin's own lists are `trusted`: they may use the scriptlets that set cookies and
storage, which is how a cookie notice is answered with "essential only". A list the user adds
would never be.

The lists and uBlock Origin's scriptlets are GPL-3.0 (EasyList also CC BY-SA 3.0). They are not
part of Niche's source or its app bundle: Niche downloads them as data, uses them as they are,
and credits each in Settings ▸ Privacy ▸ Credits with its licence and a link.

## Packs and updates

A pack is raw-deflated JSON (`{format, built, lists: [{id, group, title, licence, homepage,
trusted, languages?, text}], resources: {scriptlets, redirects}}`) with a detached Ed25519
signature (`<name>.sig`, base64). `ShieldsPack.publicKey` is the public half; the private half
is the `SHIELDS_SIGNING_KEY` secret of the workflow. Niche checks the signature when it
downloads a pack and again every time it reads one from disk, and reads nothing it can't verify.

- `shields.pack`: the main lists and all resources (about 5.6 MB).
- `shields-<id>.pack` and `shields-regional.json`: the regional lists and their index.

Niche asks for the small `.sig` first; the same signature as the pack on disk means the same
pack, and nothing more is downloaded. It looks once a day (`ShieldsUpdate`), again after an hour
when a look failed, and from Settings ▸ Privacy "Update Now". A list that is down fails the
day's job, so yesterday's packs stay published. On a new Mac nothing is blocked until the first
pack arrives, a few seconds after launch; `ShieldsService.status` says so in Settings.

The request for the packs goes to GitHub and carries nothing about the user. It is the only
thing Shields sends anywhere.

## What the engine does not do

- **`$csp` rules** (a list injecting a Content-Security-Policy) are not applied: CEF lets a
  handler read a response's headers, not change them.
- **Blocking a whole page** (`$document` rules, which uBlock Origin answers with a warning page):
  a page the user asks for always loads; the malware lists still stop what a page loads.
- **Hiding inside frames**: the stylesheet goes to a page's top document. Scriptlets run in
  every frame.
- **Service workers' own requests** have no tab and are not checked.
- **`removeparam` with a regular expression** (adblock-rust supports plain names only).
- **CNAME uncloaking** (a tracker hiding behind a site's own subdomain) and **fingerprint
  noise** need engine patches; neither is here.
- **A site where protection is off** runs no list scripts, but a tab that existed before the
  switch learns it by message: a cross-process navigation in that tab straight afterwards can
  still run them once.

## Working on it

- `scripts/build-shields.sh` builds the library (cargo decides what is stale); `--test` runs the
  engine's own tests (`Sources/NicheShields/tests`). `scripts/test.sh` runs them too. Rust comes
  from [rustup](https://rustup.rs).
- A test instance never reaches the network for lists: `NICHE_SHIELDS_SOURCE=off` (the smoke
  test), or a `file://` folder with `NICHE_SHIELDS_UNSIGNED=1`. Scenarios get a small pack built
  from `Tests/Fixtures/Shields` by `scripts/shields-fixture-pack.py`; `scripts/scenario.sh
  shields` drives it.
- To run against the real lists locally: `node scripts/shields-pack.mjs --out /tmp/shields
  --key <pem>` and `NICHE_SHIELDS_SOURCE=file:///tmp/shields/`.
- `niche://debug?shields=<label>&url=…&page=…&type=script` logs what the engine says about a
  request; without `url`, how much is loaded.
- Updating adblock-rust: change the pinned version in `Sources/NicheShields/Cargo.toml`, run
  `scripts/build-shields.sh --test` and `scripts/scenario.sh shields`. Its serialized format
  changes between versions, which is why nothing serialized is kept on disk: the engine is built
  from list text at launch (about 0.3 s, off the main thread).
