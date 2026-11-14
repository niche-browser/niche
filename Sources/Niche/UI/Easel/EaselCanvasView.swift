import AppKit
import UniformTypeIdentifiers

/// The canvas's own colours: it is dark in both appearances.
enum EaselPalette {
    /// The veil over the window's backdrop in a tab (Arc's 50 % black), and Peek's ground (#0B0B0B).
    static let veil = NSColor(white: 0, alpha: 0.5)
    static let peekGround = NSColor(white: 11.0 / 255, alpha: 1)
}

/// Arc's Easel canvas (Arc 1.172.1, `easelCanvasView`): as wide as the page area and 2436 pt
/// tall, scrolling; the title box 894 pt wide, centred, 52 pt down, bold white; the toolbar
/// (EaselToolbar) centred 20 pt above the bottom. Shapes, arrows and
/// strokes are drawn with a drag, text with a click, pictures from a file or the clipboard.
@MainActor
final class EaselCanvasView: NSView {
    private(set) var document: Easel
    var onTitle: (String) -> Void = { _ in }
    private let store: JSONStore<Easel>
    private let scroll = NSScrollView()
    private let sheet: EaselSheetView
    private let toolbar = EaselToolbar()

    init(document: Easel) {
        self.document = document
        store = EaselFiles.store(document.id)
        // A new easel is on disk from the start, so Library ▸ Easels lists it.
        if !FileManager.default.fileExists(atPath: store.url.path) { store.saveNow(document) }
        sheet = EaselSheetView(document: document)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = EaselPalette.veil.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = sheet
        addSubview(scroll)
        addSubview(toolbar)
        sheet.onChange = { [weak self] doc in self?.changed(doc) }
        sheet.onToolDone = { [weak self] in self?.toolbar.tool = .pointer; self?.sheet.tool = .pointer }
        toolbar.onDuplicate = { [weak self] in self?.sheet.duplicateSelected() }
        toolbar.onPick = { [weak self] tool in
            guard let self else { return }
            if tool == .image { self.sheet.addPictureFromFile(); return }
            self.sheet.tool = tool
            self.toolbar.tool = tool
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func changed(_ doc: Easel) {
        let renamed = doc.title != document.title
        document = doc
        guard !EaselFiles.deleted.contains(doc.id) else { return }
        store.save(doc)
        if renamed { onTitle(doc.title) }
    }

    /// A deleted easel's tab, closing, writes nothing back.
    func saveNow() { if !EaselFiles.deleted.contains(document.id) { store.saveNow(document) } }

    func focus() { window?.makeFirstResponder(sheet) }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        sheet.frame = NSRect(x: 0, y: 0, width: max(bounds.width - (scroll.verticalScroller?.frame.width ?? 0) * 0, 300),
                             height: Easel.canvasHeight)
        // Centred under the drawing, where both hands find it, rather than in Arc's bottom-left corner.
        let size = toolbar.fittingSize
        toolbar.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: bounds.height - Design.Space.xxl - size.height,
                               width: size.width, height: size.height)
    }
}

/// The drawing itself.
@MainActor
final class EaselSheetView: NSView, NSTextFieldDelegate {
    private(set) var document: Easel
    var tool: Easel.Tool = .pointer { didSet { window?.invalidateCursorRects(for: self) } }
    var onChange: (Easel) -> Void = { _ in }
    var onToolDone: () -> Void = {}
    private let title = EaselTextField()
    private var texts: [UUID: NSTextField] = [:]
    private var selected: UUID? { didSet { if selected != nil { titlePicked = false }; needsDisplay = true; placeSizePill(); window?.invalidateCursorRects(for: self) } }
    /// A corner of the picked item being dragged (Arc's AspectRatioControlPoints).
    private var resizing: (corner: Easel.Corner, from: Easel.Rect)?
    /// The title box is being typed in: the pill acts on it.
    private var titlePicked = false { didSet { placeSizePill() } }
    /// Arc's black pill beside a picked text box: +, Aa, − (text size).
    private let sizePill = EaselSizePill()
    private var dragStart: Easel.Point?
    private var dragLast: Easel.Point?
    private var preview: Easel.Item?
    private var stroke: [Easel.Point] = []
    private var images: [String: NSImage] = [:]

