#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE
import DiskScanCore
import SunburstGeometry
#endif

/// Top disk-capacity bar (simplify-v2/capacity-bar). Standard 76 pt: title row,
/// 10 pt bar, one-line legend. Compact 36 pt (content height < 720): title | bar |
/// used/total on one line, no legend. Segments come from `CapacityBarModel` (root
/// level, built once per scan root + tree generation). Resize = frames only; hover =
/// opacity only; drill-down = `setScope` (colour/opacity + bracket). While scanning
/// it shows progress + Stop; transient notices take the legend row for a few seconds.
final class CapacityBarView: NSView, NSViewToolTipOwner {
    typealias Model = CapacityBarModel<FileNode>
    var onNavigate: ((FileNode) -> Void)?
    /// Legend / tooltip / accessibility texts per segment (app supplies size formatting).
    var sizeText: (Double) -> String = { SizeText.format(UInt64(max(0, $0))) }

    let stopButton = NSButton(title: tr("button.stop"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField.label("", size: 13, weight: .semibold)
    private let usedLabel = NSTextField.label("", size: 13, color: .drTextSecondary)
    private let legendRow = NSStackView()
    private let noticeLabel = NSTextField.label("", size: 11, color: .drTextSecondary)
    private let barHost = NSView()
    private let track = CALayer()
    private var segLayers: [CALayer] = []
    private let bracket = CAShapeLayer()
    private let line = CALayer()
    private var axElements: [SegmentElement] = []
    private var heightC: NSLayoutConstraint!

    private(set) var model: Model?
    private var scope: Model.Scope?
    private var currentText: String?
    private var hover: Int?
    private var scanning = false
    private var noticeTimer: Timer?
    private var lastLegendWidth: CGFloat = -1
    private var hatch: NSColor?
    private var hatchMode: ThemeMode?

    var compact = false { didSet { if compact != oldValue { applyMode() } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(line)
        barHost.wantsLayer = true
        barHost.translatesAutoresizingMaskIntoConstraints = false
        barHost.layer?.addSublayer(track)
        track.cornerRadius = 3
        track.masksToBounds = true
        track.borderWidth = 0.5                       // thin stroke on the free-space track
        bracket.fillColor = nil
        bracket.lineWidth = 1.5
        bracket.isHidden = true
        barHost.layer?.addSublayer(bracket)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        // Regular-size Stop (review ruling on deviation 1); ⌘. stays in the File menu.
        stopButton.bezelStyle = .rounded; stopButton.controlSize = .regular; stopButton.font = .systemFont(ofSize: 13)
        stopButton.isHidden = true
        usedLabel.font = .drNumber(13)
        usedLabel.alignment = .right
        usedLabel.lineBreakMode = .byTruncatingMiddle
        usedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        legendRow.orientation = .horizontal
        legendRow.spacing = 14
        legendRow.alignment = .centerY
        noticeLabel.lineBreakMode = .byTruncatingMiddle
        noticeLabel.isHidden = true
        for v in [titleLabel, usedLabel, spinner, stopButton, legendRow, noticeLabel, barHost] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        heightC = heightAnchor.constraint(equalToConstant: 76)
        heightC.isActive = true
        applyMode()
        applyColors()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // MARK: Layout (frames only — no model work)

    private var modeConstraints: [NSLayoutConstraint] = []
    private func applyMode() {
        NSLayoutConstraint.deactivate(modeConstraints)
        let pad: CGFloat = compact ? 20 : 24
        heightC.constant = compact ? 36 : 76
        if compact {
            modeConstraints = [
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                barHost.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 14),
                barHost.centerYAnchor.constraint(equalTo: centerYAnchor),
                barHost.heightAnchor.constraint(equalToConstant: 8 + 9),
                usedLabel.leadingAnchor.constraint(equalTo: barHost.trailingAnchor, constant: 14),
                usedLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                spinner.leadingAnchor.constraint(equalTo: usedLabel.trailingAnchor, constant: 6),
                spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
                stopButton.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
                stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
                usedLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.4),
            ]
        } else {
            modeConstraints = [
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),
                usedLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
                usedLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),
                spinner.leadingAnchor.constraint(equalTo: usedLabel.trailingAnchor, constant: 6),
                spinner.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                stopButton.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
                stopButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
                barHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
                barHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
                barHost.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                barHost.heightAnchor.constraint(equalToConstant: 10 + 9),   // bar + bracket room
                legendRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
                legendRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -pad),
                legendRow.topAnchor.constraint(equalTo: barHost.topAnchor, constant: 10 + 8),
                noticeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
                noticeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -pad),
                noticeLabel.centerYAnchor.constraint(equalTo: legendRow.centerYAnchor),
                legendRow.heightAnchor.constraint(equalToConstant: 14),
            ]
        }
        NSLayoutConstraint.activate(modeConstraints)
        legendRow.isHidden = compact || noticeVisible
        noticeLabel.isHidden = compact || !noticeVisible
        lastLegendWidth = -1; shownLegend = nil
        refreshTexts()
        needsLayout = true
    }

    private var barHeight: CGFloat { compact ? 8 : 10 }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        line.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let w = barHost.bounds.width
        track.frame = CGRect(x: 0, y: 0, width: w, height: barHeight)
        if let m = model {
            for (i, s) in m.segments.enumerated() where i < segLayers.count {
                let x0 = (CGFloat(s.start) * w).rounded(.down), x1 = CGFloat(s.end) * w
                segLayers[i].frame = CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: barHeight)
                segLayers[i].sublayers?.first?.frame = CGRect(x: max(0, x1 - x0 - 1.5), y: 0, width: 1.5, height: barHeight)
            }
        }
        layoutBracket()
        CATransaction.commit()
        if !compact && abs(barHost.bounds.width - lastLegendWidth) > 0.5 { lastLegendWidth = barHost.bounds.width; refitLegend() }
        if !inLiveResize { rebuildToolTipsAndAX() }
    }

    private func layoutBracket() {
        guard let b = scope?.bracket else { bracket.isHidden = true; return }
        let w = barHost.bounds.width
        let x0 = CGFloat(b.lowerBound) * w + 0.75, x1 = CGFloat(b.upperBound) * w - 0.75
        let y0 = barHeight + 2, y1 = barHeight + 2 + 5
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x0, y: y1))
        p.addLine(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x1, y: y0))
        bracket.path = p
        bracket.isHidden = false
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        rebuildToolTipsAndAX()
    }

    // MARK: Model / state

    func setVolumeTitle(_ title: String) { titleLabel.stringValue = title }

    /// New root-level model (once per scan root + tree generation).
    func setModel(_ m: Model?) {
        model = m
        hover = nil
        scope = nil
        widthCache = [:]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        segLayers.forEach { $0.removeFromSuperlayer() }
        segLayers = (m?.segments ?? []).map { _ in
            let l = CALayer()
            l.addSublayer(CALayer())       // 1.5 pt right-edge gap in the window colour
            track.addSublayer(l)
            return l
        }
        CATransaction.commit()
        applyColors()
        lastLegendWidth = -1; shownLegend = nil
        refreshTexts()
        needsLayout = true
    }

    /// Drill-down marking: colour/opacity + bracket; nil text = at the scan root.
    func setScope(_ s: Model.Scope?, currentText: String?) {
        scope = s
        self.currentText = currentText
        applyColors()
        lastLegendWidth = -1; shownLegend = nil
        needsLayout = true
    }

    func setScanning(_ on: Bool, progress: String? = nil) {
        scanning = on
        stopButton.isHidden = !on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if on { setModel(nil) }
        if let progress { usedLabel.stringValue = progress } else { refreshTexts() }
    }

    func setProgress(_ text: String) { if scanning { usedLabel.stringValue = text } }

    /// Transient status (refused adds, deletion summary, scan notes). P2-5: duration
    /// clamp(8 s + 1 s per 10 characters, 8, 15), paused while the pointer is over the
    /// bar, announced to VoiceOver; in compact mode 「已使用…」 moves to the tooltip.
    private var noticeVisible: Bool { !noticeLabel.stringValue.isEmpty }
    private var noticeRemaining: TimeInterval = 0
    private var noticeStarted = Date()
    private var pointerInside = false
    func showNotice(_ text: String, seconds: TimeInterval? = nil) {
        noticeTimer?.invalidate(); noticeTimer = nil
        noticeLabel.stringValue = text
        noticeLabel.toolTip = text
        if compact {
            refreshTexts()
        } else {
            noticeLabel.isHidden = text.isEmpty
            legendRow.isHidden = !text.isEmpty
        }
        guard !text.isEmpty else { refreshTexts(); return }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        noticeRemaining = seconds ?? CapacityNotice.duration(forText: text)
        if !pointerInside { startNoticeTimer() }
    }
    private func startNoticeTimer() {
        guard noticeVisible, noticeRemaining > 0 else { return }
        noticeStarted = Date()
        noticeTimer = Timer.scheduledTimer(timeInterval: noticeRemaining, target: self, selector: #selector(noticeExpired(_:)),
                                           userInfo: nil, repeats: false)
    }
    private func pauseNoticeTimer() {
        guard let t = noticeTimer else { return }
        t.invalidate(); noticeTimer = nil
        noticeRemaining = max(1, noticeRemaining - Date().timeIntervalSince(noticeStarted))
    }
    override func mouseEntered(with event: NSEvent) { pointerInside = true; pauseNoticeTimer() }

    @objc private func noticeExpired(_ t: Timer) { showNotice("") }

    private func refreshTexts() {
        guard !scanning else { return }
        guard let m = model else { usedLabel.stringValue = ""; return }
        let used = m.total > m.scanned || m.used != m.scanned
            ? tr("capacity.used", sizeText(m.used), sizeText(m.total))
            : tr("capacity.scanned", sizeText(m.scanned))
        if compact && noticeVisible {
            usedLabel.stringValue = noticeLabel.stringValue
            usedLabel.toolTip = used                 // restored when the notice ends
        } else {
            usedLabel.stringValue = used
            usedLabel.toolTip = nil
        }
    }

    // MARK: Colours (appearance swap only)

    private func color(for i: Int, _ mode: ThemeMode) -> CGColor {
        guard let m = model else { return .clear }
        let s = m.segments[i]
        let inScope = scope?.inScope[i] ?? true
        if !inScope { return NSColor(SunburstPalette.fixed(.other, mode)).cgColor }
        if s.kind == .protected {
            if hatch == nil || hatchMode != mode { hatch = SunburstView.hatchColor(mode); hatchMode = mode }
            return hatch!.cgColor
        }
        return NSColor(mode == .light ? s.light : s.dark).cgColor
    }

    private func applyColors() {
        let mode = themeMode
        CATransaction.begin(); CATransaction.setDisableActions(true)
        line.backgroundColor = resolvedCGColor(.drSeparator)
        track.backgroundColor = resolvedCGColor(.drToken)
        track.borderColor = resolvedCGColor(.separatorColor)
        bracket.strokeColor = resolvedCGColor(NSColor.labelColor.withAlphaComponent(0.7))
        let gapColor = resolvedCGColor(.windowBackgroundColor)
        for i in segLayers.indices {
            let l = segLayers[i]
            l.backgroundColor = color(for: i, mode)
            let inScope = scope?.inScope[i] ?? true
            l.opacity = !inScope ? 0.55 : (hover == nil || hover == i ? 1 : 0.6)
            l.sublayers?.first?.backgroundColor = gapColor
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        widthCache = [:]
        applyColors()
        lastLegendWidth = -1; shownLegend = nil
        needsLayout = true
    }

    // MARK: Legend (one line, never wraps)

    private func legendText(_ it: Model.LegendItem, _ m: Model) -> (String, String) {
        switch it.kind {
        case let .branch(i): return (m.segments[i].name, sizeText(it.bytes))
        case let .folded(list): return (tr("capacity.more", list.count), sizeText(it.bytes))
        case .protected: return (tr("capacity.protected"), sizeText(it.bytes))
        case .other: return (tr("capacity.other"), sizeText(it.bytes))
        case .systemGap: return (tr("capacity.system"), sizeText(it.bytes))
        case .free: return (tr("capacity.free"), sizeText(it.bytes))
        }
    }
    private func legendDot(_ it: Model.LegendItem, _ m: Model, _ mode: ThemeMode) -> NSColor {
        switch it.kind {
        case let .branch(i): return NSColor(mode == .light ? m.segments[i].light : m.segments[i].dark)
        case .folded: return .clear
        case .protected: return SunburstView.hatchColor(mode)
        case .other, .systemGap: return NSColor(SunburstPalette.fixed(.other, mode))
        case .free: return .drToken
        }
    }
    private static let nameFont = NSFont.systemFont(ofSize: 11)
    private static let valueFont = NSFont.drNumber(11)
    /// Measured legend item widths, keyed by text (P2-4): filled on model/appearance
    /// change and for new “+N 项” strings only; resizes reuse them.
    private var widthCache: [String: Double] = [:]
    private var shownLegend: [Model.LegendItem]?
    private var shownCurrentText: String??
    private func itemWidth(_ it: Model.LegendItem, _ m: Model) -> Double {
        let (n, v) = legendText(it, m)
        let k = n + "\u{1}" + v
        if let w = widthCache[k] { return w }
        let w = (n as NSString).size(withAttributes: [.font: Self.nameFont]).width
            + (v as NSString).size(withAttributes: [.font: Self.valueFont]).width
        let r = Double(ceil(w) + 8 + 5 + 4)
        widthCache[k] = r
        return r
    }

    /// Recomputes the fold only; views are rebuilt only when the result changes.
    private func refitLegend() {
        guard let m = model, !compact else { rebuildLegend(items: [], force: true); return }
        let items = currentText == nil ? m.fittedLegend(width: Double(barHost.bounds.width), itemWidth: { self.itemWidth($0, m) }) : []
        rebuildLegend(items: items, force: false)
    }

    private func rebuildLegend(items: [Model.LegendItem], force: Bool) {
        if !force, shownLegend == items, shownCurrentText == .some(currentText) { return }
        shownLegend = items
        shownCurrentText = .some(currentText)
        legendRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let m = model, !compact else { return }
        if let cur = currentText {
            let a = NSMutableAttributedString(string: cur, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor])
            a.append(NSAttributedString(string: "  " + tr("capacity.scopeHint"), attributes: [.font: Self.nameFont, .foregroundColor: NSColor.drTextSecondary]))
            let l = NSTextField(labelWithAttributedString: a)
            l.lineBreakMode = .byTruncatingTail
            legendRow.addArrangedSubview(l)
            return
        }
        let mode = themeMode
        for it in items {
            let (n, v) = legendText(it, m)
            var isFolded = false
            if case .folded = it.kind { isFolded = true }
            let b = LegendItemButton(dot: legendDot(it, m, mode), strokeDot: it.kind == .free, name: n, value: v,
                                     nameColor: isFolded ? .drTextSecondary : .labelColor,
                                     nameFont: Self.nameFont, valueFont: Self.valueFont)
            switch it.kind {
            case let .branch(i):
                b.target = self; b.action = #selector(legendClicked(_:)); b.tag = i
                b.toolTip = tooltip(for: i)
            case let .folded(list):
                b.toolTip = list.map { "\(m.segments[$0].name) \(sizeText(m.segments[$0].bytes))" }.joined(separator: "\n")
                b.isEnabled = true
            case .protected:
                if let i = m.segments.firstIndex(where: { $0.kind == .protected }) {
                    b.target = self; b.action = #selector(legendClicked(_:)); b.tag = i
                }
            case .systemGap: b.toolTip = tr("capacity.systemTip")
            default: break
            }
            legendRow.addArrangedSubview(b)
        }
    }

    @objc private func legendClicked(_ sender: NSButton) { navigate(sender.tag) }

    private func navigate(_ i: Int) {
        guard let m = model, m.segments.indices.contains(i), m.segments[i].isClickable, let n = m.segments[i].node else { return }
        onNavigate?(n)
    }

    // MARK: Hover / click / tooltips / accessibility

    private func share(_ s: Model.Segment, of m: Model) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: s.bytes / max(m.total, 1)), number: .percent)
    }
    private func tooltip(for i: Int) -> String {
        guard let m = model else { return "" }
        let s = m.segments[i]
        switch s.kind {
        case .systemGap: return tr("capacity.system") + "\n" + tr("capacity.systemTip")
        case .other: return tr("capacity.tooltip", s.name, sizeText(s.bytes), share(s, of: m))
        default: return tr("capacity.tooltip", s.node.map { DisplayPath.forUser($0.path) } ?? s.name, sizeText(s.bytes), share(s, of: m))
        }
    }

    private func segmentIndex(at p: NSPoint) -> Int? {
        guard let m = model else { return nil }
        let q = barHost.convert(p, from: self)
        guard q.y >= -3, q.y <= barHeight + 3, barHost.bounds.width > 0 else { return nil }
        let f = Double(q.x / barHost.bounds.width)
        return m.segments.firstIndex { f >= $0.start && f < $0.end }
    }

    private func rebuildToolTipsAndAX() {
        removeAllToolTips()
        guard let m = model else { axElements = []; return }
        var els: [SegmentElement] = []
        for (i, s) in m.segments.enumerated() where i < segLayers.count {
            let r = barHost.convert(segLayers[i].frame.insetBy(dx: 0, dy: -3), to: self)
            addToolTip(r, owner: self, userData: nil)
            let e = SegmentElement()
            e.index = i
            e.owner = self
            e.setAccessibilityParent(self)
            e.setAccessibilityRole(s.isClickable ? .button : .staticText)
            let name = s.kind == .systemGap ? tr("capacity.system") : s.name
            e.setAccessibilityLabel(tr("capacity.axLabel", name, sizeText(s.bytes), share(s, of: m)))
            e.setAccessibilityFrameInParentSpace(r)
            els.append(e)
        }
        axElements = els
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        segmentIndex(at: point).map(tooltip(for:)) ?? ""
    }

    override func accessibilityChildren() -> [Any]? {
        (axElements as [Any]) + subviews.filter { !$0.isHidden && $0 !== barHost }
    }

    fileprivate func pressSegment(_ i: Int) { navigate(i) }

    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t)
        trackingArea = t
    }
    override func mouseMoved(with event: NSEvent) {
        let i = segmentIndex(at: convert(event.locationInWindow, from: nil))
        guard i != hover else { return }
        hover = i
        applyColors()
    }
    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        if noticeVisible && noticeTimer == nil { startNoticeTimer() }
        guard hover != nil else { return }
        hover = nil
        applyColors()
    }
    override func mouseDown(with event: NSEvent) {
        if let i = segmentIndex(at: convert(event.locationInWindow, from: nil)) { navigate(i) } else { super.mouseDown(with: event) }
    }
}

