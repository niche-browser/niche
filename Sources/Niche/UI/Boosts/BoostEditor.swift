import AppKit
import SwiftUI

/// The Boost editor: a glass panel at the window's right edge, under the toolbar, that changes
/// the page beside it as you edit. It began as Arc 1.172.1's (a 183 pt column, captured 7 Nov 2026;
/// docs/screenshots/arc-boost-*.png) and keeps its parts and motion (BoostEditorMotion): Done, the
/// Boost's menu (rename, shuffle, reset, delete, all Boosts) and Undo; the colour wheel with Invert,
/// Adjust (contrast, brightness, saturation) and Reset; 20 fonts; text size and case; Zap, and Code,
/// which widens the panel to a CSS / JavaScript editor with the selector picker and DevTools under it.
/// Since 0.1.3 it is 248 pt wide, follows the window's light or dark look, and labels its buttons.
@MainActor
final class BoostEditorController {
    static let shared = BoostEditorController()
    private var panel: NSPanel?
    private var model: BoostEditorModel?

    /// What the editor does to the page beside it.
    struct PageActions {
        var zap: (Bool) -> Void
        var pick: (Bool) -> Void
        var toggleDevTools: () -> Void
        var devToolsOpen: () -> Bool
        var reload: () -> Void
    }

    func open(_ boost: Boost, over window: NSWindow, page: PageActions) {
        close()
        let m = BoostEditorModel(boost: boost)
        m.page = page
        m.devToolsOpen = page.devToolsOpen()
        m.onClose = { [weak self] in self?.close() }
        m.onWidth = { [weak self] w in self?.resize(width: w) }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.becomesKeyOnlyIfNeeded = true
        let host = FirstClickHostingView(rootView: BoostEditorView(model: m))
        host.sizingOptions = []
        // Glass under the controls, rounded by its mask so the window's shadow follows the corners.
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = Self.roundedMask(radius: BoostEditorLayout.radius)
        host.autoresizingMask = [.width, .height]
        glass.addSubview(host)
        p.contentView = glass
        host.frame = glass.bounds
        let f = window.frame
        let w = BoostEditorLayout.width, h = min(BoostEditorLayout.height, f.height - 80)
        // Under the toolbar at the window's right edge (`h` leaves it inside the window).
        let top = f.maxY - 64
        p.setFrame(NSRect(x: f.maxX - 12 - w, y: top - h, width: w, height: h), display: false)
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        model = m
        growIn(p, glass)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = 2 * radius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static var easeOut: CAMediaTimingFunction {
        let (x1, y1, x2, y2) = BoostEditorMotion.easeOut
        return CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }

    /// Arc's opening (BoostEditorMotion): drawn at 85 % and grown to full size about the middle of
    /// its right edge. The window's shadow can't scale, so the content carries one meanwhile.
    private func growIn(_ panel: NSPanel, _ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let b = view.bounds
        let s = BoostEditorMotion.openScale
        // The layer scales about its anchor point; move the pivot to the right edge's middle.
        let dx = b.width * (BoostEditorMotion.openAnchor.x - layer.anchorPoint.x)
        let dy = b.height * (BoostEditorMotion.openAnchor.y - layer.anchorPoint.y)
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, s, s, 1)
        t = CATransform3DTranslate(t, -dx, -dy, 0)
        panel.hasShadow = false
        layer.shadowPath = CGPath(roundedRect: b, cornerWidth: BoostEditorLayout.radius, cornerHeight: BoostEditorLayout.radius, transform: nil)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -3)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak panel, weak layer] in
            layer?.shadowOpacity = 0
            panel?.hasShadow = true
            panel?.invalidateShadow()
        }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: t)
        a.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        a.duration = BoostEditorMotion.openDuration
        a.timingFunction = Self.easeOut
        layer.add(a, forKey: "nicheBoostGrow")
        CATransaction.commit()
    }

    func close() {
        model?.finishZap()
        model?.finishPicking()
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
        model = nil
    }

    var isOpen: Bool { panel != nil }

    /// The picker ends (its page went to the back).
    func stopPicking() { model?.finishPicking() }

    /// DevTools opened or closed (the hammer, ⌥⌘I or their own close button).
    func devToolsChanged() { if let model { model.devToolsOpen = model.page.devToolsOpen() } }

    /// What Zap hid, into the boost being edited.
    func addZapped(_ selectors: [String]) {
        NicheLog.note("zap kept \(selectors.count) selector\(selectors.count == 1 ? "" : "s")")
        guard let model, !selectors.isEmpty else { return }
        model.change { b in b.zapped += selectors.filter { !b.zapped.contains($0) } }
    }

    private func resize(width: CGFloat) {
        guard let panel else { return }
        var f = panel.frame
        let duration = BoostEditorMotion.resizeDuration(fromWidth: f.width, to: width)
        f.origin.x = f.maxX - width
        f.size.width = width
        // Arc: Code widens the panel in 0.35 s, Back narrows it in 0.13 s, both easing out.
        guard duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { panel.setFrame(f, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = Self.easeOut
            panel.animator().setFrame(f, display: true)
        }
    }
}

