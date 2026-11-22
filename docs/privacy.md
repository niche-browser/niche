# Privacy

What Niche does to keep a visit to yourself, what the privacy panel shows, and what neither can
do. Nothing here leaves the Mac: there is no account and no server, and what a page did is
forgotten when its tab closes (a tab keeps its last few pages, so Back shows the right one).

## What is on by default (Settings ▸ Privacy)

| Switch | What it does | Where |
|---|---|---|
| Protection level | Relaxed, Balanced (the default) or Strict: a preset over the switches below, chosen in onboarding and at the top of Settings ▸ Privacy. | `PrivacyLevel` |
| Filtering | How much Shields does on a page, as in uBlock Origin Lite: Basic (requests blocked), Optimal (also the site's own hiding rules and scripts; the default) or Complete (also the generic hiding rules). A site can have its own in the privacy panel, Off included. | `FilteringMode`, [shields.md](shields.md) |
| Shields: Ads, Trackers, Cookie notices, Pop-ups and nags, Dangerous sites, Lists for your languages | The filter engine and the community's lists ([shields.md](shields.md)): requests are blocked, blocked scripts pages need get a stand-in, leftovers and cookie notices are hidden, and notices the lists know are answered with "essential only". Pop-ups and nags is off unless the level is Strict. | `Sources/NicheShields`, `ShieldsService` |
| Block third-party cookies | A site embedded in another site's page neither gets its cookies back nor leaves new ones: on the network (`NichePrivacyCookieFilter`) and from a script (Chromium's `profile.cookie_controls_mode`). | `NicheCEF.mm` |
| Remove tracking codes from links | Click and mailing identifiers (fbclid, gclid, … and whatever else the lists' `removeparam` rules name) are taken off a page's address before it is asked for. | `NicheContentBlockingHandler` |
| Tell websites not to sell or share my data | Global Privacy Control: `Sec-GPC: 1` on every request, and `navigator.globalPrivacyControl` in the page. | `NicheCEF.mm`, `PageScript` |
| Downloads checked on the Mac | Chromium's own checks hold a kind of file that can harm the Mac and an insecure (http) download until Keep or Delete; macOS quarantines every download. Google Safe Browsing is off (`TurnOffSafeBrowsing`): it would send each checked download's address and hash to Google. | `safe-downloads.patch`, `NicheCEF.mm`, [release.md](release.md#safe-browsing) |
| Notice fingerprinting | Every page is watched for scripts that read what tells this Mac from others (`PrivacyProbeScript`); the panel names them. | `PageScript`, `NicheHelper` |

Existing users get the newer switches on: a settings file from before them has no key for them,
and they default to on. The one switch that covered ads and trackers until 17 Nov 2026 stands
for both. "Block cookie banners" (a short list of Niche's own, off by default) is gone: "Cookie
notices" replaces it and starts on.

## The privacy panel

View ▸ Show Privacy Panel, the shield beside the page's address (in the sidebar's address field,
or the toolbar when it is shown), the Site Control Center, or "privacy" in the command bar. A card
at the right of the page (`PrivacyPanelView`):

- where the page stands ("You’re protected", "2 trackers can see this visit"), over a diagram:
  the page's icon in the middle, a shield round it, the companies that got through inside (red
  when they track), the ones kept out outside with their line stopped at the shield; a chip opens
  its company's row;
- three counts: Blocked, Sees you, Other;
- "On this page": what each protection did here (`PrivacyReport`): trackers stopped, cookies kept
  back, tracking codes removed, the "don't sell" signal, fingerprinting noticed, the connection;
- "Filtering on this site": the slider (Off, Basic, Optimal, Complete). Off lets trackers and
  their cookies through there; "Use My Setting" gives the site back to the mode for every site;
- "Who is here": one bar split by kind of company;
- every company, worst first, with what it is, what it learned in plain words (which page, your
  address, a cookie that went back to it, what the page sent it, what it read to fingerprint the
  Mac) and buttons to block or allow it on this site or everywhere. The company that runs the
  site itself (Google on youtube.com) is "This site", not a tracker;
- what is happening now, one line per company and kind of thing, with how long ago;
- what Niche blocked in all, and a bar for each of the last seven days (privacy-stats.json:
  counts only, never which sites).

The numbers come from the engine (`NichePrivacyEvent`, batched to the main thread), are grouped
by company in `PrivacyLedger` (NicheCore), and the companies' names from `TrackerDirectory`, a
table written by hand for Niche (about 190 companies; a host it doesn't know is listed under its
own site). A blocked company's row says which lists stopped it ("on the ad lists and the tracker
lists"), and an ad a site serves from its own address is counted under the site itself ("This
site"). The user's own blocks are `PrivacyRules` (privacy.json), pushed to the engine as
domains; a company is blocked with every domain the directory lists for it, so blocking Google
also stops its fonts and videos, and the panel says so before the click.

**Every page is recorded all the time**, panel or no panel, from its first request: the panel
shows the whole of what a page did whenever it is opened, and never asks for a reload to find
out (it did until 17 Nov 2026). The only reload it asks for is after a rule changes, since a rule
holds from the next request. `PrivacyPages` keeps a tab's last few pages by address, so Back
and Forward show each page's own record. The shield is on every website, with the page's blocked
count when there is one. A window too narrow for the panel grows to hold it (`PrivacyPanelFit`).

**Incognito windows** have the panel too. What is blocked there is not added to the total, a
choice made there holds until the last incognito window closes and is never written to
privacy.json, and a download made there is listed until the last incognito window closes and
never written to downloads.json.

The page's start script (Global Privacy Control's property, the fingerprinting watch) travels
with each browser to its renderer, where NicheHelper runs it the moment a document's script
context exists: before the page's own scripts, on the first page of a new tab too.