/// One accessibility button per bar segment.
private final class SegmentElement: NSAccessibilityElement {
    var index = 0
    weak var owner: CapacityBarView?
    override func accessibilityPerformPress() -> Bool {
        guard let o = owner else { return false }
        o.pressSegment(index)
        return true
    }
}

/// Legend entry: 8 pt dot + name + value; a borderless button so it is clickable
/// and has a larger hit target than the 10 pt bar.
private final class LegendItemButton: NSButton {
    convenience init(dot: NSColor, strokeDot: Bool, name: String, value: String, nameColor: NSColor,
                     nameFont: NSFont, valueFont: NSFont) {
        self.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        let s = NSMutableAttributedString()
        if dot != .clear {
            let img = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in
                dot.setFill(); NSBezierPath(ovalIn: r).fill()
                if strokeDot {      // P2-6: the free dot gets the track's 0.5 pt separator stroke
                    let p = NSBezierPath(ovalIn: r.insetBy(dx: 0.25, dy: 0.25)); p.lineWidth = 0.5
                    NSColor.separatorColor.setStroke(); p.stroke()
                }
                return true
            }
            let att = NSTextAttachment()
            att.image = img
            att.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            s.append(NSAttributedString(attachment: att))
            s.append(NSAttributedString(string: " "))
        }
        s.append(NSAttributedString(string: name + " ", attributes: [.font: nameFont, .foregroundColor: nameColor]))
        s.append(NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: NSColor.drTextSecondary]))
        attributedTitle = s
        setAccessibilityLabel("\(name) \(value)")
    }
}
#endif
