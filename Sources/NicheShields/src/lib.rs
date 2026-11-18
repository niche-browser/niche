//! Shields: Niche's filter engine. A C interface (include/NicheShields.h) over adblock-rust:
//! build an engine from filter lists, install it, check requests, ask what to hide on a page,
//! and hand page processes the rules that inject scripts.

use adblock::lists::{FilterSet, ParseOptions, RuleTypes};
use adblock::request::Request;
use adblock::resources::{MimeType, PermissionMask, Resource, ResourceType};
use adblock::Engine;
use serde::Serialize;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, RwLock};

/// What trusted lists may do: uBlock Origin's "trusted" scriptlets (set a cookie, write to
/// storage), which answer cookie notices.
const TRUSTED: PermissionMask = PermissionMask::from_bits(1);
/// `NicheShieldsVerdict.group` when the engine can't say which list a rule came from.
pub const UNKNOWN_GROUP: u8 = 255;
/// The first bytes of a page blob.
const PAGE_MAGIC: &[u8; 8] = b"NSHPAGE2";
/// The most a page blob may unpack to.
const PAGE_LIMIT: usize = 64 << 20;

pub struct Builder {
    rules: FilterSet,
    /// The rules that inject scripts, on their own: what page processes load.
    page_rules: FilterSet,
    /// The group of each list, by the engine's source index.
    groups: Vec<u8>,
    resources: Vec<Resource>,
    page_resources: Vec<Resource>,
    /// Lines that are rules (not comments or headers), as the lists have them.
    rule_count: u32,
}

pub struct ShieldsEngine {
    engine: Engine,
    groups: Vec<u8>,
    rule_count: u32,
    page_blob: Vec<u8>,
    /// The generic hiding selectors that are not a plain class or id: what every page is told
    /// to hide whatever its site. Worked out on first use.
    generic_selectors: std::sync::OnceLock<std::collections::HashSet<String>>,
}

pub struct Page {
    engine: Engine,
}

#[derive(Default)]
pub struct Verdict {
    pub blocked: bool,
    pub exception: bool,
    pub group: u8,
    pub redirect: Option<String>,
    pub rewritten: Option<String>,
}

#[derive(Serialize)]
struct Cosmetic {
    hide: Vec<String>,
    procedural: Vec<String>,
    exceptions: Vec<String>,
    generichide: bool,
}

static INSTALLED: RwLock<Option<Arc<ShieldsEngine>>> = RwLock::new(None);

fn installed() -> Option<Arc<ShieldsEngine>> {
    INSTALLED.read().ok().and_then(|guard| guard.clone())
}

/// A line of a list that is a rule: not blank, a comment (`!`), or a header (`[Adblock Plus]`).
fn is_rule(line: &str) -> bool {
    let line = line.trim();
    !(line.is_empty() || line.starts_with('!') || line.starts_with('[') || (line.starts_with('#') && !line.starts_with("##") && !line.starts_with("#@#") && !line.starts_with("#?#")))
}

/// A line of a hosts file (`127.0.0.1 ads.example`, as Peter Lowe's list is published) as the
/// rule it stands for (`||ads.example^`), or the line as it is. uBlock Origin reads hosts files
/// this way; read as a filter rule such a line matches nothing. The machine's own names stay out.
fn hosts_line_as_rule(line: &str) -> Option<String> {
    let mut words = line.split('#').next()?.split_whitespace();
    let address = words.next()?;
    if !matches!(address, "127.0.0.1" | "0.0.0.0" | "::1" | "::") {
        return None;
    }
    let host = words.next()?;
    if words.next().is_some() || !host.contains('.') || matches!(host, "localhost.localdomain" | "0.0.0.0" | "127.0.0.1") {
        return Some(String::new());
    }
    if !host.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-' || b == b'_') {
        return Some(String::new());
    }
    Some(format!("||{host}^"))
}

/// A list with its hosts-file lines, if it has any, turned into rules.
fn with_hosts_as_rules(text: &str) -> std::borrow::Cow<'_, str> {
    if !text.lines().any(|line| hosts_line_as_rule(line).is_some()) {
        return std::borrow::Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    for line in text.lines() {
        match hosts_line_as_rule(line) {
            Some(rule) => out.push_str(&rule),
            None => out.push_str(line),
        }
        out.push('\n');
    }
    std::borrow::Cow::Owned(out)
}

/// A line that injects a script (`example.com##+js(...)`) or excepts one.
fn injects_script(line: &str) -> bool {
    line.contains("##+js(") || line.contains("#@#+js(")
}

impl Builder {
    pub fn new() -> Self {
        // Debug: the engine then says which list a matched rule came from.
        Builder { rules: FilterSet::new(true), page_rules: FilterSet::new(false), groups: Vec::new(), resources: Vec::new(), page_resources: Vec::new(), rule_count: 0 }
    }

