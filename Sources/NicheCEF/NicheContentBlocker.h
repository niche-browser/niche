// The user's own say over what a page may load, and the host and site arithmetic the blocker
// and the privacy panel share. What is an ad or a tracker is the filter engine's business
// (Shields, Sources/NicheShields); this is what comes before it: whether a request is to
// another site than the page's, and whether the user allowed it, blocked it, or switched
// protection off for the page's site. Plain C++ with no CEF or Cocoa dependency so it can be
// tested on its own. Lookups run on CEF's IO thread for every request, so the rules are an
// immutable value published through an atomic pointer and never locked.
#pragma once

#include <atomic>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

namespace niche_blocker {

using DomainSet = std::unordered_set<std::string>;

inline char Lower(char c) { return (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c; }

// Lowercased, without a trailing dot. Empty for anything that isn't a domain name.
inline std::string NormalizeHost(std::string_view h) {
    while (!h.empty() && h.back() == '.') h.remove_suffix(1);
    std::string r;
    r.reserve(h.size());
    for (char c : h) {
        char l = Lower(c);
        if (!((l >= 'a' && l <= 'z') || (l >= '0' && l <= '9') || l == '-' || l == '.' || l == '_')) return {};
        r.push_back(l);
    }
    return r;
}

// The listed domain covering `host` (host itself or a parent), or empty. A bare
// top-level label is never matched.
inline std::string MatchedEntry(const DomainSet& set, const std::string& host) {
    size_t pos = 0;
    while (true) {
        size_t dot = host.find('.', pos);
        if (dot == std::string::npos) return {};  // only the TLD is left
        std::string suffix = host.substr(pos);
        if (set.count(suffix)) return suffix;
        pos = dot + 1;
    }
}

inline bool IsSubdomainOrSame(std::string_view host, std::string_view domain) {
    if (host.size() == domain.size()) return host == domain;
    return host.size() > domain.size() && host.substr(host.size() - domain.size()) == domain &&
           host[host.size() - domain.size() - 1] == '.';
}

// Approximate registrable domain (eTLD+1) without the Public Suffix List: the
// last two labels, or three under the common "co.uk"-style second levels and
// under the hosts that give every customer a name ("someone.github.io"). A
// miss only ever makes two hosts look like one site, which fails open.
inline std::string_view Site(std::string_view host) {
    size_t last = host.rfind('.');
    if (last == std::string_view::npos || last == 0) return host;
    size_t second = host.rfind('.', last - 1);
    if (second == std::string_view::npos) return host;
    std::string_view tld = host.substr(last + 1);
    std::string_view sld = host.substr(second + 1, last - second - 1);
    static const std::string_view kSecondLevels[] = {"co", "com", "net", "org", "gov", "edu", "ac",
                                                     "ne", "or", "go", "gob", "mil", "nic", "ltd", "plc"};
    bool cc = tld.size() == 2;
    bool sl = false;
    for (auto s : kSecondLevels) sl = sl || s == sld;
    // Hosts that give each customer a name of their own: one name there is one site.
    static const std::string_view kHosted[] = {
        "github.io", "gitlab.io", "pages.dev", "workers.dev", "vercel.app", "netlify.app", "web.app", "firebaseapp.com",
        "herokuapp.com", "azurewebsites.net", "cloudfront.net", "amazonaws.com", "appspot.com", "blogspot.com",
        "wordpress.com", "myshopify.com", "glitch.me", "onrender.com", "fly.dev", "surge.sh", "neocities.org",
        "wixsite.com", "webflow.io", "framer.app", "notion.site", "substack.com", "tumblr.com", "typepad.com"};
    std::string_view two = host.substr(second + 1);
    bool hosted = false;
    for (auto h : kHosted) hosted = hosted || h == two;
    if (((cc && sl) || hosted) && second > 0) {
        size_t third = host.rfind('.', second - 1);
        return third == std::string_view::npos ? host : host.substr(third + 1);
    }
    return host.substr(second + 1);
}

inline bool IsIPLiteral(std::string_view host) {
    if (host.find(':') != std::string_view::npos) return true;  // IPv6
    for (char c : host) if (!((c >= '0' && c <= '9') || c == '.')) return false;
    return !host.empty();
}

// A host's site for telling first party from third: the registrable domain, or the address itself.
inline std::string_view SiteOrHost(std::string_view host) { return IsIPLiteral(host) ? host : Site(host); }

// The user's own decisions from the privacy panel, on top of the filter lists. Domains cover
// their subdomains; sites are SiteOrHost() of the tab's top-level page. An immutable value
// behind an atomic pointer, never freed (a handful of swaps per session, each a few hundred
// bytes): an IO-thread lookup may still be reading the old one.
struct Rules {
    DomainSet blocked;   // on every site
    DomainSet allowed;   // on every site, though listed
    std::unordered_map<std::string, DomainSet> blockedOn;   // by the page's site
    std::unordered_map<std::string, DomainSet> allowedOn;
    std::unordered_set<std::string> offSites;   // protection is off on these sites
    std::unordered_map<std::string, int> siteModes;   // a site's own filtering mode (kMode…), the off ones too
};

// How much Shields does on a page (NicheCore's FilteringMode, uBlock Origin Lite's modes):
// nothing; requests blocked; also what the lists say about the page's own site (its selectors
// hidden, its scripts run); also the generic hiding rules.
enum : int { kModeNone = 0, kModeBasic = 1, kModeOptimal = 2, kModeComplete = 3 };

// The mode for every site without one of its own (Settings ▸ Privacy "Filtering").
inline std::atomic<int>& StandardMode() { static std::atomic<int> v{kModeOptimal}; return v; }

inline std::atomic<const Rules*>& UserRules() { static std::atomic<const Rules*> v{nullptr}; return v; }
inline void PublishRules(const Rules* rules) { UserRules().store(rules, std::memory_order_release); }

inline bool Covers(const DomainSet& set, const std::string& host) { return !set.empty() && !MatchedEntry(set, host).empty(); }

// What the user decided about a request, before the filter engine is asked.
enum class Choice : int {
    kNone = 0,      // nothing: the engine decides
    kAllowed = 1,   // allowed here or everywhere, whatever the lists say
    kBlocked = 2,   // blocked here or everywhere
    kOff = 3,       // protection is off for the page's site: everything loads
};

struct UserSay {
    Choice choice = Choice::kNone;
    bool thirdParty = false;   // another site than the page's
};

// The user's say over one request. In this order: a site with protection off loads everything;
// a request to the page's own site is the engine's alone (the user's rules name other companies);
// the choice for this site (allow, then block); the choice for every site (allow, then block).
// Hosts must be normalized.
inline UserSay Say(const std::string& requestHost, const std::string& pageHost) {
    UserSay say;
    if (requestHost.empty() || pageHost.empty()) return say;
    std::string page(SiteOrHost(pageHost));
    say.thirdParty = SiteOrHost(requestHost) != std::string_view(page);
    const Rules* r = UserRules().load(std::memory_order_acquire);
    if (!r) return say;
    if (r->offSites.count(page)) { say.choice = Choice::kOff; return say; }
    if (!say.thirdParty) return say;
    if (auto it = r->allowedOn.find(page); it != r->allowedOn.end() && Covers(it->second, requestHost)) { say.choice = Choice::kAllowed; return say; }
    if (auto it = r->blockedOn.find(page); it != r->blockedOn.end() && Covers(it->second, requestHost)) { say.choice = Choice::kBlocked; return say; }
    if (Covers(r->allowed, requestHost)) { say.choice = Choice::kAllowed; return say; }
    if (Covers(r->blocked, requestHost)) say.choice = Choice::kBlocked;
    return say;
}

// What happens to a request, for the privacy panel.
enum class Verdict : int { kAllowed = 0, kBlockedByList = 1, kBlockedByUser = 2 };

// The user's say and the engine's answer (`listed`: one of its rules would block the request)
// as one verdict: protection off or the user's allow lets it load; the user's block or the
// engine's stops it.
inline Verdict Combine(const UserSay& say, bool listed) {
    switch (say.choice) {
        case Choice::kOff: case Choice::kAllowed: return Verdict::kAllowed;
        case Choice::kBlocked: return Verdict::kBlockedByUser;
        case Choice::kNone: return listed ? Verdict::kBlockedByList : Verdict::kAllowed;
    }
    return Verdict::kAllowed;
}

// Whether the user turned protection off for the site of this page's host.
inline bool ProtectionOff(const std::string& pageHost) {
    const Rules* r = UserRules().load(std::memory_order_acquire);
    return r && r->offSites.count(std::string(SiteOrHost(pageHost))) > 0;
}

// The filtering mode in force on a page of this host: its site's own, else the one for every site.
inline int ModeFor(const std::string& pageHost) {
    const Rules* r = UserRules().load(std::memory_order_acquire);
    if (r) {
        const std::string site(SiteOrHost(pageHost));
        if (r->offSites.count(site)) return kModeNone;
        if (auto it = r->siteModes.find(site); it != r->siteModes.end()) return it->second;
    }
    return StandardMode().load(std::memory_order_relaxed);
}

// Host of an http(s)/ws(s) URL, normalized; empty for other schemes. Parses just
// enough of the URL for this purpose (scheme, optional userinfo, port, IPv6).
inline std::string WebHost(std::string_view url) {
    size_t colon = url.find("://");
    if (colon == std::string_view::npos) return {};
    std::string scheme;
    for (char c : url.substr(0, colon)) scheme.push_back(Lower(c));
    if (scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss") return {};
    std::string_view rest = url.substr(colon + 3);
    rest = rest.substr(0, rest.find_first_of("/?#"));
    if (size_t at = rest.rfind('@'); at != std::string_view::npos) rest = rest.substr(at + 1);
    if (!rest.empty() && rest.front() == '[') {
        size_t close = rest.find(']');
        return close == std::string_view::npos ? std::string() : std::string(rest.substr(0, close + 1));
    }
    return NormalizeHost(rest.substr(0, rest.find(':')));
}

}  // namespace niche_blocker
