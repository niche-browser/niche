import AppKit
import NicheCEF
import SwiftUI

/// Arc's Previews card beside a Gmail or Google Calendar favorite (Arc 1.172.1, measured on
/// the maintainer's signed-in Arc, 8 Nov 2026; NicheCore FavoritePreviewMetrics and FavoritePreviewMotion).
/// It shows a moment after the pointer lands on a tile that isn't the open tab, takes the pointer
/// (rows light up, a click opens the mail or event in the favorite), and goes once the pointer has
/// left both the tile and the card. Gmail's card lists the unread mail with a ＋ for a new one;
/// Calendar's is today's timeline with a gear (Last fetch, Refresh, Disable Live Calendar) and a ＋.
@MainActor
final class FavoritePreviewCard {
    static let shared = FavoritePreviewCard()

    /// The favorite the pointer is on, and what its card can do.
    struct Target {
        var favorite: String
        var profilePath: String?
        /// Loads a URL in the favorite (and selects it).
        var open: (String) -> Void
        /// Opens a URL in a new tab (Join).
        var openNewTab: (String) -> Void
        var disableLiveCalendar: () -> Void = {}
    }

    private var panel: PreviewPanel?
    private weak var tile: NSView?
    private var target: Target?
    private var showWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var wantsShow = false
    private var inbox: [String: GmailPreview.Inbox] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: LiveCalendarClient.changed, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FavoritePreviewCard.shared.contentChanged() }
        }
    }

    // MARK: Pointer

    func hover(_ tile: NSView, target: Target) {
        closeWork?.cancel()
        if self.tile === tile, panel != nil { return }
        if panel != nil { dismiss(animated: false) }
        self.tile = tile
        self.target = target
        wantsShow = false
        showWork?.cancel()
        if let feed = GmailPreview.feedURL(for: target.favorite) {
            fetchMail(feed, profilePath: target.profilePath, for: tile)
        } else if CalendarPreview.isCalendar(target.favorite) {
            LiveCalendarClient.shared.refresh(favorite: target.favorite, profilePath: target.profilePath, ifOlderThan: 60)
        }
        let work = DispatchWorkItem { [weak self, weak tile] in
            guard let self, let tile, self.tile === tile, tile.window != nil else { return }
            self.wantsShow = true
            self.showIfReady()
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FavoritePreviewMotion.showDelay, execute: work)
    }

    func leave(_ tile: NSView) {
        guard self.tile === tile else { return }
        showWork?.cancel()
        scheduleClose()
    }

    /// The tile was clicked, or its window went: the card goes at once.
    func cancel(_ tile: NSView) {
        guard self.tile === tile else { return }
        dismiss(animated: false)
    }

    fileprivate func pointerEnteredCard() { closeWork?.cancel() }
    fileprivate func pointerLeftCard() { scheduleClose() }

    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            if let panel = self.panel, panel.frame.contains(p), panel.cardFrame.contains(p) { return }
            if let tile = self.tile, let w = tile.window, w.convertToScreen(tile.convert(tile.bounds, to: nil)).contains(p) { return }
            self.dismiss(animated: true)
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FavoritePreviewMotion.closeDelay, execute: work)
    }

    func dismiss(animated: Bool) {
        showWork?.cancel()
        closeWork?.cancel()
        wantsShow = false
        tile = nil
        target = nil
        guard let p = panel else { return }
        panel = nil
        p.close(animated: animated)
    }

    // MARK: Content

    private func fetchMail(_ feed: String, profilePath: String?, for tile: NSView) {
        NicheCEFRuntime.fetchURL(feed, headers: nil, profilePath: profilePath) { status, _, _, body in
            MainActor.assumeIsolated {
                // Arc shows its "exhale" card whenever it has no unread mail to list, signed out
                // included (seen on a space with no Google sign-in, 7 Nov 2026).
                let parsed = status == 200 ? GmailPreview.parse(body) : nil
                let key = feed + "|" + (profilePath ?? "")
                let new = parsed ?? self.inbox[key] ?? GmailPreview.Inbox(unread: 0, mails: [])
                self.inbox[key] = new
                guard self.tile === tile else { return }
                if self.panel != nil { self.refreshPanel() } else { self.showIfReady() }
            }
        }
    }

    private func contentChanged() {
        guard let target, CalendarPreview.isCalendar(target.favorite) else { return }
        if panel != nil { refreshPanel() } else { showIfReady() }
    }

    private func content() -> AnyView? {
        guard let target else { return nil }
        if let feed = GmailPreview.feedURL(for: target.favorite) {
            guard let inbox = inbox[feed + "|" + (target.profilePath ?? "")] else { return nil }
            return AnyView(GmailPreviewView(inbox: inbox, now: Date(), open: { [weak self] in self?.open($0) },
                                            compose: { [weak self] in GmailPreview.composeURL(for: target.favorite).map { self?.open($0) } }))
        }
        if CalendarPreview.isCalendar(target.favorite) {
            let state = LiveCalendarClient.shared.state(for: target.favorite, profilePath: target.profilePath)
            // Arc's card shows its timeline whether or not the fetch worked; Niche waits for a first answer.
            guard let state else { return nil }
            return AnyView(CalendarPreviewView(state: state, now: Date(), actions: calendarActions(target)))
        }
        return nil
    }

    private func calendarActions(_ target: Target) -> CalendarPreviewView.Actions {
        CalendarPreviewView.Actions(
            open: { [weak self] in self?.open($0) },
            join: { [weak self] url in self?.dismiss(animated: false); target.openNewTab(url) },
            newEvent: { [weak self] in CalendarPreview.newEventURL(for: target.favorite).map { self?.open($0) } },
            gear: { [weak self] point in self?.gearMenu(target, at: point) },
            signIn: { [weak self] in self?.open(target.favorite) })
    }

    private func open(_ url: String) {
        let t = target
        dismiss(animated: false)
        t?.open(url)
    }

    /// Arc's gear on the Calendar card: Last fetch, Refresh, then Disable Live Calendar.
    private func gearMenu(_ target: Target, at point: CGPoint) {
        guard let panel else { return }
        let m = NSMenu()
        m.autoenablesItems = false
        let fetched = LiveCalendarClient.shared.state(for: target.favorite, profilePath: target.profilePath)?.fetched
        MenuItems.add(m, CalendarPreview.lastFetch(fetched, now: Date()), enabled: false) {}
        MenuItems.add(m, "Refresh") { LiveCalendarClient.shared.refresh(favorite: target.favorite, profilePath: target.profilePath) }
        m.addItem(.separator())
        MenuItems.add(m, "Disable Live Calendar") { [weak self] in
            self?.dismiss(animated: false)
            target.disableLiveCalendar()
        }
        guard let view = panel.contentView else { return }
        // The menu holds the pointer: keep the card while it is up.
        closeWork?.cancel()
        m.popUp(positioning: nil, at: view.convert(point, from: nil), in: view)
        scheduleClose()
    }

    private func showIfReady() {
        guard wantsShow, panel == nil, let tile, let window = tile.window, let view = content() else { return }
        let p = PreviewPanel(content: view)
        let t = window.convertToScreen(tile.convert(tile.bounds, to: nil))
        // Arc: the card's left edge 4 pt in from the tile's right edge, its top 3.5 pt above the tile's bottom.
        p.place(cardTopLeft: NSPoint(x: t.maxX - 4, y: t.minY + 3.5))
        window.addChildWindow(p, ordered: .above)
        p.open()
        panel = p
    }

    private func refreshPanel() {
        guard let panel, let view = content() else { return }
        panel.replace(view)
    }

    // MARK: Testing

    /// niche://debug?gmailPreview=<unread>: the card for a sample inbox where Arc's 264 pt sidebar
    /// has its fourth favorite tile.
    func demoGmail(unread: Int, in window: NSWindow) {
        let now = Date()
        let mails = (0..<min(unread, 20)).map {
            GmailPreview.Mail(from: "Sender \($0 + 1)", subject: "Subject line \($0 + 1)", snippet: "The first lines of mail \($0 + 1), long enough to run onto a second line of the card.",
                              received: now.addingTimeInterval(-Double($0 + 1) * 2400))
        }
        let favorite = "https://mail.google.com/mail/u/0/"
        inbox[GmailPreview.feedURL(for: favorite)! + "|"] = GmailPreview.Inbox(unread: unread, mails: mails)
        demo(favorite, in: window)
    }

    /// niche://debug?calendarPreview=1: today's card with a meeting starting in 90 s and two
    /// overlapping events, as if fetched.
    func demoCalendar(in window: NSWindow) {
        let favorite = "https://calendar.google.com/calendar/u/0/r"
        let now = Date()
        let events = [
            CalendarPreview.Event(title: "Design review", start: now.addingTimeInterval(90), end: now.addingTimeInterval(90 + 1800),
                                  meetingURL: "https://meet.google.com/niche-demo"),
            CalendarPreview.Event(title: "Lunch", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000)),
            CalendarPreview.Event(title: "Call with Ada", start: now.addingTimeInterval(7800), end: now.addingTimeInterval(9600),
                                  meetingURL: "https://zoom.us/j/1"),
        ]
        LiveCalendarClient.shared.setDemo(events, favorite: favorite, profilePath: nil)
        demo(favorite, in: window)
    }

    private func demo(_ favorite: String, in window: NSWindow) {
        guard let content = window.contentView else { return }
        dismiss(animated: false)
        let anchor = NSView(frame: NSRect(x: 200, y: content.bounds.height - 44 - FavoritesLayout.tileHeight, width: 56, height: FavoritesLayout.tileHeight))
        content.addSubview(anchor)
        tile = anchor
        target = Target(favorite: favorite, profilePath: nil, open: { NicheLog.note("preview opens \($0)") },
                        openNewTab: { NicheLog.note("preview joins \($0)") })
        wantsShow = true
        showIfReady()
        anchor.removeFromSuperview()
        NicheLog.note("preview card shown: \(panel.map { "\(Int($0.cardFrame.width))x\(Int($0.cardFrame.height))" } ?? "none")")
    }
}

