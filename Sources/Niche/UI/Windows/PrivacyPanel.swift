import AppKit
import SwiftUI

/// The privacy panel's own measures.
enum PrivacyPanelMetrics {
    /// The card's width beside the page.
    static let width: CGFloat = 360
    static let headerHeight: CGFloat = 44
    /// The diagram: its height, the page's disc in the middle, the ring where the parties that got
    /// through sit, the shield, and the ring outside it for the ones kept out.
    static let orbitHeight: CGFloat = 216
    static let orbitCentre: CGFloat = 46
    static let orbitInner: CGFloat = 48
    static let orbitShield: CGFloat = 72
    static let orbitOuter: CGFloat = 96
    static let orbitShieldLine: CGFloat = 2
    /// The shield's glow, and how far the ring that leaves it when something is blocked travels.
    static let orbitGlow: CGFloat = 10
    static let orbitGlowStrength: CGFloat = 0.45
    static let orbitPulseScale: CGFloat = 1.42
    static let orbitPulseStrength: CGFloat = 0.55
    static let orbitPulseTime: TimeInterval = 0.9
    /// The dim end of the shield's sweep of colour.
    static let orbitSweepLow: CGFloat = 0.35
    /// A party's chip, with its initial: one that sees the visit, one kept out, one that only
    /// makes the page work.
    static let chipSeen: CGFloat = 22
    static let chipBlocked: CGFloat = 20
    static let chipOther: CGFloat = 18
    /// Chips drawn per ring; a page with more shows the first of them and "+N".
    static let orbitInside = 9
    static let orbitOutside = 12
    /// The plate in front of a party's name and of a line of the report.
    static let glyphPlate: CGFloat = 28
    /// Lines of the live feed shown.
    static let feedLines = 7
    /// The dot in front of a feed line and a legend entry.
    static let toneDot: CGFloat = 7
    /// How strongly a state's colour tints the plate and pill behind it.
    static let tintWash: CGFloat = 0.14
    /// The hero card's wash of its state's colour, top and bottom.
    static let heroWashTop: CGFloat = 0.16
    static let heroWashBottom: CGFloat = 0.02
    /// The line from the page to a party that only makes it work.
    static let faintLine: CGFloat = 0.5
    /// A party that sees the visit: its line's strength.
    static let seenLine: CGFloat = 0.55
    /// The bar that shows what kinds of companies are on the page.
    static let kindsBar: CGFloat = 8
    /// The week's chart at the foot: a day's bar and the tallest one.
    static let chartBar: CGFloat = 10
    static let chartHeight: CGFloat = 34
    static let chartFloor: CGFloat = 3
    /// A day of the chart that is not today.
    static let chartPast: CGFloat = 0.38
    /// The "Live" dot's slow breath.
    static let liveBreath: TimeInterval = 1.4
    static let liveLow: CGFloat = 0.35
}

/// What the panel shows, set by its window: the tab on screen and why there may be nothing to say.
@MainActor
@Observable
final class PrivacyPanelModel {
    var tabID: UUID?
    var pageURL = ""
    /// Why the panel has nothing for this tab (Niche's own page, Safari's engine); nil for a website.
    var unavailable: String?
    /// The site's icon, for the middle of the diagram.
    var favicon: NSImage?
    /// Which protections Settings ▸ Privacy has on.
    var protections = PrivacyProtections()
    /// Settings ▸ Privacy "Filtering": the mode every site has unless it has its own.
    var standardMode = FilteringMode.standard
    /// False in an incognito window: what is chosen here is not written down.
    var remembersChoices = true
    /// When the user last changed a rule or the site's switch while a tab was showing.
    var ruleChangedAt: [UUID: Date] = [:]
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onReload: () -> Void = {}
    @ObservationIgnored var onSettings: () -> Void = {}

    var site: String? { PrivacySite.site(ofURL: pageURL) }
    var secure: Bool { pageURL.lowercased().hasPrefix("https:") }

    var ledger: PrivacyLedger? {
        _ = PrivacyMonitor.shared.revision
        return tabID.flatMap { PrivacyMonitor.shared.ledger(tab: $0, pageURL: pageURL) }
    }

    /// A rule changed since the page loaded: rules apply to what is asked for next, so what is
    /// shown is how the page was let in before. Every page is recorded from its first request,
    /// so this is the only time the panel asks for a reload.
    var reloadHint: String? {
        guard let tabID, let ledger, let changed = ruleChangedAt[tabID], changed > ledger.started else { return nil }
        return "Reload the page for this to take effect."
    }

