#if canImport(AppKit)
import AppKit

/// Home page: title + volume cards + Scan Folder card + FDA tip (native, radius ≤ 8).
final class HomePageView: NSView {
    var onSelectVolume: ((VolumeRow) -> Void)?
    var onScanFolder: (() -> Void)?
    var onOpenFDA: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let cardsStack = NSStackView()
    private let tipBar = NSView()
    private let tipLabel = NSTextField(wrappingLabelWithString: "")
    private let tipButton = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.stringValue = tr("home.title")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        cardsStack.orientation = .horizontal
        cardsStack.spacing = 24
        cardsStack.alignment = .top
        cardsStack.translatesAutoresizingMaskIntoConstraints = false

        tipLabel.stringValue = tr("home.fdaTip") + "\n" + tr("volume.hint")
        tipLabel.font = .systemFont(ofSize: 12)
        tipLabel.textColor = .drTextSecondary
        tipButton.title = tr("menu.openFDA")
        tipButton.bezelStyle = .rounded
        tipButton.target = self
        tipButton.action = #selector(tapFDA)
        tipBar.wantsLayer = true
        tipBar.translatesAutoresizingMaskIntoConstraints = false
        let tipStack = NSStackView(views: [tipLabel, tipButton])
        tipStack.orientation = .horizontal
        tipStack.spacing = 12
        tipStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        tipStack.translatesAutoresizingMaskIntoConstraints = false
        tipBar.addSubview(tipStack)
        NSLayoutConstraint.activate([
            tipStack.leadingAnchor.constraint(equalTo: tipBar.leadingAnchor),
            tipStack.trailingAnchor.constraint(equalTo: tipBar.trailingAnchor),
            tipStack.topAnchor.constraint(equalTo: tipBar.topAnchor),
            tipStack.bottomAnchor.constraint(equalTo: tipBar.bottomAnchor),
        ])

        let col = NSStackView(views: [titleLabel, cardsStack, tipBar])
        col.orientation = .vertical
        col.spacing = 28
        col.alignment = .centerX
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([
            col.centerXAnchor.constraint(equalTo: centerXAnchor),
            col.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            col.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            col.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            tipBar.widthAnchor.constraint(equalTo: cardsStack.widthAnchor),
        ])
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func tapFDA() { onOpenFDA?() }

    func reload(volumes: [VolumeRow]) {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rooted = volumes.filter { $0.isRoot }
        let external = volumes.filter { !$0.isRoot }
        if let first = rooted.first {
            cardsStack.addArrangedSubview(makeVolumeCard(first, subtitle: tr("home.internalDisk")))
        } else if let first = volumes.first {
            cardsStack.addArrangedSubview(makeVolumeCard(first, subtitle: tr("home.internalDisk")))
        }
        if let ext = external.first {
            cardsStack.addArrangedSubview(makeVolumeCard(ext, subtitle: tr("home.externalDisk")))
        }
        cardsStack.addArrangedSubview(makeFolderCard())
        refreshAppearance()
        needsLayout = true
    }