// MARK: - Join reminder

/// Live Calendar's Show Next Meeting Link: from the chosen lead (Arc's default, two minutes
/// before) until the call ends, a card beside the Calendar favorite names the meeting with a Join
/// button and a close button (Arc's LiveCalendarReminder; its look isn't visible in Arc 1.172.1,
/// whose calendar no longer reads, so the card is Niche's, in the preview card's style).
@MainActor
final class MeetingReminder {
    static let shared = MeetingReminder()
    private var panel: PreviewPanel?
    private var shown: String?

    func update(tile: NSView, favorite: String?, events: [CalendarPreview.Event], timing: CalendarPreview.LinkTiming, join: @escaping (String) -> Void) {
        let meeting = favorite == nil ? nil : CalendarPreview.meetingToJoin(in: events, now: Date(), timing: timing,
                                                                            dismissed: LiveCalendarClient.shared.dismissed)
        guard let meeting, let url = meeting.meetingURL, let window = tile.window, window.isVisible else {
            if meeting == nil { close() }
            return
        }
        let key = CalendarPreview.key(meeting)
        let view = AnyView(MeetingReminderView(event: meeting, now: Date(),
                                               join: { [weak self] in self?.close(); LiveCalendarClient.shared.dismiss(meeting); join(url) },
                                               dismiss: { [weak self] in self?.close(); LiveCalendarClient.shared.dismiss(meeting) }))
        if let panel, shown == key { panel.replace(view); return }
        close()
        let p = PreviewPanel(content: view)
        let t = window.convertToScreen(tile.convert(tile.bounds, to: nil))
        p.place(cardTopLeft: NSPoint(x: t.maxX - 4, y: t.minY + 3.5))
        window.addChildWindow(p, ordered: .above)
        p.open()
        panel = p
        shown = key
        NicheLog.note("meeting link shown: \(meeting.title)")
    }

