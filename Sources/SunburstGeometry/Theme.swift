// Theme.swift — design tokens for DiskRings (Finder-style redesign, simplify-v2).
// Values from README §4.1, mirrored in Resources/DesignTokens.json;
// `ThemeTokensTests` checks every value against that file.
// Portable (no AppKit): the app wraps these in dynamic NSColors (Theme+AppKit).

public struct RGB: Equatable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double   // sRGB, 0...1
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public init(_ hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }
    /// Parses "#RRGGBB" / "RRGGBB" (case-insensitive). For "#RRGGBBAA" the alpha is ignored here —
    /// use `RGBA(hex:)` when alpha matters. Nil for anything else.
    public init?(hex: String) {
        guard let rgba = RGBA(hex: hex) else { return nil }
        self = rgba.rgb
    }
    public var hex: String {
        func h(_ x: Double) -> String {
            let v = Int((min(max(x, 0), 1) * 255).rounded())
            let d = Array("0123456789ABCDEF")
            return String([d[v / 16], d[v % 16]])
        }
        return "#" + h(r) + h(g) + h(b)
    }
    /// Linear mix in sRGB space: 0 = self, 1 = other.
    public func mixed(with o: RGB, _ f: Double) -> RGB {
        RGB(r: r + (o.r - r) * f, g: g + (o.g - g) * f, b: b + (o.b - b) * f)
    }
    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (a.luminance, b.luminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// Colour with alpha.
public struct RGBA: Equatable, Hashable, Sendable {
    public var rgb: RGB
    public var a: Double   // 0...1
    public init(rgb: RGB, a: Double) { self.rgb = rgb; self.a = a }
    /// "#RRGGBB" (a=1) or "#RRGGBBAA".
    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard (s.count == 6 || s.count == 8), s.allSatisfy({ $0.isHexDigit }) else { return nil }
        let r = Double(Int(s.prefix(2), radix: 16)!) / 255
        let g = Double(Int(s.dropFirst(2).prefix(2), radix: 16)!) / 255
        let b = Double(Int(s.dropFirst(4).prefix(2), radix: 16)!) / 255
        let a: Double
        if s.count == 8 {
            a = Double(Int(s.suffix(2), radix: 16)!) / 255
        } else {
            a = 1
        }
        self.init(rgb: RGB(r: r, g: g, b: b), a: a)
    }
    public var hex: String {
        func h(_ x: Double) -> String {
            let v = Int((min(max(x, 0), 1) * 255).rounded())
            let d = Array("0123456789ABCDEF")
            return String([d[v / 16], d[v % 16]])
        }
        var out = rgb.hex
        if abs(a - 1) > 0.0005 { out += h(a) }
        return out
    }
    /// Always emits #RRGGBBAA (even when a == 1).
    public var hex8: String {
        func h(_ x: Double) -> String {
            let v = Int((min(max(x, 0), 1) * 255).rounded())
            let d = Array("0123456789ABCDEF")
            return String([d[v / 16], d[v % 16]])
        }
        return rgb.hex + h(a)
    }
}

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ThemeMode: Sendable, CaseIterable { case light, dark }

/// Tokens: simplify-v2 blue `brand` for result-page chrome; home-colors.md
/// teal `accent` / `accentContainer` / `freeTrack` for home + FDA. Chart colours
/// come from `SunburstPalette` (OKLCH), not from these tokens.
public struct ThemeTokens: Equatable, Sendable {
    public let bgWindow: RGB   // bg.window / windowBg
    public let bgContent: RGB   // bg.content
    public let bgGroup: RGB   // bg.group / surface (cards)
    public let separator: RGB   // separator
    public let textPrimary: RGB   // text.primary
    public let textSecondary: RGB   // text.secondary (custom; not secondaryLabelColor)
    public let textTertiary: RGB   // text.tertiary
    public let brand: RGB   // brand — result-page blue (simplify-v2)
    public let brandText: RGB   // brand.text
    public let accent: RGB   // home / FDA teal (home-colors.md)
    public let accentContainer: RGB   // accent.container / fda.bg
    public let onAccent: RGB   // accent.on
    public let freeTrack: RGB   // home capacity-bar track
    public let danger: RGB
    public let dangerText: RGB
    public let dangerTint: RGB
    public let dangerLine: RGB
    public let warnText: RGB
    public let warnIcon: RGB
    public let token: RGB
    public let tokenWarn: RGB
    public let control: RGB

    public static let names: [String] = [
        "bg.window", "bg.content", "bg.group", "separator",
        "text.primary", "text.secondary", "text.tertiary",
        "brand", "brand.text",
        "accent", "accent.container", "accent.on", "freeTrack",
        "danger", "danger.text", "danger.tint", "danger.line",
        "warn.text", "warn.icon", "token", "token.warn", "control"]