    pub fn add_list(&mut self, text: &str, group: u8, trusted: bool) {
        let permissions = if trusted { TRUSTED } else { PermissionMask::default() };
        let text = with_hosts_as_rules(text);
        let text = text.as_ref();
        self.rule_count += text.lines().filter(|line| is_rule(line)).count() as u32;
        let scripts: String = text.lines().filter(|line| injects_script(line)).collect::<Vec<_>>().join("\n");
        if !scripts.is_empty() {
            self.page_rules.add_filter_list(scripts, ParseOptions { rule_types: RuleTypes::CosmeticOnly, permissions, ..Default::default() });
        }
        let record = self.rules.add_filter_list(text.to_owned(), ParseOptions { permissions, ..Default::default() });
        if self.groups.len() <= record.source_index {
            self.groups.resize(record.source_index + 1, UNKNOWN_GROUP);
        }
        self.groups[record.source_index] = group;
    }

    /// False when the JSON is not a list of resources.
    pub fn add_resources(&mut self, json: &str, for_pages: bool) -> bool {
        match serde_json::from_str::<Vec<Resource>>(json) {
            Ok(resources) => {
                if for_pages {
                    self.page_resources.extend(resources.iter().cloned());
                }
                self.resources.extend(resources);
                true
            }
            Err(_) => false,
        }
    }

    pub fn build(self) -> ShieldsEngine {
        let mut engine = Engine::new_with_filter_set(self.rules);
        let rule_count = self.rule_count;
        // uBlock Origin keeps a few scripts among its stand-in files (noeval.js, nofab.js) and
        // its lists inject them like any scriptlet: page processes get those too. A scriptlet
        // of the same name stays the scriptlet.
        let mut page_resources = self.page_resources;
        let named: std::collections::HashSet<String> =
            page_resources.iter().flat_map(|r| std::iter::once(r.name.clone()).chain(r.aliases.iter().cloned())).collect();
        for resource in &self.resources {
            let script = matches!(resource.kind, ResourceType::Mime(MimeType::ApplicationJavascript) | ResourceType::Template);
            if script && !named.contains(&resource.name) && !resource.aliases.iter().any(|alias| named.contains(alias)) {
                page_resources.push(resource.clone());
            }
        }
        engine.use_resources(self.resources);

        let page_engine = Engine::new_with_filter_set(self.page_rules);
        let rules = page_engine.serialize();
        let resources = serde_json::to_vec(&page_resources).unwrap_or_default();
        let mut plain = Vec::with_capacity(8 + rules.len() + resources.len());
        plain.extend_from_slice(&(rules.len() as u64).to_le_bytes());
        plain.extend_from_slice(&rules);
        plain.extend_from_slice(&resources);
        let mut page_blob = PAGE_MAGIC.to_vec();
        page_blob.extend_from_slice(&miniz_oxide::deflate::compress_to_vec(&plain, 8));
        ShieldsEngine { engine, groups: self.groups, rule_count, page_blob, generic_selectors: std::sync::OnceLock::new() }
    }
}

impl Default for Builder {
    fn default() -> Self {
        Self::new()
    }
}

impl ShieldsEngine {
    pub fn check(&self, url: &str, source: &str, kind: &str) -> Verdict {
        let Ok(request) = Request::new(url, source, kind, "GET") else { return Verdict { group: UNKNOWN_GROUP, ..Default::default() } };
        let result = self.engine.check_network_request(&request);
        let blocked = result.should_block();
        let group = result
            .filter
            .as_ref()
            .and_then(|rule| rule.source_location.as_ref())
            .and_then(|at| self.groups.get(at.source_index as usize).copied())
            .unwrap_or(UNKNOWN_GROUP);
        Verdict {
            blocked,
            exception: result.exception.is_some() && !blocked,
            group,
            redirect: if blocked { result.redirect } else { None },
            rewritten: result.rewritten_url,
        }
    }

    /// What a page at `url` is told to hide. `generic` false leaves the generic rules out, the
    /// ones that name no site (uBlock Origin Lite's "optimal" mode): only what the lists say
    /// about this page's own site is hidden, and the page is told not to ask for the rest.
    pub fn cosmetic(&self, url: &str, generic: bool) -> String {
        let found = self.engine.url_cosmetic_resources(url);
        let mut out = Cosmetic {
            hide: found.hide_selectors.into_iter().collect(),
            procedural: found.procedural_actions.into_iter().collect(),
            exceptions: found.exceptions.into_iter().collect(),
            generichide: found.generichide,
        };
        if !generic {
            // A page of a site no list names is told exactly the generic ones.
            let everywhere = self.generic_selectors.get_or_init(|| {
                self.engine.url_cosmetic_resources("https://no-site-of-its-own.invalid/").hide_selectors.into_iter().collect()
            });
            if !found.generichide {
                out.hide.retain(|selector| !everywhere.contains(selector));
            }
            out.generichide = true;
        }
        out.hide.sort();
        out.procedural.sort();
        out.exceptions.sort();
        serde_json::to_string(&out).unwrap_or_else(|_| "{}".into())
    }