    func ruleChanged() {
        if let tabID { ruleChangedAt[tabID] = Date() }
    }
}

/// The panel's card at the right of the panes: rounded and shadowed like a page's card, with the
/// SwiftUI panel inside. The panel is live but small, and everything in it is rows and words.
final class PrivacyPanelCard: NSView {
    let model = PrivacyPanelModel()
    private let shadowView = CardShadowView()
    private var host: NSHostingView<PrivacyPanelView>?
    var cornerRadius: CGFloat = NicheMetrics.contentCornerRadius {
        didSet { layer?.cornerRadius = cornerRadius; syncShadow() }
    }
    var castsShadow = true { didSet { syncShadow() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        let host = NSHostingView(rootView: PrivacyPanelView(model: model))
        host.autoresizingMask = [.width, .height]
        host.frame = bounds
        addSubview(host)
        self.host = host
        setAccessibilityElement(false)
        setAccessibilityLabel("Privacy")
    }

    required init?(coder: NSCoder) { fatalError() }

    // The same shadow as a page card (PaneCardView): a sibling behind it.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let superview {
            if shadowView.superview !== superview { superview.addSubview(shadowView, positioned: .below, relativeTo: self) }
        } else {
            shadowView.removeFromSuperview()
        }
        syncShadow()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); syncShadow() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); syncShadow() }
    override var isHidden: Bool { didSet { syncShadow() } }

    private func syncShadow() {
        let on = castsShadow && cornerRadius > 0 && !isHidden && superview != nil
        shadowView.isHidden = !on
        guard on else { return }
        shadowView.cornerRadius = cornerRadius
        let f = frame.insetBy(dx: -CardShadowView.pad, dy: -CardShadowView.pad)
        if shadowView.frame != f { shadowView.frame = f }
    }
}

