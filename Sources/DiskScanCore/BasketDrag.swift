import Foundation

/// Internal drag-to-delete-zone helpers (pure). No AppKit; no 「拖到这里」 copy.
///
/// Payload is a list of absolute paths on a private pasteboard type. Protection is
/// supplied by the caller (same `protectionReason` / DeletionGuard path as 「加入删除区」).
public enum BasketDrag: Sendable {
    /// Private UTI — never registered for Finder / external drops.
    public static let pasteboardType = "app.diskrings.DiskRings.internal-file-nodes"

    /// Forbidden placeholder strings (product: no 「拖到这里」 / “Drop here”).
    public static let forbiddenPlaceholders = ["拖到这里", "拖到此處", "Drop here", "Drag here", "Drop items here"]

    public enum Highlight: Equatable, Sendable {
        case idle
        /// At least one path would be accepted.
        case accepting
        /// Drag is over the zone but every path is protected / empty.
        case rejecting
    }

    public struct Evaluation: Equatable, Sendable {
        public let paths: [String]
        public let accepted: [String]
        public let refused: [String]
        public var canDrop: Bool { !accepted.isEmpty }
        public init(paths: [String], accepted: [String], refused: [String]) {
            self.paths = paths; self.accepted = accepted; self.refused = refused
        }

        /// `isProtected` mirrors `protectionReason(node) != nil` for each path.
        public static func evaluate(paths: [String], isProtected: (String) -> Bool) -> Evaluation {
            let unique = Self.uniquePreservingOrder(paths)
            var ok: [String] = [], no: [String] = []
            for p in unique {
                if isProtected(p) { no.append(p) } else { ok.append(p) }
            }
            return Evaluation(paths: unique, accepted: ok, refused: no)
        }

        private static func uniquePreservingOrder(_ paths: [String]) -> [String] {
            var seen = Set<String>(), out: [String] = []
            for p in paths where !p.isEmpty && !seen.contains(p) { seen.insert(p); out.append(p) }
            return out
        }
    }

    public static func highlight(isOverZone: Bool, evaluation: Evaluation?) -> Highlight {
        guard isOverZone, let e = evaluation else { return .idle }
        if e.paths.isEmpty { return .rejecting }
        return e.canDrop ? .accepting : .rejecting
    }

    /// Encode / decode path lists for the private pasteboard (newline-separated).
    public static func encodePaths(_ paths: [String]) -> String { paths.joined(separator: "\n") }
    public static func decodePaths(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    /// Resolve absolute paths under a scan root (same path rules as `FileNode.path`).
    public static func resolve(paths: [String], under root: FileNode) -> [FileNode] {
        let rootPath = root.path
        return paths.compactMap { path -> FileNode? in
            if path == rootPath { return root }
            guard path.hasPrefix(rootPath) else { return nil }
            var rel = String(path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if rel.isEmpty { return root }
            return root.descendant(atRelativePath: rel.split(separator: "/").map(String.init))
        }
    }
}
