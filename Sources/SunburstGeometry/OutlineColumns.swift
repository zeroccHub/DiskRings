/// Column geometry for the right-hand outline (normal tree and search results).
///
/// Size and share are FIXED-width, right-aligned and never user-resizable; the name column
/// takes whatever is left (firstColumnOnly autoresizing + explicit refit on every pane resize).
/// All numbers in points.
public enum OutlineColumns {
    /// Widest size string the formatter emits.
    public static let widestSize = "999.9 GB"
    /// Box estimate of `widestSize` in 13 pt monospaced-digit system font (0.6 em/char,
    /// generous vs the real ~7.3 pt advance); the app measures the real font and uses the max.
    public static let estimatedWidestSizeText: Double = Double(widestSize.count) * 13 * 0.6
    public static let sizePadding: Double = 12          // 4 trailing inset + 8 breathing room
    public static let sizeMinimum: Double = 72
    public static let shareWidth: Double = 52            // "100%" / "9.9%" in 11 pt
    public static let nameMinimum: Double = 120
    /// NSTableView adds intercellSpacing.width to every column.
    public static let intercellSpacing: Double = 4
    /// `.inset` style: horizontal row inset on both sides (measured on macOS 12–15: 10 + 10).
    public static let styleInset: Double = 20

    public static func sizeWidth(measuredText: Double? = nil) -> Double {
        let text = max(measuredText ?? 0, estimatedWidestSizeText)
        return max(sizeMinimum, (text + sizePadding).rounded(.up))
    }

    public struct Widths: Equatable {
        public let name: Double, size: Double, share: Double
        public var total: Double { name + size + share + 3 * OutlineColumns.intercellSpacing + OutlineColumns.styleInset }
    }

    /// Widths for a pane (clip view) width; `scroller` = legacy vertical scroller width (0 for overlay).
    public static func widths(pane: Double, scroller: Double = 0, measuredSizeText: Double? = nil) -> Widths {
        let size = sizeWidth(measuredText: measuredSizeText)
        let fixed = size + shareWidth + 3 * intercellSpacing + styleInset + scroller
        return Widths(name: max(nameMinimum, (pane - fixed).rounded(.down)), size: size, share: shareWidth)
    }

    /// Names compressed from a chain ("Library › Application Support") truncate in the middle so
    /// both ends stay readable; plain names truncate at the tail.
    public static func truncation(forName name: String) -> ResultRowLayout.Truncation {
        name.contains(" › ") ? .middle : .tail
    }
}
