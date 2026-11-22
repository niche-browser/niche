// NicheCEF: the Objective-C surface Swift uses to drive Chromium (CEF).
// Everything here runs on the main thread.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class NicheBrowser;

typedef NS_ENUM(NSInteger, NicheDownloadState) {
    NicheDownloadStateInProgress = 0,
    NicheDownloadStateComplete = 1,
    NicheDownloadStateCancelled = 2,
    NicheDownloadStateInterrupted = 3,
};

/// Where a page's context menu opens a link that isn't for a tab.
typedef NS_ENUM(NSInteger, NicheLinkWindow) {
    NicheLinkWindowNew = 0,
    NicheLinkWindowIncognito = 1,
    NicheLinkWindowLittle = 2,
};

@interface NicheDownloadInfo : NSObject
@property (nonatomic) uint32_t identifier;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, copy) NSString *suggestedName;
@property (nonatomic) int64_t receivedBytes;
@property (nonatomic) int64_t totalBytes;
@property (nonatomic) NSInteger percent;
@property (nonatomic) NicheDownloadState state;
/// In progress, but held by Pause until Resume.
@property (nonatomic) BOOL paused;
/// Where the file goes once it is done: `fullPath` is a .crdownload (or "Unconfirmed …"
/// for a held one) while it runs. Empty until Chromium has decided (safe-downloads.patch).
@property (nonatomic, copy) NSString *targetPath;
/// What Chromium found unsafe about it, held until Keep (+keepDownload:) or Delete (+cancelDownload:):
/// "" for nothing, else file, url, content, uncommon, unwanted, host, policy, other or insecure.
@property (nonatomic, copy) NSString *danger;
/// Chromium dropped it without a word (an insecure download Chrome blocks silently, and lists nothing).
@property (nonatomic) BOOL silent;
/// Chromium blocked the file outright (an insecure download it doesn't offer to keep).
@property (nonatomic) BOOL blocked;
@end

/// What a page did that the privacy panel shows (NicheCEFRuntime.setPrivacyEventHandler).
typedef NS_ENUM(NSInteger, NichePrivacyEventKind) {
    /// The tab asked for another top-level page: what was gathered for the last one is over.
    NichePrivacyEventKindNavigation = 0,
    /// A request to another site than the page's: let through, or blocked (`verdict`).
    NichePrivacyEventKindRequest = 1,
    /// A cookie a request to another site would carry (`detail` is its name); `verdict` 1 when
    /// it was held back.
    NichePrivacyEventKindCookieSent = 2,
    /// A cookie another site's answer would leave (`detail` its name, `cookieDays` how long it
    /// lasts); `verdict` 1 when it was held back.
    NichePrivacyEventKindCookieSaved = 3,
    /// Click identifiers were taken off the page's address before it was asked for.
    NichePrivacyEventKindCleanedAddress = 4,
};

@interface NichePrivacyEvent : NSObject
@property (nonatomic) NichePrivacyEventKind kind;
/// The browser it happened in (NicheBrowser.browserIdentifier).
@property (nonatomic) NSInteger browser;
/// The host asked, its site (registrable domain) and the site of the tab's top-level page.
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *site;
@property (nonatomic, copy) NSString *pageSite;
/// What was asked for: page, frame, script, style, image, font, media, data, ping or other.
@property (nonatomic, copy) NSString *resource;
/// 0 let through, 1 blocked by the list, 2 blocked by the user's own rule.
@property (nonatomic) NSInteger verdict;
/// On the ad and tracker list, blocked or not.
@property (nonatomic) BOOL listed;
/// For a request that was let through: the method, whether it says which site it came from and
/// which page, and how many bytes it sends up.
@property (nonatomic, copy) NSString *method;
@property (nonatomic) BOOL sendsSite;
@property (nonatomic) BOOL sendsPage;
@property (nonatomic) int64_t bytesSent;
/// A cookie's name.
@property (nonatomic, copy) NSString *detail;
/// How long a saved cookie lasts, in days; 0 until the browser quits.
@property (nonatomic) double cookieDays;
/// A request's address as a hash: the same address asked for twice has the same key. Never the
/// address itself.
@property (nonatomic) uint64_t key;
/// The top-level page it happened on, as `privacyPageKeyForURL:` numbers it. For a page change,
/// the page asked for.
@property (nonatomic) uint64_t pageKey;
/// For a request the lists blocked: the group of the list that did (as given to
/// NicheShieldsBuild); -1 otherwise.
@property (nonatomic) NSInteger group;
@end