/// The privacy panel: what the page on screen did, in words anyone can read. Top to bottom: where
/// the page stands, over a diagram of who got through the shield and who was kept out, and the
/// three counts; what each of Niche's protections did here; the switch for this site; what kinds
/// of companies are on the page; every company with what it learned and a way to block or allow
/// it; what is happening now; and how much Niche has blocked this week and in all.
struct PrivacyPanelView: View {
    let model: PrivacyPanelModel
    @State private var expanded: Set<String> = []
    private let monitor = PrivacyMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Design.hairline).frame(height: Design.Space.hair)
            if let reason = model.unavailable {
                PrivacyEmptyState(symbol: "shield.slash", title: "Nothing to watch here", detail: reason)
            } else if let ledger = model.ledger, let site = model.site {
                content(ledger, site: site)
            } else {
                PrivacyEmptyState(symbol: "shield", title: "Nothing to watch here", detail: "Open a website to see who it talks to.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Design.accent)
        // The card sits under the window's title bar area; it is not part of it.
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: Design.Space.m) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: Design.Icon.bar, weight: .medium))
                .foregroundStyle(Design.accent)
                .accessibilityHidden(true)
            Text("Privacy").font(Design.Font.section)
            PrivacyLiveBadge()
            Spacer()
            Button(action: model.onSettings) {
                Image(systemName: "gearshape").font(.system(size: Design.Icon.regular))
            }
            .buttonStyle(PrivacyIconButtonStyle())
            .help("Privacy Settings")
            .accessibilityLabel("Privacy Settings")
            Button(action: model.onClose) {
                Image(systemName: "xmark").font(.system(size: Design.Icon.small, weight: .semibold))
            }
            .buttonStyle(PrivacyIconButtonStyle())
            .help("Close Privacy Panel")
            .accessibilityLabel("Close Privacy Panel")
        }
        .padding(.horizontal, Design.Space.xl)
        .frame(height: PrivacyPanelMetrics.headerHeight)
    }

    private func content(_ ledger: PrivacyLedger, site: String) -> some View {
        let summary = ledger.summary
        let parties = ledger.sorted
        let off = monitor.rules.isOff(on: site)
        return ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Design.Space.xl) {
                    PrivacyHero(site: site, favicon: model.favicon, standing: PrivacyReport.standing(summary, siteOff: off),
                                summary: summary, parties: parties, shielded: !off) { id in
                        expanded.insert(id)
                        withAnimation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.standard)) { scroller.scrollTo(id, anchor: .center) }
                    }
                    if let hint = model.reloadHint {
                        PrivacyReloadHint(text: hint, reload: model.onReload)
                    }
                    PrivacySection("On this page") {
                        PrivacyReportCard(rows: PrivacyReport.rows(summary, protections: model.protections, siteOff: off, secure: model.secure))
                    }
                    filtering(site: site)
                    if summary.parties > 1 {
                        PrivacySection("Who is here") { PrivacyKinds(kinds: summary.kinds, total: summary.parties) }
                    }
                    if !parties.isEmpty { partyList(parties, site: site) }
                    if !ledger.feed.isEmpty { PrivacyFeed(items: ledger.feed) }
                    PrivacyTotals(stats: monitor.stats)
                }
                .padding(Design.Space.xl)
            }
            .scrollIndicators(.automatic)
        }
    }

    /// The site's filtering slider (uBlock Origin Lite's modes): Off lets everything through
    /// there, the others say how much Shields does. A site left at the mode for every site
    /// follows Settings; one moved keeps its own, and says so.
    private func filtering(site: String) -> some View {
        let own = monitor.rules.ownMode(on: site)
        let mode = own ?? model.standardMode
        return VStack(alignment: .leading, spacing: Design.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Filtering on this site").font(Design.Font.control)
                Spacer(minLength: Design.Space.m)
                if own != nil {
                    Button("Use My Setting") {
                        monitor.setMode(model.standardMode, on: site, standard: model.standardMode, remembered: model.remembersChoices)
                        model.ruleChanged()
                    }
                    .buttonStyle(.link)
                    .font(Design.Font.detail)
                    .help("Go back to \(model.standardMode.title), the mode for every site in Settings ▸ Privacy")
                }
            }
            FilteringSlider(modes: FilteringMode.allCases, mode: mode) { picked in
                monitor.setMode(picked, on: site, standard: model.standardMode, remembered: model.remembersChoices)
                model.ruleChanged()
            }
            Text(mode == .none ? "Off: ads, trackers and their cookies get through on \(site)." : mode.detail)
                .font(Design.Font.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Space.l)
        .privacyCard()
    }

    private func partyList(_ parties: [PrivacyLedger.Party], site: String) -> some View {
        let seen = parties.filter { $0.listing == .seesYou }
        let blocked = parties.filter { $0.listing == .blocked }
        let others = parties.filter { $0.listing == .other }
        return VStack(alignment: .leading, spacing: Design.Space.xl) {
            group("Can see this visit", seen, site: site)
            group("Blocked", blocked, site: site)
            group("Also on this page", others, site: site)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ parties: [PrivacyLedger.Party], site: String) -> some View {
        if !parties.isEmpty {
            PrivacySection(title, count: parties.count) {
                VStack(spacing: 0) {
                    ForEach(Array(parties.enumerated()), id: \.element.id) { i, party in
                        if i > 0 { Rectangle().fill(Design.hairline).frame(height: Design.Space.hair).padding(.leading, Design.Space.l + PrivacyPanelMetrics.glyphPlate + Design.Space.l) }
                        PrivacyPartyRow(party: party, pageSite: site, choice: monitor.rules.choice(for: party.id, on: site),
                                        expanded: expanded.contains(party.id),
                                        toggle: { if !expanded.insert(party.id).inserted { expanded.remove(party.id) } },
                                        choose: { choice in
                                            monitor.setChoice(choice, for: party.id, on: site, remembered: model.remembersChoices)
                                            model.ruleChanged()
                                        })
                        .id(party.id)
                    }
                }
                .privacyCard()
            }
        }
    }
}

private extension View {
    /// The panel's card: a soft fill with a hairline round it.
    func privacyCard() -> some View {
        background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(Design.fill(.subtle)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).strokeBorder(Design.hairline))
    }
}