    pub fn generic(&self, classes: &str, ids: &str, exceptions: &str) -> String {
        let names = |text: &str| text.lines().filter(|l| !l.is_empty()).map(str::to_owned).collect::<Vec<_>>();
        let except = exceptions.lines().filter(|l| !l.is_empty()).map(str::to_owned).collect();
        let mut selectors = self.engine.hidden_class_id_selectors(names(classes), names(ids), &except);
        selectors.sort();
        serde_json::to_string(&selectors).unwrap_or_else(|_| "[]".into())
    }

    pub fn rule_count(&self) -> u32 {
        self.rule_count
    }

    pub fn page_blob(&self) -> &[u8] {
        &self.page_blob
    }
}

impl Page {
    pub fn load(blob: &[u8]) -> Option<Page> {
        if blob.len() < 8 || &blob[..8] != PAGE_MAGIC {
            return None;
        }
        let plain = miniz_oxide::inflate::decompress_to_vec_with_limit(&blob[8..], PAGE_LIMIT).ok()?;
        let length = u64::from_le_bytes(plain.get(..8)?.try_into().ok()?) as usize;
        let rules = plain.get(8..8usize.checked_add(length)?)?;
        let resources: Vec<Resource> = serde_json::from_slice(&plain[8 + length..]).ok()?;
        let mut engine = Engine::default();
        engine.deserialize(rules).ok()?;
        engine.use_resources(resources);
        Some(Page { engine })
    }

    pub fn script(&self, url: &str) -> Option<String> {
        let script = self.engine.url_cosmetic_resources(url).injected_script;
        if script.is_empty() {
            return None;
        }
        // In a function of its own, so the scriptlets' helpers are not the page's globals, with
        // the `scriptletGlobals` uBlock Origin's scriptlets expect to find (its logging and
        // resource secrets, which Niche has none of): without it their shared helper throws on
        // first use and the scriptlet silently does nothing (17 Nov 2026, womex.com's notice).
        Some(format!("(function() {{\nconst scriptletGlobals = {{}};\n{script}\n}})();"))
    }
}

// MARK: The C interface

unsafe fn text<'a>(pointer: *const c_char) -> &'a str {
    if pointer.is_null() {
        return "";
    }
    CStr::from_ptr(pointer).to_str().unwrap_or("")
}

unsafe fn slice<'a>(pointer: *const c_char, length: usize) -> &'a str {
    if pointer.is_null() {
        return "";
    }
    std::str::from_utf8(std::slice::from_raw_parts(pointer as *const u8, length)).unwrap_or("")
}

fn c_string(value: String) -> *mut c_char {
    CString::new(value).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Runs `work`; a panic in the engine becomes `fallback` instead of taking the browser down.
fn guarded<T>(fallback: T, work: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(work)).unwrap_or(fallback)
}

#[no_mangle]
pub extern "C" fn niche_shields_builder_new() -> *mut Builder {
    Box::into_raw(Box::new(Builder::new()))
}

/// # Safety
/// `builder` is from `niche_shields_builder_new`; `text` points at `length` bytes.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_builder_add_list(builder: *mut Builder, text: *const c_char, length: usize, group: u8, trusted: bool) {
    if builder.is_null() {
        return;
    }
    let (builder, list) = (&mut *builder, slice(text, length));
    guarded((), || builder.add_list(list, group, trusted));
}

/// # Safety
/// As `niche_shields_builder_add_list`.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_builder_add_resources(builder: *mut Builder, json: *const c_char, length: usize, for_pages: bool) {
    if builder.is_null() {
        return;
    }
    let (builder, json) = (&mut *builder, slice(json, length));
    guarded((), || {
        builder.add_resources(json, for_pages);
    });
}

/// # Safety
/// `builder` is from `niche_shields_builder_new` and is not used again.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_builder_build(builder: *mut Builder) -> *mut ShieldsEngine {
    let builder = if builder.is_null() { Builder::new() } else { *Box::from_raw(builder) };
    let engine = guarded(None, || Some(builder.build())).unwrap_or_else(|| Builder::new().build());
    Box::into_raw(Box::new(engine))
}

/// # Safety
/// `builder` is from `niche_shields_builder_new`, was not built, and is not used again.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_builder_free(builder: *mut Builder) {
    if !builder.is_null() {
        drop(Box::from_raw(builder));
    }
}

