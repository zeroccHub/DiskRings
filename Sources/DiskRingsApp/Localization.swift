#if canImport(AppKit)
import AppKit
#if !SINGLE_MODULE
import DiskScanCore
#endif

/// Localization for the app layer. All user-visible strings go through
/// `tr(<stable key>, args...)`, a thin wrapper around NSLocalizedString that
/// reads from the bundle chosen by `AppLanguage` (zh-Hans for any Chinese
/// system language, otherwise English). Keys live in
/// Resources/{en,zh-Hans}.lproj/Localizable.strings (tests check both).
enum AppL10n {
    /// The .lproj bundle to read from; falls back to the main bundle.
    static let bundle: Bundle = {
        let pick = AppLanguage.pick(preferred: Locale.preferredLanguages,
                                    available: Bundle.main.localizations)
        if let p = Bundle.main.path(forResource: pick, ofType: "lproj"), let b = Bundle(path: p) { return b }
        return .main
    }()

    /// Lookup for core messages (ReasonText); nil when the key is missing so
    /// the core falls back to English.
    static let lookup: @Sendable (String) -> String? = { key in
        let v = NSLocalizedString(key, tableName: nil, bundle: bundle, value: "\u{1}", comment: "")
        return v == "\u{1}" ? nil : v
    }

    static func reason(_ r: DeletionGuard.Reason) -> String { ReasonText.text(r, lookup: lookup) }
    static func caution(_ c: DeletionGuard.Caution) -> String { ReasonText.text(c, lookup: lookup) }
    static func error(_ e: Error) -> String {
        if let d = e as? DeletionError { return ReasonText.text(d, lookup: lookup) }
        return "\(e)"
    }
}

/// Localized string for `key`, formatted with `args` (printf-style, positional
/// `%1$@` allowed). Uses the user's locale for numbers.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, tableName: nil, bundle: AppL10n.bundle, comment: "")
    return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}
#endif
