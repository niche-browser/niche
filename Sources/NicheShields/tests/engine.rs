//! What Niche relies on the engine for, on small lists of its own: nothing here needs the network.
use niche_shields::{Builder, Page, UNKNOWN_GROUP};

const ADS: u8 = 0;
const TRACKERS: u8 = 1;
const COOKIES: u8 = 3;

fn engine() -> niche_shields::ShieldsEngine {
    let mut b = Builder::new();
    b.add_list("||ads.example^\n||cdn.example/banner.js$script,redirect=noop.js\n@@||ads.example/allowed.js\n/advert/*$image", ADS, false);
    b.add_list("||tracker.example^$third-party\n$removeparam=fbclid\n||pixel.example^$important", TRACKERS, false);
    b.add_list("##.cookie-banner\nnews.example###consent-wall\nnews.example#@#.cookie-banner\nshop.example##+js(trusted-set-cookie, consent, essential)\nshop.example##.promo:has-text(Sale)", COOKIES, true);
    b.add_list("untrusted.example##+js(trusted-set-cookie, consent, all)", ADS, false);
    assert!(b.add_resources(r#"[{"name":"noop.js","aliases":[],"kind":{"mime":"application/javascript"},"content":"KGZ1bmN0aW9uKCl7fSkoKTs="}]"#, false));
    assert!(b.add_resources(
        r#"[{"name":"trusted-set-cookie.js","aliases":[],"kind":{"mime":"application/javascript"},"content":"ZnVuY3Rpb24gdHJ1c3RlZFNldENvb2tpZShuYW1lLCB2YWx1ZSkgeyBkb2N1bWVudC5jb29raWUgPSBuYW1lICsgJz0nICsgdmFsdWU7IH0=","permission":1}]"#,
        true
    ));
    assert!(!b.add_resources("not json", false));
    b.build()
}

#[test]
fn a_listed_host_is_blocked_and_says_which_group() {
    let e = engine();
    let v = e.check("https://ads.example/a.js", "https://news.example/", "script");
    assert!(v.blocked && !v.exception);
    assert_eq!(v.group, ADS);
    let v = e.check("https://tracker.example/t.gif", "https://news.example/", "image");
    assert!(v.blocked);
    assert_eq!(v.group, TRACKERS);
}

#[test]
fn an_exception_lets_a_request_through() {
    let v = engine().check("https://ads.example/allowed.js", "https://news.example/", "script");
    assert!(!v.blocked && v.exception);
}

#[test]
fn third_party_rules_spare_the_site_itself() {
    let e = engine();
    assert!(!e.check("https://tracker.example/t.gif", "https://www.tracker.example/", "image").blocked);
    // A rule without that option also holds on the site's own pages.
    assert!(e.check("https://news.example/advert/top.png", "https://news.example/", "image").blocked);
}

#[test]
fn an_important_rule_beats_exceptions() {
    assert!(engine().check("https://pixel.example/p", "https://news.example/", "image").blocked);
}

#[test]
fn a_blocked_script_a_page_needs_gets_a_stand_in() {
    let v = engine().check("https://cdn.example/banner.js", "https://news.example/", "script");
    assert!(v.blocked);
    assert!(v.redirect.as_deref().unwrap_or("").starts_with("data:application/javascript;base64,"));
}

#[test]
fn tracking_parameters_are_removed_from_an_address() {
    let v = engine().check("https://shop.example/item?id=5&fbclid=abc", "https://shop.example/", "document");
    assert!(!v.blocked);
    assert_eq!(v.rewritten.as_deref(), Some("https://shop.example/item?id=5"));
    assert!(engine().check("https://shop.example/item?id=5", "https://shop.example/", "document").rewritten.is_none());
}

#[test]
fn an_address_that_is_none_is_let_through() {
    let v = engine().check("not an address", "", "script");
    assert!(!v.blocked);
    assert_eq!(v.group, UNKNOWN_GROUP);
}

#[test]
fn a_page_is_told_what_to_hide() {
    let e = engine();
    let news: serde_json::Value = serde_json::from_str(&e.cosmetic("https://news.example/")).unwrap();
    assert_eq!(news["hide"], serde_json::json!(["#consent-wall"]));
    assert_eq!(news["exceptions"], serde_json::json!([".cookie-banner"]));
    let shop: serde_json::Value = serde_json::from_str(&e.cosmetic("https://shop.example/")).unwrap();
    assert_eq!(shop["procedural"].as_array().unwrap().len(), 1);
    assert!(shop["procedural"][0].as_str().unwrap().contains("has-text"));
}

#[test]
fn generic_rules_apply_to_the_classes_a_page_shows() {
    let e = engine();
    assert_eq!(e.generic("cookie-banner\nheader", "main", ""), r#"[".cookie-banner"]"#);
    assert_eq!(e.generic("header", "main", ""), "[]");
    // The page's own exception.
    assert_eq!(e.generic("cookie-banner", "", ".cookie-banner"), "[]");
}

#[test]
fn page_processes_get_the_scripts_and_nothing_else() {
    let e = engine();
    let page = Page::load(e.page_blob()).expect("a page blob loads");
    let script = page.script("https://shop.example/cart").expect("the shop has a scriptlet");
    assert!(script.contains("trustedSetCookie") && script.contains("essential"));
    // Wrapped: nothing of it becomes a global of the page, and uBlock's scriptlets find the
    // object they expect.
    assert!(script.starts_with("(function() {\nconst scriptletGlobals = {};") && script.ends_with("})();"));
    assert!(page.script("https://news.example/").is_none());
    // A list that is not trusted can't use a trusted scriptlet.
    assert!(page.script("https://untrusted.example/").is_none());
    assert!(Page::load(b"something else").is_none());
    assert!(Page::load(&e.page_blob()[..12]).is_none());
}

#[test]
fn an_engine_counts_its_rules() {
    assert!(engine().rule_count() > 0);
    assert_eq!(Builder::new().build().rule_count(), 0);
}
