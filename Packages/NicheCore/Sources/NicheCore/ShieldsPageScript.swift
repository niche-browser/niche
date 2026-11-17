import Foundation

/// What Shields runs in a page to hide what the filter lists say to hide: leftover ad slots,
/// cookie notices, newsletter pop-ups. The engine (Sources/NicheShields) knows the rules; this
/// applies them. NicheCEF runs it in the page's top document through NicheHelper (never the
/// page's console, no globals), hands it the page's rules as JSON, and answers its reports.
///
/// - Selectors to hide go into one constructed stylesheet the document adopts, forty to a rule;
///   a rule the page's CSS engine refuses is retried one selector at a time, so one bad selector
///   costs only itself.
/// - Generic rules (`##.cookie-banner`, tens of thousands of them) apply only to pages that show
///   the class or id: the script reports each class and id name once, as they appear
///   ("sh:" + classes + U+001F + ids + U+001F + the page's exceptions, names newline-separated),
///   and gets back the selectors that match.
/// - Procedural rules (`:has-text()`, `:upward()`, `:matches-css()`, `:remove()` …) are worked
///   out here, again whenever the page changes.
public enum ShieldsPageScript {
    /// The prefix of the script's reports among NicheCEF's page messages.
    public static let report = "sh:"
    /// Between the three parts of a report.
    public static let separator = "\u{1f}"

