import JavaScriptCore
import NicheCore
import Testing

/// The Chrome Web Store said "Add to Chrome" and asked to "Switch to Chrome" in Niche: Google's page
/// says that to every browser, and a browser that wants its own name there rewrites the page.
struct WebStoreBrandingTests {
    private func relabel(_ text: String) -> String? {
        let js = JSContext()!
        let result = js.evaluateScript("(\(WebStoreBranding.relabel))(\(String(reflecting: text)), 'Niche')")
        return result.flatMap { $0.isNull ? nil : $0.toString() }
    }

    @Test func theInstallButtonsSayNiche() {
        #expect(relabel("Add to Chrome") == "Add to Niche")
        #expect(relabel("  Remove from Chrome ") == "Remove from Niche")
    }

    @Test func everythingElseKeepsItsWords() {
        // The store's own name, other buttons, and a label already rewritten.
        #expect(relabel("Chrome Web Store") == nil)
        #expect(relabel("Install Chrome") == nil)
        #expect(relabel("Add to Niche") == nil)
        #expect(relabel("Add to Chromebook") == nil)
    }

    @Test func itDoesNothingOutsideTheStore() throws {
        // Every page runs it; elsewhere it returns before touching the document (there is none here).
        let js = try #require(JSContext())
        var failure: String?
        js.exceptionHandler = { _, e in failure = e?.toString() }
        js.evaluateScript("var window = this; var location = { hostname: 'example.com' };")
        js.evaluateScript(WebStoreBranding.script(appName: "Niche"))
        #expect(failure == nil)
    }

    /// A small DOM in JavaScriptCore with what the script touches: elements, `document.open()`
    /// (a new <html>, the document's event listeners gone), and MutationObservers that hear a
    /// change only below the node they observe while that node is still in the document.
    private static let fakeDocument = #"""
    var window = this; window.top = window;
    var location = { hostname: 'chromewebstore.google.com' };
    var frames = [], listeners = [], observers = [];
    function requestAnimationFrame(f) { frames.push(f); }
    function addEventListener(type, f) { listeners.push({ type, f }); }
    function flush() { while (frames.length) frames.shift()(); }
    function fire(type) { listeners.filter(l => l.type === type).forEach(l => l.f()); }
    class El {
      constructor(tag, text) { this.tagName = tag; this.kids = []; this.parentElement = null; this.attrs = {}; this.own = text || '';
        this.style = { setProperty: (k, v) => { this.style[k] = v; } }; }
      get textContent() { return this.own + this.kids.map(k => k.textContent).join(''); }
      set textContent(v) { this.own = v; this.kids = []; changed(this); }
      get childElementCount() { return this.kids.length; }
      get isConnected() { let e = this; while (e.parentElement) e = e.parentElement; return e === document.documentElement; }
      appendChild(c) { c.parentElement = this; this.kids.push(c); changed(this); return c; }
      getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
      setAttribute(k, v) { this.attrs[k] = v; }
      querySelectorAll(sel) { const out = []; const walk = n => n.kids.forEach(k => { if (k.tagName === sel.toUpperCase()) out.push(k); walk(k); }); walk(this); return out; }
    }
    function changed(node) {
      for (const o of observers) {
        let e = node; while (e && e !== o.target) e = e.parentElement;
        const inside = o.target === document || (e === o.target && o.target.isConnected);
        if (inside) o.f([]);
      }
    }
    class MutationObserver { constructor(f) { this.f = f; } observe(target) { observers.push({ target, f: this.f }); } }
    var document = {
      readyState: 'loading', documentElement: new El('html'),
      get head() { return this.documentElement.kids.find(k => k.tagName === 'HEAD') || null; },
      get body() { return this.documentElement.kids.find(k => k.tagName === 'BODY') || null; },
      createElement: tag => new El(tag.toUpperCase()),
      querySelectorAll(sel) { return this.documentElement.querySelectorAll(sel); },
      open() { listeners = []; this.documentElement = new El('html'); changed(this); },
    };
    function page() {
      document.documentElement.appendChild(new El('HEAD'));
      const body = document.documentElement.appendChild(new El('BODY'));
      const button = body.appendChild(new El('BUTTON'));
      button.appendChild(new El('SPAN', 'Add to Chrome'));
      return button;
    }
    """#

    @Test func theStoreStaysRewrittenWhenItReplacesItsDocument() throws {
        // A store tab a page opened (the Extensions page's "Chrome Web Store" link) ran the script
        // while the document was still empty; the store then wrote a new document, which dropped
        // the script's DOMContentLoaded listener, its style and the body it would have watched.
        // The tab said "Add to Chrome" and showed "Switch to Chrome?" until Niche restarted.
        let js = try #require(JSContext())
        var failure: String?
        js.exceptionHandler = { _, e in failure = e?.toString() }
        js.evaluateScript(Self.fakeDocument)
        js.evaluateScript(WebStoreBranding.script(appName: "Niche"))
        js.evaluateScript("document.open(); var button = page(); document.readyState = 'complete'; fire('DOMContentLoaded'); flush();")
        #expect(failure == nil)
        #expect(js.evaluateScript("button.textContent").toString() == "Add to Niche")
        // The rule hiding the "Switch to Chrome?" card is in the document that shows.
        #expect(js.evaluateScript("document.querySelectorAll('style').some(s => s.textContent.includes('promo-header'))").toBool())
        // The store redraws the button later (another item): still Niche's name.
        js.evaluateScript("button.kids[0].textContent = 'Add to Chrome'; flush();")
        #expect(js.evaluateScript("button.textContent").toString() == "Add to Niche")
    }

    @Test func theSwitchToChromeCalloutInGooglesBarIsHidden() throws {
        // 13 Nov 2026: Google moved "Switch to Chrome?" out of the page into its header bar, as a
        // frame named "callout" from another origin (no #promo-header to find, no text to read)
        // in a box laid over the install button. The box goes, when the bar adds it later too.
        let js = try #require(JSContext())
        var failure: String?
        js.exceptionHandler = { _, e in failure = e?.toString() }
        js.evaluateScript(Self.fakeDocument)
        js.evaluateScript("page();")
        js.evaluateScript(WebStoreBranding.script(appName: "Niche"))
        js.evaluateScript("""
            var bar = document.body.appendChild(new El('HEADER'));
            var box = bar.appendChild(new El('DIV'));
            var callout = box.appendChild(new El('IFRAME')); callout.setAttribute('name', 'callout');
            var other = document.body.appendChild(new El('DIV'));
            var proxy = other.appendChild(new El('IFRAME')); proxy.setAttribute('name', 'apiproxy');
            changed(document.body); flush();
            """)
        #expect(failure == nil)
        #expect(js.evaluateScript("box.style.display").toString() == "none")
        // Only that frame's box: the bar and the store's other frames stay.
        #expect(js.evaluateScript("bar.style.display === undefined && other.style.display === undefined").toBool())
        // And the rule is in the page's style, so the box never shows for a frame.
        #expect(js.evaluateScript(#"document.querySelectorAll('style').some(s => s.textContent.includes('iframe[name="callout"]'))"#).toBool())
    }

    @Test func theNameIsQuotedForTheScript() {
        #expect(WebStoreBranding.script(appName: "Ni\"che").contains(#""Ni\"che""#))
    }
}
