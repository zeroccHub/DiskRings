import XCTest
import Foundation
@testable import SunburstGeometry

final class ThemeTokensTests: XCTestCase {
    /// Resources/DesignTokens.json mirrors simplify-v2 README §4.1.
    func loadJSON() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/DesignTokens.json").standardized
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(obj as? [String: [String: String]])
    }

    func testEveryTokenMatchesDesignFile() throws {
        let json = try loadJSON()
        for (mode, tokens) in [("light", ThemeTokens.light), ("dark", ThemeTokens.dark)] {
            let file = try XCTUnwrap(json[mode])
            XCTAssertEqual(Set(file.keys), Set(ThemeTokens.names), mode)
            for (name, hex) in file { XCTAssertEqual(tokens[name]?.hex, hex.uppercased(), "\(mode).\(name)") }
            XCTAssertEqual(ThemeTokens.parse(file), tokens, "parsed \(mode) == constants")
        }
    }

    func testREADMEFixedButtonColours() {
        // Result-page blue (simplify-v2) — keep for filled buttons / delete chrome.
        XCTAssertEqual(ThemeTokens.light.brand.hex, "#0064D2"); XCTAssertEqual(ThemeTokens.dark.brand.hex, "#1A6FD6")
        XCTAssertEqual(ThemeTokens.light.danger.hex, "#D70015"); XCTAssertEqual(ThemeTokens.dark.danger.hex, "#D12C24")
        XCTAssertEqual(ThemeTokens.light.dangerText.hex, "#C4001A"); XCTAssertEqual(ThemeTokens.dark.dangerText.hex, "#FF8A84")
    }

    /// home-colors.md: home + FDA use deep-teal accent (not result-page blue, not danger).
    func testHomeColorsTealAccentAndSurfaces() {
        XCTAssertEqual(ThemeTokens.light.accent.hex, "#0B7A6E")
        XCTAssertEqual(ThemeTokens.dark.accent.hex, "#3DD6BE")
        XCTAssertEqual(ThemeTokens.light.accentContainer.hex, "#DDF3EF")
        XCTAssertEqual(ThemeTokens.dark.accentContainer.hex, "#123F3A")
        XCTAssertEqual(ThemeTokens.light.freeTrack.hex, "#E8E8ED")
        XCTAssertEqual(ThemeTokens.dark.freeTrack.hex, "#3A3A3C")
        XCTAssertEqual(ThemeTokens.light.bgWindow.hex, "#F5F5F7")
        XCTAssertEqual(ThemeTokens.dark.bgWindow.hex, "#1C1C1E")
        XCTAssertEqual(ThemeTokens.light.bgGroup.hex, "#FFFFFF")  // surface / cards
        XCTAssertEqual(ThemeTokens.dark.bgGroup.hex, "#2C2C2E")
        XCTAssertEqual(ThemeTokens.light.separator.hex, "#D9D9DE")
        XCTAssertEqual(ThemeTokens.dark.separator.hex, "#48484A")
        // FDA must not reuse danger red
        XCTAssertNotEqual(ThemeTokens.light.accentContainer, ThemeTokens.light.dangerTint)
        XCTAssertNotEqual(ThemeTokens.light.accent, ThemeTokens.light.danger)
        // onAccent contrast on accent fill
        XCTAssertGreaterThanOrEqual(RGB.contrast(ThemeTokens.light.onAccent, ThemeTokens.light.accent), 4.5)
        XCTAssertGreaterThanOrEqual(RGB.contrast(ThemeTokens.dark.onAccent, ThemeTokens.dark.accent), 4.5)
    }

    func testHexParsing() {
        XCTAssertEqual(RGB(hex: "#0064D2"), RGB(0x0064D2))
        XCTAssertEqual(RGB(hex: "4c9bff")?.hex, "#4C9BFF")
        XCTAssertEqual(RGBA(hex: "#FFFFFFB8")?.hex8, "#FFFFFFB8")
        for bad in ["", "#", "#12345", "#1234567", "#GG0000", "0x123456", " #123456"] { XCTAssertNil(RGB(hex: bad), bad) }
        var d = ["brand": "#0064D2"]; XCTAssertNil(ThemeTokens.parse(d), "missing tokens rejected")
        d = Dictionary(uniqueKeysWithValues: ThemeTokens.names.map { ($0, ThemeTokens.light[$0]!.hex) })
        XCTAssertEqual(ThemeTokens.parse(d), .light)
        d["danger"] = "nope"; XCTAssertNil(ThemeTokens.parse(d))
    }

    func testReadableContrastInBothModes() {
        for m in ThemeMode.allCases {
            let t = ThemeTokens.forMode(m)
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.textPrimary, t.bgWindow), 7, "\(m) primary text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.textSecondary, t.bgContent), 4.5, "\(m) secondary text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.textSecondary, t.bgGroup), 4.5, "\(m) secondary on surface/card")
            // P2-1: secondary text also on the token fill and on the real system window background.
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.textSecondary, t.token), 4.5, "\(m) secondary on token")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.textSecondary, m == .light ? RGB(0xECECEC) : RGB(0x323232)), 4.5, "\(m) secondary on system window bg")
            XCTAssertGreaterThanOrEqual(RGB.contrast(RGB(0xFFFFFF), t.brand), 4.5, "\(m) white on brand")
            XCTAssertGreaterThanOrEqual(RGB.contrast(RGB(0xFFFFFF), t.danger), 4.5, "\(m) white on danger")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.dangerText, t.dangerTint), 4.5, "\(m) danger text on tint")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.warnText, t.tokenWarn), 4.5, "\(m) high-risk text on token")
        }
    }

    func testChartInkContrastOnEveryRootColour() {
        for m in ThemeMode.allCases {
            for h in SunburstPalette.hues {
                let l = m == .light ? 0.70 + SunburstPalette.hueLift(h) : 0.525
                let c = OKLCH.rgb(l, m == .light ? 0.115 : 0.100, h)
                XCTAssertGreaterThanOrEqual(RGB.contrast(SunburstPalette.ink(m), c), 4.5, "\(m) hue \(h)")
            }
        }
    }
}