    /// A function expression taking `send(string)` and returning `apply(json)`, where the JSON
    /// is the engine's cosmetic answer (`hide`, `procedural`, `exceptions`, `generichide`) or
    /// `{"generic": [selectors]}`.
    public static let content = #"""
    (function (send) {
      const doc = document;
      const css = '{display:none!important}';
      const hidden = new Set(), seen = new Set(), exceptions = new Set();
      let sheet = null, procedural = [], generic = true, timer = 0, started = false;
      let classes = [], ids = [];

      const adopt = () => {
        if (!sheet) sheet = new CSSStyleSheet();
        if (!doc.adoptedStyleSheets.includes(sheet)) doc.adoptedStyleSheets = [...doc.adoptedStyleSheets, sheet];
      };
      const add = rule => { try { sheet.insertRule(rule, sheet.cssRules.length); return true; } catch (e) { return false; } };
      const hide = selectors => {
        const fresh = selectors.filter(s => s && !hidden.has(s) && !exceptions.has(s));
        if (!fresh.length) return;
        adopt();
        for (const s of fresh) hidden.add(s);
        for (let i = 0; i < fresh.length; i += 40) {
          const part = fresh.slice(i, i + 40);
          if (!add(part.join(',') + css)) for (const s of part) add(s + css);
        }
      };

      // Class and id names, each reported once.
      const take = el => {
        const id = el.id;
        if (typeof id === 'string' && id && !seen.has('#' + id)) { seen.add('#' + id); ids.push(id); }
        const list = el.classList;
        if (list) for (let i = 0; i < list.length; i++) {
          const c = list[i];
          if (!seen.has('.' + c)) { seen.add('.' + c); classes.push(c); }
        }
      };
      const note = root => {
        if (!generic || seen.size > 30000 || !root) return;
        if (root.nodeType === 1) take(root);
        if (root.querySelectorAll) for (const el of root.querySelectorAll('[id],[class]')) take(el);
      };

      // Procedural rules.
      const pattern = (arg, exact) => {
        const m = /^\/(.+)\/([a-z]*)$/.exec(arg);
        if (m) { try { const r = new RegExp(m[1], m[2]); return s => r.test(s); } catch (e) {} }
        return exact ? s => s === arg : s => s.includes(arg);
      };
      const unique = nodes => [...new Set(nodes.filter(Boolean))];
      const style = pseudo => (nodes, arg) => {
        const at = arg.indexOf(':');
        if (at < 0) return [];
        const name = arg.slice(0, at).trim(), value = pattern(arg.slice(at + 1).trim(), true);
        return nodes.filter(n => value(getComputedStyle(n, pseudo).getPropertyValue(name).trim()));
      };
      const steps = {
        'css-selector': (nodes, arg, first) => first ? [...doc.querySelectorAll(arg)] : unique(nodes.flatMap(n => [...n.querySelectorAll(arg)])),
        'has-text': (nodes, arg) => { const t = pattern(arg, false); return nodes.filter(n => t(n.textContent || '')); },
        'min-text-length': (nodes, arg) => nodes.filter(n => (n.textContent || '').length >= Number(arg)),
        'matches-path': (nodes, arg) => pattern(arg, false)(location.pathname + location.search) ? nodes : [],
        'matches-attr': (nodes, arg) => {
          const m = /^"?([^="]+)"?(?:="?(.*?)"?)?$/.exec(arg);
          if (!m) return [];
          const name = pattern(m[1], true), value = m[2] === undefined ? null : pattern(m[2], true);
          return nodes.filter(n => [...n.attributes].some(a => name(a.name) && (!value || value(a.value))));
        },
        'matches-css': style(null),
        'matches-css-before': style('::before'),
        'matches-css-after': style('::after'),
        'upward': (nodes, arg) => {
          const n = Number(arg);
          return unique(nodes.map(node => {
            if (n > 0) { let p = node; for (let i = 0; i < n && p; i++) p = p.parentElement; return p; }
            return node.parentElement && node.parentElement.closest(arg);
          }));
        },
        'xpath': (nodes, arg) => unique(nodes.flatMap(n => {
          const out = [];
          try {
            const found = doc.evaluate(arg, n, null, 7, null);
            for (let i = 0; i < found.snapshotLength; i++) { const x = found.snapshotItem(i); if (x.nodeType === 1) out.push(x); }
          } catch (e) {}
          return out;
        })),
      };
      const act = (node, action) => {
        if (!action) return node.style.setProperty('display', 'none', 'important');
        if (action.type === 'remove') return node.remove();
        if (action.type === 'style') { node.style.cssText += ';' + action.arg; return; }
        if (action.type === 'remove-attr') {
          const name = pattern(action.arg, true);
          for (const a of [...node.attributes]) if (name(a.name)) node.removeAttribute(a.name);
          return;
        }
        if (action.type === 'remove-class') {
          const name = pattern(action.arg, true);
          for (const c of [...node.classList]) if (name(c)) node.classList.remove(c);
        }
      };
      const run = () => {
        for (const rule of procedural) {
          try {
            let nodes = [];
            rule.selector.forEach((step, i) => { const f = steps[step.type]; nodes = f ? f(nodes, step.arg, i === 0) : []; });
            for (const node of nodes) act(node, rule.action);
          } catch (e) {}
        }
      };

      const flush = () => {
        timer = 0;
        if (classes.length || ids.length) {
          send('sh:' + classes.join('\n') + '\x1f' + ids.join('\n') + '\x1f' + [...exceptions].join('\n'));
          classes = []; ids = [];
        }
        if (procedural.length) run();
      };
      const schedule = () => { if (!timer) timer = setTimeout(flush, 120); };
      const start = () => {
        note(doc.documentElement);
        schedule();
        new MutationObserver(records => {
          for (const r of records) {
            if (r.type === 'attributes') note(r.target);
            else for (const n of r.addedNodes) note(n);
          }
          schedule();
        }).observe(doc, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id'] });
      };

      return data => {
        let d;
        try { d = JSON.parse(data); } catch (e) { return; }
        if (d.exceptions) for (const x of d.exceptions) exceptions.add(x);
        if (d.generichide) generic = false;
        if (d.hide) hide(d.hide);
        if (d.generic) hide(d.generic);
        if (d.procedural) {
          for (const text of d.procedural) { try { const rule = JSON.parse(text); if (rule && rule.selector) procedural.push(rule); } catch (e) {} }
          if (procedural.length) run();
        }
        if (!started) { started = true; start(); }
      };
    })
    """#
}
