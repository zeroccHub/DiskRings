import Foundation

/// Keyboard rules for the delete flow and navigation (UI review P1-1 / P2-11),
/// kept in one pure place so they are unit-tested.
/// - The main window has NO default button: the delete bar's buttons never take ↩
///   (otherwise ↩ in the list/search + ↩ in the sheet = two keystrokes to delete).
/// - ⌘⌫ (menu) is the only shortcut that opens the confirm sheet.
/// - ↩ only exists inside the sheet, and only for Trash; Permanent must be clicked.
/// - ⌘↓ enters the selected folder (↩ is never used for drilling).
public enum ShortcutPolicy {
    public static let deleteBarKeyEquivalent = ""
    /// Menu key equivalent for 「移到废纸篓…」 (with `openConfirmModifierIsCommand`).
    public static let openConfirmKey = "\u{8}"
    public static let openConfirmModifierIsCommand = true
    /// Hint drawn next to the delete bar's primary button.
    public static let openConfirmHint = "⌘⌫"
    public static func sheetPrimaryKeyEquivalent(permanent: Bool) -> String { permanent ? "" : "\r" }
    /// NSDownArrowFunctionKey, with ⌘.
    public static let drillInKey = "\u{F701}"
    public static let goUpKey = "\u{F700}"
}

/// Filled (brand/danger) button title colour (UI review P1-2): white only while the
/// fill is actually drawn — enabled AND in the key window. Otherwise the system
/// colours (disabledControlTextColor / labelColor) on the system bezel.
public enum FilledButtonStyle {
    public static func usesWhiteTitle(isEnabled: Bool, windowIsKey: Bool) -> Bool { isEnabled && windowIsKey }
}
