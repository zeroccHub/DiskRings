import Foundation

/// Resolves which outline rows a command (context menu or button) should act on.
///
/// AppKit sets `clickedRow` when the context menu opens, but does **not** always put that
/// row into `selectedRowIndexes` on the first right-click. The bottom 「加入删除区」 button
/// only runs after a real selection, so it worked; the menu called the same selector with
/// an empty selection and added nothing.
public enum OutlineActionTargets: Sendable {
    /// Rows to act on: keep a non-empty selection; otherwise fall back to `clickedRow`.
    public static func rowIndexes(selected: IndexSet, clickedRow: Int, rowCount: Int) -> IndexSet {
        if !selected.isEmpty { return selected }
        if clickedRow >= 0, clickedRow < rowCount { return IndexSet(integer: clickedRow) }
        return IndexSet()
    }

    /// Whether opening / invoking the context menu should select `clickedRow` first.
    public static func shouldSelectClickedRow(selected: IndexSet, clickedRow: Int, rowCount: Int) -> Bool {
        guard clickedRow >= 0, clickedRow < rowCount else { return false }
        return !selected.contains(clickedRow)
    }
}