## What it does not do

Say these as they are; the panel must not promise more.

- **It shows what leaves the browser, not what a company does with it.** "Sees you" means a
  tracking host got a request with your address and the site's name; what is stored at the other
  end can't be known.
- **The site itself.** Requests to the page's own site are never blocked or listed: first-party
  analytics and what a site logs about its own visitors are out of reach.
- **What comes from the cache is not a request.** A script the browser already has is not asked
  for again, so its company is not listed for that load: nothing went to it. The panel's Reload
  (after a rule changes) asks for everything afresh.
- **Fingerprinting is noticed, not prevented.** The watch reports canvas, graphics chip, audio
  and font probes by the top document's scripts; frames inside the page are not heard, and the
  values a script reads are the real ones. It stands in front of a few methods in the page's
  world as proxies that keep each method's name, length and place and print as built in; a site
  that looks hard enough can still tell.
- **Protection off for a site lifts the network side only.** Trackers load and third-party
  cookies travel with requests again, but a script inside an embedded frame still can't read or
  write its cookies there: Chromium's profile-wide setting has no per-site exception Niche could
  set through CEF (tried 17 Nov 2026). An embedded sign-in that needs script cookies needs
  "Block third-party cookies" off in Settings.
- **Shared hosts.** `someone.github.io` and the like count as one site each (a short list in
  `NicheContentBlocker.h` and `PrivacySite`, not the full Public Suffix List).
- **Incognito downloads show in every window's list** while an incognito window is open; they
  leave the list when the last one closes and are never written to downloads.json.
- **The company table is incomplete and can go stale** when a product changes hands. A wrong
  owner is a wrong name in the panel, never a wrong block: blocking goes by the filter lists and
  the user's own rules.
- **What Shields itself can't do** ($csp rules, hiding inside frames, service workers' own
  requests, a first launch before the lists arrive) is listed in [shields.md](shields.md).
- **Pages in Safari's engine** (DRM services) are not watched or blocked.
- **Requests without a tab** (service workers running with no page) are not listed.

## Checking it

`scripts/scenario.sh privacy-panel` drives the panel on a fixture page whose third parties are
the run's own server under other names. `niche://debug?privacy=<label>` writes what the panel
has for the page on screen to the log; `privacyPanel=1|0`, `privacyRule=<choice>&party=<id>` and
`privacyProtection=off|on` do what the panel's controls do.