/// A titled part of the panel, with how many things are in it when that says something.
private struct PrivacySection<Content: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder let content: Content

    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            HStack(spacing: Design.Space.s) {
                Text(title).font(Design.Font.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let count {
                    Text("\(count)").font(Design.Font.caption).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, Design.Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A report line's or a party's colour by what happened: kept out, seen, or neither.
private enum PrivacyTone {
    static func color(_ tone: PrivacyLedger.FeedItem.Tone) -> Color {
        switch tone {
        case .blocked, .cleaned: Design.positive
        case .saw: Design.danger
        case .neutral: Design.inkColor(.tertiary)
        }
    }

    static func color(_ party: PrivacyLedger.Party) -> Color {
        switch party.listing {
        case .blocked: return Design.positive
        case .seesYou: return Design.danger
        case .other: return Design.inkColor(.secondary)
        }
    }

    static func color(_ tone: PrivacyReport.Tone) -> Color {
        switch tone {
        case .good: Design.positive
        case .bad: Design.danger
        case .quiet: Design.inkColor(.secondary)
        case .off: Design.inkColor(.tertiary)
        }
    }

    /// A kind of company in the "Who is here" bar: the kinds that track each have a colour, what
    /// makes the page work is grey.
    static func color(_ category: TrackerCategory) -> Color {
        switch category {
        case .sessionRecording: Color(nsColor: .systemPink)
        case .fingerprinting: Color(nsColor: .systemPurple)
        case .dataBroker: Color(nsColor: .systemIndigo)
        case .advertising: Design.danger
        case .tracker: Color(nsColor: .systemOrange)
        case .social: Color(nsColor: .systemBlue)
        case .analytics: Design.warning
        case .marketing: Color(nsColor: .systemTeal)
        case .security, .payments, .support, .consent, .media, .hosting, .unknown: Design.inkColor(.tertiary)
        }
    }
}

/// "Live" beside the title: the panel follows the page as it happens.
private struct PrivacyLiveBadge: View {
    @State private var low = false

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle().fill(Design.positive)
                .frame(width: Design.Space.s, height: Design.Space.s)
                .opacity(low ? PrivacyPanelMetrics.liveLow : 1)
            Text("Live").font(Design.Font.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Design.Space.m)
        .padding(.vertical, Design.Space.xxs)
        .background(Capsule().fill(Design.fill(.subtle)))
        .onAppear {
            guard !Design.Motion.reduced else { return }
            withAnimation(.easeInOut(duration: PrivacyPanelMetrics.liveBreath).repeatForever(autoreverses: true)) { low = true }
        }
        .accessibilityHidden(true)
    }
}

/// The header's two small buttons: a glyph on a plate that shows under the pointer.
private struct PrivacyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Plate(configuration: configuration) }

    private struct Plate: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(.secondary)
                .frame(width: Design.Space.controlCompact, height: Design.Space.controlCompact)
                .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous)
                    .fill(Design.fill(configuration.isPressed ? .pressed : hovered ? .hover : .subtle).opacity(hovered || configuration.isPressed ? 1 : 0)))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

private struct PrivacyEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Design.Space.m) {
            Image(systemName: symbol).font(.system(size: Design.Icon.large * 2, weight: .light)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(Design.Font.section)
            Text(detail).font(Design.Font.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A rule changed since the page loaded: it holds from the next load.
private struct PrivacyReloadHint: View {
    let text: String
    let reload: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.m) {
            Image(systemName: "arrow.clockwise").font(.system(size: Design.Icon.regular, weight: .medium)).foregroundStyle(Design.accent)
                .accessibilityHidden(true)
            Text(text).font(Design.Font.detail)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Design.Space.s)
            Button("Reload", action: reload).buttonStyle(.settingsProminent)
        }
        .padding(Design.Space.l)
        .background(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous).fill(Design.accentWash))
    }
}

/// The top of the panel: the site, the diagram, where the page stands, and the three counts, on
/// a wash of the state's colour.
private struct PrivacyHero: View {
    let site: String
    let favicon: NSImage?
    let standing: PrivacyReport.Standing
    let summary: PrivacyLedger.Summary
    let parties: [PrivacyLedger.Party]
    let shielded: Bool
    let open: (String) -> Void

    var body: some View {
        let tone = PrivacyTone.color(standing.tone)
        let m = PrivacyPanelMetrics.self
        return VStack(spacing: 0) {
            PrivacyOrbit(parties: parties, shielded: shielded, favicon: favicon, initial: String(site.prefix(1)).uppercased(),
                         blocked: summary.blockedRequests, open: open)
            VStack(spacing: Design.Space.xs) {
                Text(site).font(Design.Font.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(standing.title).font(Design.Font.ui(.headline, .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !standing.detail.isEmpty {
                    Text(standing.detail).font(Design.Font.detail).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Design.Space.xl)
            .padding(.top, Design.Space.m)
            .padding(.bottom, Design.Space.xl)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Design.hairline).frame(height: Design.Space.hair)
            HStack(spacing: 0) {
                PrivacyCount(n: summary.blocked, label: "Blocked", color: Design.positive)
                Rectangle().fill(Design.hairline).frame(width: Design.Space.hair)
                PrivacyCount(n: summary.sawYou, label: summary.sawYou == 1 ? "Sees you" : "See you", color: Design.danger)
                Rectangle().fill(Design.hairline).frame(width: Design.Space.hair)
                PrivacyCount(n: summary.others, label: "Other", color: Design.inkColor(.secondary))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous)
                .fill(LinearGradient(colors: [tone.opacity(m.heroWashTop), tone.opacity(m.heroWashBottom)], startPoint: .top, endPoint: .bottom))
        )
        .background(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous).fill(Design.fill(.subtle)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous).strokeBorder(Design.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous))
        .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.standard), value: standing.tone)
    }
}

