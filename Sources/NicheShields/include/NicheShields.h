// Shields: the C interface of Sources/NicheShields (Rust). The browser process builds an engine
// from filter lists, installs it, and asks it about every request and page; page processes load
// the small part of it that must run before a page's own scripts. Strings are UTF-8; a string or
// blob a function returns is the caller's to free with the matching free function. Every
// function is safe to call from any thread.
#ifndef NICHE_SHIELDS_H_
#define NICHE_SHIELDS_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NicheShieldsBuilder NicheShieldsBuilder;
typedef struct NicheShieldsEngine NicheShieldsEngine;
typedef struct NicheShieldsPage NicheShieldsPage;

// --- Building (browser process) ---------------------------------------------------------------

NicheShieldsBuilder* niche_shields_builder_new(void);
// One filter list. `group` is the caller's number for what the list is for (ads, trackers, ...),
// handed back with every request the list blocks. `trusted` lists may use the scriptlets that
// set cookies and storage (the lists Niche ships; never a list the user added).
void niche_shields_builder_add_list(NicheShieldsBuilder* builder, const char* text, size_t length, uint8_t group, bool trusted);
// Resources as a JSON array of adblock-rust `Resource` objects. `for_pages` marks scriptlets,
// which page processes need too; the rest are the stand-ins served for blocked requests.
void niche_shields_builder_add_resources(NicheShieldsBuilder* builder, const char* json, size_t length, bool for_pages);
// Consumes the builder. Never null.
NicheShieldsEngine* niche_shields_builder_build(NicheShieldsBuilder* builder);
// For a builder that is not built after all.
void niche_shields_builder_free(NicheShieldsBuilder* builder);

// How many network and cosmetic rules the engine holds (what the lists parsed to).
uint32_t niche_shields_engine_rule_count(const NicheShieldsEngine* engine);
// What page processes load (niche_shields_page_load): the rules that inject scripts, and the
// scriptlets they name. Free with niche_shields_blob_free.
uint8_t* niche_shields_engine_page_blob(const NicheShieldsEngine* engine, size_t* length);
void niche_shields_blob_free(uint8_t* blob, size_t length);

// Makes `engine` the one requests are checked against and frees the one before it once no
// check is using it. Takes ownership; null uninstalls.
void niche_shields_install(NicheShieldsEngine* engine);
bool niche_shields_installed(void);

// --- Asking (browser process) -----------------------------------------------------------------

typedef struct {
    // Cancel the request.
    bool blocked;
    // A rule matched but an exception let it through.
    bool exception;
    // The `group` of the list whose rule blocked it; 255 when unknown.
    uint8_t group;
    // For a blocked request some pages can't do without: a `data:` address holding a harmless
    // stand-in to answer with instead. Null otherwise.
    char* redirect;
    // The address with tracking parameters removed, when a rule removed some. Null otherwise.
    char* rewritten;
} NicheShieldsVerdict;

// `type` is one of: document, sub_frame, script, stylesheet, image, font, media, xmlhttprequest,
// ping, websocket, other. `source` is the page (or frame) the request is made from. False, with
// `verdict` cleared, when no engine is installed.
bool niche_shields_check(const char* url, const char* source, const char* type, NicheShieldsVerdict* verdict);
void niche_shields_verdict_free(NicheShieldsVerdict* verdict);

// What to hide on a page, as JSON: {"hide": [selectors], "procedural": [filters as JSON text],
// "exceptions": [selectors], "generichide": bool}. Null when no engine is installed.
char* niche_shields_cosmetic(const char* url, bool generic);
// The generic selectors that apply to a page showing these classes and ids (newline-separated),
// less the page's `exceptions` (newline-separated): a JSON array.
char* niche_shields_generic(const char* classes, const char* ids, const char* exceptions);
void niche_shields_string_free(char* string);

// --- Page processes ---------------------------------------------------------------------------

// Null when the blob is not one niche_shields_engine_page_blob made.
NicheShieldsPage* niche_shields_page_load(const uint8_t* blob, size_t length);
// The script a document at `url` starts with (the lists' scriptlets for it); null when none.
char* niche_shields_page_script(const NicheShieldsPage* page, const char* url);
void niche_shields_page_free(NicheShieldsPage* page);

#ifdef __cplusplus
}
#endif

#endif  // NICHE_SHIELDS_H_