@MainActor
@Observable
final class BoostEditorModel {
    var boost: Boost { didSet { if boost != oldValue { BoostStore.shared.update(boost) } } }
    var history: [Boost] = []
    var showingCode = false
    var codeIsJS = false
    var zapping = false
    var picking = false
    var devToolsOpen = false
    @ObservationIgnored var page = BoostEditorController.PageActions(zap: { _ in }, pick: { _ in }, toggleDevTools: {}, devToolsOpen: { false }, reload: {})
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onWidth: (CGFloat) -> Void = { _ in }

    init(boost: Boost) { self.boost = boost }

    /// One step of the editor, undoable.
    func change(_ edit: (inout Boost) -> Void) {
        history.append(boost)
        var b = boost
        edit(&b)
        boost = b
    }

    func undo() { if let last = history.popLast() { boost = last } }

    func shuffle() {
        change {
            $0.hue = Double.random(in: 0..<1)
            $0.strength = Double.random(in: 0.3...0.8)
            $0.font = Int.random(in: 0..<Boost.fonts.count)
        }
    }

    func resetAll() {
        change { b in
            let fresh = Boost(id: b.id, host: b.host, name: b.name)
            b = fresh
        }
    }

    func toggleZap() {
        finishPicking()
        zapping.toggle()
        page.zap(zapping)
    }

    func finishZap() { if zapping { zapping = false; page.zap(false) } }

    /// The eyedropper: outline elements on the page; a click offers their selectors.
    func togglePicker() {
        finishZap()
        picking.toggle()
        page.pick(picking)
    }

    func finishPicking() { if picking { picking = false; page.pick(false) } }

    func toggleDevTools() {
        page.toggleDevTools()
        devToolsOpen.toggle()
    }

    func setCode(_ on: Bool) {
        if !on { finishPicking() }
        showingCode = on
        onWidth(on ? BoostEditorLayout.codeWidth : BoostEditorLayout.width)
    }
}
/// The editor's measures (Niche 0.1.3; Arc's was a 183 pt column of 147 pt controls).
enum BoostEditorLayout {
    static let width: CGFloat = 248
    static let codeWidth: CGFloat = 480
    static let height: CGFloat = 572
    static let inset: CGFloat = 14
    static var column: CGFloat { width - 2 * inset }
    static let radius: CGFloat = 16
    static let control: CGFloat = 32
}

/// Colours that follow the panel's appearance: ink on a translucent plate, the accent for what is on.
private enum BoostStyle {
    static let plate = Color.primary.opacity(0.06)
    static let plateHover = Color.primary.opacity(0.1)
    static let hairline = Color.primary.opacity(0.1)
    static let secondary = Color.secondary
    static let label = Font.system(size: 11, weight: .semibold)
}