    func close() {
        panel?.close(animated: true)
        panel = nil
        shown = nil
    }
}

private struct MeetingReminderView: View {
    let event: CalendarPreview.Event
    let now: Date
    let join: () -> Void
    let dismiss: () -> Void

    private var when: String {
        let s = Int(event.start.timeIntervalSince(now))
        if s <= 0 { return "Now · " + CalendarPreview.timeRange(event) }
        return "In \(max(1, Int(ceil(Double(s) / 60)))) min · " + CalendarPreview.timeRange(event)
    }

    var body: some View {
        CardStyle.card(
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: Design.Space.xxs) {
                    Text(event.title).font(Design.Font.ui(.body, .semibold)).foregroundStyle(CardStyle.text).lineLimit(1)
                    Text(when).font(Design.Font.caption).foregroundStyle(CardStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Join").font(Design.Font.ui(.detail, .semibold))
                    .padding(.horizontal, Design.Space.l).padding(.vertical, 5)
                    .background(Capsule().fill(CalendarPreviewView.nowColor))
                    .foregroundStyle(CardStyle.onNow)
                    .contentShape(Capsule())
                    .onTapGesture(perform: join)
                    .accessibilityAddTraits(.isButton)
                Image(systemName: "xmark").font(Design.Font.ui(.micro, .bold)).foregroundStyle(CardStyle.secondary)
                    .frame(width: 18, height: 18).contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)
                    .accessibilityLabel("Dismiss")
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, FavoritePreviewMetrics.inset).padding(.vertical, 10)
            .frame(width: FavoritePreviewMetrics.width))
    }
}

