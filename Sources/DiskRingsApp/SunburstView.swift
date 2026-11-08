#if canImport(AppKit)
import AppKit
import QuartzCore
#if !SINGLE_MODULE
import DiskScanCore
import SunburstGeometry
#endif

@MainActor
protocol SunburstViewDelegate: AnyObject {
    func sunburstView(_ view: SunburstView, didSelect node: FileNode?, sector: Int?)
    func sunburstView(_ view: SunburstView, drillInto node: FileNode)
    func sunburstViewRequestsParent(_ view: SunburstView)
    func sunburstView(_ view: SunburstView, didHover sector: Int?)
    func sunburstView(_ view: SunburstView, collect node: FileNode)
    func sunburstView(_ view: SunburstView, dragNodes nodes: [FileNode])
}

/// Finder-style sunburst (simplify-v2 variant 1). Draws ONLY from a cached
/// `ChartModel` (≤150 sectors, design units). One CAShapeLayer per sector under
/// a container whose transform maps design units → view; `layout()` changes the
/// transform only. Hover changes opacity, selection a 2 pt stroke layer, and an
/// appearance change swaps precomputed colours. No tree walks here.
final class SunburstView: NSView, NSDraggingSource {
    weak var delegate: SunburstViewDelegate?

    private(set) var model: ChartModel<FileNode>?
    private let container = CALayer()
    private var sectorLayers: [CAShapeLayer] = []
    private var labelLayers: [CALayer] = []
    private var labelSectors: [Int] = []
    private let selectionLayer = CAShapeLayer()
    private let hoverLayer = CAShapeLayer()      // 1.5 pt textPrimary hover stroke
    private let centerName = NSTextField.label("", size: 13, weight: .semibold)
    private let centerSize = NSTextField.label("", size: 26, weight: .semibold)
    private let centerSub = NSTextField.label("", size: 11, color: .drTextSecondary)
    private let emptyLabel = NSTextField.label("", size: 13, color: .drTextSecondary)
    private let hintLabel = NSTextField.label(tr("chart.hint"), size: 11, color: .drTextSecondary)
    private var focusTexts = ("", "", "")
    /// Selection outline / hover / tooltip against the current layout (testable model).
    private var outlineState = ChartOutlineState<FileNode>()
    var hoverIndex: Int? { outlineState.hoverIndex }
    var selectedIndex: Int? { outlineState.selectedIndex }
    private var hatch: NSColor?
    /// Centre label width = min(160, 2·92·k − 16) (P2-7), updated in layout.
    private let centerStack = NSStackView()
    private lazy var centerWidth: NSLayoutConstraint = centerStack.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
    private var centerK: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(container)
        selectionLayer.fillColor = nil
        selectionLayer.lineJoin = .round
        selectionLayer.isHidden = true
        hoverLayer.fillColor = nil
        hoverLayer.lineJoin = .round
        hoverLayer.isHidden = true
        centerSize.font = .drNumber(26, weight: .semibold)
        for l in [centerName, centerSize, centerSub] { l.alignment = .center; l.lineBreakMode = .byTruncatingMiddle }
        let stack = centerStack
        for v in [centerName, centerSize, centerSub] { stack.addArrangedSubview(v) }
        for v in [centerName, centerSize, centerSub] { v.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true }
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(emptyLabel)
        addSubview(hintLabel)
        emptyLabel.alignment = .center
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            centerWidth,
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        setEmpty(tr("chart.empty"))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: Model

    /// Installs a new cached model (rebuild path). Builds ≤150 layers once.
    func setModel(_ m: ChartModel<FileNode>?, focusName: String, focusSize: String, focusSub: String) {
        model = m
        labelPolicy.reset(m?.labelTier ?? 1)
        focusTexts = (focusName, focusSize, focusSub)
        // Never carry the previous layout's outline/hover/tooltip into the new one (stale
        // hollow wedge after drilling): keep the selection only if its node is still a sector.
        outlineState.layoutChanged(m)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        sectorLayers = []; labelLayers = []; labelSectors = []
        if let m {
            emptyLabel.isHidden = true
            hintLabel.isHidden = false
            for s in m.sectors {
                let sl = CAShapeLayer()
                sl.path = Self.path(for: s)
                sl.lineWidth = CGFloat(m.layout.config.gapPoints)
                sl.lineJoin = .round
                container.addSublayer(sl)
                sectorLayers.append(sl)
            }
            container.addSublayer(hoverLayer)
            container.addSublayer(selectionLayer)
            addLabelLayers(m)
        } else {
            hintLabel.isHidden = true
        }
        applyColors()
        applyOutline()
        CATransaction.commit()
        toolTip = nil
        showCenter(nil)
        needsLayout = true
    }