    static let ink = Design.onDark(.primary)
    /// A new easel's title, in points, until its pill changes it.
    private static let titleSize: Double = 34
    static let selection = NSColor(srgbRed: 0.47, green: 0.71, blue: 0.95, alpha: 1)
    static let arcSelection = NSColor(srgbRed: 127 / 255, green: 184 / 255, blue: 214 / 255, alpha: 1)

    init(document: Easel) {
        self.document = document
        super.init(frame: .zero)
        title.stringValue = document.title
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.alignment = .center
        title.font = Self.font(document.titleStyle, size: document.titleSize ?? Self.titleSize, title: true)
        title.textColor = .white
        title.placeholderString = "Untitled Easel"
        title.delegate = self
        title.onFocus = { [weak self] in self?.selected = nil; self?.titlePicked = true }
        addSubview(title)
        sizePill.isHidden = true
        sizePill.onStep = { [weak self] step in self?.resizeSelectedText(by: step) }
        sizePill.onStyle = { [weak self] in self?.cycleSelectedStyle() }
        addSubview(sizePill)
        for item in document.items { if case .text = item.kind { addTextField(for: item) } }
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The window moves by its background: a drag here draws instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let w = min(CGFloat(Easel.titleWidth), bounds.width - 40)
        title.frame = NSRect(x: (bounds.width - w) / 2, y: CGFloat(Easel.titleTop) + 24, width: w, height: 48)
        for item in document.items { texts[item.id]?.frame = rect(item.frame) }
    }

    private func rect(_ r: Easel.Rect) -> NSRect { NSRect(x: r.x, y: r.y, width: r.width, height: r.height) }
    private func point(_ e: NSEvent) -> Easel.Point { let p = convert(e.locationInWindow, from: nil); return .init(p.x, p.y) }