/// Builds a Shields engine from filter lists and makes it the one in use. Building parses
/// hundreds of thousands of rules (about a tenth of a second): do it off the main thread.
@interface NicheShieldsBuild : NSObject
/// One list's text. `group` is the caller's number for what the list is for; it comes back
/// with every request the list blocks. `trusted`: the list may use the scriptlets that set
/// cookies and storage (the lists Niche ships, never one the user added).
- (void)addList:(NSData *)text group:(NSInteger)group trusted:(BOOL)trusted;
/// Resources as JSON (adblock-rust's format): scriptlets (`forPages`) and the stand-ins served
/// for blocked requests.
- (void)addResources:(NSData *)json forPages:(BOOL)forPages;
/// Builds and installs. Returns how many rules the lists held. The builder is spent.
- (NSInteger)install;
@end

/// The connection of the page on screen (Chromium's SSL status of the visible navigation entry).
@interface NicheSSLStatus : NSObject
/// The page came over a connection with a certificate (https, whatever the certificate's errors).
@property (nonatomic) BOOL secureConnection;
/// net::CertStatus bits: the certificate's errors and notes.
@property (nonatomic) NSUInteger certStatus;
/// net::SSLStatus::ContentStatus bits: http content the page showed or ran.
@property (nonatomic) NSUInteger contentStatus;
/// The server's certificate, then its issuers, DER encoded; empty without a certificate.
@property (nonatomic, copy) NSArray<NSData *> *certificates;
@end