/// One of the three counts: a number in its colour over what it counts.
private struct PrivacyCount: View {
    let n: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Design.Space.xxs) {
            Text("\(n)").font(Design.Font.ui(.pane, .semibold)).monospacedDigit()
                .foregroundStyle(n == 0 ? Design.inkColor(.tertiary) : color)
                .contentTransition(.numericText())
            Text(label).font(Design.Font.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Space.l)
        .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.standard), value: n)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) \(label)")
    }
}

/// The diagram: the page in the middle, a shield round it. A company that got through sits inside
/// the shield, joined to the page (red when it tracks); one that was blocked sits outside, its
/// line stopped at the shield. Each is a chip with the company's initial; a click opens its row.
private struct PrivacyOrbit: View {
    let parties: [PrivacyLedger.Party]
    let shielded: Bool
    let favicon: NSImage?
    let initial: String
    /// Requests blocked so far: the shield sends a ring out when it grows.
    let blocked: Int
    let open: (String) -> Void
    @State private var pulse = false

    private struct Chip: Identifiable {
        let id: String
        let label: String
        let name: String
        let party: PrivacyLedger.Party?
    }

    private static func chips(_ parties: [PrivacyLedger.Party], limit: Int) -> [Chip] {
        guard parties.count > limit else { return parties.map { Chip(id: $0.id, label: String($0.name.prefix(1)).uppercased(), name: $0.name, party: $0) } }
        let shown = parties.prefix(limit - 1)
        let rest = parties.count - shown.count
        return shown.map { Chip(id: $0.id, label: String($0.name.prefix(1)).uppercased(), name: $0.name, party: $0) }
            + [Chip(id: "+more", label: "+\(rest)", name: "\(rest) more", party: nil)]
    }

