# Security

## Reporting a vulnerability

Please report security problems privately through
[GitHub's private vulnerability reporting](https://github.com/niche-browser/niche/security/advisories/new),
not in a public issue. Include the Niche version (Niche ▸ About Niche), your macOS version, and
the steps or a page that shows the problem.

Reports are read within a few days. Reporters are credited in the release notes unless
they'd rather not be.

## Supported versions

Only the latest release is supported. Niche updates itself, and fixes are not backported.

## Scope

In scope: anything Niche adds on top of Chromium, for example

- the `niche://` scheme and what pages or other apps can reach through it
- import from other browsers, and the passwords and cookies it moves
- the update feed and signature checks (Sparkle)
- extensions, native messaging hosts and the Chrome Web Store install flow
- Niche's patches to CEF (`scripts/cef-patches`) and the switches Niche starts Chromium with
- passkeys, Safe Storage and other Keychain use

Out of scope: bugs in Chromium itself, which belong with the
[Chromium project](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/).
If Niche ships a Chromium version with a known, fixed vulnerability for longer than a few
days, that is worth an ordinary issue.

Known gap: without a Google API key at build time (docs/release.md, Safe Browsing), Niche has
no Safe Browsing, so there are no warnings for known phishing or malware pages.