@protocol NicheBrowserDelegate <NSObject>
- (void)browser:(NicheBrowser *)browser didChangeTitle:(NSString *)title;
- (void)browser:(NicheBrowser *)browser didChangeURL:(NSString *)url;
- (void)browser:(NicheBrowser *)browser didChangeLoading:(BOOL)loading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)browser:(NicheBrowser *)browser didChangeProgress:(double)progress;
- (void)browser:(NicheBrowser *)browser didFinishLoadingURL:(NSString *)url title:(NSString *)title statusCode:(NSInteger)statusCode;
- (void)browser:(NicheBrowser *)browser didLoadFavicon:(NSImage *)image forURL:(NSString *)iconURL;
- (void)browser:(NicheBrowser *)browser didChangeStatusMessage:(NSString *)message;
/// The page's theme colour (meta theme-color or body background) as "#RRGGBB", or "" when unknown.
- (void)browser:(NicheBrowser *)browser didReportThemeColor:(NSString *)hex;
- (void)browser:(NicheBrowser *)browser didChangeFullscreen:(BOOL)fullscreen;
/// Cmd-click, middle-click and similar: open a plain new tab.
- (void)browser:(NicheBrowser *)browser requestsNewTabWithURL:(NSString *)url inBackground:(BOOL)background;
/// window.open / target=_blank: return a popup host (a NicheBrowser created with
/// a nil URL) so the popup keeps its opener relationship, or nil to block it.
- (nullable NicheBrowser *)browser:(NicheBrowser *)browser popupHostForURL:(NSString *)url inBackground:(BOOL)background;
/// Return a view to host DevTools in (Niche docks it inside the content card);
/// nil makes CEF open its own DevTools window.
- (nullable NSView *)devToolsHostViewForBrowser:(NicheBrowser *)browser;
/// DevTools was created for docking (a host view was returned): `view.window`
/// is CEF's hidden Alloy window, to be attached as a child window.
- (void)browser:(NicheBrowser *)browser didCreateDevToolsView:(NSView *)view;
/// The DevTools browser closed (either mode).
- (void)browserDidCloseDevTools:(NicheBrowser *)browser;
/// Chrome-style hosting: the page's window exists (also for popups).
- (void)browser:(NicheBrowser *)browser didCreateHostWindow:(NSWindow *)window;
/// Chrome's docked DevTools frontend placed the page: `bounds` are points with a
/// top-left origin inside the DevTools window's content view (setInspectedPageBounds).
- (void)browser:(NicheBrowser *)browser devToolsPageBounds:(NSRect)bounds;
/// Chrome's DevTools frontend docked (YES) or undocked into its own window (NO).
- (void)browser:(NicheBrowser *)browser devToolsDocked:(BOOL)docked;
/// Reserved shortcuts, before the page sees the key. Return YES to consume.
- (BOOL)browser:(NicheBrowser *)browser handleKeyEvent:(NSEvent *)event;
/// Keys the page did not handle (Chrome gives the page first chance at
/// unreserved shortcuts like ⌘F). Return YES to consume.
- (BOOL)browser:(NicheBrowser *)browser handleUnhandledKeyEvent:(NSEvent *)event;
- (void)browser:(NicheBrowser *)browser didUpdateDownload:(NicheDownloadInfo *)download;
/// Ask the user. `kinds` is a bitmask: 1 = camera, 2 = microphone,
/// 4 = location, 8 = notifications, 16 = a type NicheCEF has no bit for, and from
/// 1 << 5 Chrome's other types (kPermissionKinds in NicheCEF.mm, worded by NicheCore's
/// PermissionPrompt).
- (void)browser:(NicheBrowser *)browser requestsPermissionForOrigin:(NSString *)origin kinds:(NSUInteger)kinds completion:(void (^)(BOOL allowed))completion;
- (void)browserDidReceiveFocus:(NicheBrowser *)browser;
- (void)browserDidClose:(NicheBrowser *)browser;
@optional
/// The page's context menu: Open Link in New Window, Little Window or Incognito Window.
- (void)browser:(NicheBrowser *)browser requestsWindowWithURL:(NSString *)url kind:(NicheLinkWindow)kind;
/// The page's context menu on an image: Capture Image… at `point` (page points from the top
/// left). Without it the menu has no such item.
- (void)browser:(NicheBrowser *)browser requestsCaptureOfImageAt:(NSPoint)point;
/// A video of this page entered or left Chromium's Picture in Picture window
/// (whether the page, the user or Niche asked for it).
- (void)browser:(NicheBrowser *)browser didChangePictureInPicture:(BOOL)active;
/// The video in the Picture in Picture window started or stopped playing.
- (void)browser:(NicheBrowser *)browser didChangePictureInPicturePlayback:(BOOL)playing;
/// The colour the page paints behind its content (root/body background, else the
/// canvas colour of its color scheme), as "#RRGGBB"; "" when a new page starts loading
/// and has not reported one yet (show +[NicheBrowser pageCanvasColor] then). The shell fills
/// the area under the page window with it, so a page lagging behind a resize shows no white edge.
- (void)browser:(NicheBrowser *)browser didReportBackgroundColor:(NSString *)hex;
/// Find in page progress: `count` matches, `activeMatch` is the highlighted one
/// (1-based). Either is -1 while Chromium has no new value for it.
- (void)browser:(NicheBrowser *)browser didFindMatches:(NSInteger)count activeMatch:(NSInteger)activeMatch;
/// The page started or stopped using the camera or microphone.
- (void)browser:(NicheBrowser *)browser didChangeMediaCapture:(BOOL)capturing;
/// The page started or stopped playing sound (see `isAudible`).
- (void)browser:(NicheBrowser *)browser didChangeAudible:(BOOL)audible;
/// The page's sound started or stopped as it happened, before the 2 s that `isAudible` and
/// `browser:didChangeAudible:` hold a quiet page audible.
- (void)browser:(NicheBrowser *)browser didChangeSoundPlaying:(BOOL)playing;
/// `hasCommittedLoad` changed: the main frame committed, or a new navigation started.
- (void)browser:(NicheBrowser *)browser didChangeCommittedLoad:(BOOL)committed;
/// The page's main-frame load failed with a net error (ERR_ABORTED, a navigation cut off,
/// is left out): `url` is the address that failed.
- (void)browser:(NicheBrowser *)browser didFailLoadingURL:(NSString *)url errorCode:(NSInteger)errorCode;
/// An extension asked to bring this page's tab to the front (chrome.tabs.update with
/// active: true; scripts/cef-patches/extension-tab-activate.patch), or with byPage the page
/// did (window.focus(), or clients.focus() from a notification click; page-activate.patch).
- (void)browserRequestsActivation:(NicheBrowser *)browser byPage:(BOOL)byPage;
/// Arc's Peek: a link the user clicked (`shiftClick` NO: before it navigates the page or
/// opens as a target=_blank tab) or Shift-clicked (YES, instead of a new window). Return
/// YES to show it in a Peek; the page then stays where it is.
- (BOOL)browser:(NicheBrowser *)browser opensPeekForURL:(NSString *)url shiftClick:(BOOL)shiftClick newTab:(BOOL)newTab;
/// A main-frame navigation (a link, a redirect, history, an address Niche loaded) before its request
/// goes out; `method` is its HTTP method. Return YES to cancel it here because Niche shows `url` in
/// another engine (ProtectedMediaSites: WebKit for DRM services). Called on the main thread from
/// inside Chromium: don't close the browser before returning.
- (BOOL)browser:(NicheBrowser *)browser handsOffNavigationToURL:(NSString *)url method:(NSString *)method;
/// The DevTools frontend shows `panel` ("elements", "console", "network", …): on load, and
/// on every switch, from Niche or the frontend's own tab bar.
- (void)browser:(NicheBrowser *)browser devToolsShowsPanel:(NSString *)panel;
@end