private struct BoostEditorView: View {
    @Bindable var model: BoostEditorModel
    @State private var showColors = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(BoostStyle.hairline).frame(height: 1)
            if model.showingCode { code } else { controls }
        }
        // Laid out at its final width and kept centred while the panel widens or narrows.
        .frame(width: model.showingCode ? BoostEditorLayout.codeWidth : BoostEditorLayout.width)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: BoostEditorLayout.radius, style: .continuous)
            .strokeBorder(BoostStyle.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: BoostEditorLayout.radius, style: .continuous))
    }

    @ViewBuilder private var header: some View {
        if model.showingCode {
            ZStack {
                Picker("", selection: $model.codeIsJS) {
                    Text("CSS").tag(false)
                    Text("JavaScript").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                HStack {
                    Button { model.setCode(false) } label: {
                        Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(BoostStyle.plate))
                    }
                    .buttonStyle(.plain).padding(.leading, 10)
                    Spacer()
                }
            }
            .frame(height: 48)
        } else {
            boostHeader
        }
    }

    private var boostHeader: some View {
        HStack(spacing: 0) {
            iconButton("xmark", help: "Done") { model.onClose() }
            Spacer(minLength: 4)
            Menu {
                Button("Rename this Boost…") { rename() }
                Button("Shuffle") { model.shuffle() }
                Button("Reset all Edits") { model.resetAll() }
                Divider()
                Button("Delete this Boost", role: .destructive) { delete() }
                Divider()
                Button("All Boosts…") { NotificationCenter.default.post(name: .nicheShowBoostsLibrary, object: nil) }
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text(model.boost.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Text(model.boost.host).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: 150)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Spacer(minLength: 4)
            iconButton("arrow.uturn.backward", help: "Undo") { model.undo() }
                .disabled(model.history.isEmpty).opacity(model.history.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    private func iconButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(BoostStyle.plate))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColorWheel(hue: model.boost.hue, strength: model.boost.strength) { h, s in
                model.change { $0.hue = h; $0.strength = s }
            }
            .frame(width: BoostEditorLayout.column, height: 168)
            .padding(.top, BoostEditorLayout.inset)
            HStack(spacing: 6) {
                chip("circle.lefthalf.filled", "Invert", on: model.boost.invert, help: "Invert lightness") { model.change { $0.invert.toggle() } }
                chip("slider.horizontal.3", "Adjust", on: showColors, help: "Contrast, brightness and saturation") { showColors.toggle() }
                    .popover(isPresented: $showColors, arrowEdge: .leading) { advanced }
                chip("arrow.counterclockwise", "Reset", on: false, help: "Back to the site's own colours") {
                    model.change { $0.hue = 0; $0.strength = 0; $0.invert = false; $0.contrast = 50; $0.brightness = 50; $0.saturation = 50 }
                }
                .disabled(model.boost.colorsUntouched).opacity(model.boost.colorsUntouched ? 0.4 : 1)
            }
            .padding(.top, 10)
            sectionLabel("Font").padding(.top, 16)
            fonts.padding(.top, 6)
            HStack(spacing: 6) {
                sizeControl
                caseMenu
            }
            .padding(.top, 10)
            HStack(spacing: 6) {
                action("Zap", symbol: "bolt.fill", on: model.zapping, help: "Click things on the page to hide them") { model.toggleZap() }
                action("Code", symbol: "curlybraces", on: false, help: "Your own CSS and JavaScript") { model.setCode(true) }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .frame(width: BoostEditorLayout.column)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(BoostStyle.label).kerning(0.6).foregroundStyle(.secondary)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Contrast", \.contrast)
            slider("Brightness", \.brightness)
            slider("Saturation", \.saturation)
        }
        .padding(16)
        .frame(width: 240)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<Boost, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(model.boost[keyPath: key] - 50))").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { model.boost[keyPath: key] }, set: { v in model.change { $0[keyPath: key] = v } }), in: 0...100)
                .controlSize(.small).tint(Design.accent)
        }
    }

    /// A preview of `Boost.fonts[i]`; the CSS generic families map onto SwiftUI's designs.
    private static func previewFont(_ i: Int, size: CGFloat) -> Font {
        switch Boost.fonts[i] {
        case "-apple-system": .system(size: size)
        case "ui-rounded": .system(size: size, design: .rounded)
        case "ui-serif": .system(size: size, design: .serif)
        case "ui-monospace": .system(size: size, design: .monospaced)
        case let name: .custom(name, size: size)
        }
    }

    private static func fontName(_ i: Int) -> String {
        switch Boost.fonts[i] {
        case "-apple-system": "System"
        case "ui-rounded": "Rounded"
        case "ui-serif": "Serif"
        case "ui-monospace": "Monospaced"
        case let name: name
        }
    }

    private var fonts: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 5)
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Boost.fonts.indices, id: \.self) { i in
                let on = model.boost.font == i
                Button { model.change { $0.font = $0.font == i ? nil : i } } label: {
                    Text("Aa").font(Self.previewFont(i, size: 15))
                        .foregroundStyle(on ? Design.accent : Color.primary.opacity(0.75))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Design.accent.opacity(0.14) : BoostStyle.plate))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Design.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(Self.fontName(i)).accessibilityLabel(Self.fontName(i))
            }
        }
    }

    private static let sizes: [Double] = [0.8, 0.9, 1, 1.1, 1.25, 1.5]

    /// Smaller / the size / larger, one step through `sizes` per click.
    private var sizeControl: some View {
        let scale = model.boost.textScale
        let i = Self.sizes.firstIndex(where: { abs($0 - scale) < 0.001 }) ?? 2
        return HStack(spacing: 0) {
            stepButton("textformat.size.smaller", help: "Smaller text", enabled: i > 0) { model.change { $0.textScale = Self.sizes[i - 1] } }
            Text(scale == 1 ? "100%" : "\(Int((scale * 100).rounded()))%")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
            stepButton("textformat.size.larger", help: "Larger text", enabled: i < Self.sizes.count - 1) { model.change { $0.textScale = Self.sizes[i + 1] } }
        }
        .frame(height: BoostEditorLayout.control)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BoostStyle.plate))
    }

    private func stepButton(_ symbol: String, help: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: BoostEditorLayout.control).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).help(help).accessibilityLabel(help)
    }

    private var caseMenu: some View {
        Menu {
            Picker("Text Case", selection: Binding(get: { model.boost.textCase }, set: { c in model.change { $0.textCase = c } })) {
                ForEach(Boost.TextCase.allCases, id: \.self) { c in Text(c.title).tag(c) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "textformat").font(.system(size: 11, weight: .semibold))
                Text(model.boost.textCase.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: BoostEditorLayout.control)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BoostStyle.plate))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Text case")
    }

    private func chip(_ symbol: String, _ title: String, on: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Design.accent : BoostStyle.plate))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func action(_ title: String, symbol: String, on: Bool, help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(on ? "Zapping…" : title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Design.accent : BoostStyle.plate))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BoostStyle.hairline, lineWidth: on ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var code: some View {
        VStack(spacing: 0) {
            CodeEditor(text: Binding(get: { model.codeIsJS ? model.boost.js : model.boost.css },
                                     set: { v in if model.codeIsJS { model.boost.js = v } else { model.boost.css = v } }))
                .overlay(alignment: .topLeading) {
                    if (model.codeIsJS ? model.boost.js : model.boost.css).isEmpty {
                        Text(model.codeIsJS ? "// Runs on every page of \(model.boost.host)" : "/* Applies to every page of \(model.boost.host) */")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.white.opacity(0.35))
                            .padding(.leading, 15).padding(.top, 10).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 6) {
                chip("eyedropper", "Pick", on: model.picking, help: model.picking ? "Hide Selector Picker" : "Show Selector Picker") {
                    model.togglePicker()
                }
                .frame(width: 84)
                chip("hammer", "DevTools", on: model.devToolsOpen, help: model.devToolsOpen ? "Hide Developer Tools" : "Show Developer Tools") {
                    model.toggleDevTools()
                }
                .frame(width: 104)
                if model.codeIsJS {
                    chip("arrow.clockwise", "Reload", on: false, help: "Refresh this Page") { model.page.reload() }.frame(width: 90)
                }
                Spacer()
            }
            .padding(.horizontal, BoostEditorLayout.inset)
            .frame(height: 56)
        }
        .frame(width: BoostEditorLayout.codeWidth)
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = "Rename this Boost"
        let field = NSTextField(string: model.boost.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { model.change { $0.name = field.stringValue } }
    }

    private func delete() {
        let alert = NSAlert()
        alert.messageText = "Delete this Boost?"
        alert.informativeText = "Its changes to \(model.boost.host) go away."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BoostStore.shared.delete(model.boost.id)
        model.onClose()
    }
}