    func setEmpty(_ text: String) {
        setModel(nil, focusName: "", focusSize: "", focusSub: "")
        emptyLabel.stringValue = text
        emptyLabel.isHidden = false
        showCenter(nil)
    }

    static func path(for s: ChartModel<FileNode>.Sector) -> CGPath {
        let p = CGMutablePath()
        // Layout angles: clockwise from 12 o'clock; CG angles: counter-clockwise from +x.
        let a0 = CGFloat.pi / 2 - CGFloat(s.startAngle), a1 = CGFloat.pi / 2 - CGFloat(s.endAngle)
        let full = s.endAngle - s.startAngle >= 2 * Double.pi - 1e-6
        if full {
            p.addEllipse(in: CGRect(x: -s.outerRadius, y: -s.outerRadius, width: 2 * s.outerRadius, height: 2 * s.outerRadius))
            p.addEllipse(in: CGRect(x: -s.innerRadius, y: -s.innerRadius, width: 2 * s.innerRadius, height: 2 * s.innerRadius))
            return p
        }
        p.addArc(center: .zero, radius: CGFloat(s.outerRadius), startAngle: a0, endAngle: a1, clockwise: true)
        p.addArc(center: .zero, radius: CGFloat(s.innerRadius), startAngle: a1, endAngle: a0, clockwise: false)
        p.closeSubpath()
        return p
    }

    private func addLabelLayers(_ m: ChartModel<FileNode>) {
        for s in m.sectors { if let l = makeLabel(s) { container.addSublayer(l); labelLayers.append(l); labelSectors.append(s.index) } }
    }

    /// Label scale tiers (designer 2026-10-13): labels are re-laid out only when the tier
    /// changes, and not during a live resize (checked again in `viewDidEndLiveResize`).
    private var labelPolicy = LabelLayout.RelayoutPolicy()