/// # Safety
/// `engine` is from `niche_shields_builder_build` and not yet installed.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_engine_rule_count(engine: *const ShieldsEngine) -> u32 {
    if engine.is_null() {
        0
    } else {
        (*engine).rule_count()
    }
}

/// # Safety
/// As `niche_shields_engine_rule_count`; `length` is writable.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_engine_page_blob(engine: *const ShieldsEngine, length: *mut usize) -> *mut u8 {
    if engine.is_null() || length.is_null() {
        return std::ptr::null_mut();
    }
    let blob = (*engine).page_blob().to_vec().into_boxed_slice();
    *length = blob.len();
    Box::into_raw(blob) as *mut u8
}

/// # Safety
/// `blob` and `length` are what `niche_shields_engine_page_blob` gave.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_blob_free(blob: *mut u8, length: usize) {
    if !blob.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(blob, length)));
    }
}

/// # Safety
/// `engine` is from `niche_shields_builder_build` (or null) and is not used again.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_install(engine: *mut ShieldsEngine) {
    let next = if engine.is_null() { None } else { Some(Arc::new(*Box::from_raw(engine))) };
    if let Ok(mut guard) = INSTALLED.write() {
        *guard = next;
    }
}

#[no_mangle]
pub extern "C" fn niche_shields_installed() -> bool {
    installed().is_some()
}

#[repr(C)]
pub struct CVerdict {
    blocked: bool,
    exception: bool,
    group: u8,
    redirect: *mut c_char,
    rewritten: *mut c_char,
}

/// # Safety
/// The strings are null-terminated; `verdict` is writable.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_check(url: *const c_char, source: *const c_char, kind: *const c_char, verdict: *mut CVerdict) -> bool {
    if verdict.is_null() {
        return false;
    }
    *verdict = CVerdict { blocked: false, exception: false, group: UNKNOWN_GROUP, redirect: std::ptr::null_mut(), rewritten: std::ptr::null_mut() };
    let Some(engine) = installed() else { return false };
    let (url, source, kind) = (text(url), text(source), text(kind));
    let Some(found) = guarded(None, || Some(engine.check(url, source, kind))) else { return false };
    (*verdict).blocked = found.blocked;
    (*verdict).exception = found.exception;
    (*verdict).group = found.group;
    (*verdict).redirect = found.redirect.map(c_string).unwrap_or(std::ptr::null_mut());
    (*verdict).rewritten = found.rewritten.map(c_string).unwrap_or(std::ptr::null_mut());
    true
}

/// # Safety
/// `verdict` was filled by `niche_shields_check`.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_verdict_free(verdict: *mut CVerdict) {
    if verdict.is_null() {
        return;
    }
    niche_shields_string_free((*verdict).redirect);
    niche_shields_string_free((*verdict).rewritten);
    (*verdict).redirect = std::ptr::null_mut();
    (*verdict).rewritten = std::ptr::null_mut();
}

/// # Safety
/// `url` is null-terminated.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_cosmetic(url: *const c_char, generic: bool) -> *mut c_char {
    let Some(engine) = installed() else { return std::ptr::null_mut() };
    let url = text(url);
    guarded(None, || Some(engine.cosmetic(url, generic))).map(c_string).unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// The strings are null-terminated.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_generic(classes: *const c_char, ids: *const c_char, exceptions: *const c_char) -> *mut c_char {
    let Some(engine) = installed() else { return std::ptr::null_mut() };
    let (classes, ids, exceptions) = (text(classes), text(ids), text(exceptions));
    guarded(None, || Some(engine.generic(classes, ids, exceptions))).map(c_string).unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `string` is from this library, or null.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(CString::from_raw(string));
    }
}

/// # Safety
/// `blob` points at `length` bytes.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_page_load(blob: *const u8, length: usize) -> *mut Page {
    if blob.is_null() {
        return std::ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(blob, length);
    guarded(None, || Page::load(bytes)).map(|page| Box::into_raw(Box::new(page))).unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `page` is from `niche_shields_page_load`; `url` is null-terminated.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_page_script(page: *const Page, url: *const c_char) -> *mut c_char {
    if page.is_null() {
        return std::ptr::null_mut();
    }
    let (page, url) = (&*page, text(url));
    guarded(None, || page.script(url)).map(c_string).unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// `page` is from `niche_shields_page_load` and is not used again.
#[no_mangle]
pub unsafe extern "C" fn niche_shields_page_free(page: *mut Page) {
    if !page.is_null() {
        drop(Box::from_raw(page));
    }
}

// The engine is shared between Chromium's IO thread and the thread that swaps it.
const _: fn() = || {
    fn shared<T: Send + Sync>() {}
    shared::<ShieldsEngine>();
};
