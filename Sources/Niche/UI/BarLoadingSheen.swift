import AppKit

/// What a bar does while its page loads: a soft band of light crosses it, with a thin beam in the
/// accent along its lower edge, and both fade when the page has loaded and the bar has taken its
/// colour. The bar is not known to be right yet (the page hasn't drawn its top edge), so it says
/// that something is on its way instead of sitting there in a colour the page won't have.
/// Still under Reduce motion. Clicks go through it to the bar's buttons.
final class BarLoadingSheen: NSView {
    private enum Metrics {
        /// The band's width, as a share of the bar's.
        static let band: CGFloat = 0.42
        /// The beam along the bar's lower edge.
        static let beam: CGFloat = 1.5
        /// One crossing, and the rest before the next.
        static let crossing: TimeInterval = 1.25
        static let rest: TimeInterval = 0.35
        /// The band's ink at its middle, and the beam's accent.
        static let bandStrength: CGFloat = 0.14
        static let beamStrength: CGFloat = 0.9
    }

    private let band = CAGradientLayer()
    private let beam = CAGradientLayer()
    private(set) var isRunning = false
    /// The bar's ink: white on a dark bar, black on a light one.
    var ink = NSColor.white { didSet { if ink != oldValue { applyColors() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.opacity = 0
        for l in [band, beam] {
            l.startPoint = CGPoint(x: 0, y: 0.5)
            l.endPoint = CGPoint(x: 1, y: 0.5)
            l.actions = ["position": NSNull(), "bounds": NSNull(), "colors": NSNull()]
            layer?.addSublayer(l)
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func applyColors() {
        let clear = ink.withAlphaComponent(Design.Opacity.hidden).cgColor
        let accent = Design.accentNS
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.colors = [clear, ink.withAlphaComponent(Metrics.bandStrength).cgColor, clear]
        beam.colors = [accent.withAlphaComponent(Design.Opacity.hidden).cgColor, accent.withAlphaComponent(Metrics.beamStrength).cgColor, accent.withAlphaComponent(Design.Opacity.hidden).cgColor]
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let w = bounds.width * Metrics.band
        band.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
        beam.bounds = CGRect(x: 0, y: 0, width: w, height: Metrics.beam)
        // Parked off the bar's left end; the crossing moves them.
        band.position = CGPoint(x: -w / 2, y: bounds.midY)
        // Along the bar's lower edge, where it meets the page. A layer-backed view's sublayers
        // measure y from the top here unless the layer says it is flipped (seen on screen).
        let fromTop = layer?.isGeometryFlipped != true
        beam.position = CGPoint(x: -w / 2, y: fromTop ? bounds.height - Metrics.beam / 2 : Metrics.beam / 2)
        if isRunning { cross() }
    }

    /// Starts or ends the sheen. It fades both ways, so a page that loads at once shows a glint
    /// rather than a flash.
    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        guard let layer else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        let to: Float = running && !Design.Motion.reduced ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = running ? Design.Motion.fast : Design.Motion.slow
        layer.add(fade, forKey: "fade")
        if running {
            cross()
        } else {
            // The crossing under way finishes under the fade, then stops.
            DispatchQueue.main.asyncAfter(deadline: .now() + Design.Motion.slow) { [weak self] in
                guard let self, !self.isRunning else { return }
                self.band.removeAnimation(forKey: "cross")
                self.beam.removeAnimation(forKey: "cross")
            }
        }
    }

    private func cross() {
        guard !Design.Motion.reduced, bounds.width > 0 else { return }
        let w = bounds.width * Metrics.band
        for l in [band, beam] {
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = -w / 2
            move.toValue = bounds.width + w / 2
            move.duration = Metrics.crossing
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let cycle = CAAnimationGroup()
            cycle.animations = [move]
            cycle.duration = Metrics.crossing + Metrics.rest
            cycle.repeatCount = .infinity
            l.add(cycle, forKey: "cross")
        }
    }
}