    private func commit(_ change: (inout Easel) -> Void) {
        change(&document)
        needsDisplay = true
        onChange(document)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for item in document.items + [preview].compactMap({ $0 }) { draw(item) }
        if stroke.count > 1, let s = Easel.freehand(stroke) { draw(s) }
        if let id = selected, let item = document.items.first(where: { $0.id == id }) {
            if Easel.resizes(item.kind) {
                // Arc 1.172.1: a square 2 pt outline on the item's edge (#7FB8D6) and, at each corner,
                // a 7.5 pt ring of it round a 3 pt dark dot (8 Nov 2026, 2x stills).
                let r = rect(item.frame)
                Self.arcSelection.setStroke()
                let path = NSBezierPath(rect: r.insetBy(dx: -1, dy: -1))
                path.lineWidth = 2
                path.stroke()
                for c in [NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY)] {
                    Self.arcSelection.setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 3.75, y: c.y - 3.75, width: 7.5, height: 7.5)).fill()
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
                }
            } else {
                let r = rect(item.frame).insetBy(dx: -4, dy: -4)
                Self.selection.setStroke()
                let path = NSBezierPath(roundedRect: r, xRadius: Design.Radius.inset, yRadius: Design.Radius.inset)
                path.lineWidth = 2
                path.stroke()
            }
        }
    }

    private func draw(_ item: Easel.Item) {
        let color = item.color.flatMap { NSColor(hexString: $0) } ?? Self.ink
        color.setStroke()
        let r = rect(item.frame)
        switch item.kind {
        case .rectangle:
            let p = NSBezierPath(roundedRect: r, xRadius: Design.Radius.small, yRadius: Design.Radius.small); p.lineWidth = 3; p.stroke()
        case .ellipse:
            let p = NSBezierPath(ovalIn: r); p.lineWidth = 3; p.stroke()
        case .arrow(let a, let b):
            let p = NSBezierPath()
            p.move(to: NSPoint(x: a.x, y: a.y)); p.line(to: NSPoint(x: b.x, y: b.y))
            let angle = atan2(b.y - a.y, b.x - a.x), head = 16.0
            for side in [-0.5, 0.5] {
                p.move(to: NSPoint(x: b.x, y: b.y))
                p.line(to: NSPoint(x: b.x - head * cos(angle + side), y: b.y - head * sin(angle + side)))
            }
            p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .freehand(let pts):
            guard let first = pts.first else { return }
            let p = NSBezierPath()
            p.move(to: NSPoint(x: first.x, y: first.y))
            for q in pts.dropFirst() { p.line(to: NSPoint(x: q.x, y: q.y)) }
            p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case .image(let file):
            let image = images[file] ?? NSImage(contentsOf: EaselFiles.pictures(document.id).appendingPathComponent(file))
            images[file] = image
            image?.draw(in: r)
        case .text:
            break  // a text field of its own
        }
    }

    // MARK: Tools

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        dragStart = p
        dragLast = p
        switch tool {
        case .pointer:
            // A corner of the picked picture or shape resizes it; anywhere else picks (and moves).
            if let id = selected, let item = document.items.first(where: { $0.id == id }), Easel.resizes(item.kind),
               let corner = Easel.corner(of: item.frame, at: p) {
                resizing = (corner, item.frame)
                return
            }
            selected = document.item(at: p)?.id
        case .text:
            let item = Easel.Item(kind: .text("", size: 18), frame: .init(x: p.x, y: p.y - 12, width: 240, height: 26))
            commit { $0.items.append(item) }
            addTextField(for: item)
            selected = item.id
            window?.makeFirstResponder(texts[item.id])
            onToolDone()
        case .freehand:
            stroke = [p]
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        guard let start = dragStart, let last = dragLast else { return }
        dragLast = p
        switch tool {
        case .pointer:
            guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }) else { return }
            if let r = resizing {
                var keep = true
                if case .image = document.items[i].kind {} else { keep = event.modifierFlags.contains(.shift) }
                document.items[i].frame = Easel.resized(r.from, corner: r.corner, to: p, keepRatio: keep)
                needsDisplay = true
                return
            }
            document.items[i] = document.items[i].moved(by: .init(p.x - last.x, p.y - last.y))
            texts[id]?.frame = rect(document.items[i].frame)
            needsDisplay = true
        case .freehand:
            stroke.append(p)
            needsDisplay = true
        default:
            preview = Easel.Item.drawn(tool, from: start, to: p)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragLast = nil; preview = nil; stroke = []; resizing = nil }
        switch tool {
        case .pointer:
            if selected != nil { onChange(document); window?.invalidateCursorRects(for: self) }
        case .freehand:
            if stroke.count > 1, let item = Easel.freehand(stroke) { commit { $0.items.append(item) }; selected = nil }
        default:
            if let item = preview, item.frame.width + item.frame.height > 6 {
                commit { $0.items.append(item) }
                selected = item.id
                onToolDone()
            }
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, let id = selected {  // Delete, Forward Delete
            texts.removeValue(forKey: id)?.removeFromSuperview()
            selected = nil
            commit { $0.items.removeAll { $0.id == id } }
        } else if event.keyCode == 53 {
            selected = nil
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general) else { return }
        addPicture(image, at: nil)
    }

    func addPictureFromFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { if let image = NSImage(contentsOf: url) { self.addPicture(image, at: nil) } }
        }
    }

    private func addPicture(_ image: NSImage, at point: NSPoint?) {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let name = UUID().uuidString + ".png"
        try? png.write(to: EaselFiles.pictures(document.id).appendingPathComponent(name))
        let scale = min(1, 420 / max(image.size.width, image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let center = point ?? NSPoint(x: visible.midX, y: visible.midY)
        let item = Easel.Item(kind: .image(file: name), frame: .init(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                                     width: size.width, height: size.height))
        images[name] = image
        commit { $0.items.append(item) }
        selected = item.id
    }

    // Pictures and image files dropped on the canvas.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let at = convert(sender.draggingLocation, from: nil)
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] ?? []
        let pictures = urls.compactMap(NSImage.init(contentsOf:)) + (urls.isEmpty ? [NSImage(pasteboard: sender.draggingPasteboard)].compactMap { $0 } : [])
        for image in pictures { addPicture(image, at: at) }
        return !pictures.isEmpty
    }

    // MARK: Text

    /// The pill sits 20 pt left of the picked text box, level with its top (Arc: buttons 24 pt,
    /// 44 pt left of the title box).
    private func placeSizePill() {
        if titlePicked {
            sizePill.isHidden = false
            sizePill.frame = NSRect(origin: NSPoint(x: title.frame.minX - EaselSizePill.gap, y: title.frame.minY), size: EaselSizePill.size)
            return
        }
        guard let id = selected, let item = document.items.first(where: { $0.id == id }), case .text = item.kind else {
            sizePill.isHidden = true
            return
        }
        sizePill.isHidden = false
        sizePill.frame = NSRect(origin: NSPoint(x: item.frame.x - EaselSizePill.gap, y: item.frame.y), size: EaselSizePill.size)
    }

    /// Arc's four looks for the Aa button (Easel.FontStyle) in macOS's own designs.
    static func font(_ style: Easel.FontStyle?, size: Double, title: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: title ? .bold : .medium)
        switch style ?? .standard {
        case .standard: return base
        case .serif:
            let regular = NSFont.systemFont(ofSize: size, weight: .regular)
            return regular.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? regular
        case .wide: return NSFont.systemFont(ofSize: size, weight: .heavy, width: .expanded)
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }

    private func cycleSelectedStyle() {
        if titlePicked {
            commit { $0.titleStyle = ($0.titleStyle ?? .standard).next }
            title.font = Self.font(document.titleStyle, size: document.titleSize ?? Self.titleSize, title: true)
            return
        }
        guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        commit { $0.items[i].style = ($0.items[i].style ?? .standard).next }
        texts[id]?.font = Self.font(document.items[i].style, size: size, title: false)
    }

    /// Arc's Duplicate button: a copy of the picked item, 20 pt down and right, picked.
    func duplicateSelected() {
        guard let id = selected, let item = document.items.first(where: { $0.id == id }) else { return }
        var copy = item.moved(by: .init(20, 20))
        copy.id = UUID()
        if case .image(let file) = item.kind {
            let pics = EaselFiles.pictures(document.id), name = UUID().uuidString + ".png"
            try? FileManager.default.copyItem(at: pics.appendingPathComponent(file), to: pics.appendingPathComponent(name))
            copy.kind = .image(file: name)
        }
        commit { $0.items.append(copy) }
        if case .text = copy.kind { addTextField(for: copy) }
        selected = copy.id
    }

    private func resizeSelectedText(by step: Double) {
        if titlePicked {
            let new = min(96, max(14, (document.titleSize ?? Self.titleSize) + step))
            commit { $0.titleSize = new }
            title.font = Self.font(document.titleStyle, size: new, title: true)
            return
        }
        guard let id = selected, let i = document.items.firstIndex(where: { $0.id == id }),
              case .text(let string, let size) = document.items[i].kind else { return }
        let new = min(96, max(10, size + step))
        let height = ceil(new * 1.45)
        commit {
            $0.items[i].kind = .text(string, size: new)
            $0.items[i].frame.height = height
        }
        texts[id]?.font = Self.font(document.items[i].style, size: new, title: false)
        texts[id]?.frame = rect(document.items[i].frame)
        placeSizePill()
    }

    private func addTextField(for item: Easel.Item) {
        guard case .text(let string, let size) = item.kind else { return }
        let f = EaselTextField(string: string)
        let id = item.id
        f.onFocus = { [weak self] in self?.selected = id }
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Self.font(item.style, size: size, title: false)
        f.textColor = .white
        f.placeholderString = "Type something"
        f.delegate = self
        f.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
        f.frame = rect(item.frame)
        addSubview(f)
        texts[item.id] = f
    }

    /// A text box being typed in is the picked one: its size pill shows.
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === title { selected = nil; titlePicked = true; return }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else { return }
        selected = id
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === title {
            commit { $0.title = f.stringValue.isEmpty ? "Untitled Easel" : f.stringValue }
            return
        }
        guard let id = f.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let i = document.items.firstIndex(where: { $0.id == id }), case .text(_, let size) = document.items[i].kind else { return }
        let width = max(240, ceil(f.intrinsicContentSize.width) + 8)
        commit {
            $0.items[i].kind = .text(f.stringValue, size: size)
            $0.items[i].frame.width = width
        }
        f.frame.size.width = width
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .pointer ? .arrow : (tool == .text ? .iBeam : .crosshair))
        // The picked picture's or shape's corners: the diagonal resize cursors.
        guard tool == .pointer, let id = selected, let item = document.items.first(where: { $0.id == id }), Easel.resizes(item.kind) else { return }
        let f = item.frame, g = Easel.cornerGrab
        for (corner, x, y) in [(Easel.Corner.topLeft, f.x, f.y), (.topRight, f.x + f.width, f.y),
                               (.bottomLeft, f.x, f.y + f.height), (.bottomRight, f.x + f.width, f.y + f.height)] {
            let falling = corner == .topLeft || corner == .bottomRight
            addCursorRect(NSRect(x: x - g, y: y - g, width: 2 * g, height: 2 * g), cursor: falling ? Self.nwseCursor : Self.neswCursor)
        }
    }

    /// macOS's diagonal frame-resize cursors (macOS 15+), else the crosshair.
    static let nwseCursor: NSCursor = {
        if #available(macOS 15.0, *) { return NSCursor.frameResize(position: .topLeft, directions: .all) }
        return .crosshair
    }()
    static let neswCursor: NSCursor = {
        if #available(macOS 15.0, *) { return NSCursor.frameResize(position: .topRight, directions: .all) }
        return .crosshair
    }()
}

