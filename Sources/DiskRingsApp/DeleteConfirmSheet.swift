#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE
import DiskScanCore
#endif

/// Delete confirmation sheet (simplify-v2 §6, 600 pt wide):
/// groups ⚠ 高风险 / 可重建（或 普通）/ 🔒 已排除, method radios (Trash default,
/// ↩ = primary), and for Permanent a typed 「永久删除」 that must match exactly;
/// the red button has no key equivalent. Runs the existing deletion pipeline via `onConfirm`.
@MainActor
final class DeleteConfirmSheet: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    private var snapshot: DeleteConfirmPolicy.Snapshot
    private let languageIsChinese: Bool
    private let homeDirectory: String
    private let onConfirm: (DeleteConfirmPolicy.Method, [String]) -> Void
    private let onCancel: () -> Void

    private let titleLabel = NSTextField.label("", size: 15, weight: .semibold)
    private let subtitleLabel = NSTextField.label("", size: 11, color: .drTextSecondary)
    private let trashRadio = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let permRadio = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let permBox = NSView()
    private let permWarning = NSTextField.label("", size: 13)
    private let typeField = NSTextField()
    private let matched = NSTextField.label("", size: 11, color: .systemGreen)
    private let footerHint = NSTextField.label("", size: 11, color: .drTextSecondary)
    private let cancelButton = NSButton(title: tr("button.cancel"), target: nil, action: nil)
    private let primaryButton = FilledButton.make("", color: .drBrand, target: nil, action: nil)
    private var checkboxes: [NSButton: String] = [:]

    init(snapshot: DeleteConfirmPolicy.Snapshot, languageIsChinese: Bool, homeDirectory: String,
         onConfirm: @escaping (DeleteConfirmPolicy.Method, [String]) -> Void, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot
        self.languageIsChinese = languageIsChinese
        self.homeDirectory = homeDirectory
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        window = QuitForwardingSheetWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
                                           styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        build()
        refresh()
    }

    // MARK: Build

    private func build() {
        let content = NSView()
        window.contentView = content

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        let titles = NSStackView(views: [titleLabel, subtitleLabel])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12; header.alignment = .top

        let list = NSStackView()
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        let high = snapshot.highRiskItems, normal = snapshot.normalItems
        if !high.isEmpty {
            list.addArrangedSubview(groupHeader("⚠ " + tr("confirm.group.highRisk", high.count), color: .drWarnText))
            for it in high { list.addArrangedSubview(itemRow(it, detail: "⚠ " + Self.consequence(it.riskReasons), detailColor: .drWarnText)) }
        }
        if !normal.isEmpty {
            let allCaches = normal.allSatisfy { isCache($0.path) }
            list.addArrangedSubview(groupHeader(allCaches ? tr("confirm.group.rebuildable", normal.count) : tr("confirm.group.normal", normal.count),
                                                color: .drTextSecondary))
            for it in normal {
                list.addArrangedSubview(itemRow(it, detail: isCache(it.path) ? tr("confirm.detail.cache") : DisplayPath.forUser(it.path), detailColor: .drTextSecondary))
            }
        }
        if !snapshot.excluded.isEmpty {
            list.addArrangedSubview(groupHeader("🔒 " + tr("confirm.group.excluded", snapshot.excluded.count), color: .drTextSecondary))
            for ex in snapshot.excluded { list.addArrangedSubview(excludedRow(ex)) }
        }
        for v in list.arrangedSubviews { v.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(list)
        let scroll = NSScrollView()
        scroll.documentView = flipped
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: flipped.topAnchor), list.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: flipped.trailingAnchor), list.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        let listHeight = min(260, max(80, list.fittingSize.height))
        scroll.heightAnchor.constraint(equalToConstant: listHeight).isActive = true

        // Method
        let methodLabel = NSTextField.label(tr("confirm.method.label"))
        for (b, t, d) in [(trashRadio, tr("confirm.method.trash"), tr("confirm.method.trashDetail")),
                          (permRadio, tr("confirm.method.permanent"), tr("confirm.method.permanentDetail"))] {
            let s = NSMutableAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            s.append(NSAttributedString(string: "  " + d, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.drTextSecondary]))
            b.attributedTitle = s
            b.target = self; b.action = #selector(methodChanged(_:))
        }
        let radios = NSStackView(views: [trashRadio, permRadio])
        radios.orientation = .vertical; radios.alignment = .leading; radios.spacing = 6
        let method = NSStackView(views: [methodLabel, radios])
        method.alignment = .top; method.spacing = 10

        // Permanent confirmation box
        permBox.wantsLayer = true
        permBox.layer?.cornerRadius = 8
        permBox.layer?.borderWidth = 1
        permBox.translatesAutoresizingMaskIntoConstraints = false
        permWarning.lineBreakMode = .byWordWrapping
        let warnIcon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) ?? NSImage())
        warnIcon.contentTintColor = .drWarnIcon
        let warnRow = NSStackView(views: [warnIcon, permWarning]); warnRow.spacing = 6
        let phrase = DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: languageIsChinese)
        let typeLabel = NSTextField.label(tr("confirm.type.prompt", phrase), size: 13, color: .drTextSecondary)
        typeField.placeholderString = phrase
        typeField.delegate = self
        typeField.font = .systemFont(ofSize: 13)
        typeField.translatesAutoresizingMaskIntoConstraints = false
        typeField.widthAnchor.constraint(equalToConstant: 168).isActive = true
        matched.stringValue = "✓ " + tr("confirm.type.matched")
        let typeRow = NSStackView(views: [typeLabel, typeField, matched]); typeRow.spacing = 8
        let permStack = NSStackView(views: [warnRow, typeRow])
        permStack.orientation = .vertical; permStack.alignment = .leading; permStack.spacing = 10
        permStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        permStack.translatesAutoresizingMaskIntoConstraints = false
        permBox.addSubview(permStack)
        NSLayoutConstraint.activate([
            permStack.leadingAnchor.constraint(equalTo: permBox.leadingAnchor), permStack.trailingAnchor.constraint(equalTo: permBox.trailingAnchor),
            permStack.topAnchor.constraint(equalTo: permBox.topAnchor), permStack.bottomAnchor.constraint(equalTo: permBox.bottomAnchor),
        ])

        // Footer
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"   // esc
        cancelButton.target = self; cancelButton.action = #selector(cancel(_:))
        primaryButton.target = self; primaryButton.action = #selector(confirm(_:))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [footerHint, spacer, cancelButton, primaryButton])
        footer.spacing = 10
        cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let col = NSStackView(views: [header, scroll, method, permBox, footer])
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 16
        col.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        col.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: content.leadingAnchor), col.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            col.topAnchor.constraint(equalTo: content.topAnchor), col.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 600),
            icon.widthAnchor.constraint(equalToConstant: 40), icon.heightAnchor.constraint(equalToConstant: 40),
        ])
        for v in [scroll, permBox, footer] as [NSView] { v.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -40).isActive = true }
        applyChrome()
        (snapshot.method == .permanent ? permRadio : trashRadio).state = .on
    }

    /// One consequence line per high-risk item (keys from DeleteConfirmPolicy.consequenceKey).
    static func consequence(_ reasons: [String]) -> String {
        switch DeleteConfirmPolicy.consequenceKey(for: reasons) {
        case "confirm.consequence.app": return tr("confirm.consequence.app")
        case "confirm.consequence.library": return tr("confirm.consequence.library")
        case "confirm.consequence.hidden": return tr("confirm.consequence.hidden")
        case "confirm.consequence.large": return tr("confirm.consequence.large")
        default: return tr("confirm.consequence.generic")
        }
    }

    private func isCache(_ path: String) -> Bool {
        BasketRisk.libraryState(path: path, homeDirectory: homeDirectory) == .caches
    }

    private func groupHeader(_ text: String, color: NSColor) -> NSView {
        let v = TintedView(color: .drToken)
        let l = NSTextField.label(text, size: 11, weight: .semibold, color: color)
        v.addSubview(l)
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 26),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func rowShell(lead: NSView, name: String, path: String, size: NSAttributedString, detail: String, detailColor: NSColor, muted: Bool) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let n = NSTextField.label(name, size: 13, color: muted ? .drTextSecondary : .labelColor)
        let p = NSTextField.label(DisplayPath.forUser((path as NSString).deletingLastPathComponent), size: 11, color: .drTextSecondary)
        let s = NSTextField(labelWithAttributedString: size); s.translatesAutoresizingMaskIntoConstraints = false
        let d = NSTextField.label(detail, size: 11, color: detailColor)
        p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for x in [lead, icon, n, p, s, d] as [NSView] { x.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(x) }
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 46),
            lead.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            lead.centerYAnchor.constraint(equalTo: n.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 34),
            icon.centerYAnchor.constraint(equalTo: n.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            n.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            n.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            p.leadingAnchor.constraint(equalTo: n.trailingAnchor, constant: 6),
            p.firstBaselineAnchor.constraint(equalTo: n.firstBaselineAnchor),
            p.trailingAnchor.constraint(lessThanOrEqualTo: s.leadingAnchor, constant: -8),
            s.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            s.firstBaselineAnchor.constraint(equalTo: n.firstBaselineAnchor),
            d.leadingAnchor.constraint(equalTo: n.leadingAnchor),
            d.topAnchor.constraint(equalTo: n.bottomAnchor, constant: 2),
            d.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -12),
        ])
        return v
    }

    private func itemRow(_ it: DeleteConfirmPolicy.Item, detail: String, detailColor: NSColor) -> NSView {
        let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
        cb.state = it.checked ? .on : .off
        checkboxes[cb] = it.id
        let size = NSAttributedString(string: SizeText.format(it.bytes), attributes: [.font: NSFont.drNumber(13), .foregroundColor: NSColor.labelColor])
        return rowShell(lead: cb, name: it.name, path: it.path, size: size, detail: detail, detailColor: detailColor, muted: false)
    }

    private func excludedRow(_ ex: DeleteConfirmPolicy.ExcludedItem) -> NSView {
        let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage())
        lock.contentTintColor = .drTextTertiary
        let size = NSAttributedString(string: SizeText.format(ex.bytes), attributes: [
            .font: NSFont.drNumber(13), .foregroundColor: NSColor.drTextTertiary,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue])
        let reason = ex.reasonCode == "sipProtected" ? tr("confirm.excluded.sip") : tr("confirm.excluded.other", ex.reasonCode)
        return rowShell(lead: lock, name: (ex.name as NSString).lastPathComponent, path: ex.path, size: size,
                        detail: reason, detailColor: .drTextSecondary, muted: true)
    }

    private func applyChrome() {
        permBox.layer?.backgroundColor = permBox.resolvedCGColor(.drDangerTint)
        permBox.layer?.borderColor = permBox.resolvedCGColor(.drDangerLine)
    }

    // MARK: State

    private var typedText: String { typeField.stringValue }

    private func refresh() {
        let perm = snapshot.method == .permanent
        let n = snapshot.checkedCount
        let bytes = SizeText.format(snapshot.checkedBytes)
        titleLabel.stringValue = perm ? tr("confirm.title.permanent", n) : tr("confirm.title.trash", n)
        subtitleLabel.stringValue = perm ? tr("confirm.subtitle.permanent", bytes) : tr("confirm.subtitle.trash", bytes)
        permBox.isHidden = !perm
        let hr = snapshot.checkedHighRiskCount
        let w = hr > 0 ? tr("confirm.warning.risk", bytes, hr) : tr("confirm.warning", bytes)
        permWarning.attributedStringValue = NSAttributedString(string: w, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        let enabled = DeleteConfirmPolicy.primaryEnabled(snapshot: snapshot, typedText: typedText, languageIsChinese: languageIsChinese)
        matched.isHidden = !(perm && typedText == DeleteConfirmPolicy.typeConfirmPhrase(languageIsChinese: languageIsChinese))
        if perm {
            primaryButton.bezelColor = .drDanger
            primaryButton.setFilledTitle(tr("confirm.primary.permanent", n))
            primaryButton.keyEquivalent = ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: true)   // must be clicked
            footerHint.stringValue = tr("confirm.footer.permanent")
        } else {
            primaryButton.bezelColor = .drBrand
            primaryButton.setFilledTitle(tr("confirm.primary.trash"))
            primaryButton.keyEquivalent = ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: false)  // ↩ (sheet only)
            footerHint.stringValue = tr("confirm.footer.trash")
        }
        primaryButton.isEnabled = enabled
        if let c = window.contentView { window.setContentSize(c.fittingSize) }
    }

    @objc private func methodChanged(_ sender: NSButton) {
        snapshot = DeleteConfirmPolicy.settingMethod(sender === permRadio ? .permanent : .trash, in: snapshot)
        trashRadio.state = sender === permRadio ? .off : .on
        permRadio.state = sender === permRadio ? .on : .off
        if snapshot.method == .permanent { window.makeFirstResponder(typeField) } else { typeField.stringValue = "" }
        refresh()
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let id = checkboxes[sender] else { return }
        snapshot = DeleteConfirmPolicy.settingChecked(id: id, checked: sender.state == .on, in: snapshot)
        refresh()
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    /// Return in the phrase field never deletes (permanent has no ↩).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        sel == #selector(NSResponder.insertNewline(_:)) && snapshot.method == .permanent
    }

    @objc private func confirm(_ sender: Any?) {
        guard DeleteConfirmPolicy.primaryEnabled(snapshot: snapshot, typedText: typedText, languageIsChinese: languageIsChinese) else { NSSound.beep(); return }
        let method = snapshot.method
        let paths = snapshot.checkedItems.map(\.path)
        close()
        onConfirm(method, paths)
    }

    @objc private func cancel(_ sender: Any?) {
        close()
        onCancel()
    }

    private func close() {
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Plain view with a dynamic background colour.
final class TintedView: NSView {
    private let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = resolvedCGColor(color)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = resolvedCGColor(color)
    }
}