    var body: some View {
        let m = PrivacyPanelMetrics.self
        let inside = Self.chips(parties.filter { $0.listing != .blocked }, limit: m.orbitInside)
        let outside = Self.chips(parties.filter { $0.listing == .blocked }, limit: m.orbitOutside)
        return GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // Where the two rings of chips sit.
                ForEach([m.orbitInner, m.orbitOuter], id: \.self) { radius in
                    Circle().strokeBorder(Design.hairline, lineWidth: m.faintLine)
                        .frame(width: radius * 2, height: radius * 2).position(centre)
                }
                ForEach(Array(inside.enumerated()), id: \.element.id) { i, chip in
                    let seen = chip.party?.sawYou == true
                    Path { p in
                        p.move(to: centre)
                        p.addLine(to: Self.point(i, of: inside.count, radius: m.orbitInner, centre: centre, turn: 0))
                    }
                    .stroke(seen ? Design.danger.opacity(m.seenLine) : Design.inkColor(.quaternary), lineWidth: seen ? Design.Space.hair : m.faintLine)
                }
                // A blocked company's reach, stopped where it meets the shield.
                ForEach(Array(outside.enumerated()), id: \.element.id) { i, _ in
                    Path { p in
                        p.move(to: Self.point(i, of: outside.count, radius: m.orbitOuter, centre: centre, turn: 0.5))
                        p.addLine(to: Self.point(i, of: outside.count, radius: m.orbitShield, centre: centre, turn: 0.5))
                    }
                    .stroke(Design.positive.opacity(m.seenLine), style: StrokeStyle(lineWidth: Design.Space.hair, dash: [Design.Space.xxs, Design.Space.xxs]))
                }
                if shielded {
                    Circle().stroke(Design.positive, lineWidth: m.orbitShieldLine)
                        .frame(width: m.orbitShield * 2, height: m.orbitShield * 2)
                        .scaleEffect(pulse ? m.orbitPulseScale : 1)
                        .opacity(pulse ? 0 : m.orbitPulseStrength)
                        .position(centre)
                }
                Circle()
                    .strokeBorder(shielded ? AnyShapeStyle(AngularGradient(colors: [Design.positive, Design.positive.opacity(m.orbitSweepLow), Design.positive], center: .center))
                                           : AnyShapeStyle(Design.inkColor(.quaternary)),
                                  style: StrokeStyle(lineWidth: m.orbitShieldLine, dash: shielded ? [] : [Design.Space.xs, Design.Space.xs]))
                    .frame(width: m.orbitShield * 2, height: m.orbitShield * 2)
                    .shadow(color: shielded ? Design.positive.opacity(m.orbitGlowStrength) : .clear, radius: m.orbitGlow)
                    .position(centre)
                ForEach(Array(inside.enumerated()), id: \.element.id) { i, chip in
                    let seen = chip.party?.sawYou == true
                    chipView(chip, size: seen ? m.chipSeen : m.chipOther, color: seen ? Design.danger : Design.inkColor(.secondary), filled: seen)
                        .position(Self.point(i, of: inside.count, radius: m.orbitInner, centre: centre, turn: 0))
                }
                ForEach(Array(outside.enumerated()), id: \.element.id) { i, chip in
                    chipView(chip, size: m.chipBlocked, color: Design.positive, filled: false)
                        .position(Self.point(i, of: outside.count, radius: m.orbitOuter, centre: centre, turn: 0.5))
                }
                centreDisc.position(centre)
            }
            .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.standard), value: inside.map(\.id) + outside.map(\.id))
        }
        .frame(height: m.orbitHeight)
        .onChange(of: blocked) { old, new in
            guard new > old, !Design.Motion.reduced else { return }
            pulse = false
            withAnimation(.easeOut(duration: m.orbitPulseTime)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagram: \(parties.filter { $0.listing != .blocked }.count) inside the shield, \(parties.filter { $0.listing == .blocked }.count) kept out")
    }

    private var centreDisc: some View {
        let m = PrivacyPanelMetrics.self
        return Group {
            if let favicon {
                Image(nsImage: favicon).resizable().interpolation(.high)
                    .frame(width: Design.Icon.large, height: Design.Icon.large)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous))
            } else {
                Text(initial).font(Design.Font.title)
            }
        }
        .frame(width: m.orbitCentre, height: m.orbitCentre)
        .background(Circle().fill(Design.fill(.strong)))
        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Circle().strokeBorder(Design.hairline))
    }

    private func chipView(_ chip: Chip, size: CGFloat, color: Color, filled: Bool) -> some View {
        Button { if let party = chip.party { open(party.id) } } label: {
            Text(chip.label).font(Design.Font.ui(.micro, .semibold)).monospacedDigit()
                .foregroundStyle(filled ? Color.white : color)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? color : color.opacity(PrivacyPanelMetrics.tintWash)))
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(Circle().strokeBorder(color.opacity(filled ? 0 : PrivacyPanelMetrics.seenLine), lineWidth: Design.Space.hair))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(chip.name)
        .transition(.scale.combined(with: .opacity))
    }

    /// The `i`th of `n` places round a ring, the first at the top; `turn` shifts a ring by a share
    /// of one step so the two rings' chips don't line up.
    static func point(_ i: Int, of n: Int, radius: CGFloat, centre: CGPoint, turn: CGFloat) -> CGPoint {
        let step = 2 * CGFloat.pi / CGFloat(max(1, n))
        let angle = (CGFloat(i) + turn) * step - .pi / 2
        return CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    }
}

/// What each of Niche's protections did on this page: a line each, with its result at the right.
private struct PrivacyReportCard: View {
    let rows: [PrivacyReport.Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 { Rectangle().fill(Design.hairline).frame(height: Design.Space.hair).padding(.leading, Design.Space.l + PrivacyPanelMetrics.glyphPlate + Design.Space.l) }
                let tint = PrivacyTone.color(row.tone)
                HStack(spacing: Design.Space.l) {
                    Image(systemName: row.symbol)
                        .font(.system(size: Design.Icon.regular, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: PrivacyPanelMetrics.glyphPlate, height: PrivacyPanelMetrics.glyphPlate)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(tint.opacity(PrivacyPanelMetrics.tintWash)))
                        .accessibilityHidden(true)
                    Text(row.title).font(Design.Font.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Design.Space.s)
                    Text(row.value).font(Design.Font.detail.weight(.medium)).monospacedDigit()
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
                .padding(.horizontal, Design.Space.l)
                .padding(.vertical, Design.Space.m)
                .accessibilityElement(children: .combine)
            }
        }
        .privacyCard()
    }
}

/// What kinds of companies the page reached out to: one bar split by kind, and what each colour is.
private struct PrivacyKinds: View {
    let kinds: [PrivacyLedger.Summary.Kind]
    let total: Int

    /// The kinds that track, each on its own; everything that makes the page work as one.
    private var segments: [(title: String, count: Int, color: Color)] {
        var out = kinds.filter { $0.category.tracks }.map { ($0.category.title, $0.count, PrivacyTone.color($0.category)) }
        let helpers = kinds.filter { !$0.category.tracks }.map(\.count).reduce(0, +)
        if helpers > 0 { out.append(("Makes the page work", helpers, Design.inkColor(.tertiary))) }
        return out
    }