@interface NicheBrowser : NSObject
@property (nonatomic, weak, nullable) id<NicheBrowserDelegate> delegate;
/// Embedded (Alloy) hosting: a plain NSView that owns the Chromium view. Put
/// it in your hierarchy and size it; Chromium follows.
@property (nonatomic, readonly) NSView *containerView;
/// Chrome-style hosting (see +[NicheCEFRuntime setChromeHosting:]): the page
/// lives in its own frameless Chrome window, delivered through
/// -browser:didCreateHostWindow:. Attach it as a child window and size it.
@property (nonatomic, readonly, nullable) NSWindow *hostWindow;
@property (nonatomic, readonly, copy) NSString *currentURL;
@property (nonatomic, readonly, copy) NSString *currentTitle;
@property (nonatomic, readonly) BOOL isLoading;
/// NO from the start of a main-frame navigation until it commits (the server answered and the
/// new page began to load), YES after.
@property (nonatomic, readonly) BOOL hasCommittedLoad;
/// The address the main frame is navigating to, redirects followed (OnBeforeBrowse); what a
/// page still waiting for its answer is waiting for (GitHub #256). nil before the first.
@property (nonatomic, readonly, copy, nullable) NSString *navigatingURL;
/// Main-frame navigations started (not redirects): another one restarts a wait.
@property (nonatomic, readonly) NSInteger navigationStarts;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) BOOL isCreated;
@property (nonatomic, readonly) BOOL isClosed;
/// YES once the page closed itself (window.close()) rather than through -close.
@property (nonatomic, readonly) BOOL closedByPage;
@property (nonatomic, readonly) BOOL hasDevTools;
/// Anything you want to hang on the browser (Swift stores the tab id).
@property (nonatomic, strong, nullable) id userInfo;
/// Runs in the shared off-the-record profile (+[NicheCEFRuntime endIncognitoSession]).
/// Chromium's number for this browser (0 before it exists), as NichePrivacyEvent.browser names it.
@property (nonatomic, readonly) NSInteger browserIdentifier;
@property (nonatomic, readonly) BOOL isIncognito;
/// The profile folder this page's cookies, logins and storage live in (a space's own
/// profile, under the cache root), or nil for the Default profile.
@property (nonatomic, readonly, copy, nullable) NSString *profilePath;

/// Pass a URL to create a browser now. Pass nil to create a popup host that
/// adopts the next popup CEF gives it (see -browser:popupHostForURL:...).
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<NicheBrowserDelegate>)delegate;
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<NicheBrowserDelegate>)delegate
                    incognito:(BOOL)incognito;
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<NicheBrowserDelegate>)delegate
                    incognito:(BOOL)incognito profilePath:(nullable NSString *)profilePath;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoading;