// MARK: - Panel

/// The card's window: no key, no title, the card inset by room for its shadow; it scales and
/// fades as Arc's does (the window's own shadow couldn't follow the scale, so the card draws one).
private final class PreviewPanel: NSPanel {
    static let margin: CGFloat = 24
    private let card = NSView()
    private var host: NSHostingView<AnyView>

    init(content: AnyView) {
        host = FirstMouseHostingView(rootView: content)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        let root = TrackingView()
        root.wantsLayer = true
        contentView = root
        card.wantsLayer = true
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.35
        card.layer?.shadowRadius = 10
        card.layer?.shadowOffset = CGSize(width: 0, height: -4)
        root.addSubview(card)
        card.addSubview(host)
        fit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The card on screen (the window is larger, for the shadow).
    var cardFrame: NSRect { frame.insetBy(dx: Self.margin, dy: Self.margin) }

    private func fit() {
        let size = host.fittingSize
        let m = Self.margin
        setContentSize(NSSize(width: size.width + 2 * m, height: size.height + 2 * m))
        card.frame = NSRect(x: m, y: m, width: size.width, height: size.height)
        host.frame = card.bounds
        card.layer?.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: CardStyle.radius, cornerHeight: CardStyle.radius, transform: nil)
        (contentView as? TrackingView)?.cardRect = card.frame
    }

    func place(cardTopLeft p: NSPoint) {
        setFrameTopLeftPoint(NSPoint(x: p.x - Self.margin, y: p.y + Self.margin))
    }

    func replace(_ view: AnyView) {
        let top = NSPoint(x: frame.minX, y: frame.maxY)
        host.rootView = view
        fit()
        setFrameTopLeftPoint(top)
    }

    /// Arc's opening: from about 80 % about a point near the tile, fading in, some 4 frames.
    func open() {
        orderFront(nil)
        guard let layer = card.layer else { return }
        setAnchor(layer)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = FavoritePreviewMotion.openScale
            grow.toValue = 1
            animations.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = FavoritePreviewMotion.openDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "open")
    }

    func close(animated: Bool) {
        parent?.removeChildWindow(self)
        guard animated, let layer = card.layer else { orderOut(nil); return }
        setAnchor(layer)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.orderOut(nil) }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : FavoritePreviewMotion.closeScale
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = FavoritePreviewMotion.closeDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "close")
        CATransaction.commit()
    }

    /// The scale's fixed point: a third of the way in, near the top (measured from Arc's frames).
    private func setAnchor(_ layer: CALayer) {
        let anchor = CGPoint(x: 0.33, y: 0.86)
        let f = card.frame
        layer.anchorPoint = anchor
        layer.position = CGPoint(x: f.minX + anchor.x * f.width, y: f.minY + anchor.y * f.height)
    }
}

