import JavaScriptCore
import NicheCore
import Testing

/// The script that hides what the filter lists say to hide, run in JavaScriptCore against a
/// small stand-in for a document.
struct ShieldsPageScriptTests {
    private static let fakePage = #"""
    var sent = [], timers = [], observers = [];
    function setTimeout(f) { timers.push(f); return timers.length; }
    function tick() { const t = timers; timers = []; t.forEach(f => f()); }
    class CSSStyleSheet {
      constructor() { this.cssRules = []; }
      insertRule(rule) { if (rule.indexOf('!!bad') >= 0) throw new Error('bad selector'); this.cssRules.push(rule); }
    }
    class MutationObserver { constructor(f) { this.f = f; observers.push(this); } observe() {} }
    function el(tag, id, classes, text) {
      const e = { nodeType: 1, tag, id: id || '', classList: classes || [], textContent: text || '', parentElement: null, children: [], removed: false,
                  attributes: [], style: { shown: true, cssText: '', setProperty(n, v) { if (n === 'display' && v === 'none') this.shown = false; } },
                  remove() { this.removed = true; },
                  querySelectorAll(sel) { return all(this).filter(x => x !== this && matches(x, sel)); },
                  closest(sel) { let p = this; while (p && !matches(p, sel)) p = p.parentElement; return p; } };
      return e;
    }
    function put(parent, child) { child.parentElement = parent; parent.children.push(child); return child; }
    function all(root) { return [root].concat(root.children.flatMap(all)); }
    function matches(e, sel) {
      return sel.split(',').some(s => { s = s.trim();
        if (s === '[id]') return !!e.id; if (s === '[class]') return e.classList.length > 0;
        if (s[0] === '#') return e.id === s.slice(1); if (s[0] === '.') return e.classList.indexOf(s.slice(1)) >= 0;
        return e.tag === s; });
    }
    var html = el('html'), body = put(html, el('body', 'top', ['page']));
    var card = put(body, el('div', '', ['card'])), promo = put(card, el('span', '', ['promo'], 'Big Sale today'));
    var plain = put(body, el('span', '', ['promo'], 'Nothing here'));
    var document = { documentElement: html, adoptedStyleSheets: [], querySelectorAll(sel) { return all(html).filter(x => matches(x, sel)); } };
    var location = { pathname: '/shop', search: '' };
    function getComputedStyle() { return { getPropertyValue() { return ''; } }; }
    """#

    private func page() throws -> JSContext {
        let js = try #require(JSContext())
        js.exceptionHandler = { _, e in Issue.record("script threw: \(e?.toString() ?? "?")") }
        js.evaluateScript(Self.fakePage)
        js.evaluateScript("var apply = " + ShieldsPageScript.content + "(s => sent.push(s));")
        return js
    }

    @Test func selectorsGoIntoOneAdoptedSheetAndABadOneCostsOnlyItself() throws {
        let js = try page()
        js.evaluateScript(#"apply(JSON.stringify({ hide: ['.ad', '#banner', '!!bad', '.slot'] }))"#)
        #expect(js.evaluateScript("document.adoptedStyleSheets.length")?.toInt32() == 1)
        let rules = js.evaluateScript("document.adoptedStyleSheets[0].cssRules")?.toArray() as? [String] ?? []
        #expect(rules == [".ad{display:none!important}", "#banner{display:none!important}", ".slot{display:none!important}"])
        // The same selectors again add nothing.
        js.evaluateScript(#"apply(JSON.stringify({ hide: ['.ad'] }))"#)
        #expect(js.evaluateScript("document.adoptedStyleSheets[0].cssRules.length")?.toInt32() == 3)
    }

    @Test func classAndIdNamesAreReportedOnceAndTheAnswerIsHidden() throws {
        let js = try page()
        js.evaluateScript(#"apply(JSON.stringify({ hide: [], exceptions: ['.keep'] })); tick();"#)
        let sent = js.evaluateScript("sent")?.toArray() as? [String] ?? []
        #expect(sent == [ShieldsPageScript.report + "page\ncard\npromo" + ShieldsPageScript.separator + "top" + ShieldsPageScript.separator + ".keep"])
        // A node the page adds later: only the names not seen yet.
        js.evaluateScript("var late = put(body, el('div', 'cookie-wall', ['card', 'consent'])); observers[0].f([{ type: 'childList', addedNodes: [late] }]); tick();")
        #expect((js.evaluateScript("sent[1]")?.toString() ?? "").hasPrefix(ShieldsPageScript.report + "consent" + ShieldsPageScript.separator + "cookie-wall"))
        js.evaluateScript(#"apply(JSON.stringify({ generic: ['#cookie-wall', '.keep'] }))"#)
        let rules = js.evaluateScript("document.adoptedStyleSheets[0].cssRules")?.toArray() as? [String] ?? []
        // The page's own exception is not hidden.
        #expect(rules == ["#cookie-wall{display:none!important}"])
    }

    @Test func aPageThatOptsOutOfGenericRulesReportsNothing() throws {
        let js = try page()
        js.evaluateScript(#"apply(JSON.stringify({ hide: ['.ad'], generichide: true })); tick();"#)
        #expect(js.evaluateScript("sent.length")?.toInt32() == 0)
    }

    @Test func proceduralRulesFindTheirElements() throws {
        let js = try page()
        let rules = [#"{"selector":[{"type":"css-selector","arg":".promo"},{"type":"has-text","arg":"Sale"},{"type":"upward","arg":"1"}]}"#,
                     #"{"selector":[{"type":"css-selector","arg":".promo"},{"type":"has-text","arg":"/nothing/i"}],"action":{"type":"remove"}}"#,
                     #"{"selector":[{"type":"css-selector","arg":".page"},{"type":"matches-path","arg":"/elsewhere"}],"action":{"type":"remove"}}"#]
        let json = try #require(String(data: JSONSerialization.data(withJSONObject: ["procedural": rules]), encoding: .utf8))
        js.setObject(json, forKeyedSubscript: "rules" as NSString)
        js.evaluateScript("apply(rules)")
        #expect(js.evaluateScript("card.style.shown")?.toBool() == false)   // the promo's parent
        #expect(js.evaluateScript("promo.style.shown")?.toBool() == true)
        #expect(js.evaluateScript("plain.removed")?.toBool() == true)
        #expect(js.evaluateScript("body.removed")?.toBool() == false)       // another path
    }

    @Test func somethingThatIsNotJSONIsIgnored() throws {
        let js = try page()
        js.evaluateScript("apply('not json')")
        #expect(js.evaluateScript("document.adoptedStyleSheets.length")?.toInt32() == 0)
    }
}