/// Leaves element fullscreen (a video), as Esc does.
- (void)exitFullscreen;
- (void)setFocused:(BOOL)focused;
- (void)showDevToolsInspectingPoint:(NSPoint)point;
- (void)showDevTools;
/// What the next -showDevTools asks of the frontend, as Chrome's DevToolsToggleAction does: a
/// panel to select ("console", "network", "elements"), or "inspect" for the element picker. Done
/// once the frontend is up (at once when DevTools are already open), then cleared.
@property (nonatomic, copy, nullable) NSString *devToolsAction;
/// Does devToolsAction in DevTools already open, without showing them again; a frontend
/// still loading does it once up.
- (void)applyDevToolsAction;
- (void)closeDevTools;
- (double)zoomLevel;
- (void)setZoomLevel:(double)level;
- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding:(BOOL)clearSelection;
- (void)setAudioMuted:(BOOL)muted;
/// Pops the page's video out into Chromium's floating Picture in Picture
/// window. Manual requests toggle (a second call brings the video back).
/// `automatic` is the "leaving a video tab" case: only a playing video of some
/// size qualifies, and nothing happens when there is none.
- (void)requestPictureInPictureAutomatic:(BOOL)automatic NS_SWIFT_NAME(requestPictureInPicture(automatic:));
- (void)exitPictureInPicture;
/// Picture in Picture's close button: the video pauses and goes back to the page, as in Arc
/// and Chrome (back to tab and returning to the tab keep it playing).
- (void)closePictureInPicture;
/// YES while a video of this page is in the Picture in Picture window.
@property (nonatomic, readonly) BOOL isInPictureInPicture;
/// YES while that video is playing.
@property (nonatomic, readonly) BOOL isPictureInPicturePlaying;
/// The page is using the camera or microphone, as Chrome's tab recording indicator counts it.
@property (nonatomic, readonly) BOOL isCapturingMedia;
/// The page is playing sound, in any frame (Chromium's audible state). Like Chrome's tab
/// speaker it stays YES for 2 s after the page goes quiet. Muting the tab doesn't change it.
@property (nonatomic, readonly) BOOL isAudible;
/// Play/pause the video in the Picture in Picture window.
- (void)togglePictureInPicturePlayback;
/// Seek the video in the Picture in Picture window by `seconds` (negative = back).
- (void)skipPictureInPictureBy:(double)seconds NS_SWIFT_NAME(skipPictureInPicture(by:));
- (void)print;
- (void)viewSource;
/// One of Chrome's own commands by its IDC name ("IDC_ROUTE_MEDIA" for Cast…, "IDC_TASK_MANAGER"),
/// where Chromium can run it for this page. NO when it can't.
- (BOOL)runChromeCommand:(NSString *)name NS_SWIFT_NAME(runChromeCommand(_:));
- (void)executeJavaScript:(NSString *)script;
/// Asks the page for its background colour again (-browser:didReportBackgroundColor:);
/// pages can switch themes without a load.
- (void)probeBackgroundColor;
/// What the page area shows before a page reports its background: Arc's black while
/// websites are dark, white while they are light.
@property (class, nonatomic, readonly) NSColor *pageCanvasColor;
/// Runs script in this browser's DevTools frontend, if open (debug aid behind niche://debug?devtoolsjs=).
- (void)executeJavaScript:(NSString *)script inDevTools:(BOOL)inDevTools;
/// Runtime.evaluate (`params` without a context) in the main frame's isolated world `world`,
/// where the isolated document start script runs.
- (void)evaluateInIsolatedWorld:(NSString *)world params:(NSString *)params
                     completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// Chrome DevTools Protocol call on this browser's own session (no DevTools window).
/// `params` is a JSON object string; the completion gets the result JSON or an error.
- (void)sendDevToolsMethod:(NSString *)method params:(NSString *)params
                completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// The page on screen's connection; nil before anything has committed.
- (nullable NicheSSLStatus *)sslStatus;
- (void)notifyMoveOrResizeStarted;
/// Asynchronous. -browserDidClose: fires when Chromium is done.
- (void)close;
@end

