#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE
import SunburstGeometry
#endif

/// Dynamic (light/dark) NSColors from DesignTokens.json.
/// `drBrand` = result-page blue (simplify-v2); `drAccent` = home/FDA teal (home-colors.md).
/// Surfaces use named tokens so CALayer fills re-resolve via `resolvedCGColor`.
extension NSColor {
    convenience init(_ c: RGB, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
    }

    static func dr(_ name: String, _ pick: @escaping @Sendable (ThemeTokens) -> RGB) -> NSColor {
        NSColor(name: NSColor.Name("dr." + name)) { appearance in
            NSColor(pick(ThemeTokens.forMode(ThemeMode(appearance))))
        }
    }

    static let drBrand = dr("brand") { $0.brand }
    static let drBrandText = dr("brandText") { $0.brandText }
    /// Home / FDA teal (home-colors.md). Not the result-page blue `drBrand`.
    static let drAccent = dr("accent") { $0.accent }
    static let drAccentContainer = dr("accentContainer") { $0.accentContainer }
    static let drOnAccent = dr("onAccent") { $0.onAccent }
    static let drFreeTrack = dr("freeTrack") { $0.freeTrack }
    static let drDanger = dr("danger") { $0.danger }
    static let drDangerText = dr("dangerText") { $0.dangerText }
    static let drDangerTint = dr("dangerTint") { $0.dangerTint }
    static let drDangerLine = dr("dangerLine") { $0.dangerLine }
    static let drWarnText = dr("warnText") { $0.warnText }
    static let drWarnIcon = dr("warnIcon") { $0.warnIcon }
    static let drToken = dr("token") { $0.token }
    static let drTokenWarn = dr("tokenWarn") { $0.tokenWarn }
    /// Not `secondaryLabelColor` (≈3.9:1 on white) — README §4.1.
    static let drTextSecondary = dr("textSecondary") { $0.textSecondary }
    static let drTextTertiary = dr("textTertiary") { $0.textTertiary }
    static let drSeparator = dr("separator") { $0.separator }
    /// Surfaces (DesignTokens bg.* / control) — prefer these over one-shot system fills on CALayers.
    static let drBgWindow = dr("bgWindow") { $0.bgWindow }
    static let drBgContent = dr("bgContent") { $0.bgContent }
    static let drBgGroup = dr("bgGroup") { $0.bgGroup }
    static let drControl = dr("control") { $0.control }
}

extension NSFont {
    /// Numbers: system font with monospaced digits (no monospaced fonts anywhere).
    static func drNumber(_ size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension ThemeMode {
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

extension NSView {
    /// Resolves a dynamic NSColor for THIS view's appearance (CALayer colours
    /// don't update by themselves; callers re-apply on appearance change).
    func resolvedCGColor(_ c: NSColor) -> CGColor {
        var out = c.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { out = c.cgColor }
        return out
    }
    var themeMode: ThemeMode { ThemeMode(effectiveAppearance) }
}

extension NSTextField {
    static func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingMiddle
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }
}

/// Native push button with a fixed brand/danger fill (README §5). The title is white
/// ONLY while the fill is drawn — enabled and in the key window (P1-2); otherwise the
/// plain system title colours (disabled / label) on the system bezel, so a disabled
/// 「永久删除 3 项」 or a delete bar behind a sheet stays readable.
final class FilledButton: NSButton {
    private(set) var plainTitle = ""
    /// Optional shortcut hint after the title (e.g. ⌘⌫): 11 pt, white 70% / text.secondary.
    var shortcutHint: String? { didSet { applyTitle() } }
    private var observers: [NSObjectProtocol] = []

    static func make(_ title: String, color: NSColor, target: AnyObject?, action: Selector?) -> FilledButton {
        let b = FilledButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.bezelColor = color
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setFilledTitle(title)
        return b
    }
    func setFilledTitle(_ t: String) { plainTitle = t; applyTitle() }
    override var isEnabled: Bool { didSet { applyTitle() } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if let w = window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyTitle() }
                })
            }
        }
        applyTitle()
    }

    var usesWhiteTitle: Bool { FilledButtonStyle.usesWhiteTitle(isEnabled: isEnabled, windowIsKey: window?.isKeyWindow == true) }

    func applyTitle() {
        let white = usesWhiteTitle
        guard white || shortcutHint != nil else {
            title = plainTitle          // system colours: disabledControlTextColor / labelColor
            return
        }
        let main: NSColor = white ? .white : (isEnabled ? .labelColor : .disabledControlTextColor)
        let s = NSMutableAttributedString(string: plainTitle, attributes: [.foregroundColor: main, .font: NSFont.systemFont(ofSize: 13)])
        if let h = shortcutHint {
            s.append(NSAttributedString(string: "  " + h, attributes: [
                .foregroundColor: white ? NSColor.white.withAlphaComponent(0.7) : NSColor.drTextSecondary,
                .font: NSFont.systemFont(ofSize: 11)]))
        }
        attributedTitle = s
    }
}
#endif
