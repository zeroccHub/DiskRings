#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE  // SwiftPM: separate modules. build.sh compiles one module with -D SINGLE_MODULE.
import DiskScanCore
#endif

/// Sheet shown while `DeletionList.deleteAll` runs in the background: phase,
/// item counter, current path, a progress bar and a Cancel button.
/// Cancel takes effect during a pre-scan or between top-level items, never
/// in the middle of removing an item.
/// Sheet window that handles Cmd-Q itself: a window-modal sheet is key, so
/// it sees the key equivalent first; forwarding it straight to
/// `NSApp.terminate(_:)` doesn't depend on menu validation through the sheet's
/// responder chain, and a repeated Cmd-Q while quitting is swallowed instead
/// of beeping.
final class QuitForwardingSheetWindow: NSWindow {
    var onQuitKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "q", let onQuitKey {
            onQuitKey()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class DeletionProgressSheet {
    let window: NSWindow
    let cancellation = DeletionCancellation()
    private let phaseLabel = NSTextField(labelWithString: tr("progress.preparing"))
    private let pathLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancelButton = NSButton(title: tr("button.cancel"), target: nil, action: nil)
    private let permanent: Bool
    /// Once set, progress updates keep the "Quitting…" / "Cancelling…" text.
    private var quitting = false

    init(itemCount: Int, permanent: Bool) {
        self.permanent = permanent
        window = QuitForwardingSheetWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: true)
        window.title = permanent ? tr("progress.title.permanent") : tr("progress.title.trash")
        // R10: the phase text wraps (Chinese and English) instead of being clipped.
        phaseLabel.lineBreakMode = .byWordWrapping
        phaseLabel.maximumNumberOfLines = 3
        phaseLabel.preferredMaxLayoutWidth = 420
        phaseLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(max(itemCount, 1))
        bar.doubleValue = 0
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}"   // Escape
        let stack = NSStackView(views: [phaseLabel, pathLabel, bar, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            phaseLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
    }

    func update(_ p: DeletionProgress) {
        pathLabel.stringValue = DisplayPath.forUser(p.currentPath)
        bar.doubleValue = Double(p.deletedCount)
        // Previously every update overwrote "Quitting…" — the user saw no reaction to Cmd-Q.
        if quitting {
            phaseLabel.stringValue = tr("progress.quitting", p.deletedCount, p.itemCount)
            return
        }
        if cancellation.isCancelled { return }
        switch p.phase {
        case .checking: phaseLabel.stringValue = tr("progress.checking", p.itemIndex, p.itemCount, p.deletedCount)
        case .verifying: phaseLabel.stringValue = tr("progress.verifying", p.itemIndex, p.itemCount, p.entriesChecked, p.deletedCount)
        case .deleting: phaseLabel.stringValue = permanent ? tr("progress.deleting.permanent", p.itemIndex, p.itemCount, p.deletedCount) : tr("progress.deleting.trash", p.itemIndex, p.itemCount, p.deletedCount)
        case .finished: phaseLabel.stringValue = tr("progress.finishing")
        }
    }

    func showQuitPending() {
        quitting = true
        cancelButton.isEnabled = false
        cancelButton.title = tr("progress.quittingButton")
        phaseLabel.stringValue = tr("progress.quitPending")
    }

    @objc private func cancel(_ sender: Any?) {
        cancellation.cancel()
        cancelButton.title = tr("progress.cancelling")
        cancelButton.isEnabled = false
        phaseLabel.stringValue = tr("progress.cancellingDetail")
    }
}
#endif
