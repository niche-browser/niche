import Foundation

/// A host's site as the engine's blocker tells first party from third (`niche_blocker::SiteOrHost`
/// in NicheContentBlocker.h, the same rule in C++): the last two labels, three under a
/// "co.uk"-style second level or a host that gives every customer a name ("someone.github.io"),
/// an address as it is. The privacy panel's rules are kept by it, so
/// the two must agree; both have the same cases in their tests.
public enum PrivacySite {
    private static let secondLevels: Set<String> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gob", "mil", "nic", "ltd", "plc"]

    /// Hosts that give each customer a name of their own: one name there is one site.
    private static let hosted: Set<String> = [
        "github.io", "gitlab.io", "pages.dev", "workers.dev", "vercel.app", "netlify.app", "web.app", "firebaseapp.com",
        "herokuapp.com", "azurewebsites.net", "cloudfront.net", "amazonaws.com", "appspot.com", "blogspot.com",
        "wordpress.com", "myshopify.com", "glitch.me", "onrender.com", "fly.dev", "surge.sh", "neocities.org",
        "wixsite.com", "webflow.io", "framer.app", "notion.site", "substack.com", "tumblr.com", "typepad.com"]

    public static func site(ofHost host: String) -> String {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !isAddress(h) else { return h }
        let labels = h.split(separator: ".")
        guard labels.count > 2 else { return h }
        let tld = labels[labels.count - 1], sld = labels[labels.count - 2]
        let take = (tld.count == 2 && secondLevels.contains(String(sld))) || hosted.contains(sld + "." + tld) ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }

    /// The site of an http(s) address's host; nil for anything else (Niche's own pages, files).
    public static func site(ofURL url: String) -> String? {
        guard let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty else { return nil }
        return site(ofHost: host)
    }

    private static func isAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        return !host.isEmpty && host.allSatisfy { $0.isNumber || $0 == "." }
    }
}
