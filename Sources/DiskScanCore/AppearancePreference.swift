import Foundation

/// View > Appearance: Follow System / Light / Dark. Portable so the stored
/// value handling is unit-tested on Linux; the app maps it to
/// `NSApp.appearance` (nil / .aqua / .darkAqua).
public enum AppearancePreference: String, CaseIterable, Sendable {
    case system, light, dark

    public static let defaultsKey = "DiskRingsAppearance"

    /// Stored choice; anything missing or unknown means `.system`.
    public static func load(from defaults: UserDefaults = .standard) -> AppearancePreference {
        defaults.string(forKey: defaultsKey).flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// Localization key of the menu title.
    public var menuKey: String { "menu.appearance." + rawValue }

    /// Fixed Aqua appearance this preference forces, or `nil` when following the system.
    /// AppKit maps `.aqua` → `NSAppearance(named: .aqua)`, `.darkAqua` → `.darkAqua`,
    /// and `nil` → `NSApp.appearance = nil`.
    public enum ResolvedAppearance: String, Sendable {
        case aqua, darkAqua
    }

    public var resolvedAppearance: ResolvedAppearance? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }
}
