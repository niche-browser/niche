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

int main() {
    PublishRules(nullptr);

    // Without rules of the user's, the filter engine decides everything.
    UserSay say = Say("cdn.tracker.example", "news.test");
    expect(say.choice == Choice::kNone && say.thirdParty, "no rules: nothing to say about another site's request");
    say = Say("static.news.test", "www.news.test");
    expect(say.choice == Choice::kNone && !say.thirdParty, "the page's own site is first party");
    say = Say("", "news.test");
    expect(say.choice == Choice::kNone && !say.thirdParty, "no host: nothing to say");
    expect(Combine(Say("cdn.tracker.example", "news.test"), true) == Verdict::kBlockedByList, "what the lists block is blocked");
    expect(Combine(Say("cdn.tracker.example", "news.test"), false) == Verdict::kAllowed, "what they don't loads");
    // An ad a site serves from its own address is the lists' to block too.
    expect(Combine(Say("static.news.test", "www.news.test"), true) == Verdict::kBlockedByList, "a first-party request the lists block is blocked");
    expect(!ProtectionOff("login.bank.test"), "no rules: protection is on everywhere");

    // Blocked and allowed on every site.
    Rules* r = rules();
    r->blocked = {"cdn.test"};
    r->allowed = {"tracker.example"};
    PublishRules(r);
    expect(Say("fonts.cdn.test", "news.test").choice == Choice::kBlocked, "a company blocked everywhere is blocked");
    expect(Say("a.fonts.cdn.test", "other.test").choice == Choice::kBlocked, "with its subdomains, on every site");
    expect(Say("fonts.cdn.test", "www.cdn.test").choice == Choice::kNone, "never on its own site");
    expect(Combine(Say("fonts.cdn.test", "news.test"), false) == Verdict::kBlockedByUser, "though no list names it");
    expect(Combine(Say("cdn.tracker.example", "news.test"), true) == Verdict::kAllowed, "a listed company the user allows loads");
    expect(Combine(Say("ads.network.test", "news.test"), true) == Verdict::kBlockedByList, "the rest of the lists still block");

    // On one site.
    r = rules();
    r->blockedOn["news.test"] = {"cdn.test"};
    r->allowedOn["shop.test"] = {"network.test"};
    r->blocked = {"video.test"};
    r->allowedOn["cinema.test"] = {"video.test"};
    PublishRules(r);
    expect(Say("fonts.cdn.test", "www.news.test").choice == Choice::kBlocked, "blocked on this site");
    expect(Say("fonts.cdn.test", "other.test").choice == Choice::kNone, "and only on this site");
    expect(Combine(Say("ads.network.test", "shop.test"), true) == Verdict::kAllowed, "allowed on this site though listed");
    expect(Combine(Say("ads.network.test", "news.test"), true) == Verdict::kBlockedByList, "and only on this site");
    expect(Say("video.test", "cinema.test").choice == Choice::kAllowed, "a site's own allow wins over a block everywhere");
    expect(Say("video.test", "news.test").choice == Choice::kBlocked, "which holds elsewhere");

    // Protection off for a site: everything loads there, its own requests included.
    r = rules();
    r->offSites = {"bank.test"};
    r->blocked = {"cdn.test"};
    PublishRules(r);
    expect(Say("cdn.tracker.example", "login.bank.test").choice == Choice::kOff, "a site with protection off");
    expect(Combine(Say("cdn.tracker.example", "login.bank.test"), true) == Verdict::kAllowed, "loads what the lists block");
    expect(Combine(Say("fonts.cdn.test", "bank.test"), false) == Verdict::kAllowed, "the user's blocks rest there too");
    expect(Combine(Say("ads.bank.test", "www.bank.test"), true) == Verdict::kAllowed, "and so do the lists' first-party rules");
    expect(ProtectionOff("login.bank.test") && !ProtectionOff("news.test"), "the switch is the site's, subdomains included");
    expect(Combine(Say("cdn.tracker.example", "news.test"), true) == Verdict::kBlockedByList, "other sites stay protected");
    PublishRules(nullptr);

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
    expect(Say("127.0.0.2", "127.0.0.1").thirdParty, "two addresses are two sites");

    if (failures) {
        std::fprintf(stderr, "Content blocker: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    std::printf("Content blocker: %d checks passed\n", checks);
    return 0;
}