    var body: some View {
        let segments = segments
        return VStack(alignment: .leading, spacing: Design.Space.l) {
            GeometryReader { geo in
                let gap = Design.Space.xxs
                let width = max(0, geo.size.width - gap * CGFloat(max(0, segments.count - 1)))
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        Capsule().fill(s.color).frame(width: max(PrivacyPanelMetrics.kindsBar, width * CGFloat(s.count) / CGFloat(max(1, total))))
                    }
                }
            }
            .frame(height: PrivacyPanelMetrics.kindsBar)
            .clipShape(Capsule())
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: Design.Space.s) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: Design.Space.s) {
                        Circle().fill(s.color).frame(width: PrivacyPanelMetrics.toneDot, height: PrivacyPanelMetrics.toneDot)
                            .accessibilityHidden(true)
                        Text(s.title).font(Design.Font.detail).lineLimit(1)
                        Text("\(s.count)").font(Design.Font.detail).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Design.Space.l)
        .privacyCard()
    }
}

/// What is happening now: the newest lines of the ledger's feed, each with how long ago.
private struct PrivacyFeed: View {
    let items: [PrivacyLedger.FeedItem]

    var body: some View {
        PrivacySection("Happening now") {
            TimelineView(.periodic(from: .now, by: Double(PrivacyPanelMetrics.feedLines))) { clock in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.suffix(PrivacyPanelMetrics.feedLines).reversed().enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Rectangle().fill(Design.hairline).frame(height: Design.Space.hair).padding(.leading, Design.Space.l + PrivacyPanelMetrics.toneDot + Design.Space.m) }
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                            Circle().fill(PrivacyTone.color(item.tone))
                                .frame(width: PrivacyPanelMetrics.toneDot, height: PrivacyPanelMetrics.toneDot)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.count > 1 ? "\(item.title) ×\(item.count)" : item.title).font(Design.Font.detail).monospacedDigit()
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text(item.detail).font(Design.Font.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Design.Space.s)
                            Text(PrivacyReport.ago(item.at, now: clock.date)).font(Design.Font.caption).monospacedDigit().foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Design.Space.l)
                        .padding(.vertical, Design.Space.m)
                        .accessibilityElement(children: .combine)
                    }
                }
                .privacyCard()
            }
        }
    }
}

/// The foot of the panel: what Niche blocked in all, and a bar for each of the last seven days.
private struct PrivacyTotals: View {
    let stats: PrivacyStats

    var body: some View {
        let now = Date()
        let week = stats.recent(7, now: now)
        let top = max(1, week.map(\.blocked).max() ?? 1)
        let m = PrivacyPanelMetrics.self
        return HStack(alignment: .bottom, spacing: Design.Space.l) {
            VStack(alignment: .leading, spacing: Design.Space.xxs) {
                Text(stats.total).font(Design.Font.ui(.pane, .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(stats.blocked == 1 ? "tracker blocked by Niche" : "trackers blocked by Niche").font(Design.Font.caption).foregroundStyle(.secondary)
                Text("\(stats.today(now: now)) today").font(Design.Font.caption).monospacedDigit().foregroundStyle(.tertiary)
            }
            Spacer(minLength: Design.Space.m)
            HStack(alignment: .bottom, spacing: Design.Space.xs) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: Design.Space.xs) {
                        RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
                            .fill(Design.positive.opacity(i == week.count - 1 ? 1 : m.chartPast))
                            .frame(width: m.chartBar, height: max(m.chartFloor, m.chartHeight * CGFloat(day.blocked) / CGFloat(top)))
                        Text(Self.letter(day.day)).font(Design.Font.ui(.micro)).foregroundStyle(.tertiary)
                    }
                    .help("\(day.blocked) blocked")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Blocked each day this week: " + week.map { "\($0.blocked)" }.joined(separator: ", "))
        }
        .padding(Design.Space.l)
        .privacyCard()
        .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.standard), value: stats.blocked)
    }

    /// The day's first letter ("M", "T").
    private static func letter(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEEE"
        return f.string(from: day)
    }
}

/// A company on the page: what it is, where it stands, and when opened what it learned and the
/// buttons to block or allow it.
private struct PrivacyPartyRow: View {
    let party: PrivacyLedger.Party
    let pageSite: String
    let choice: PrivacyRules.Choice
    let expanded: Bool
    let toggle: () -> Void
    let choose: (PrivacyRules.Choice) -> Void
    @State private var hovered = false

