import Foundation

/// The Chrome Web Store as Niche shows it. Google's page says "Add to Chrome" and "Switch to
/// Chrome?" to every browser (its scripts name no other); a browser that wants its own name there
/// rewrites the page. This script runs in Niche's isolated world in every page (PageScript) and
/// returns at once anywhere but the store. There it:
/// - says "Add to Niche" / "Remove from Niche" on the install button (`relabel`);
/// - hides the "Switch to Chrome?" card (a dialog holding `#promo-header`, or a link to
///   google.com/chrome) and the "Switch to Chrome to install extensions and themes" banner (the
///   block around its Install Chrome button);
/// and does both again whenever the store redraws.
public enum WebStoreBranding {
    public static let host = "chromewebstore.google.com"

    /// `(text, name) => label | null`: the button label to show instead, or null to leave it.
    public static let relabel = #"(t, n) => { const m = /^\s*(Add to|Remove from) Chrome\s*$/.exec(t || ''); return m ? m[1] + ' ' + n : null; }"#

    public static func script(appName: String) -> String {
        let name = (try? String(data: JSONSerialization.data(withJSONObject: [appName]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()) } ?? "\"Niche\""
        return """
        (() => {
          if (location.hostname !== '\(host)' || window.top !== window || window.__nicheStore) return;
          window.__nicheStore = true;
          const name = \(name);
          const relabel = \(relabel);
          const style = document.createElement('style');
          style.textContent = 'div[role="dialog"]:has(#promo-header), div[role="dialog"]:has(a[href*="google.com/chrome/"]) { display: none !important; }';
          (document.head || document.documentElement).appendChild(style);
          const hideBanner = button => {
            let e = button;
            while (e.parentElement && !/Switch to Chrome to install/.test(e.textContent)) e = e.parentElement;
            const text = e.textContent.trim();
            while (e.parentElement && e.parentElement !== document.body && e.parentElement.textContent.trim() === text) e = e.parentElement;
            if (e !== document.body && e !== document.documentElement) e.style.setProperty('display', 'none', 'important');
          };
          const fix = () => {
            for (const b of document.querySelectorAll('button')) {
              const label = b.getAttribute('aria-label') || '';
              if (/^Switch to Chrome/.test(label) || b.textContent.trim() === 'Install Chrome') { hideBanner(b); continue; }
              const named = relabel(label, name);
              if (named) b.setAttribute('aria-label', named);
              for (const s of b.querySelectorAll('span')) {
                if (s.childElementCount) continue;
                const r = relabel(s.textContent, name);
                if (r) s.textContent = r;
              }
            }
          };
          let queued = false;
          const start = () => {
            fix();
            new MutationObserver(() => {
              if (queued) return;
              queued = true;
              requestAnimationFrame(() => { queued = false; fix(); });
            }).observe(document.body, { childList: true, subtree: true, characterData: true });
          };
          if (document.body) start(); else addEventListener('DOMContentLoaded', start, { once: true });
        })();
        """
    }
}