/// Clicks in the card act at once, though its window never becomes key (Arc's
/// HostingViewAcceptingFirstMouse).
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Tells the card's controller when the pointer comes onto the card and leaves it.
private final class TrackingView: NSView {
    var cardRect: NSRect = .zero { didSet { updateTrackingAreas() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: cardRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { FavoritePreviewCard.shared.pointerEnteredCard() } }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { FavoritePreviewCard.shared.pointerLeftCard() } }
}

// MARK: - Views

private enum CardStyle {
    static let radius = Design.Radius.control
    static let fill = Design.graphite
    static let edge = Color(red: 63 / 255, green: 62 / 255, blue: 60 / 255)
    static let line = Color(nsColor: Design.hairlineOnDark)
    static let text = Design.onDarkColor(.primary)
    static let secondary = Design.onDarkColor(.secondary)
    static let hover = Design.fillOnDarkColor(.hover)
    /// Ink on the cream of the now line (a Join capsule).
    static let onNow = Design.onLightColor(.primary)
    /// The round buttons: an opaque dark disc with a light rim (＋) or a lighter wash (gear), each
    /// a step brighter under the pointer.
    static let button = Color(white: 0.14)
    static let buttonHover = Color(white: 0.2)
    static let buttonRim = Design.fillOnDarkColor(.pressed)
    static let buttonLight = Color.white.opacity(0.24)
    static let buttonLightHover = Color.white.opacity(0.3)
    /// An event's block: opaque, over the hour lines and the now line.
    static let event = Color(white: 0.22)
    static let eventHover = Color(white: 0.27)

    static func card<V: View>(_ v: V) -> some View {
        v.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }
}

/// Arc's round buttons at the card's bottom right: 32 pt, dark with a light rim (＋), or lighter (gear).
private struct RoundButton: View {
    let symbol: String
    var light = false
    var label: String
    let run: (CGPoint) -> Void
    @State private var hovered = false

    var body: some View {
        GeometryReader { g in
            Circle()
                .fill(light ? (hovered ? CardStyle.buttonLightHover : CardStyle.buttonLight) : (hovered ? CardStyle.buttonHover : CardStyle.button))
                .overlay(Circle().strokeBorder(light ? Color.clear : CardStyle.buttonRim, lineWidth: 1))
                .overlay(Image(systemName: symbol).font(Design.Font.ui(.title, .semibold)).foregroundStyle(CardStyle.text))
                .shadow(color: Color(nsColor: Design.Shadow.cardColor), radius: Design.Shadow.cardRadius, y: Design.Shadow.cardOffset)
                .contentShape(Circle())
                .onHover { hovered = $0 }
                .onTapGesture {
                    let f = g.frame(in: .global)
                    run(CGPoint(x: f.midX, y: f.maxY))
                }
        }
        .frame(width: FavoritePreviewMetrics.buttonSize, height: FavoritePreviewMetrics.buttonSize)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

private struct GmailPreviewView: View {
    let inbox: GmailPreview.Inbox
    let now: Date
    let open: (String) -> Void
    let compose: () -> Void

    var body: some View {
        if inbox.mails.isEmpty { empty } else { list }
    }

    /// Arc's "exhale" card (docs/screenshots/arc-gmail-preview-empty.png): 240 pt wide, the line
    /// centred 23.5 pt down, the leaf 38.5 pt, the card 62.5 pt tall.
    private var empty: some View {
        CardStyle.card(
            VStack(spacing: -2) {
                Text(GmailPreview.emptyText).font(Design.Font.body).multilineTextAlignment(.center)
                Text("🍃").font(Design.Font.body)
            }
            .foregroundStyle(CardStyle.secondary)
            .padding(.vertical, 15.5).padding(.horizontal, Design.Space.xl)
            .frame(width: 240))
    }

    private var list: some View {
        let rowStep = FavoritePreviewMetrics.mailRowHeight + 1
        let height = min(CGFloat(inbox.mails.count) * rowStep - 1, FavoritePreviewMetrics.maxHeight)
        return CardStyle.card(
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(inbox.mails.enumerated()), id: \.offset) { i, mail in
                            if i > 0 { Rectangle().fill(CardStyle.line).frame(height: 1) }
                            MailRow(mail: mail, now: now) { mail.link.map(open) }
                        }
                    }
                }
                RoundButton(symbol: "plus", label: "New Email") { _ in compose() }
                    .padding(FavoritePreviewMetrics.buttonInset)
            }
            .frame(width: FavoritePreviewMetrics.width, height: height))
    }
}