    private var tint: Color { PrivacyTone.color(party) }
    private var status: String { PrivacyWords.status(party) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Design.Space.l) {
                    Image(systemName: party.category.symbol)
                        .font(.system(size: Design.Icon.regular, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: PrivacyPanelMetrics.glyphPlate, height: PrivacyPanelMetrics.glyphPlate)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.inset, style: .continuous).fill(tint.opacity(PrivacyPanelMetrics.tintWash)))
                    VStack(alignment: .leading, spacing: Design.Space.hair) {
                        Text(party.name).font(Design.Font.control).lineLimit(1).truncationMode(.middle)
                        Text(party.category.title + (party.categories.count > 1 ? " +\(party.categories.count - 1)" : ""))
                            .font(Design.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Design.Space.s)
                    Text(status).font(Design.Font.caption.weight(.medium))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.horizontal, Design.Space.m)
                        .padding(.vertical, Design.Space.xxs)
                        .background(Capsule().fill(tint.opacity(PrivacyPanelMetrics.tintWash)))
                        .layoutPriority(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Design.Icon.tiny, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, Design.Space.l)
                .padding(.vertical, Design.Space.m)
                .background(Design.fill(.hover).opacity(hovered ? 1 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel("\(party.name), \(party.category.title), \(status)")
            .accessibilityHint(expanded ? "Hides the details" : "Shows what it learned and how to block or allow it")
            if expanded { detail }
        }
        .animation(Design.Motion.reduced ? nil : .easeOut(duration: Design.Motion.fast), value: expanded)
    }

    private var detail: some View {
        let learned = party.learned(pageSite: pageSite)
        return VStack(alignment: .leading, spacing: Design.Space.m) {
            Text(party.category.explanation).font(Design.Font.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if learned.isEmpty {
                Label("It learned nothing. Niche stopped it before it heard of this visit.", systemImage: "checkmark.shield")
                    .font(Design.Font.detail).foregroundStyle(Design.positive)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    Text("What it got").font(Design.Font.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(learned, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(Design.Font.detail)
                    }
                }
            }
            if let withheld = party.withheld {
                Label(withheld, systemImage: "checkmark.shield")
                    .font(Design.Font.detail).foregroundStyle(Design.positive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if party.categories.count > 1 {
                Text(party.categories.map(\.title).joined(separator: ", ")).font(Design.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let why = party.blockedWhy {
                Text("\(PrivacyWords.count(party.blocked, "request")) blocked. \(why)").font(Design.Font.caption).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(party.hosts.sorted().prefix(3).joined(separator: ", ") + (party.hosts.count > 3 ? " and \(party.hosts.count - 3) more" : ""))
                .font(Design.Font.caption).foregroundStyle(.tertiary).lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            actions
        }
        .padding(.leading, Design.Space.l + PrivacyPanelMetrics.glyphPlate + Design.Space.l)
        .padding(.trailing, Design.Space.l)
        .padding(.bottom, Design.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var actions: some View {
        if party.id == pageSite {
            Text("This is the site itself.").font(Design.Font.caption).foregroundStyle(.secondary)
        } else if party.ownsSite {
            Text("\(party.name) runs \(pageSite).").font(Design.Font.caption).foregroundStyle(.secondary)
        } else if let said = PrivacyWords.said(choice, name: party.name) {
            HStack(spacing: Design.Space.m) {
                Text(said).font(Design.Font.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Undo") { choose(.standard) }.buttonStyle(.settings)
            }
        } else if party.listing == .blocked {
            HStack(spacing: Design.Space.m) {
                Button(PrivacyRules.Choice.allowedHere.title) { choose(.allowedHere) }.buttonStyle(.settings)
                Button("Everywhere") { choose(.allowedEverywhere) }.buttonStyle(.settings)
                    .accessibilityLabel(PrivacyRules.Choice.allowedEverywhere.title)
            }
        } else {
            VStack(alignment: .leading, spacing: Design.Space.s) {
                HStack(spacing: Design.Space.m) {
                    Button(PrivacyRules.Choice.blockedHere.title) { choose(.blockedHere) }.buttonStyle(.settingsProminent)
                    Button("Everywhere") { choose(.blockedEverywhere) }.buttonStyle(.settings)
                        .accessibilityLabel(PrivacyRules.Choice.blockedEverywhere.title)
                }
                if let caveat = PrivacyWords.blockCaveat(party: party.id, name: party.name, tracks: party.tracks) {
                    Text(caveat).font(Design.Font.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