@interface NicheCEFRuntime : NSObject
/// Call once, after NSApplication exists, before creating browsers.
/// Experiment: a Chrome-style (extension-capable) Views window; the handler gets its NSWindow.
+ (void)spikeChromeWindowWithURL:(NSString *)url handler:(void (^)(NSWindow *))handler;
/// Host pages as Chrome-style windows (Chrome extensions, Chrome's docked
/// DevTools) instead of embedded Alloy views. Set before any browser exists.
+ (void)setChromeHosting:(BOOL)enabled;
+ (BOOL)chromeHosting;
/// The two "open link" items at the top of a page's context menu, in order: their titles and
/// whether each opens its tab in the background. Exactly two; read when a menu opens.
+ (void)setLinkMenuTitles:(NSArray<NSString *> *)titles opensInBackground:(NSArray<NSNumber *> *)background;
/// Run in every frame of every page browser before the page's own scripts (and once in the
/// document already loaded): `script` in the page's world, `isolatedScript` in the isolated
/// world named `world` (invisible to the page). Set before browsers are created.
+ (void)setDocumentStartScript:(NSString *)script isolatedScript:(NSString *)isolatedScript world:(NSString *)world;
/// Shields, the filter engine (Sources/NicheShields): a request a page makes is cancelled when
/// one of the installed lists' rules says so (unless the user allowed it, or switched protection
/// off for the page's site), a blocked script some pages need is answered with a harmless
/// stand-in, tracking codes come off a page's address, and pages are told what to hide. Nothing
/// is blocked until an engine is installed (NicheShieldsBuilder).
+ (BOOL)shieldsInstalled;
/// Takes the engine out: nothing is blocked or hidden by the lists.
+ (void)removeShields;
/// Settings ▸ Privacy "Remove tracking codes from links": the installed lists' rules for it apply
/// to a page's address before it is asked for.
+ (void)setTrackingCodeRemoval:(BOOL)enabled;
/// NicheCore's ShieldsPageScript.content: what pages are given to hide what the lists say.
+ (void)setShieldsPageScript:(NSString *)script;
/// What the engine says about one request, for checks and the log: "blocked=1 exception=0
/// group=1 stand-in=0 rewritten=-", or "no engine".
+ (NSString *)shieldsVerdictForURL:(NSString *)url onPageURL:(NSString *)pageURL type:(NSString *)type;
/// The privacy panel's feed, on the main thread in batches a few times a second at most: every
/// page change, every request to another site than the page's and every cookie it gets back or
/// leaves, all the time, so a panel opened later has the page's whole story. Nothing is kept
/// by the bridge.
+ (void)setPrivacyEventHandler:(void (^)(NSArray<NichePrivacyEvent *> *events))handler;
/// A page's address as events name it (`NichePrivacyEvent.pageKey`): a hash of it without its
/// fragment, the same for the run of the app.
+ (uint64_t)privacyPageKeyForURL:(NSString *)url;
/// The user's own rules on top of the list (niche_blocker::Rules): domains blocked or allowed on
/// every site, the same per site of the top-level page, sites where nothing is blocked, and
/// sites with a filtering mode of their own.
/// Domains cover their subdomains. Takes effect for the next request.
+ (void)setPrivacyRulesBlocked:(NSArray<NSString *> *)blocked allowed:(NSArray<NSString *> *)allowed
                     blockedOn:(NSDictionary<NSString *, NSArray<NSString *> *> *)blockedOn
                     allowedOn:(NSDictionary<NSString *, NSArray<NSString *> *> *)allowedOn
                      offSites:(NSArray<NSString *> *)offSites
                     siteModes:(NSDictionary<NSString *, NSNumber *> *)siteModes;