    private func makeVolumeCard(_ v: VolumeRow, subtitle: String) -> NSView {
        let card = CardView()
        card.widthAnchor.constraint(equalToConstant: 340).isActive = true
        card.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let kind = NSTextField(labelWithString: subtitle)
        kind.font = .systemFont(ofSize: 12, weight: .medium)
        kind.textColor = .drTextSecondary
        let name = NSTextField(labelWithString: v.name)
        name.font = .systemFont(ofSize: 17, weight: .bold)
        name.textColor = .labelColor

        var capacity = "—"
        if let total = v.total {
            let used: Int64
            if let avail = v.available { used = max(0, total - avail) } else { used = 0 }
            capacity = "\(SizeText.format(UInt64(used))) / \(SizeText.format(UInt64(total)))"
        }
        let size = NSTextField(labelWithString: capacity)
        size.font = .drNumber(22, weight: .semibold)
        size.textColor = .labelColor

        let bar = VolumeUsageBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        if let total = v.total, total > 0, let avail = v.available {
            bar.fraction = CGFloat(max(0, total - avail)) / CGFloat(total)
        }

        let free = NSTextField(labelWithString: v.capacityText)
        free.font = .systemFont(ofSize: 12)
        free.textColor = .drTextSecondary

        let stack = NSStackView(views: [kind, name, size, bar, free])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(cardClicked(_:)))
        card.addGestureRecognizer(click)
        card.identifier = NSUserInterfaceItemIdentifier(v.url.path)
        return card
    }

    private func makeFolderCard() -> NSView {
        let card = CardView()
        card.widthAnchor.constraint(equalToConstant: 340).isActive = true
        card.heightAnchor.constraint(equalToConstant: 220).isActive = true
        // Slightly stronger border than volume cards (folder is an action affordance).
        card.layer?.borderWidth = 1.5
        let title = NSTextField(labelWithString: tr("button.scanFolder"))
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .drAccent
        title.alignment = .center
        let hint = NSTextField(wrappingLabelWithString: tr("home.scanFolderHint"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .drTextSecondary
        hint.alignment = .center
        hint.preferredMaxLayoutWidth = 280
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -24),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(folderClicked))
        card.addGestureRecognizer(click)
        return card
    }

    @objc private func folderClicked() { onScanFolder?() }

    @objc private func cardClicked(_ gr: NSClickGestureRecognizer) {
        guard let path = gr.view?.identifier?.rawValue, !path.isEmpty else { return }
        // Resolve against last-loaded volumes via the controller callback with a synthetic row —
        // HomePageView stores only the path; controller looks it up.
        onSelectVolume?(VolumeRow(url: URL(fileURLWithPath: path), name: URL(fileURLWithPath: path).lastPathComponent,
                                  total: nil, available: nil, isRoot: path == "/"))
    }

    func setVolumeRows(_ volumes: [VolumeRow]) {
        // Re-bind click identifiers to full VolumeRow by rebuilding.
        reload(volumes: volumes)
        // Replace the simple callback path: cards already call onSelectVolume with path-only row;
        // controller should match by url.path.
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    /// Re-resolve every CALayer fill/border and semantic text colour for the current
    /// effectiveAppearance. Parent-driven: stack-hosted CardViews do not always get
    /// viewDidChangeEffectiveAppearance when NSApp.appearance flips (P2 home-theme bug).
    func refreshAppearance() {
        applyHomeChrome()
        // textPrimary ≈ labelColor; keep system label for title so it tracks appearance.
        titleLabel.textColor = .labelColor
        tipLabel.textColor = .drTextSecondary          // fda.body
        tipButton.contentTintColor = .drAccent         // fda.action
        applyTipChrome()
        for case let card as CardView in cardsStack.arrangedSubviews {
            card.applyChrome()
            refreshCardLabels(in: card)
        }
        needsDisplay = true
    }

    private func applyHomeChrome() {
        layer?.backgroundColor = resolvedCGColor(.drBgWindow)   // windowBg
    }

    /// FDA bar: accentContainer fill + accent border @ alpha (not danger/warn).
    private func applyTipChrome() {
        tipBar.layer?.cornerRadius = 8
        tipBar.layer?.backgroundColor = tipBar.resolvedCGColor(.drAccentContainer)
        tipBar.layer?.borderWidth = 1
        let borderAlpha: CGFloat = tipBar.themeMode == .light ? 0.28 : 0.35
        tipBar.layer?.borderColor = tipBar.resolvedCGColor(NSColor.drAccent.withAlphaComponent(borderAlpha))
    }

    /// NSTextField colours use dynamic NSColor / named tokens and re-resolve themselves;
    /// CALayer-backed usage bars need an explicit display pass.
    private func refreshCardLabels(in root: NSView) {
        for v in root.subviews {
            if let bar = v as? VolumeUsageBarView { bar.needsDisplay = true }
            refreshCardLabels(in: v)
        }
    }
}

/// Plain bordered box: design-token group fill + separator, radius 8 (no glass).
final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        applyChrome()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func applyChrome() {
        layer?.backgroundColor = resolvedCGColor(.drBgGroup)
        layer?.borderColor = resolvedCGColor(.drSeparator)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyChrome() }
}

final class VolumeUsageBarView: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.drFreeTrack.setFill()   // freeTrack
        track.fill()
        let f = min(1, max(0, fraction))
        if f > 0 {
            var r = bounds
            r.size.width = max(4, bounds.width * f)
            let fill = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            NSColor.drAccent.setFill()   // home accent (teal)
            fill.fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
#endif
