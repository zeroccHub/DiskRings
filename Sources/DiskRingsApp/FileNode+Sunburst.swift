#if !SINGLE_MODULE  // SwiftPM: separate modules. build.sh compiles one module with -D SINGLE_MODULE.
import DiskScanCore
import SunburstGeometry
#endif

import Foundation

extension FileNode {
    /// True if this node is still reachable from `root` (i.e. not deleted/detached).
    func isAttached(to root: FileNode) -> Bool {
        if self === root { return true }
        return root.isAncestor(of: self)
    }

    /// User-facing path (no `/System/Volumes/Data` firmlink prefix); display only.
    var displayPath: String { DisplayPath.forUser(path) }

    /// "actual (logical)" text used in tooltips and labels.
    var sizeSummary: String {
        let actual = SizeText.format(contributedSize(.actual))
        let logical = SizeText.format(contributedSize(.logical))
        #if canImport(AppKit)
        return tr("size.summary", actual, logical)
        #else
        return "≈\(actual) on disk (estimate), \(logical) logical"
        #endif
    }

    // Chart flags (high risk, hidden counts) come from TreeAnalysis (SunburstGeometry),
    // computed once in the background — never by walking subtrees while drawing.
}
