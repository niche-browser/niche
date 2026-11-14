// The engine-side decisions that need no CEF: built and run by scripts/test-engine-policies.sh.
#include <cstdio>
#include <string_view>

#include "../../Sources/NicheCEF/NicheProtocolPolicy.h"

static int checks = 0, failures = 0;

static void expect(bool ok, const char* what) {
    ++checks;
    if (!ok) {
        ++failures;
        std::fprintf(stderr, "FAILED: %s\n", what);
    }
}

int main() {
    using niche_protocol::AllowsOSExecution;
    // 13 Nov 2026: the check compared four characters with "niche:", so it never matched and a
    // page could launch niche://commandbar and niche://open.
    expect(!AllowsOSExecution("niche://debug?embedDump=1"), "a page can't launch niche://debug");
    expect(!AllowsOSExecution("niche://open?url=https://example.com/"), "nor niche://open");
    expect(!AllowsOSExecution("niche:commandbar"), "nor the scheme without slashes");
    expect(!AllowsOSExecution("NICHE://dismiss"), "whatever the case");
    expect(!AllowsOSExecution("  \tniche://dismiss"), "or the space in front");
    expect(AllowsOSExecution("mailto:someone@example.com"), "mailto: goes to macOS");
    expect(AllowsOSExecution("nichely://x"), "another app's scheme that starts the same goes to macOS");
    expect(AllowsOSExecution("zoommtg://zoom.us/join?confno=1"), "an app's link goes to macOS");
    expect(AllowsOSExecution(""), "an empty address is not Niche's");
    if (failures) {
        std::fprintf(stderr, "Engine policies: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    std::printf("Engine policies: %d checks passed\n", checks);
    return 0;
}