/// Arc's mail row: sender and age, the subject, two lines of the mail, 11 pt in.
private struct MailRow: View {
    let mail: GmailPreview.Mail
    let now: Date
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                Text(mail.from).font(Design.Font.ui(.body, .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let r = mail.received { Text(GmailPreview.age(of: r, now: now)).font(Design.Font.body) }
            }
            .foregroundStyle(CardStyle.text)
            Text(mail.subject).font(Design.Font.body).foregroundStyle(CardStyle.text).lineLimit(1)
            Text(mail.snippet).font(Design.Font.detail).foregroundStyle(CardStyle.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, FavoritePreviewMetrics.inset)
        .padding(.top, 8.5)
        .frame(maxWidth: .infinity, minHeight: FavoritePreviewMetrics.mailRowHeight, maxHeight: FavoritePreviewMetrics.mailRowHeight, alignment: .topLeading)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(CardStyle.hover).padding(FavoritePreviewMetrics.hoverInset)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Arc's Calendar card: today from the current hour, an hour per 42 pt with its label at the top
/// left, a cream now line with a dot, the events in columns where they overlap, and the gear and
/// ＋ at the bottom right.
struct CalendarPreviewView: View {
    struct Actions {
        var open: (String) -> Void
        var join: (String) -> Void
        var newEvent: () -> Void
        var gear: (CGPoint) -> Void
        var signIn: () -> Void
    }

    let state: LiveCalendarClient.State
    let now: Date
    let actions: Actions

    static let nowColor = Color(red: 1, green: 0.94, blue: 0.78)

    var body: some View {
        if state.signedOut { signIn } else { timeline }
    }

    /// Arc's CalendarPreviewLoginView: a sign-in, in the card's style.
    private var signIn: some View {
        CardStyle.card(
            VStack(spacing: Design.Space.m) {
                Text("Sign in to Google Calendar to see today's meetings here.")
                    .font(Design.Font.body).multilineTextAlignment(.center).foregroundStyle(CardStyle.secondary)
                Button("Sign In", action: actions.signIn).buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.vertical, 14).padding(.horizontal, Design.Space.xl)
            .frame(width: FavoritePreviewMetrics.width))
    }

    private var timeline: some View {
        let hour = FavoritePreviewMetrics.hourHeight
        let placed = CalendarPreview.layout(state.events, day: now, hourHeight: hour)
        return CardStyle.card(
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { scroller in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(0..<24, id: \.self) { h in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Rectangle().fill(CardStyle.line).frame(height: 1)
                                        Text(CalendarPreview.hourLabel(h)).font(Design.Font.caption).foregroundStyle(CardStyle.secondary)
                                            .padding(.leading, 5).padding(.top, 3)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: hour)
                                    .id(h)
                                }
                            }
                            GeometryReader { g in
                                let width = g.size.width - FavoritePreviewMetrics.eventsLeft - FavoritePreviewMetrics.eventsRight
                                // The now line under the events, so it never runs through a title; its dot stays clear of them.
                                nowLine(width: g.size.width).offset(y: nowY(hour) - 3)
                                ForEach(Array(placed.enumerated()), id: \.offset) { _, p in
                                    let w = width / CGFloat(p.columns)
                                    EventBlock(event: p.event, now: now, compact: p.height < 30, join: actions.join, open: actions.open)
                                        .frame(width: max(0, w - 2), height: max(0, p.height - 2), alignment: .topLeading)
                                        .clipped()
                                        .offset(x: FavoritePreviewMetrics.eventsLeft + CGFloat(p.column) * w, y: p.top + 1)
                                }
                            }
                        }
                        .frame(height: 24 * hour)
                        .background(GeometryReader { _ in Color.clear.onAppear { scrollToNow(scroller) } })
                    }
                }
                HStack(spacing: FavoritePreviewMetrics.buttonGap) {
                    RoundButton(symbol: "gearshape.fill", light: true, label: "Calendar Settings", run: actions.gear)
                    RoundButton(symbol: "plus", label: "New Event") { _ in actions.newEvent() }
                }
                .padding(FavoritePreviewMetrics.buttonInset)
            }
            .frame(width: FavoritePreviewMetrics.width, height: FavoritePreviewMetrics.calendarHeight))
    }

    private func nowY(_ hour: CGFloat) -> CGFloat {
        CGFloat(now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 3600) * hour
    }

    private func nowLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle().fill(Self.nowColor).frame(width: 6, height: 6)
            Rectangle().fill(Self.nowColor).frame(height: 1.5)
        }
        .padding(.leading, FavoritePreviewMetrics.eventsLeft - 3)
        .padding(.trailing, FavoritePreviewMetrics.eventsRight)
        .frame(width: width, height: 6)
    }

    /// The current hour's line 13 pt under the card's top, as Arc opens it.
    private func scrollToNow(_ scroller: ScrollViewProxy) {
        let h = Calendar.current.component(.hour, from: now)
        let anchor = UnitPoint(x: 0, y: 13 / FavoritePreviewMetrics.calendarHeight)
        DispatchQueue.main.async { scroller.scrollTo(h, anchor: anchor) }
    }
}

