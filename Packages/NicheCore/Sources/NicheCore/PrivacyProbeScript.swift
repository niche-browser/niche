import Foundation

/// What a script can read to recognise a Mac without a cookie.
public enum PrivacyProbe: String, Codable, CaseIterable, Sendable {
    case canvas, webgl, audio, fonts

    /// "… read <this>".
    public var what: String {
        switch self {
        case .canvas: "how your Mac draws text and shapes"
        case .webgl: "your graphics chip"
        case .audio: "how your Mac processes sound"
        case .fonts: "which fonts you have installed"
        }
    }
}

/// Notices a page reading what tells this Mac from others (`PrivacyProbe`): text drawn on a canvas
/// and read back, the graphics chip's name, sound rendered off screen from an oscillator, the
/// width of text in dozens of fonts. Those are the measurements fingerprinting scripts take; one
/// of them alone can be innocent, which is why the panel names it and leaves the judgment to the
/// reader.
///
/// Every page starts with it (Settings ▸ Privacy, "Notice fingerprinting"), so the panel knows
/// what a page read whenever it is opened. It stands in front of a few methods in the page's
/// own world as a `Proxy` of each: the method keeps its name, its length and its place on the
/// prototype, and reads as built in when a script prints it, so a site that checks whether its
/// browser was tampered with is not put off. Each report goes to Niche's isolated world as a `CustomEvent` named `event`, as "<probe> <script
/// address>", at most three per probe and document, and is said again when Niche's world asks
/// (it can arrive after a page's first scripts); that world keeps each report once. Only the top document's scripts are heard.
public enum PrivacyProbeScript {
    /// How many fonts' text widths a page measures before it counts as listing the fonts.
    public static let fontThreshold = 40

    /// The script for the page's world.
    public static func script(event: String) -> String {
        """
        (() => {
          if (window.top !== window) return;
          // Taken now, before the page's scripts run: one that replaces them later never sees a report.
          const dispatch = window.EventTarget && EventTarget.prototype.dispatchEvent, Report = window.CustomEvent;
          const listen = window.EventTarget && EventTarget.prototype.addEventListener;
          if (!dispatch || !listen || !Report) return;
          const sent = {}, said = [];
          // Niche's own world can arrive after the first scripts of a page: it asks, and hears
          // again what was reported before it listened.
          listen.call(window, '\(event)q', () => { for (const detail of said) dispatch.call(window, new Report('\(event)', { detail })); });
          const report = kind => {
            if ((sent[kind] = (sent[kind] || 0) + 1) > 3) return;
            let source = '';
            try { source = ((new Error().stack || '').match(/https?:\\/\\/[^\\s)]+/) || [''])[0].replace(/(:\\d+)+$/, ''); } catch (e) {}
            said.push(kind + ' ' + source);
            dispatch.call(window, new Report('\(event)', { detail: kind + ' ' + source }));
          };
          const wrap = (proto, name, kind, when) => {
            const d = proto && Object.getOwnPropertyDescriptor(proto, name);
            if (!d || typeof d.value !== 'function') return;
            Object.defineProperty(proto, name, { ...d, value: new Proxy(d.value, { apply(target, self, args) {
              try { if (when(self, args) && kind) report(kind); } catch (e) {}
              return Reflect.apply(target, self, args);
            } }) });
          };
          const context = window.CanvasRenderingContext2D && CanvasRenderingContext2D.prototype;
          const canvas = window.HTMLCanvasElement && HTMLCanvasElement.prototype;
          const texted = new WeakSet();
          for (const name of ['fillText', 'strokeText']) wrap(context, name, null, c => { if (c.canvas) texted.add(c.canvas); return false; });
          wrap(canvas, 'toDataURL', 'canvas', c => texted.has(c));
          wrap(canvas, 'toBlob', 'canvas', c => texted.has(c));
          wrap(context, 'getImageData', 'canvas', c => c.canvas && texted.has(c.canvas));
          const fonts = new Set();
          let listed = false;
          wrap(context, 'measureText', 'fonts', c => {
            if (listed) return false;
            fonts.add(c.font);
            return listed = fonts.size >= \(fontThreshold);
          });
          for (const gl of [window.WebGLRenderingContext, window.WebGL2RenderingContext]) {
            wrap(gl && gl.prototype, 'getParameter', 'webgl', (_, args) => args[0] === 37445 || args[0] === 37446);
          }
          const offline = window.OfflineAudioContext;
          const tones = new WeakSet();
          wrap(window.BaseAudioContext && BaseAudioContext.prototype, 'createOscillator', null, c => {
            if (offline && c instanceof offline) tones.add(c);
            return false;
          });
          wrap(offline && offline.prototype, 'startRendering', 'audio', c => tones.has(c));
        })();
        """
    }

    /// What Niche's isolated world adds to keep the reports until they are read (`niche` is its
    /// `window.__niche`).
    public static func listener(event: String) -> String {
        """
        addEventListener('\(event)', e => {
          const q = niche.probes = niche.probes || [], heard = niche.heard = niche.heard || new Set(), d = String(e.detail);
          if (!heard.has(d) && heard.size < 60) { heard.add(d); q.push(d); }
        });
        dispatchEvent(new CustomEvent('\(event)q'));
        """
    }

    /// Reads and empties the reports, in the isolated world: a JSON array of strings.
    public static let drain = "JSON.stringify((window.__niche && window.__niche.probes || []).splice(0))"

    /// One report as the page script sends it: the probe and the host of the script that did it
    /// ("" when the stack named none: an inline script, which is the page's own).
    public static func parse(_ report: String) -> (probe: PrivacyProbe, host: String)? {
        let parts = report.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let probe = PrivacyProbe(rawValue: String(first)) else { return nil }
        let address = parts.count > 1 ? String(parts[1]) : ""
        return (probe, URLComponents(string: address)?.host?.lowercased() ?? "")
    }
}
