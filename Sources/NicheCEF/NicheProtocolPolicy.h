// Which addresses a page may hand to macOS (CefRequestHandler::OnProtocolExecution). Plain C++
// with no CEF or Cocoa dependency so it can be tested on its own (scripts/test-engine-policies.sh).
#pragma once

#include <cctype>
#include <string>
#include <string_view>

namespace niche_protocol {

// niche:// is Niche's own scripting scheme: a page must not drive it. Everything else
// (mailto:, an app's link) goes to macOS. Schemes compare without case and a page may put
// spaces or control characters in front, as URL parsers skip them.
inline bool AllowsOSExecution(std::string_view url) {
    static constexpr std::string_view scheme = "niche:";
    size_t start = 0;
    while (start < url.size() && static_cast<unsigned char>(url[start]) <= ' ') ++start;
    if (url.size() - start < scheme.size()) return true;
    for (size_t i = 0; i < scheme.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(url[start + i])) != scheme[i]) return true;
    }
    return false;
}

}  // namespace niche_protocol