/// The colour wheel: a rounded square framed by the hue circle, dotted inside. The handle is the
/// tint: its hue round the middle, its strength out from it. In the middle, the site's own colours.
private struct ColorWheel: View {
    let hue: Double
    let strength: Double
    let set: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let c = CGPoint(x: w / 2, y: h / 2)
            let reach = min(w, h) / 2 - 22
            let angle = hue * 2 * .pi, r = strength * reach
            let handle = CGPoint(x: c.x + cos(angle) * r, y: c.y - sin(angle) * r)
            let tint = Color(hue: hue, saturation: 0.65, brightness: 0.9)
            ZStack {
                // The frame: every hue, faint, so the wheel says what it picks before it is touched.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AngularGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 0.75, brightness: 0.95) },
                                          center: .center, angle: .degrees(0)))
                    .opacity(0.55)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .padding(6)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(RadialGradient(colors: [tint.opacity(strength * 0.35), .clear], center: UnitPoint(x: handle.x / w, y: handle.y / h),
                                         startRadius: 0, endRadius: reach))
                    .padding(6)
                Canvas { ctx, s in
                    for x in stride(from: 14.0, to: s.width - 13, by: 7) {
                        for y in stride(from: 14.0, to: s.height - 13, by: 7) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.primary.opacity(0.13)))
                        }
                    }
                }
                Circle().fill(Color.primary.opacity(0.25)).frame(width: 6, height: 6).position(c)
                Circle().fill(strength > 0 ? tint : Color(white: 0.55))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .position(handle)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - c.x, dy = c.y - g.location.y
                var a = atan2(dy, dx) / (2 * .pi)
                if a < 0 { a += 1 }
                set(a, min(1, hypot(dx, dy) / reach))
            })
            .accessibilityElement()
            .accessibilityLabel("Colour")
            .accessibilityValue(strength == 0 ? "Original" : "Hue \(Int(hue * 360)) degrees, strength \(Int(strength * 100)) percent")
        }
    }
}

/// The Code panel's editor: dark, monospaced, no smart quotes.
private struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        tv.textColor = NSColor(white: 0.92, alpha: 1)
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.delegate = context.coordinator
        tv.string = text
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        let tv = view.documentView as! NSTextView
        if tv.string != text { tv.string = text }
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { text.wrappedValue = tv.string } }
    }
}

/// The editor sits beside the page, which keeps the keyboard: its first click acts, as Arc's does.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Notification.Name {
    static let nicheShowBoostsLibrary = Notification.Name("nicheShowBoostsLibrary")
}
