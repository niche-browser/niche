// The blocker's decisions (Sources/NicheCEF/NicheContentBlocker.h): built and run by
// scripts/test-engine-policies.sh.
#include <cstdio>
#include <string>

#include "../../Sources/NicheCEF/NicheContentBlocker.h"

static int checks = 0, failures = 0;

static void expect(bool ok, const char* what) {
    ++checks;
    if (!ok) {
        ++failures;
        std::fprintf(stderr, "FAILED: %s\n", what);
    }
}

using namespace niche_blocker;

static Rules* rules() { return new Rules(); }
// A profile with these rules (the published tables are never freed, so neither are these).
static const Profile* with(const Rules* r) { auto* p = new Profile(); p->rules = *r; return p; }
static const Profile* cur = nullptr;

int main() {
    cur = nullptr;

    // Without rules of the user's, the filter engine decides everything.
    UserSay say = Say(cur, "cdn.tracker.example", "news.test");
    expect(say.choice == Choice::kNone && say.thirdParty, "no rules: nothing to say about another site's request");
    say = Say(cur, "static.news.test", "www.news.test");
    expect(say.choice == Choice::kNone && !say.thirdParty, "the page's own site is first party");
    say = Say(cur, "", "news.test");
    expect(say.choice == Choice::kNone && !say.thirdParty, "no host: nothing to say");
    expect(Combine(Say(cur, "cdn.tracker.example", "news.test"), true) == Verdict::kBlockedByList, "what the lists block is blocked");
    expect(Combine(Say(cur, "cdn.tracker.example", "news.test"), false) == Verdict::kAllowed, "what they don't loads");
    // An ad a site serves from its own address is the lists' to block too.
    expect(Combine(Say(cur, "static.news.test", "www.news.test"), true) == Verdict::kBlockedByList, "a first-party request the lists block is blocked");
    expect(!ProtectionOff(cur, "login.bank.test"), "no rules: protection is on everywhere");

    // Blocked and allowed on every site.
    Rules* r = rules();
    r->blocked = {"cdn.test"};
    r->allowed = {"tracker.example"};
    cur = with(r);
    expect(Say(cur, "fonts.cdn.test", "news.test").choice == Choice::kBlocked, "a company blocked everywhere is blocked");
    expect(Say(cur, "a.fonts.cdn.test", "other.test").choice == Choice::kBlocked, "with its subdomains, on every site");
    expect(Say(cur, "fonts.cdn.test", "www.cdn.test").choice == Choice::kNone, "never on its own site");
    expect(Combine(Say(cur, "fonts.cdn.test", "news.test"), false) == Verdict::kBlockedByUser, "though no list names it");
    expect(Combine(Say(cur, "cdn.tracker.example", "news.test"), true) == Verdict::kAllowed, "a listed company the user allows loads");
    expect(Combine(Say(cur, "ads.network.test", "news.test"), true) == Verdict::kBlockedByList, "the rest of the lists still block");

    // On one site.
    r = rules();
    r->blockedOn["news.test"] = {"cdn.test"};
    r->allowedOn["shop.test"] = {"network.test"};
    r->blocked = {"video.test"};
    r->allowedOn["cinema.test"] = {"video.test"};
    cur = with(r);
    expect(Say(cur, "fonts.cdn.test", "www.news.test").choice == Choice::kBlocked, "blocked on this site");
    expect(Say(cur, "fonts.cdn.test", "other.test").choice == Choice::kNone, "and only on this site");
    expect(Combine(Say(cur, "ads.network.test", "shop.test"), true) == Verdict::kAllowed, "allowed on this site though listed");
    expect(Combine(Say(cur, "ads.network.test", "news.test"), true) == Verdict::kBlockedByList, "and only on this site");
    expect(Say(cur, "video.test", "cinema.test").choice == Choice::kAllowed, "a site's own allow wins over a block everywhere");
    expect(Say(cur, "video.test", "news.test").choice == Choice::kBlocked, "which holds elsewhere");

    // Protection off for a site: everything loads there, its own requests included.
    r = rules();
    r->offSites = {"bank.test"};
    r->blocked = {"cdn.test"};
    cur = with(r);
    expect(Say(cur, "cdn.tracker.example", "login.bank.test").choice == Choice::kOff, "a site with protection off");
    expect(Combine(Say(cur, "cdn.tracker.example", "login.bank.test"), true) == Verdict::kAllowed, "loads what the lists block");
    expect(Combine(Say(cur, "fonts.cdn.test", "bank.test"), false) == Verdict::kAllowed, "the user's blocks rest there too");
    expect(Combine(Say(cur, "ads.bank.test", "www.bank.test"), true) == Verdict::kAllowed, "and so do the lists' first-party rules");
    expect(ProtectionOff(cur, "login.bank.test") && !ProtectionOff(cur, "news.test"), "the switch is the site's, subdomains included");
    expect(Combine(Say(cur, "cdn.tracker.example", "news.test"), true) == Verdict::kBlockedByList, "other sites stay protected");
    cur = nullptr;

    // Each profile its own (22 Nov 2026: one set for every profile). Hobbies switched protection
    // off for a site and runs Basic; Default blocks a company there and runs Optimal.
    expect(ProfileFor("Default") == nullptr, "nothing published: no profile's Shields yet");
    expect(ModeFor(ProfileFor("Default"), "news.test") == kModeNone, "and nothing is done to a page");
    auto* home = new Profile();
    home->rules.blocked = {"cdn.test"};
    home->engine = 0;
    auto* hobbies = new Profile();
    hobbies->rules.offSites = {"news.test"};
    hobbies->standardMode = kModeBasic;
    hobbies->engine = 1;
    hobbies->globalPrivacyControl = true;
    PublishProfiles(new Profiles{{"Default", home}, {"Profile B1", hobbies}});
    expect(ProfileFor("Profile B1") == hobbies && ProfileFor("Default") == home, "each profile by its folder");
    expect(ProfileFor("Profile C2") == home, "one not published yet follows Default");
    expect(Say(ProfileFor("Default"), "fonts.cdn.test", "news.test").choice == Choice::kBlocked, "Default's block holds in Default");
    expect(Say(ProfileFor("Profile B1"), "fonts.cdn.test", "news.test").choice == Choice::kOff, "Hobbies' site switch holds in Hobbies");
    expect(Say(ProfileFor("Profile B1"), "fonts.cdn.test", "shop.test").choice == Choice::kNone, "and Default's block isn't Hobbies'");
    expect(!ProtectionOff(ProfileFor("Default"), "news.test"), "nor Hobbies' switch Default's");
    expect(ModeFor(ProfileFor("Default"), "shop.test") == kModeOptimal, "Default's mode for every site");
    expect(ModeFor(ProfileFor("Profile B1"), "shop.test") == kModeBasic, "Hobbies' own");
    expect(ModeFor(ProfileFor("Profile B1"), "news.test") == kModeNone, "and its site switched off");
    expect(ProfileFor("Profile B1")->engine == 1 && ProfileFor("Default")->engine == 0, "each with its lists' engine");
    PublishProfiles(nullptr);

    // Sites.
    expect(SiteOrHost("a.b.example.co.uk") == "example.co.uk", "a site under a second-level domain");
    expect(SiteOrHost("127.0.0.1") == "127.0.0.1", "an address is its own site");
    // The same cases as PrivacySiteTests (NicheCore): the panel's rules are kept by site.
    expect(SiteOrHost("www.news.test") == "news.test", "a site is its last two labels");
    expect(SiteOrHost("localhost") == "localhost", "a single label is its own site");
    expect(SiteOrHost("shop.example.com.au") == "example.com.au", "three under com.au");
    expect(SiteOrHost("a.b.c.example.de") == "example.de", "two under a plain country code");
    expect(SiteOrHost("someone.github.io") == "someone.github.io", "a name on a shared host is its own site");
    expect(SiteOrHost("www.someone.github.io") == "someone.github.io", "and covers its own subdomains");
    expect(SiteOrHost("github.io") == "github.io", "the shared host itself");
    expect(SiteOrHost("shop.myshopify.com") != SiteOrHost("other.myshopify.com"), "two shops are two sites");
    expect(Say(cur, "127.0.0.2", "127.0.0.1").thirdParty, "two addresses are two sites");

    if (failures) {
        std::fprintf(stderr, "Content blocker: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    std::printf("Content blocker: %d checks passed\n", checks);
    return 0;
}