    private func applyLabelTier(_ t: Double) {
        guard var m = model, m.applyLabelScale(t) else { return }
        model = m
        outlineState.layoutChanged(m)          // same geometry, but never keep stale hover/tooltip
        toolTip = nil
        showCenter(nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        labelLayers.forEach { $0.removeFromSuperlayer() }
        labelLayers = []; labelSectors = []
        addLabelLayers(m)
        applyColors()
        applyOutline()
        CATransaction.commit()
        applyOpacities()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        if let t = labelPolicy.liveResizeEnded(scale: Double(scale)) { applyLabelTier(t) }
    }

    private func makeLabel(_ s: ChartModel<FileNode>.Sector) -> CALayer? {
        let mid = SunburstLayout<FileNode>.point(angle: s.midAngle, radius: (s.innerRadius + s.outerRadius) / 2)
        let scale = (window?.backingScaleFactor ?? 2) * 1.15
        if s.isProtected {
            guard s.span * (s.innerRadius + s.outerRadius) / 2 > 18 else { return nil }
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 12, height: 14)
            l.position = CGPoint(x: mid.x, y: mid.y)
            l.contentsGravity = .resizeAspect
            l.name = "lock"
            return l
        }
        let lab = s.label
        guard lab.tier != .hidden else { return nil }
        // Pre-placed by LabelLayout (tier, box, rotation): build text layers only.
        let group = CALayer()
        group.name = "label"
        group.bounds = CGRect(x: 0, y: 0, width: lab.width, height: lab.height)
        group.position = CGPoint(x: lab.center.x, y: lab.center.y)
        if lab.rotation != 0 { group.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(lab.rotation))) }
        func line(_ text: String, size: Double, weight: NSFont.Weight, y: Double, h: Double) -> CATextLayer {
            let t = CATextLayer()
            t.contentsScale = scale
            t.alignmentMode = .center
            t.truncationMode = .end   // text is pre-fitted; .end only guards estimate error
            t.isWrapped = false
            t.string = text
            let font = weight == .regular ? NSFont.drNumber(CGFloat(size)) : NSFont.systemFont(ofSize: CGFloat(size), weight: weight)
            t.font = font
            t.fontSize = font.pointSize
            t.opacity = 1
            t.frame = CGRect(x: 0, y: y, width: lab.width, height: h + 1)
            return t
        }
        // Fonts/line heights come from the label (per scale tier, ≥ 10 pt on screen); ink opacity 1.0.
        switch lab.tier {
        case .nameAndSize:
            group.addSublayer(line(lab.lines[0], size: lab.nameFont, weight: .medium, y: lab.sizeLine, h: lab.nameLine))
            group.addSublayer(line(lab.lines[1], size: lab.sizeFont, weight: .regular, y: 0, h: lab.sizeLine))
        case .sizeOnly:
            group.addSublayer(line(lab.lines[0], size: lab.sizeFont, weight: .regular, y: 0, h: lab.sizeLine))
        case .rotated:
            let isSize = lab.isSizeLine
            group.addSublayer(line(lab.lines[0], size: isSize ? lab.sizeFont : lab.nameFont,
                                   weight: isSize ? .regular : .medium, y: 0, h: isSize ? lab.sizeLine : lab.nameLine))
        case .hidden:
            return nil
        }
        return group
    }

    private func applyColors() {
        guard let m = model else { return }
        let mode = themeMode
        let bg = resolvedCGColor(.windowBackgroundColor)
        if hatch == nil || hatchMode != mode { hatch = Self.hatchColor(mode); hatchMode = mode }
        for (i, s) in m.sectors.enumerated() {
            let c = mode == .light ? s.color.light : s.color.dark
            sectorLayers[i].fillColor = s.color.role == .protected ? hatch!.cgColor : NSColor(c).cgColor
            sectorLayers[i].strokeColor = bg
        }
        selectionLayer.strokeColor = resolvedCGColor(.labelColor)
        hoverLayer.strokeColor = resolvedCGColor(.labelColor)
        let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        for (j, l) in labelLayers.enumerated() {
            if l.name == "label" {
                // Ink picked per sector for contrast against its fill (LabelLayout.ink).
                let sec = m.sectors[labelSectors[j]]
                let c = NSColor(mode == .light ? sec.inkLight : sec.inkDark).cgColor
                for t in l.sublayers ?? [] { (t as? CATextLayer)?.foregroundColor = c }
            } else if l.name == "lock", let lock {
                let tinted = NSImage(size: NSSize(width: 12, height: 14), flipped: false) { r in
                    lock.draw(in: r)
                    (mode == .light ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.9, blue: 0.92, alpha: 1)).set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                l.contents = tinted.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
            }
        }
    }
    private var hatchMode: ThemeMode?

    /// 45° hatch over the protected grey (README §4.5), 6 pt period.
    static func hatchColor(_ mode: ThemeMode) -> NSColor {
        let base = NSColor(SunburstPalette.fixed(.protected, mode))
        let img = NSImage(size: NSSize(width: 6, height: 6), flipped: false) { r in
            base.setFill(); r.fill()
            (mode == .light ? NSColor(white: 0, alpha: 0.13) : NSColor(white: 1, alpha: 0.13)).setStroke()
            let p = NSBezierPath(); p.lineWidth = 1.7
            p.move(to: NSPoint(x: -1, y: -1)); p.line(to: NSPoint(x: 7, y: 7))
            p.move(to: NSPoint(x: -4, y: 2)); p.line(to: NSPoint(x: 2, y: 8))
            p.move(to: NSPoint(x: 4, y: -2)); p.line(to: NSPoint(x: 8, y: 2))
            p.stroke()
            return true
        }
        return NSColor(patternImage: img)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyColors()          // colour swap only — no rebuild
        CATransaction.commit()
    }

    // MARK: Transform-only resize

    var scale: CGFloat { CGFloat(ChartModel<FileNode>.scale(width: Double(bounds.width), height: Double(bounds.height))) }
    var chartCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY + 10) }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let k = scale
        container.anchorPoint = .zero      // sublayerTransform is applied about the anchor
        container.frame = bounds
        container.sublayerTransform = CATransform3DConcat(CATransform3DMakeScale(k, k, 1),
                                                          CATransform3DMakeTranslation(chartCenter.x, chartCenter.y, 0))
        selectionLayer.lineWidth = 2 / k
        hoverLayer.lineWidth = 1.5 / k
        CATransaction.commit()
        if let t = labelPolicy.boundsChanged(scale: Double(k), inLiveResize: inLiveResize) { applyLabelTier(t) }
        if abs(k - centerK) > 0.005 {      // P2-7: centre text fits the hole (radius 92·k)
            centerK = k
            centerWidth.constant = min(160, 2 * 92 * k - 16)
            centerSize.font = .drNumber(28 * max(k, 0.85), weight: .semibold)
        }
    }

    // MARK: Hover / selection

    func sectorIndex(at viewPoint: NSPoint) -> SunburstHit {
        guard let m = model else { return .none }
        let k = Double(scale), c = chartCenter
        return m.layout.hitTest(Point2D(x: Double(viewPoint.x - c.x) / k, y: Double(viewPoint.y - c.y) / k))
    }

    /// Opacity-only hover (other branches → 0.42). `notify` = false when driven by the outline.
    /// Hover branch → sector and label opacity.
    private func applyOpacities() {
        guard let m = model else { return }
        let ops = m.opacities(hover: hoverIndex)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, l) in sectorLayers.enumerated() where i < ops.count { l.opacity = Float(ops[i]) }
        // Labels outside the hovered branch fade with their sector.
        for (j, l) in labelLayers.enumerated() { l.opacity = ops[labelSectors[j]] < 1 ? 0 : 1 }
        CATransaction.commit()
    }

    func setHover(_ index: Int?, notify: Bool = false) {
        guard model != nil, outlineState.hover(index, in: model, path: { $0.displayPath }) else { return }
        applyOpacities()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyOutline()
        CATransaction.commit()
        // Sectors whose label is hidden or shortened: name, path, size · share as tooltip.
        toolTip = outlineState.tooltip
        showCenter(index)
        if notify { delegate?.sunburstView(self, didHover: index) }
    }

    func setSelected(_ index: Int?) {
        outlineState.select(index, in: model)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyOutline()
        CATransaction.commit()
    }

    /// Draws exactly the state's outlines (geometry recomputed from the current layout), or hides them.
    private func applyOutline() {
        func set(_ layer: CAShapeLayer, _ o: ChartOutlineState<FileNode>.Outline?) {
            guard let o else { layer.path = nil; layer.isHidden = true; return }
            let p = CGMutablePath()
            let a0 = CGFloat.pi / 2 - CGFloat(o.start), a1 = CGFloat.pi / 2 - CGFloat(o.end)
            if o.end - o.start >= 2 * Double.pi - 1e-6 {
                p.addEllipse(in: CGRect(x: -o.outer, y: -o.outer, width: 2 * o.outer, height: 2 * o.outer))
                p.addEllipse(in: CGRect(x: -o.inner, y: -o.inner, width: 2 * o.inner, height: 2 * o.inner))
            } else {
                p.addArc(center: .zero, radius: CGFloat(o.outer), startAngle: a0, endAngle: a1, clockwise: true)
                p.addArc(center: .zero, radius: CGFloat(o.inner), startAngle: a1, endAngle: a0, clockwise: false)
                p.closeSubpath()
            }
            layer.path = p
            layer.isHidden = false
        }
        set(selectionLayer, outlineState.outline)
        set(hoverLayer, outlineState.hoverOutline)
    }

    private func showCenter(_ index: Int?) {
        if let i = index, let m = model, i < m.sectors.count {
            let s = m.sectors[i]
            centerName.stringValue = (s.isHighRisk ? "⚠ " : "") + s.name
            centerSize.stringValue = s.sizeText
            let share = m.layout.rootSize > 0 ? s.size / m.layout.rootSize * 100 : 0
            centerSub.stringValue = String(format: "%.1f%%", share)
        } else {
            centerName.stringValue = focusTexts.0
            centerSize.stringValue = focusTexts.1
            centerSub.stringValue = focusTexts.2
        }
    }

    // MARK: Mouse

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if case let .segment(i) = sectorIndex(at: p) { setHover(i, notify: true) } else { setHover(nil, notify: true) }
    }
    override func mouseExited(with event: NSEvent) { setHover(nil, notify: true) }

    private var dragStartPoint: NSPoint?
    private var dragSectorIndex: Int?
    private var didStartBasketDrag = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        didStartBasketDrag = false
        let p = convert(event.locationInWindow, from: nil)
        dragStartPoint = p
        switch sectorIndex(at: p) {
        case .center:
            dragSectorIndex = nil
            delegate?.sunburstViewRequestsParent(self)
        case let .segment(i):
            dragSectorIndex = i
            guard let s = model?.sectors[i] else { return }
            if event.clickCount >= 2, let n = s.node, n.isDirectory, !n.children.isEmpty {
                dragStartPoint = nil
                delegate?.sunburstView(self, drillInto: n)
            } else {
                setSelected(i)
                delegate?.sunburstView(self, didSelect: s.node, sector: i)
            }
        case .none:
            dragSectorIndex = nil
            setSelected(nil)
            delegate?.sunburstView(self, didSelect: nil, sector: nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartBasketDrag, let start = dragStartPoint, let i = dragSectorIndex,
              let n = model?.sectors[i].node else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - start.x, dy = p.y - start.y
        guard (dx * dx + dy * dy) >= 36 else { return }   // 6 pt threshold
        didStartBasketDrag = true
        let pbItem = NSPasteboardItem()
        _ = pbItem.setString(BasketDrag.encodePaths([n.path]), forType: .init(BasketDrag.pasteboardType))
        let item = NSDraggingItem(pasteboardWriter: pbItem)
        let frame = NSRect(x: p.x - 16, y: p.y - 10, width: 120, height: 24)
        item.setDraggingFrame(frame, contents: n.name as NSString)
        beginDraggingSession(with: [item], event: event, source: self)
        delegate?.sunburstView(self, dragNodes: [n])
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        dragSectorIndex = nil
        didStartBasketDrag = false
        super.mouseUp(with: event)
    }

    // MARK: Keyboard (P2-11): ←/→ siblings, ↓ child ring, ↑ parent ring; ⌘↓ / ⌘↑ are
    // the View-menu drill-in / go-up items. ↩ is deliberately NOT used (P1-1).

    override func keyDown(with event: NSEvent) {
        guard let m = model, !event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        let step: ChartModel<FileNode>.Step?
        switch event.specialKey {
        case .leftArrow?: step = .previous
        case .rightArrow?: step = .next
        case .downArrow?: step = .child
        case .upArrow?: step = .parent
        default: step = nil
        }
        if let st = step {
            guard let i = m.step(from: selectedIndex, st) else { NSSound.beep(); return }
            setSelected(i)
            setHover(nil, notify: true)
            delegate?.sunburstView(self, didSelect: m.sectors[i].node, sector: i)
        } else if event.charactersIgnoringModifiers == " ", let i = selectedIndex, let n = m.sectors[i].node {
            delegate?.sunburstView(self, collect: n)
        } else {
            super.keyDown(with: event)
        }
    }

    override func drawFocusRingMask() { }
    override var focusRingMaskBounds: NSRect { .zero }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard case let .segment(i) = sectorIndex(at: p), let n = model?.sectors[i].node else { return nil }
        let menu = NSMenu()
        let item = menu.addItem(withTitle: tr("button.addToBasket"), action: #selector(collectFromMenu(_:)), keyEquivalent: "")
        item.representedObject = n
        item.target = self
        return menu
    }
    @objc private func collectFromMenu(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? FileNode { delegate?.sunburstView(self, collect: n) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }
}
#endif