// MARK: - Undo toast (Trash only, 8 seconds)

@MainActor
final class UndoToastController {
    private weak var host: NSView?
    private var bar: NSView?
    private var timer: Timer?
    private var pairs: [TrashUndoLog.Pair] = []

    private var onShowSkipped: (() -> Void)?

    func show(in host: NSView, pairs: [TrashUndoLog.Pair], freedLabel: String,
              skippedCount: Int = 0, onShowSkipped: (() -> Void)? = nil) {
        dismiss()
        guard !pairs.isEmpty else { return }
        self.host = host
        self.pairs = pairs
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 8
        bar.layer?.backgroundColor = host.resolvedCGColor(.controlBackgroundColor)
        bar.layer?.borderColor = host.resolvedCGColor(.separatorColor)
        bar.layer?.borderWidth = 1
        bar.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: tr("toast.trashed", freedLabel))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        let undo = NSButton(title: tr("toast.undo"), target: self, action: #selector(undo))
        undo.bezelStyle = .rounded
        var views: [NSView] = [label]
        if skippedCount > 0, let cb = onShowSkipped {
            self.onShowSkipped = cb
            let link = NSButton(title: "", target: self, action: #selector(showSkipped))
            link.isBordered = false
            link.attributedTitle = NSAttributedString(string: tr("toast.skipped", skippedCount), attributes: [
                .foregroundColor: NSColor.drBrandText, .font: NSFont.systemFont(ofSize: 13)])
            views.append(link)
        }
        views.append(undo)
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        host.addSubview(bar)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            bar.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -24),
        ])
        self.bar = bar
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    @objc private func showSkipped() {
        let cb = onShowSkipped
        cb?()
    }

    @objc private func undo() {
        for p in pairs {
            do {
                _ = try FileManager.default.replaceItemAt(p.original, withItemAt: p.trashed)
            } catch {
                // Best-effort: try move
                try? FileManager.default.moveItem(at: p.trashed, to: p.original)
            }
        }
        dismiss()
    }

    func dismiss() {
        timer?.invalidate(); timer = nil
        bar?.removeFromSuperview(); bar = nil
        pairs = []
    }
}
#endif