/// Settings ▸ Privacy "Filtering": how much Shields does on every site without a mode of its
/// own (`siteModes` above): 1 requests blocked, 2 also what the lists say about the page's own
/// site (hiding and scripts), 3 also the generic hiding rules. NicheCore's FilteringMode.
+ (void)setShieldsFilteringMode:(NSInteger)mode;
/// Global Privacy Control: every request says "Sec-GPC: 1" (do not sell or share my data).
+ (void)setGlobalPrivacyControl:(BOOL)enabled;
/// Chrome's HTTPS-Only Mode ("Always use secure connections") in every profile:
/// http:// navigations are upgraded, and a site without HTTPS shows Chrome's warning
/// page before it loads. Profiles that load later get it too. Off until enabled.
+ (void)setHttpsOnlyModeEnabled:(BOOL)enabled;
/// "Block third-party cookies" in every profile: a site embedded in another site's page
/// neither gets its cookies back nor sets new ones, on the network or from a script. On a site
/// where the user turned protection off the network side is lifted; a script in an embedded
/// frame still can't use cookies there (Chromium's profile setting has no per-site exception
/// Niche can set: docs/privacy.md). Profiles that load later get it too.
+ (void)setThirdPartyCookiesBlocked:(BOOL)blocked;
/// Arc's View ▸ Appearance ("Websites, Easels, and Notes will use:"): 0 Automatic (the Mac's),
/// 1 Light, 2 Dark. Chrome's colour mode in every profile, which pages' prefers-color-scheme and
/// Chrome's own pages follow; profiles that load later get it too.
+ (void)setWebsiteAppearance:(NSInteger)mode;
@property (class, nonatomic, readonly) NSInteger websiteAppearance;
/// Chromium's secure DNS setting (chrome://settings/security), app-wide in Local State:
/// `dns_over_https.mode` and `dns_over_https.templates` as Chromium holds them now. nil
/// before Chromium is ready and once quitting starts.
+ (nullable NSString *)secureDNSMode;
+ (nullable NSString *)secureDNSTemplates;
/// Writes both, as chrome://settings/security does; Chromium's network service picks the
/// change up at once. NO when Chromium isn't ready, a policy sets them, or a write fails.
+ (BOOL)setSecureDNSMode:(NSString *)mode templates:(NSString *)templates;
/// A policy (DnsOverHttpsMode, DnsOverHttpsTemplates) sets secure DNS, so Settings can't.
+ (BOOL)secureDNSIsManaged;
/// Called on the main queue once Chromium is ready (at once if it already is) and after the
/// secure DNS setting changes.
+ (void)setSecureDNSChangeHandler:(nullable void (^)(void))handler;
/// Unpacked extension folders to load with --load-extension, set before initializing, and
/// for each in the same order the profile folders that load it ("Default|Profile <id>", "*"
/// for every profile), comma-separated; nil when every one loads in every profile.
+ (void)setExtensionPaths:(NSArray<NSString *> *)paths profiles:(nullable NSString *)profiles;
/// `locale` is Chromium's application locale ("zh-CN"); nil leaves CEF's en-US.
+ (BOOL)initializeWithCachePath:(NSString *)cachePath
                 userAgentProduct:(NSString *)product
                          logPath:(NSString *)logPath
                           locale:(nullable NSString *)locale
                   useChromeStyle:(BOOL)useChromeStyle
                  useMockKeychain:(BOOL)useMockKeychain;
/// Runs the Chromium-integrated AppKit run loop. Returns after -quitMessageLoop.
+ (void)runMessageLoop;
+ (void)quitMessageLoop;
+ (void)shutdown;
/// Closes every browser, then quits the message loop once they are gone.
+ (void)closeAllBrowsersAndQuit;
+ (NSInteger)liveBrowserCount;
/// The last incognito window closed: the next incognito page starts a fresh
/// off-the-record profile (no cookies or storage carried over).
+ (void)endIncognitoSession;
/// YES when initialize failed because another Niche is running and was told
/// about this launch (exit quietly).
+ (BOOL)anotherInstanceWasNotified;
/// Called in the running instance when another launch is handed over.
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString *> *urls))handler;
/// Pages Chromium opens on its own (an extension's chrome.tabs.create or
/// windows.create, welcome pages after an extension loads). The handler gets
/// the URL to open as a Niche tab and the Chromium profile folder it came from
/// ("Default", "Profile <id>"; nil off the record); Chrome's own window for it is closed.
/// Popup-type windows (windows.create({type: "popup"})) stay Chrome's windows.
+ (void)setStrayPageHandler:(void (^)(NSString *url, NSString * _Nullable profile))handler;
/// A new tab or window a page asks for (target=_blank, window.open) at another app's address
/// (spotify:): the handler gets the page's browser, the address and whether a click asked, and
/// returns YES when it took it (Niche's "Open <app>?"); then no tab opens (GitHub #207). On the
/// main thread, before Peek and the delegate's popupHostForURL.
+ (void)setAppLinkHandler:(BOOL (^)(NicheBrowser *browser, NSString *url, BOOL userGesture))handler;
/// Where a page's download is saved (GitHub #190): the handler gets the browser's profile folder
/// (nil for Default and off the record) and the file name Chromium suggests, and calls `completion`
/// on the main thread with the full path to save to, or nil to cancel the download (a save panel
/// the user closed). Without a handler downloads go to ~/Downloads.
+ (void)setDownloadDestinationHandler:(void (^)(NSString * _Nullable profilePath, NSString *suggestedName,
                                                void (^completion)(NSString * _Nullable path)))handler;
