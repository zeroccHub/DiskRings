#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE
import DiskScanCore
#endif

/// Bottom delete zone (56 pt, full width): danger tint + red top line, the
/// basket as tokens (high-risk = yellow token with ⚠), the risk summary, and
/// 「永久删除…」(red text) + 「移到废纸篓…」(primary; hint ⌘⌫, no ↩). Never says “drag here”.
final class DeleteBarView: NSView {
    var onRemove: ((String) -> Void)?
    var onTrash: (() -> Void)?
    var onPermanent: (() -> Void)?
    /// Evaluate an internal drag (paths) for highlight / accept — same protection as 「加入删除区」.
    var onEvaluateDrop: (([String]) -> BasketDrag.Evaluation)?
    var onAcceptDrop: (([String]) -> Bool)?

    private let line = NSView()
    private let titleIcon = NSImageView()
    private let title = NSTextField.label(tr("basket.title"), size: 13, weight: .semibold, color: .drDangerText)
    private let summary = NSTextField.label("", size: 13, color: .drTextSecondary)
    private let emptyLabel = NSTextField.label(tr("basket.empty"), size: 13, color: .drTextSecondary)
    private let tokens = NSStackView()
    private let riskIcon = NSImageView()
    private let risk = NSTextField.label("", size: 11, color: .drTextSecondary)
    let permanentButton = NSButton(title: tr("button.deletePermanently"), target: nil, action: nil)
    let trashButton = FilledButton.make(tr("button.moveToTrash"), color: .drBrand, target: nil, action: nil)
    private var chips: [BasketSnapshot.Chip] = []
    private var enabled = true
    private var dragHighlight: BasketDrag.Highlight = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        titleIcon.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        titleIcon.contentTintColor = .drDangerText
        titleIcon.translatesAutoresizingMaskIntoConstraints = false
        riskIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        riskIcon.contentTintColor = .drWarnIcon
        riskIcon.translatesAutoresizingMaskIntoConstraints = false
        tokens.orientation = .horizontal
        tokens.spacing = 10
        tokens.translatesAutoresizingMaskIntoConstraints = false
        tokens.setHuggingPriority(.defaultLow, for: .horizontal)
        tokens.setClippingResistancePriority(.defaultLow, for: .horizontal)
        permanentButton.bezelStyle = .rounded
        permanentButton.translatesAutoresizingMaskIntoConstraints = false
        permanentButton.target = self; permanentButton.action = #selector(permanentTapped)
        trashButton.target = self; trashButton.action = #selector(trashTapped)
        // No ↩ here (P1-1): ⌘⌫ (menu) opens the sheet; ↩ exists only inside the sheet.
        trashButton.keyEquivalent = ShortcutPolicy.deleteBarKeyEquivalent
        trashButton.shortcutHint = ShortcutPolicy.openConfirmHint
        setRedTitle()
        risk.lineBreakMode = .byTruncatingTail
        risk.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        emptyLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        let right = NSStackView(views: [riskIcon, risk, permanentButton, trashButton])
        right.orientation = .horizontal
        right.spacing = 10
        right.setCustomSpacing(4, after: riskIcon)
        right.setCustomSpacing(12, after: risk)
        right.translatesAutoresizingMaskIntoConstraints = false
        for v in [line, titleIcon, title, summary, emptyLabel, tokens, right] as [NSView] { addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            line.topAnchor.constraint(equalTo: topAnchor), line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor), line.heightAnchor.constraint(equalToConstant: 1),
            titleIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            summary.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            summary.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -12),
            tokens.leadingAnchor.constraint(equalTo: summary.trailingAnchor, constant: 12),
            tokens.centerYAnchor.constraint(equalTo: centerYAnchor),
            tokens.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -12),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyChrome()
        apply(snapshot: BasketSnapshot())
        registerForDraggedTypes([NSPasteboard.PasteboardType(BasketDrag.pasteboardType)])
    }

    func setDragHighlight(_ h: BasketDrag.Highlight) {
        guard h != dragHighlight else { return }
        dragHighlight = h
        applyChrome()
    }

    private func paths(from info: NSDraggingInfo) -> [String] {
        let pb = info.draggingPasteboard
        let t = NSPasteboard.PasteboardType(BasketDrag.pasteboardType)
        if let s = pb.string(forType: t) { return BasketDrag.decodePaths(s) }
        return []
    }

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let ev = onEvaluateDrop?(paths(from: info))
        let h = BasketDrag.highlight(isOverZone: true, evaluation: ev)
        setDragHighlight(h)
        return h == .accepting ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { operation(for: sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { operation(for: sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { setDragHighlight(.idle) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let eval = onEvaluateDrop?(paths(from: sender)) else { return false }
        return eval.canDrop
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDragHighlight(.idle) }
        return onAcceptDrop?(paths(from: sender)) == true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { setDragHighlight(.idle) }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func setRedTitle() {
        permanentButton.attributedTitle = NSAttributedString(string: tr("button.deletePermanently"), attributes: [
            .foregroundColor: NSColor.drDangerText, .font: NSFont.systemFont(ofSize: 13)])
    }

    func apply(snapshot: BasketSnapshot) {
        chips = snapshot.chips
        let empty = snapshot.isEmpty
        emptyLabel.isHidden = !empty
        summary.isHidden = empty
        tokens.isHidden = empty
        summary.stringValue = tr("basket.summary", snapshot.count, SizeText.format(snapshot.totalBytes))
        riskIcon.isHidden = empty || snapshot.highRiskCount == 0
        risk.isHidden = empty
        risk.stringValue = snapshot.highRiskCount > 0 ? tr("basket.riskSummary", snapshot.highRiskCount) : tr("basket.safeSummary")
        rebuildTokens()
        setEnabled(enabled)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        let can = on && !chips.isEmpty
        trashButton.isEnabled = can
        permanentButton.isEnabled = can
    }

    /// Tokens that fit; the rest collapse into “+N”.
    private func rebuildTokens() {
        tokens.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let budget = max(0, bounds.width - 760)
        var used: CGFloat = 0
        var shown = 0
        for c in chips {
            let t = TokenView(chip: c) { [weak self] p in self?.onRemove?(p) }
            let w = t.fittingSize.width + 10
            if used + w > budget && shown > 0 { break }
            if used + w > budget && budget < 120 { break }
            tokens.addArrangedSubview(t); used += w; shown += 1
        }
        if shown < chips.count {
            let more = NSTextField.label(tr("basket.more", chips.count - shown), size: 12, color: .drTextSecondary)
            tokens.addArrangedSubview(more)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 40
        super.setFrameSize(newSize)
        if changed { rebuildTokens() }
    }

    private func applyChrome() {
        layer?.backgroundColor = resolvedCGColor(.drDangerTint)
        line.layer?.backgroundColor = resolvedCGColor(dragHighlight == .accepting ? .drBrand : .drDangerLine)
        switch dragHighlight {
        case .idle:
            layer?.borderWidth = 0
            layer?.borderColor = nil
        case .accepting:
            layer?.borderWidth = 2
            layer?.borderColor = resolvedCGColor(.drBrand)
        case .rejecting:
            layer?.borderWidth = 2
            layer?.borderColor = resolvedCGColor(.drTextTertiary)
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome(); setRedTitle(); rebuildTokens()
    }

    @objc private func trashTapped() { onTrash?() }
    @objc private func permanentTapped() { onPermanent?() }
}

/// NSTokenField-style token: 24 high, radius 5; high-risk = warn token with ⚠.
final class TokenView: NSView {
    private let path: String
    private let onRemove: (String) -> Void
    private let warn: Bool
    init(chip: BasketSnapshot.Chip, onRemove: @escaping (String) -> Void) {
        path = chip.path; self.onRemove = onRemove; warn = chip.isHighRisk
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField.label((warn ? "⚠ " : "") + chip.name, size: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        let size = NSTextField.label(SizeText.format(chip.bytes), size: 12, color: .drTextSecondary)
        size.font = .drNumber(12)
        let x = NSButton(title: "×", target: self, action: #selector(remove))
        x.isBordered = false
        x.font = .systemFont(ofSize: 12)
        x.contentTintColor = .drTextTertiary
        x.toolTip = tr("basket.removeTip")
        let s = NSStackView(views: [name, size, x])
        s.spacing = 6
        s.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
            s.leadingAnchor.constraint(equalTo: leadingAnchor), s.trailingAnchor.constraint(equalTo: trailingAnchor),
            s.topAnchor.constraint(equalTo: topAnchor), s.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = DisplayPath.forUser(chip.path)
        applyChrome()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    private func applyChrome() { layer?.backgroundColor = resolvedCGColor(warn ? .drTokenWarn : .drToken) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyChrome() }
    @objc private func remove() { onRemove(path) }
}

#endif
