import Foundation

/// Pure layout numbers for the main window's chart | list split (simplify-v2 README §布局:
/// chart flexible ≥ 520; list 436, draggable 360–480; window ≥ 960×640). Unit-tested; the
/// AppKit side only applies these values and logs/asserts them after the first layout.
public enum SplitLayout {
    public static let chartMin: Double = 520
    public static let listMin: Double = 360
    public static let listMax: Double = 480
    public static let listPreferred: Double = 436
    public static let divider: Double = 1
    public static let windowMinWidth: Double = 960
    public static let windowMinHeight: Double = 640
    /// Window autosave name. Bumped (v3 → v4) so frames saved by builds with the collapsed
    /// list are ignored.
    public static let windowAutosaveName = "DiskRings.MainWindow.v4"

    /// Narrowest split that fits chartMin + divider + listMin.
    public static var minimumSplitWidth: Double { chartMin + divider + listMin }

    /// List width for a split of `total` points on first show: the preferred 436, reduced
    /// (never below listMin) so the chart keeps chartMin when possible.
    public static func initialListWidth(total: Double) -> Double {
        clampList(listPreferred, total: total)
    }

    /// Clamps a proposed list width into [listMin, listMax] and, if room allows, leaves the
    /// chart at least chartMin. The list never goes below listMin (never collapses to 0).
    public static func clampList(_ proposed: Double, total: Double) -> Double {
        let roomForList = total - divider - chartMin
        return max(listMin, min(listMax, proposed, max(roomForList, listMin)))
    }

    /// Divider position (x of the divider = chart width) for a given list width.
    public static func dividerPosition(total: Double, listWidth: Double) -> Double {
        max(0, total - divider - listWidth)
    }

    /// True when a measured layout violates the spec (used by the DEBUG assertion + log).
    public static func isListTooNarrow(listWidth: Double, collapsed: Bool) -> Bool {
        collapsed || listWidth + 0.5 < listMin
    }
}