/// A download by its identifier (NicheDownloadInfo): hold it, carry on (also one that was
/// interrupted, from the bytes it has), or stop it for good. NO when Chromium has nothing left to
/// act on: it finished, was cancelled, or belongs to an earlier run. The change comes back through
/// the delegate's didUpdateDownload.
+ (BOOL)pauseDownload:(uint32_t)identifier;
+ (BOOL)resumeDownload:(uint32_t)identifier;
+ (BOOL)cancelDownload:(uint32_t)identifier;
/// Keep a download Chromium held for the user (NicheDownloadInfo.danger), as Keep in Chrome's
/// download bubble: it finishes and lands where it was going. NO when there is none to keep or
/// no page of its profile is open to ask (the Niche.keepDownload DevTools method).
+ (BOOL)keepDownload:(uint32_t)identifier;
/// Downloads the same address again, as a new download, in the browser it came from (or another
/// one still open). NO when this run never saw the download or no page is open.
+ (BOOL)restartDownload:(uint32_t)identifier;
/// Renderer trouble and failed loads, for Niche's performance recorder (GitHub #91): `kind` is
/// terminated, unresponsive, responsive or loadError; `detail` how it ended or the net error
/// code; `site` the host (nil for incognito, Niche's own pages or a closed tab). Never a URL.
/// On the main thread. Chrome's "Page Unresponsive" dialog still shows.
+ (void)setProcessEventHandler:(void (^)(NSString *kind, NSString *detail, NSString *_Nullable site))handler;
/// YES for a popup window an extension opened (kept by the stray page handling).
+ (BOOL)isExtensionWindow:(NSWindow *)window;
/// YES for the Chrome-style window hosting one of Niche's own browsers.
+ (BOOL)isPageWindow:(NSWindow *)window;
/// Lets one of Chromium's Picture in Picture windows show over another app's full-screen Space,
/// as Arc's non-activating PiP panel does (GitHub #206). Chromium only makes it join every desktop Space.
+ (void)floatOverFullScreenSpaces:(NSWindow *)window;
+ (NSString *)chromiumVersion;
+ (NSString *)cefVersion;
/// YES when the browser-level DevTools pipe is up (it needs fds 3/4 free at start-up).
+ (BOOL)hasBrowserDevTools;
/// Browser-level DevTools protocol call (Target.*, Extensions.*) over the private pipe.
+ (void)sendBrowserDevToolsMethod:(NSString *)method params:(NSString *)params
                       completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// A GET made by the browser itself with a profile's cookies (nil is Default), as a
/// page of that profile would make it: how Arc's and Dia's live folders read github.com
/// with the user's own session. The completion gets the HTTP status (0 when the request
/// failed), the URL after redirects, the MIME type and the body as UTF-8, on the main queue.
+ (void)fetchURL:(NSString *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers
     profilePath:(nullable NSString *)profilePath
      completion:(void (^)(NSInteger status, NSString *finalURL, NSString *mimeType, NSString *body))completion;
/// Same, inside an attached target's session (Target.attachToTarget with flatten).
+ (void)sendBrowserDevToolsMethod:(NSString *)method params:(NSString *)params sessionID:(nullable NSString *)sessionID
                       completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// Protocol events from the pipe: method, params JSON, and the session they belong to.
+ (void)setBrowserDevToolsEventHandler:(nullable void (^)(NSString *method, NSString *params, NSString * _Nullable sessionID))handler;
/// A profile's `extensions.settings` pref as Chromium holds it now (nil profilePath is
/// Default), as JSON. Chromium writes it to Preferences ~10 s after a change. nil until
/// that profile has loaded.
+ (nullable NSString *)extensionSettingsForProfile:(nullable NSString *)profilePath;
/// A profile's pref as Chromium holds it now (nil profilePath is Default), as JSON: how Niche reads
/// `default_search_provider_data.template_url_data`, the engine chrome://settings/searchEngines
/// made the default. nil until that profile has loaded.
+ (nullable NSString *)preference:(NSString *)name forProfile:(nullable NSString *)profilePath;
/// Sets a profile's pref to a JSON value, as chrome://settings would. NO when the profile hasn't
/// loaded, a policy holds the pref, or the value isn't one it takes.
+ (BOOL)setPreference:(NSString *)name json:(NSString *)json forProfile:(nullable NSString *)profilePath;
/// Called on the main queue after a loaded profile's `extensions.settings` changed: an
/// extension installed, enabled, disabled or removed.
+ (void)setExtensionSettingsChangeHandler:(nullable void (^)(void))handler;
@end

/// NSApplication subclass CEF requires (CefAppProtocol). Set as
/// NSPrincipalClass and created with +sharedApplication before anything else.
@interface NicheApplication : NSApplication
@end

NS_ASSUME_NONNULL_END