    public init(bgWindow: RGB, bgContent: RGB, bgGroup: RGB, separator: RGB, textPrimary: RGB, textSecondary: RGB, textTertiary: RGB, brand: RGB, brandText: RGB, accent: RGB, accentContainer: RGB, onAccent: RGB, freeTrack: RGB, danger: RGB, dangerText: RGB, dangerTint: RGB, dangerLine: RGB, warnText: RGB, warnIcon: RGB, token: RGB, tokenWarn: RGB, control: RGB) {
        self.bgWindow = bgWindow
        self.bgContent = bgContent
        self.bgGroup = bgGroup
        self.separator = separator
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.brand = brand
        self.brandText = brandText
        self.accent = accent
        self.accentContainer = accentContainer
        self.onAccent = onAccent
        self.freeTrack = freeTrack
        self.danger = danger
        self.dangerText = dangerText
        self.dangerTint = dangerTint
        self.dangerLine = dangerLine
        self.warnText = warnText
        self.warnIcon = warnIcon
        self.token = token
        self.tokenWarn = tokenWarn
        self.control = control
    }

    public static func forMode(_ m: ThemeMode) -> ThemeTokens { m == .dark ? dark : light }

    public subscript(name: String) -> RGB? {
        switch name {
        case "bg.window": return bgWindow
        case "bg.content": return bgContent
        case "bg.group": return bgGroup
        case "separator": return separator
        case "text.primary": return textPrimary
        case "text.secondary": return textSecondary
        case "text.tertiary": return textTertiary
        case "brand": return brand
        case "brand.text": return brandText
        case "accent": return accent
        case "accent.container": return accentContainer
        case "accent.on": return onAccent
        case "freeTrack": return freeTrack
        case "danger": return danger
        case "danger.text": return dangerText
        case "danger.tint": return dangerTint
        case "danger.line": return dangerLine
        case "warn.text": return warnText
        case "warn.icon": return warnIcon
        case "token": return token
        case "token.warn": return tokenWarn
        case "control": return control
        default: return nil
        }
    }

    public static func parse(_ dict: [String: String]) -> ThemeTokens? {
        func c(_ n: String) -> RGB? { dict[n].flatMap { RGB(hex: $0) } }
        guard let bgWindow = c("bg.window"), let bgContent = c("bg.content"), let bgGroup = c("bg.group"),
              let separator = c("separator"), let textPrimary = c("text.primary"), let textSecondary = c("text.secondary"),
              let textTertiary = c("text.tertiary"), let brand = c("brand"), let brandText = c("brand.text"),
              let accent = c("accent"), let accentContainer = c("accent.container"), let onAccent = c("accent.on"),
              let freeTrack = c("freeTrack"),
              let danger = c("danger"), let dangerText = c("danger.text"), let dangerTint = c("danger.tint"),
              let dangerLine = c("danger.line"), let warnText = c("warn.text"), let warnIcon = c("warn.icon"),
              let token = c("token"), let tokenWarn = c("token.warn"), let control = c("control") else { return nil }
        return ThemeTokens(bgWindow: bgWindow, bgContent: bgContent, bgGroup: bgGroup, separator: separator,
                           textPrimary: textPrimary, textSecondary: textSecondary, textTertiary: textTertiary,
                           brand: brand, brandText: brandText, accent: accent, accentContainer: accentContainer,
                           onAccent: onAccent, freeTrack: freeTrack, danger: danger, dangerText: dangerText,
                           dangerTint: dangerTint, dangerLine: dangerLine, warnText: warnText, warnIcon: warnIcon,
                           token: token, tokenWarn: tokenWarn, control: control)
    }

    public static let light = ThemeTokens(
        bgWindow: RGB(0xF5F5F7),
        bgContent: RGB(0xFFFFFF),
        bgGroup: RGB(0xFFFFFF),
        separator: RGB(0xD9D9DE),
        textPrimary: RGB(0x1D1D1F),
        textSecondary: RGB(0x636366),
        textTertiary: RGB(0x8E8E93),
        brand: RGB(0x0064D2),
        brandText: RGB(0x0064D2),
        accent: RGB(0x0B7A6E),
        accentContainer: RGB(0xDDF3EF),
        onAccent: RGB(0xFFFFFF),
        freeTrack: RGB(0xE8E8ED),
        danger: RGB(0xD70015),
        dangerText: RGB(0xC4001A),
        dangerTint: RGB(0xFCEEEE),
        dangerLine: RGB(0xF2C6C8),
        warnText: RGB(0x8F5F00),
        warnIcon: RGB(0xE8A100),
        token: RGB(0xE9E9EB),
        tokenWarn: RGB(0xFFF3D6),
        control: RGB(0xFFFFFF))

    public static let dark = ThemeTokens(
        bgWindow: RGB(0x1C1C1E),
        bgContent: RGB(0x1C1C1E),
        bgGroup: RGB(0x2C2C2E),
        separator: RGB(0x48484A),
        textPrimary: RGB(0xF5F5F7),
        textSecondary: RGB(0xAEAEB2),
        textTertiary: RGB(0x7C7C80),
        brand: RGB(0x1A6FD6),
        brandText: RGB(0x4C9BFF),
        accent: RGB(0x3DD6BE),
        accentContainer: RGB(0x123F3A),
        onAccent: RGB(0x0B1F1C),
        freeTrack: RGB(0x3A3A3C),
        danger: RGB(0xD12C24),
        dangerText: RGB(0xFF8A84),
        dangerTint: RGB(0x2E1C1C),
        dangerLine: RGB(0x5A2A2A),
        warnText: RGB(0xFFD60A),
        warnIcon: RGB(0xFFD60A),
        token: RGB(0x3A3A3C),
        tokenWarn: RGB(0x3D3415),
        control: RGB(0x3A3A3C))
}
