/// Pure row-geometry/config model for the right-hand results list (P1 row-overflow fix).
///
/// Every text line in a row is single-line, non-wrapping and truncated; the row height is
/// fixed and computed from these numbers so content can never exceed it.
public enum ResultRowLayout {
    /// Mirrors NSLineBreakMode without importing AppKit.
    public enum Truncation: Equatable, Sendable { case tail, middle }

    public struct Line: Equatable, Sendable {
        public let fontSize: Double
        public let lineHeight: Double
        public let truncation: Truncation
        public let maxLines: Int
        public let wraps: Bool
        public let singleLineMode: Bool
    }

    /// Plain outline row (one line: name).
    public static let normalRowHeight: Double = 28
    /// Search result row (two lines: name, then relative path).
    public static let searchRowHeight: Double = 38
    public static let verticalPadding: Double = 3
    public static let lineGap: Double = 1
    /// Trailing badge (⚠ 高风险 / 🔒 受保护) gets its own fixed slot; the name never runs under it.
    public static let badgeTrailingInset: Double = 4
    public static let badgeGap: Double = 6

    public static let name = Line(fontSize: 13, lineHeight: 16, truncation: .tail, maxLines: 1, wraps: false, singleLineMode: true)
    public static let path = Line(fontSize: 11, lineHeight: 14, truncation: .middle, maxLines: 1, wraps: false, singleLineMode: true)

    public static func lines(isSearchHit: Bool) -> [Line] { isSearchHit ? [name, path] : [name] }
    public static func rowHeight(isSearchHit: Bool) -> Double { isSearchHit ? searchRowHeight : normalRowHeight }

    /// Height the content needs. Independent of string length because no line may wrap.
    public static func contentHeight(isSearchHit: Bool, text: String = "") -> Double {
        let ls = lines(isSearchHit: isSearchHit)
        return ls.reduce(0) { $0 + $1.lineHeight * Double($1.maxLines) } + lineGap * Double(ls.count - 1) + 2 * verticalPadding
    }

    /// Name width left after icon/indent and the reserved badge slot.
    public static func nameWidth(cellWidth: Double, leading: Double, badgeWidth: Double) -> Double {
        let reserve = badgeWidth > 0 ? badgeWidth + badgeGap + badgeTrailingInset : badgeTrailingInset
        return max(0, cellWidth - leading - reserve)
    }

    /// Full tooltip for a search hit: absolute-ish relative path plus name.
    public static func tooltip(name: String, relativePath: String) -> String {
        relativePath.isEmpty || relativePath == "/" ? name : relativePath + "/" + name
    }
}
