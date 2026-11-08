import XCTest
@testable import DiskScanCore

/// UI review P1-1 (no ↩ in the main window; ⌘⌫ only), P1-2 (filled-button title
/// colour by state), P2-11 (⌘↓ drill-in). The AppKit sources are scanned too, since
/// they can't be compiled on Linux.
final class ShortcutPolicyTests: XCTestCase {
    static let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/DiskRingsApp").standardized
    func source(_ f: String) throws -> String { try String(contentsOf: Self.app.appendingPathComponent(f), encoding: .utf8) }

    func testPolicyValues() {
        XCTAssertEqual(ShortcutPolicy.deleteBarKeyEquivalent, "", "delete bar never takes ↩")
        XCTAssertEqual(ShortcutPolicy.openConfirmKey, "\u{8}"); XCTAssertTrue(ShortcutPolicy.openConfirmModifierIsCommand)
        XCTAssertEqual(ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: false), "\r", "↩ only inside the sheet, Trash")
        XCTAssertEqual(ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: true), "", "permanent must be clicked")
        XCTAssertEqual(ShortcutPolicy.drillInKey, "\u{F701}")
        XCTAssertEqual(ShortcutPolicy.openConfirmHint, "⌘⌫")
    }

    /// ↩ then ↩ can't delete: the only "\r" key equivalent in the whole app is the
    /// sheet's (via the policy), and the delete bar uses the empty policy value.
    func testNoReturnKeyEquivalentOutsideTheSheet() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.app.path).filter { $0.hasSuffix(".swift") }
        for f in files {
            let s = try source(f)
            XCTAssertFalse(s.contains("keyEquivalent = \"\\r\""), "\(f): literal ↩ key equivalent")
            XCTAssertFalse(s.contains("keyEquivalent: \"\\r\""), "\(f): literal ↩ key equivalent")
        }
        let chrome = try source("Chrome.swift")
        XCTAssertTrue(chrome.contains("trashButton.keyEquivalent = ShortcutPolicy.deleteBarKeyEquivalent"))
        XCTAssertFalse(chrome.contains("permanentButton.keyEquivalent"))
        let sheet = try source("DeleteConfirmSheet.swift")
        XCTAssertTrue(sheet.contains("ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: true)"))
        XCTAssertTrue(sheet.contains("ShortcutPolicy.sheetPrimaryKeyEquivalent(permanent: false)"))
        let app = try source("AppDelegate.swift")
        XCTAssertTrue(app.contains("trashCollected(_:)), ShortcutPolicy.openConfirmKey"))
        XCTAssertTrue(app.contains("enterSelected(_:)), ShortcutPolicy.drillInKey"))
    }

    func testFilledButtonTitleIsWhiteOnlyWhenFillIsDrawn() throws {
        XCTAssertTrue(FilledButtonStyle.usesWhiteTitle(isEnabled: true, windowIsKey: true))
        XCTAssertFalse(FilledButtonStyle.usesWhiteTitle(isEnabled: false, windowIsKey: true))
        XCTAssertFalse(FilledButtonStyle.usesWhiteTitle(isEnabled: true, windowIsKey: false))
        XCTAssertFalse(FilledButtonStyle.usesWhiteTitle(isEnabled: false, windowIsKey: false))
        // No hard-coded white titles left outside FilledButton.
        let theme = try source("Theme+AppKit.swift")
        XCTAssertFalse(theme.contains("static func filled("))
        for f in ["Chrome.swift", "DeleteConfirmSheet.swift"] {
            XCTAssertFalse(try source(f).contains("NSButton.filled("), f)
        }
    }
}
