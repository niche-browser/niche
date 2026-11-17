import Foundation

/// The rows of `TrackerDirectory.standard`: company id, name, what a group of its domains is for,
/// and the domains. Add a company by adding rows; keep one category per domain.
enum TrackerDirectoryData {
    typealias Row = (id: String, name: String, category: TrackerCategory, domains: [String])

    static let rows: [Row] = big + advertising + brokers + recording + analytics + marketing + helpers

    // MARK: The large platforms

    private static let big: [Row] = [
        ("google", "Google", .advertising, ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com",
                                            "2mdn.net", "admob.com", "adservice.google.com", "adsensecustomsearchads.com"]),
        ("google", "Google", .analytics, ["google-analytics.com", "googletagmanager.com", "analytics.google.com", "app-measurement.com",
                                          "googleoptimize.com", "crashlytics.com"]),
        ("google", "Google", .hosting, ["gstatic.com", "googleapis.com", "googleusercontent.com", "ggpht.com"]),
        ("google", "Google", .media, ["youtube.com", "ytimg.com", "youtube-nocookie.com", "googlevideo.com", "maps.google.com",
                                      "maps.googleapis.com", "maps.gstatic.com"]),
        // google.com itself is what pages embed for sign-in and reCAPTCHA; its ad hosts are above.
        ("google", "Google", .security, ["google.com", "accounts.google.com", "recaptcha.net"]),

        ("meta", "Meta", .social, ["facebook.com", "facebook.net", "fbcdn.net", "fbsbx.com", "instagram.com", "cdninstagram.com", "atdmt.com"]),

        ("microsoft", "Microsoft", .sessionRecording, ["clarity.ms"]),
        ("microsoft", "Microsoft", .advertising, ["bing.com", "adnxs.com", "adnxs-simple.com"]),
        ("microsoft", "Microsoft", .social, ["linkedin.com", "licdn.com"]),
        ("microsoft", "Microsoft", .analytics, ["appcenter.ms"]),
        ("microsoft", "Microsoft", .security, ["live.com", "microsoftonline.com", "msauth.net", "msftauth.net"]),
        ("microsoft", "Microsoft", .hosting, ["azureedge.net", "msecnd.net", "githubusercontent.com", "githubassets.com", "github.io"]),

        ("amazon", "Amazon", .advertising, ["amazon-adsystem.com", "assoc-amazon.com"]),
        ("amazon", "Amazon", .hosting, ["cloudfront.net", "amazonaws.com", "media-amazon.com", "ssl-images-amazon.com"]),
        ("amazon", "Amazon", .payments, ["amazonpay.com"]),
        ("amazon", "Amazon", .media, ["twitch.tv", "ttvnw.net"]),

        ("apple", "Apple", .security, ["appleid.apple.com"]),
        ("apple", "Apple", .hosting, ["mzstatic.com"]),
        ("apple", "Apple", .media, ["apple-mapkit.com"]),

        ("tiktok", "TikTok", .social, ["tiktok.com", "tiktokcdn.com", "ttwstatic.com", "byteoversea.com", "tiktokv.com", "ibytedtos.com"]),
        ("tiktok", "TikTok", .advertising, ["analytics.tiktok.com"]),

        ("x", "X (Twitter)", .social, ["twitter.com", "x.com", "twimg.com", "t.co"]),
        ("x", "X (Twitter)", .advertising, ["ads-twitter.com"]),

        ("snap", "Snap", .social, ["snapchat.com"]),
        ("snap", "Snap", .advertising, ["sc-static.net"]),
        ("pinterest", "Pinterest", .social, ["pinterest.com", "pinimg.com"]),
        ("reddit", "Reddit", .social, ["reddit.com", "redditstatic.com", "redditmedia.com"]),

        ("adobe", "Adobe", .dataBroker, ["demdex.net"]),
        ("adobe", "Adobe", .analytics, ["omtrdc.net", "2o7.net", "adobedtm.com"]),
        ("adobe", "Adobe", .advertising, ["everesttech.net", "tubemogul.com"]),
        ("adobe", "Adobe", .marketing, ["marketo.net", "marketo.com", "mktoresp.com", "bizible.com"]),
        ("adobe", "Adobe", .hosting, ["typekit.net", "typekit.com"]),

        ("oracle", "Oracle", .dataBroker, ["bluekai.com", "bkrtx.com", "addthis.com"]),
        ("oracle", "Oracle", .advertising, ["moatads.com"]),
        ("oracle", "Oracle", .marketing, ["eloqua.com", "en25.com"]),

