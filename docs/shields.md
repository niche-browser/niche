# Shields

Niche's ad, tracker and cookie-notice blocking: one filter engine, the filter lists uBlock Origin
Lite starts with, uBlock Origin Lite's four filtering modes, updated every six hours. What the user sees of it is in [privacy.md](privacy.md); this is how it is
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

**The default set is uBlock Origin Lite's** (18 Nov 2026). uBO Lite is the blocker that works on
the sites that fight ad blockers hardest (YouTube first), and it does with exactly these lists:
its rules for such a site are written and tested against this set and no other. Niche ran
AdGuard's ad list beside them until then, 33 more script rules on a YouTube page than uBO Lite
runs there, and YouTube showed its "ad blockers are not allowed" warning.

`resources/shields/lists.json` names every list with what it is for. The ones marked `ubol` are
uBO Lite's default rulesets, and the pack builder checks them against uBO Lite's own catalogue
(`platform/mv3/rulesets.json` in the uBlock checkout) on every run: a list its defaults gained
is added, one they lost is dropped, with a line in the job's log. Nobody edits lists.json for
that. The rest are Niche's own choice on top. A group is one switch in Settings ▸ Privacy:

| Group | Lists | Default |
|---|---|---|
| core | uBlock filters – Quick fixes, Unbreak, uBO Lite (all uBO Lite's) | used whenever anything is |
| ads | uBlock filters – Ads, EasyList (uBO Lite's) | on |
| trackers | uBlock filters – Privacy, EasyPrivacy, Peter Lowe's list (uBO Lite's); URL Tracking Protection (Niche's choice) | on |
| cookies | uBlock, EasyList and AdGuard cookie-notice lists (Niche's choice; optional in uBO Lite) | on |
| annoyances | uBlock overlay notices, EasyList newsletters and notifications (Niche's choice) | off (on at Strict) |
| malware | uBlock badware, URLhaus (uBO Lite's) | on |
| regional | 37 lists by language, one small pack each | on: a Mac fetches the ones for its languages |

**More lists** (Settings ▸ Privacy): optional lists, all off to start with, each a pack of its own
(`shields-x-<id>.pack`) that a Mac fetches when its switch goes on. `shields-lists.json`
(`ShieldsCatalog`) names them. They are uBO Lite's optional rulesets that aren't regional and
aren't already in the default set, read from the same catalogue on every run (today: mobile
ads, LAN intrusion, AI widgets, social widgets, chat widgets, other annoyances), and before them
the lists Niche offers itself (`extras` in lists.json): AdGuard – Ads. Its row says what it
costs: on a few sites two sets of rules get in each other's way.

A hosts file (`127.0.0.1 ads.example`: Peter Lowe's list, URLhaus) is read as the rules it
stands for (`||ads.example^`), as uBlock Origin reads one: by the engine (`with_hosts_as_rules`),
and by the pack builder too, for the copies of Niche from before 18 Nov 2026 whose engine read
such lines as rules that match nothing. Until then Peter Lowe's list blocked nothing.

A few of uBlock Origin's scripts live among its stand-in files (noeval.js, nofab.js,
popads-dummy.js) and its lists inject them like any scriptlet; page processes get those too
(72 of the default lists' 18,780 script rules, which did nothing until 18 Nov 2026).

## Filtering modes

uBlock Origin Lite's four, with their meanings (`FilteringMode`, NicheCore). One for every site
(Settings ▸ Privacy "Filtering": Basic, Optimal, Complete) and one for a site that needs
something else (the privacy panel's slider, which adds Off):

| Mode | What Shields does on the page |
|---|---|
| Off | Nothing: every request loads, nothing is hidden, no list script runs. |
| Basic | Requests the lists name are blocked or answered with a stand-in. The page is left alone. |
| Optimal | Also what the lists say about the page's own site: its selectors are hidden and its scripts run. The default, as in uBO Lite. |
| Complete | Also the generic hiding rules, matched against the page's class and id names. |

The privacy levels set it: Relaxed is Basic, Balanced is Optimal, Strict is Complete. A site
left at the mode every site has keeps no mode of its own and follows the setting when it
changes; "Use My Setting" in the panel gives a site back. The browser process knows each
site's mode (`niche_blocker::ModeFor`), asks the engine for the page's selectors with or
without the generic ones (`niche_shields_cosmetic(url, generic)`), and tells page processes the
modes (`Niche.shieldsModes`, and `niche.shields.modes` for a new tab), where the lists' scripts
run from Optimal up. Niche ran everything, which is Complete, until 18 Nov 2026.

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

- `shields.pack`: the main lists and all resources (about 3.3 MB).
- `shields-<id>.pack` and `shields-regional.json`: the regional lists and their index.
- `shields-x-<id>.pack` and `shields-lists.json`: the optional lists and their catalogue.

Niche asks for the small `.sig` first; the same signature as the pack on disk means the same
pack, and nothing more is downloaded. The job runs every six hours and Niche looks every six
(`ShieldsUpdate`; uBlock Origin's quick fixes for sites that fight ad blockers expire after
eight, and uBO Lite itself ships about once a week), a few seconds after launch when a look is
due, again after an hour when one failed, and from Settings ▸ Privacy "Update Now". A list that
is down fails the job, so the last packs stay published. A change to the lists reaches every
copy of Niche by the next look, the ones already installed too: the packs are data, not part of
the app. On a new Mac nothing is blocked until the first
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
- **The engine is not uBO Lite's.** The lists and scripts are the same; uBO Lite hands its rules
  to Chrome's own blocker, Niche runs them through adblock-rust. A rule one of them supports and
  the other doesn't is a difference no list change closes.
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
  request; without `url`, how much is loaded. `filteringMode=basic|optimal|complete` sets the
  mode for every site, `privacyMode=off|basic|optimal|complete` the one for the site on screen,
  `shieldsExtra=<id>&on=1|0` a switch of "More lists"; `privacy=<label>` logs the page's mode.
- Updating adblock-rust: change the pinned version in `Sources/NicheShields/Cargo.toml`, run
  `scripts/build-shields.sh --test` and `scripts/scenario.sh shields`. Its serialized format
  changes between versions, which is why nothing serialized is kept on disk: the engine is built
  from list text at launch (about 0.3 s, off the main thread).