/// An event on the timeline: its title and time; a call has a Join button.
private struct EventBlock: View {
    let event: CalendarPreview.Event
    let now: Date
    /// Under half an hour: the title and start on one line.
    let compact: Bool
    let join: (String) -> Void
    let open: (String) -> Void
    @State private var hovered = false

    var body: some View {
        let past = event.end <= now
        HStack(alignment: compact ? .center : .top, spacing: Design.Space.xs) {
            if compact {
                (Text(event.title).font(Design.Font.ui(.caption, .semibold))
                    + Text("  " + CalendarPreview.timeRange(event)).font(Design.Font.ui(.micro)).foregroundColor(CardStyle.secondary))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: Design.Space.hair) {
                    Text(event.title).font(Design.Font.ui(.caption, .semibold)).lineLimit(1)
                    Text(CalendarPreview.timeRange(event)).font(Design.Font.ui(.micro)).foregroundStyle(CardStyle.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL, !past {
                Text("Join").font(Design.Font.ui(.micro, .semibold))
                    .padding(.horizontal, Design.Space.s).padding(.vertical, compact ? 0 : Design.Space.xxs)
                    .background(Capsule().fill(CalendarPreviewView.nowColor))
                    .foregroundStyle(CardStyle.onNow)
                    .contentShape(Capsule())
                    .onTapGesture { join(url) }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .foregroundStyle(CardStyle.text)
        .padding(.horizontal, 5).padding(.vertical, compact ? 0 : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
        // Opaque, over the hour lines and the now line.
        .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(hovered ? CardStyle.eventHover : CardStyle.event))
        .opacity(past ? Design.Opacity.dimmed : 1)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { event.link.map(open) }
        .accessibilityElement(children: .combine)
    }
}