        ("salesforce", "Salesforce", .dataBroker, ["krxd.net"]),
        ("salesforce", "Salesforce", .marketing, ["pardot.com", "exacttarget.com", "igodigital.com"]),
        ("salesforce", "Salesforce", .analytics, ["evergage.com"]),
        ("salesforce", "Salesforce", .support, ["salesforceliveagent.com"]),

        ("yahoo", "Yahoo", .advertising, ["yahoo.com", "advertising.com", "adtechus.com"]),
        ("yahoo", "Yahoo", .hosting, ["yimg.com"]),

        ("yandex", "Yandex", .analytics, ["yandex.ru", "yandex.net", "yandex.com"]),
        ("yandex", "Yandex", .hosting, ["yastatic.net"]),
        ("baidu", "Baidu", .analytics, ["baidu.com"]),
    ]

    // MARK: Advertising

    private static let advertising: [Row] = [
        ("criteo", "Criteo", .advertising, ["criteo.com", "criteo.net"]),
        ("tradedesk", "The Trade Desk", .advertising, ["adsrvr.org"]),
        ("taboola", "Taboola", .advertising, ["taboola.com"]),
        ("outbrain", "Outbrain", .advertising, ["outbrain.com", "outbrainimg.com", "zemanta.com"]),
        ("magnite", "Magnite", .advertising, ["rubiconproject.com", "spotxchange.com", "spotx.tv"]),
        ("pubmatic", "PubMatic", .advertising, ["pubmatic.com"]),
        ("openx", "OpenX", .advertising, ["openx.net"]),
        ("indexexchange", "Index Exchange", .advertising, ["casalemedia.com", "indexww.com"]),
        ("medianet", "Media.net", .advertising, ["media.net"]),
        ("sovrn", "Sovrn", .advertising, ["lijit.com", "sovrn.com"]),
        ("triplelift", "TripleLift", .advertising, ["3lift.com", "triplelift.com"]),
        ("sharethrough", "Sharethrough", .advertising, ["sharethrough.com"]),
        ("teads", "Teads", .advertising, ["teads.tv"]),
        ("equativ", "Equativ", .advertising, ["smartadserver.com"]),
        ("gumgum", "GumGum", .advertising, ["gumgum.com"]),
        ("33across", "33Across", .advertising, ["33across.com"]),
        ("applovin", "AppLovin", .advertising, ["applovin.com", "applvn.com"]),
        ("adform", "Adform", .advertising, ["adform.net"]),
        ("nextroll", "AdRoll", .advertising, ["adroll.com"]),
        ("rtbhouse", "RTB House", .advertising, ["creativecdn.com"]),
        ("bidswitch", "BidSwitch", .advertising, ["bidswitch.net"]),
        ("improvedigital", "Improve Digital", .advertising, ["360yield.com"]),
        ("pulsepoint", "PulsePoint", .advertising, ["contextweb.com"]),
        ("freewheel", "FreeWheel", .advertising, ["fwmrm.net", "stickyadstv.com"]),
        ("mediamath", "MediaMath", .advertising, ["mathtag.com"]),
        ("seedtag", "Seedtag", .advertising, ["seedtag.com"]),
        ("connatix", "Connatix", .advertising, ["connatix.com"]),
        ("yieldmo", "Yieldmo", .advertising, ["yieldmo.com"]),
        ("kargo", "Kargo", .advertising, ["kargo.com"]),
        ("doubleverify", "DoubleVerify", .advertising, ["doubleverify.com", "dvtps.com"]),
        ("ias", "Integral Ad Science", .advertising, ["adsafeprotected.com", "iasds01.com"]),
    ]

    // MARK: Data brokers and identity

    private static let brokers: [Row] = [
        ("quantcast", "Quantcast", .dataBroker, ["quantserve.com", "quantcount.com", "quantcast.com"]),
        ("liveramp", "LiveRamp", .dataBroker, ["rlcdn.com", "liveramp.com", "pippio.com"]),
        ("lotame", "Lotame", .dataBroker, ["crwdcntrl.net", "lotame.com"]),
        ("id5", "ID5", .dataBroker, ["id5-sync.com"]),
        ("tapad", "Tapad", .dataBroker, ["tapad.com"]),
        ("neustar", "Neustar", .dataBroker, ["agkn.com", "neustar.biz"]),
        ("eyeota", "Eyeota", .dataBroker, ["eyeota.net"]),
        ("zeotap", "Zeotap", .dataBroker, ["zeotap.com"]),
        ("liveintent", "LiveIntent", .dataBroker, ["liadm.com", "liveintent.com"]),
        ("epsilon", "Epsilon", .dataBroker, ["dotomi.com", "conversantmedia.com"]),
        ("semasio", "Semasio", .dataBroker, ["semasio.net"]),
        ("dstillery", "Dstillery", .dataBroker, ["dstillery.com", "media6degrees.com"]),
        ("bombora", "Bombora", .dataBroker, ["ml314.com", "bombora.com"]),
        ("zoominfo", "ZoomInfo", .dataBroker, ["zoominfo.com"]),
        ("6sense", "6sense", .dataBroker, ["6sc.co", "6sense.com"]),
        ("demandbase", "Demandbase", .dataBroker, ["demandbase.com", "company-target.com"]),
        ("clearbit", "Clearbit", .dataBroker, ["clearbit.com"]),
        ("nielsen", "Nielsen", .dataBroker, ["exelator.com"]),
        ("nielsen", "Nielsen", .analytics, ["imrworldwide.com"]),
        ("comscore", "Comscore", .analytics, ["scorecardresearch.com", "comscore.com"]),

        ("fingerprint", "Fingerprint", .fingerprinting, ["fingerprint.com", "fpjs.io", "fpcdn.io", "fpjscdn.net"]),
        ("threatmetrix", "ThreatMetrix", .fingerprinting, ["online-metrix.net"]),
        ("iovation", "iovation", .fingerprinting, ["iovation.com", "iesnare.com"]),
        ("maxmind", "MaxMind", .fingerprinting, ["maxmind.com", "mmapiws.com"]),
        // Tell a site's owner where a visitor's internet address is.
        ("ipinfo", "IPinfo", .analytics, ["ipinfo.io"]),
        ("ipapi", "ipapi", .analytics, ["ipapi.co"]),
        ("ip-api", "IP-API", .analytics, ["ip-api.com"]),
    ]

    // MARK: Screen recording

    private static let recording: [Row] = [
        ("hotjar", "Hotjar", .sessionRecording, ["hotjar.com", "hotjar.io"]),
        ("fullstory", "FullStory", .sessionRecording, ["fullstory.com"]),
        ("logrocket", "LogRocket", .sessionRecording, ["logrocket.com", "logrocket.io", "lr-ingest.io", "lr-in.com"]),
        ("mouseflow", "Mouseflow", .sessionRecording, ["mouseflow.com"]),
        ("smartlook", "Smartlook", .sessionRecording, ["smartlook.com"]),
        ("inspectlet", "Inspectlet", .sessionRecording, ["inspectlet.com"]),
        ("crazyegg", "Crazy Egg", .sessionRecording, ["crazyegg.com"]),
        ("luckyorange", "Lucky Orange", .sessionRecording, ["luckyorange.com", "luckyorange.net"]),
        ("contentsquare", "Contentsquare", .sessionRecording, ["contentsquare.net", "contentsquare.com", "clicktale.net"]),
        ("quantummetric", "Quantum Metric", .sessionRecording, ["quantummetric.com"]),
    ]

    // MARK: Analytics

    private static let analytics: [Row] = [
        ("mixpanel", "Mixpanel", .analytics, ["mixpanel.com", "mxpnl.com"]),
        ("amplitude", "Amplitude", .analytics, ["amplitude.com"]),
        ("segment", "Segment", .analytics, ["segment.com", "segment.io"]),
        ("heap", "Heap", .analytics, ["heap.io", "heapanalytics.com"]),
        ("posthog", "PostHog", .analytics, ["posthog.com"]),
        ("plausible", "Plausible", .analytics, ["plausible.io"]),
        ("fathom", "Fathom", .analytics, ["usefathom.com"]),
        ("matomo", "Matomo", .analytics, ["matomo.cloud"]),
        ("chartbeat", "Chartbeat", .analytics, ["chartbeat.com", "chartbeat.net"]),
        ("parsely", "Parse.ly", .analytics, ["parsely.com", "parse.ly"]),
        ("statcounter", "StatCounter", .analytics, ["statcounter.com"]),
        ("newrelic", "New Relic", .analytics, ["newrelic.com", "nr-data.net"]),
        ("sentry", "Sentry", .analytics, ["sentry.io", "sentry-cdn.com"]),
        ("datadog", "Datadog", .analytics, ["datadoghq.com", "datadoghq-browser-agent.com", "browser-intake-datadoghq.com"]),
        ("bugsnag", "Bugsnag", .analytics, ["bugsnag.com"]),
        ("rollbar", "Rollbar", .analytics, ["rollbar.com"]),
        ("optimizely", "Optimizely", .analytics, ["optimizely.com"]),
        ("vwo", "VWO", .analytics, ["visualwebsiteoptimizer.com", "vwo.com"]),
        ("abtasty", "AB Tasty", .analytics, ["abtasty.com"]),
        ("dynamicyield", "Dynamic Yield", .analytics, ["dynamicyield.com"]),
        ("automattic", "Automattic", .analytics, ["stats.wp.com", "pixel.wp.com"]),
        ("automattic", "Automattic", .hosting, ["wp.com", "wordpress.com", "gravatar.com"]),
        ("vercel", "Vercel", .analytics, ["vercel-insights.com"]),
        ("vercel", "Vercel", .hosting, ["vercel.app", "vercel.com"]),
        ("cloudflare", "Cloudflare", .analytics, ["cloudflareinsights.com"]),
        ("cloudflare", "Cloudflare", .security, ["challenges.cloudflare.com"]),
        ("cloudflare", "Cloudflare", .media, ["cloudflarestream.com"]),
        ("cloudflare", "Cloudflare", .hosting, ["cloudflare.com", "cdnjs.com"]),
        ("akamai", "Akamai", .analytics, ["go-mpulse.net", "akstat.io"]),
        ("akamai", "Akamai", .hosting, ["akamaihd.net", "akamaized.net", "akamai.net", "edgekey.net", "edgesuite.net"]),
        ("fastly", "Fastly", .analytics, ["fastly-insights.com"]),
        ("fastly", "Fastly", .hosting, ["fastly.net", "fastlylb.net"]),
        ("shopify", "Shopify", .analytics, ["shopifysvc.com"]),
        ("shopify", "Shopify", .hosting, ["shopify.com", "shopifycdn.com", "myshopify.com", "shopifycloud.com"]),
    ]

    // MARK: Marketing

    private static let marketing: [Row] = [
        ("hubspot", "HubSpot", .marketing, ["hubspot.com", "hs-analytics.net", "hs-scripts.com", "hsforms.com", "hsforms.net",
                                            "hscollectedforms.net", "hs-banner.com", "hsadspixel.net", "usemessages.com"]),
        ("mailchimp", "Mailchimp", .marketing, ["list-manage.com", "chimpstatic.com", "mailchimp.com"]),
        ("klaviyo", "Klaviyo", .marketing, ["klaviyo.com"]),
        ("braze", "Braze", .marketing, ["braze.com", "appboy.com"]),
        ("onesignal", "OneSignal", .marketing, ["onesignal.com"]),
        ("customerio", "Customer.io", .marketing, ["customer.io"]),
        ("activecampaign", "ActiveCampaign", .marketing, ["activehosted.com", "trackcmp.net"]),
        ("drip", "Drip", .marketing, ["getdrip.com"]),
        ("attentive", "Attentive", .marketing, ["attn.tv", "attentivemobile.com"]),
        ("iterable", "Iterable", .marketing, ["iterable.com"]),
        ("sailthru", "Sailthru", .marketing, ["sailthru.com"]),
    ]

    // MARK: What makes a page work

    private static let helpers: [Row] = [
        ("intercom", "Intercom", .support, ["intercom.io", "intercomcdn.com", "intercom.com"]),
        ("drift", "Drift", .support, ["drift.com", "driftt.com"]),
        ("zendesk", "Zendesk", .support, ["zendesk.com", "zdassets.com", "zopim.com"]),
        ("crisp", "Crisp", .support, ["crisp.chat"]),
        ("tawk", "tawk.to", .support, ["tawk.to"]),
        ("livechat", "LiveChat", .support, ["livechatinc.com", "livechat.com"]),
        ("freshworks", "Freshworks", .support, ["freshchat.com", "freshdesk.com", "freshworks.com"]),
        ("olark", "Olark", .support, ["olark.com"]),
        ("tidio", "Tidio", .support, ["tidio.co", "tidiochat.com"]),
        ("helpscout", "Help Scout", .support, ["helpscout.net"]),

        ("onetrust", "OneTrust", .consent, ["onetrust.com", "cookielaw.org", "cookiepro.com"]),
        ("usercentrics", "Usercentrics", .consent, ["cookiebot.com", "usercentrics.eu"]),
        ("consentmanager", "consentmanager", .consent, ["consentmanager.net"]),
        ("didomi", "Didomi", .consent, ["didomi.io", "privacy-center.org"]),
        ("trustarc", "TrustArc", .consent, ["trustarc.com", "truste.com"]),
        ("iab", "IAB Europe", .consent, ["consensu.org"]),
        ("osano", "Osano", .consent, ["osano.com"]),
        ("iubenda", "iubenda", .consent, ["iubenda.com"]),
        ("termly", "Termly", .consent, ["termly.io"]),

        ("stripe", "Stripe", .payments, ["stripe.com", "stripe.network", "stripecdn.com"]),
        ("paypal", "PayPal", .payments, ["paypal.com", "paypalobjects.com", "braintreegateway.com", "braintree-api.com"]),
        ("adyen", "Adyen", .payments, ["adyen.com"]),
        ("klarna", "Klarna", .payments, ["klarna.com", "klarnacdn.net", "klarnaservices.com"]),
        ("affirm", "Affirm", .payments, ["affirm.com"]),
        ("square", "Square", .payments, ["squareup.com", "squarecdn.com"]),
        ("riskified", "Riskified", .payments, ["riskified.com"]),
        ("sift", "Sift", .payments, ["sift.com", "siftscience.com"]),
        ("forter", "Forter", .payments, ["forter.com"]),
        ("signifyd", "Signifyd", .payments, ["signifyd.com"]),

        ("hcaptcha", "hCaptcha", .security, ["hcaptcha.com"]),
        ("arkose", "Arkose Labs", .security, ["arkoselabs.com", "funcaptcha.com"]),
        ("human", "HUMAN", .security, ["perimeterx.net", "px-cdn.net", "px-cloud.net", "pxchk.net", "humansecurity.com"]),
        ("datadome", "DataDome", .security, ["datadome.co", "captcha-delivery.com"]),
        ("okta", "Okta", .security, ["auth0.com", "okta.com", "oktacdn.com"]),

        ("vimeo", "Vimeo", .media, ["vimeo.com", "vimeocdn.com"]),
        ("spotify", "Spotify", .media, ["spotify.com", "scdn.co", "spotifycdn.com"]),
        ("soundcloud", "SoundCloud", .media, ["soundcloud.com", "sndcdn.com"]),
        ("wistia", "Wistia", .media, ["wistia.com", "wistia.net"]),
        ("jwplayer", "JW Player", .media, ["jwplayer.com", "jwpcdn.com", "jwpsrv.com"]),
        ("brightcove", "Brightcove", .media, ["brightcove.com", "brightcove.net"]),
        ("giphy", "Giphy", .media, ["giphy.com"]),
        ("mapbox", "Mapbox", .media, ["mapbox.com"]),
        ("openstreetmap", "OpenStreetMap", .media, ["openstreetmap.org"]),
        ("disqus", "Disqus", .social, ["disqus.com", "disquscdn.com"]),
        ("typeform", "Typeform", .media, ["typeform.com"]),
        ("calendly", "Calendly", .media, ["calendly.com"]),

        ("jsdelivr", "jsDelivr", .hosting, ["jsdelivr.net"]),
        ("unpkg", "unpkg", .hosting, ["unpkg.com"]),
        ("bootstrapcdn", "BootstrapCDN", .hosting, ["bootstrapcdn.com"]),
        ("jquery", "jQuery", .hosting, ["jquery.com"]),
        ("fontawesome", "Font Awesome", .hosting, ["fontawesome.com"]),
        ("netlify", "Netlify", .hosting, ["netlify.app", "netlify.com"]),
        ("bunny", "Bunny", .hosting, ["b-cdn.net", "bunny.net"]),
        ("imgix", "imgix", .hosting, ["imgix.net"]),
        ("cloudinary", "Cloudinary", .hosting, ["cloudinary.com"]),
        ("wix", "Wix", .hosting, ["wixstatic.com", "parastorage.com"]),
        ("squarespace", "Squarespace", .hosting, ["squarespace.com", "squarespace-cdn.com", "sqspcdn.com"]),
        ("webflow", "Webflow", .hosting, ["webflow.com", "website-files.com"]),
        ("monotype", "Monotype", .hosting, ["fonts.net"]),
    ]
}