/// A text field that says when it takes the keyboard: clicking a text box picks it, and its
/// pill comes up before anything is typed.
final class EaselTextField: NSTextField {
    var onFocus: () -> Void = {}
    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        if took { onFocus() }
        return took
    }
}

/// Arc's text-size pill (AX "add", "FontIcon", "remove", 24 pt buttons on black).
@MainActor
final class EaselSizePill: NSView {
    var onStep: (Double) -> Void = { _ in }
    var onStyle: () -> Void = {}
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// One button, the three stacked, and how far left of its text box the pill's edge sits.
    static let button: CGFloat = 24
    static let size = NSSize(width: button, height: 3 * button)
    static let gap: CGFloat = 44

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Design.Radius.inset, yRadius: Design.Radius.inset).fill()
        let config = Design.Icon.configuration(Design.Icon.small, weight: .bold).applying(.init(paletteColors: [.white]))
        for (i, name) in ["plus", "textformat", "minus"].enumerated() {
            guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { continue }
            let r = NSRect(x: 0, y: CGFloat(i) * Self.button, width: Self.button, height: Self.button)
            img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        switch Int(y / Self.button) {
        case 0: onStep(4)
        case 1: onStyle()
        case 2: onStep(-4)
        default: break
        }
    }
}

/// The Easel toolbar: Select, Image, Text, Ellipse, Rectangle, Arrow, Draw, then Duplicate after a
/// divider. A dark glass capsule centred at the bottom of the canvas; the picked tool sits on a
/// light plate, the one under the pointer on a fainter one, and each button names itself on hover.
@MainActor
final class EaselToolbar: NSView, NSViewToolTipOwner {
    var onPick: (Easel.Tool) -> Void = { _ in }
    /// Arc's eighth button, Duplicate (AX "Duplicate"), after the tools.
    var onDuplicate: () -> Void = {}
    var tool: Easel.Tool = .pointer { didSet { needsDisplay = true } }
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }

    private static let symbols: [Easel.Tool: String] = [
        .pointer: "cursorarrow", .image: "photo", .text: "textformat", .ellipse: "circle",
        .rectangle: "square", .arrow: "arrow.up.right", .freehand: "scribble.variable",
    ]
    private static let names: [Easel.Tool: String] = [
        .pointer: "Select", .image: "Image", .text: "Text", .ellipse: "Ellipse", .rectangle: "Rectangle", .arrow: "Arrow", .freehand: "Draw",
    ]
    private static let bar = Design.panelDark.withAlphaComponent(0.92)
    private static let rim = Design.hairlineOnDark
    private static let picked = Design.fillOnDark(.strong)
    private static let hover = Design.fillOnDark(.selected)
    private static let glyph = Design.onDark(.primary)
    private static let button: CGFloat = 36, step: CGFloat = 38, pad: CGFloat = 6, divider: CGFloat = 13

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = Design.Shadow.panelColor.cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = Design.Shadow.panelRadius
        layer?.shadowOffset = CGSize(width: 0, height: -Design.Shadow.panelOffset)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    private var count: Int { Easel.Tool.allCases.count + 1 }

    override var fittingSize: NSSize {
        NSSize(width: 2 * Self.pad + CGFloat(count - 1) * Self.step + Self.button + Self.divider, height: Self.button + 2 * Self.pad)
    }

    /// Button `i`: the tools, then Duplicate past the divider.
    private func buttonRect(_ i: Int) -> NSRect {
        let x = Self.pad + CGFloat(i) * Self.step + (i == count - 1 ? Self.divider : 0)
        return NSRect(x: x, y: Self.pad, width: Self.button, height: Self.button)
    }

    override func layout() {
        super.layout()
        let r = bounds.height / 2
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        removeAllToolTips()
        for i in 0..<count { addToolTip(buttonRect(i), owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let i = index(at: point) else { return "" }
        return i < Easel.Tool.allCases.count ? Self.names[Easel.Tool.allCases[i]] ?? "" : "Duplicate"
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: r - 0.5, yRadius: r - 0.5)
        Self.bar.setFill()
        capsule.fill()
        Self.rim.setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        let config = Design.Icon.configuration(Design.Icon.bar, weight: .semibold).applying(.init(paletteColors: [Self.glyph]))
        func plate(_ rect: NSRect, _ color: NSColor) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        }
        func glyph(_ name: String, _ label: String, in rect: NSRect) {
            guard let img = NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(config) else { return }
            img.draw(in: NSRect(x: (rect.midX - img.size.width / 2).rounded(), y: (rect.midY - img.size.height / 2).rounded(),
                                width: img.size.width, height: img.size.height))
        }
        for (i, t) in Easel.Tool.allCases.enumerated() {
            let rect = buttonRect(i)
            if t == tool { plate(rect, Self.picked) } else if hovered == i { plate(rect, Self.hover) }
            glyph(Self.symbols[t] ?? "circle", Self.names[t] ?? "", in: rect)
        }
        let d = buttonRect(count - 1)
        Self.rim.setFill()
        NSRect(x: d.minX - Self.divider / 2 - 1.5, y: Self.pad + 9, width: 1, height: Self.button - 18).fill()
        if hovered == count - 1 { plate(d, Self.hover) }
        glyph("plus.square.on.square", "Duplicate", in: d)
    }

    private func index(at p: NSPoint) -> Int? { (0..<count).first { buttonRect($0).contains(p) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { hovered = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        if i < Easel.Tool.allCases.count { onPick(Easel.Tool.allCases[i]) } else { onDuplicate() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .toolbar }
    override func accessibilityLabel() -> String? { "Easel tools" }
}

private extension NSColor {
    convenience init?(hexString: String) {
        guard let c = HexColor.components(hexString) else { return nil }
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}
