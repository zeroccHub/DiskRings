import Foundation
#if !SINGLE_MODULE
import DiskScanCore
#endif

/// Whole-tree name search (toolbar 「搜索文件和文件夹」). Runs off the main thread over the
/// scanned tree; case-insensitive substring match on each node's own name.
///   • matching: ASCII queries use an allocation-free byte scan with ASCII case folding over the
///     name's UTF-8 (no lowercase index exists in the scan/TreeAnalysis, and building one would
///     cost ~5M strings of memory); non-ASCII queries fall back to a case-insensitive Foundation
///     search per node
///   • results: the `limit` (500) largest hits, size descending (ties: name, then path), plus the
///     total number of matches
///   • cancellable: `Token.cancel()` is polled every 4096 nodes
public enum TreeSearch {
    public static let limit = 500
    public static let debounce: TimeInterval = 0.2

    /// Cancellation flag shared between the main thread and the search worker.
    public final class Token: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        public init() {}
        public func cancel() { lock.lock(); flag = true; lock.unlock() }
        public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    public struct Hit: @unchecked Sendable {
        public let node: FileNode
        public let size: Double
        /// Parent folder relative to the search root ("Users/mac387/Documents"; "" = root itself).
        public let relativePath: String
        public var name: String { node.sunburstName }
    }

    public struct Result: @unchecked Sendable {
        public let query: String
        public let hits: [Hit]            // ≤ limit, size descending
        public let total: Int             // all matches
        public let visited: Int
        public let cancelled: Bool
        /// Aborted after `timeout` (regex guard); no hits are shown then.
        public var timedOut: Bool = false
        public var isTruncated: Bool { total > hits.count }
    }

    // MARK: Query options (contains / regex, name / relative path)

    public enum Mode: String, Sendable, CaseIterable { case contains, regex }
    public enum Scope: String, Sendable, CaseIterable { case name, path }

    /// What the user asked for. `/pattern/` typed in the field forces regex mode.
    public struct Query: Equatable, Sendable {
        public var text: String
        public var mode: Mode
        public var scope: Scope
        public init(text: String, mode: Mode = .contains, scope: Scope = .name) {
            self.text = text; self.mode = mode; self.scope = scope
        }
        /// Parses the field text: surrounding whitespace trimmed; "/…/" (≥ 1 char inside) →
        /// regex with the slashes removed; otherwise the menu's mode.
        public static func parse(_ raw: String, mode: Mode, scope: Scope) -> Query {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 3, t.hasPrefix("/"), t.hasSuffix("/") {
                return Query(text: String(t.dropFirst().dropLast()), mode: .regex, scope: scope)
            }
            return Query(text: t, mode: mode, scope: scope)
        }
    }

    /// Regex guard (catastrophic backtracking): one search is aborted after this many seconds;
    /// the deadline is checked between nodes, so a single pathological match cannot be
    /// interrupted mid-call — subjects are therefore capped at `maxRegexSubject` UTF-16 units
    /// (names are ≤ 255 bytes; long relative paths keep their LAST 1024 units).
    public static let regexTimeout: TimeInterval = 10
    public static let maxRegexSubject = 1024

    public enum CompileError: Error, Equatable { case emptyPattern, invalidRegex(String) }

    /// Precompiled pattern (compiled once per query, shared read-only by the worker).
    public struct Compiled: @unchecked Sendable {
        public let query: Query
        let matcher: Matcher?
        /// True when a regex simplified to a literal and runs on the fast substring matcher.
        public var usesLiteralMatcher: Bool { matcher != nil && query.mode == .regex }
        let regex: NSRegularExpression?
        public func matches(_ subject: String) -> Bool {
            if let m = matcher { return m.matches(subject) }
            guard let re = regex else { return false }
            let ns = subject as NSString
            var range = NSRange(location: 0, length: ns.length)
            if range.length > TreeSearch.maxRegexSubject {
                range = NSRange(location: ns.length - TreeSearch.maxRegexSubject, length: TreeSearch.maxRegexSubject)
            }
            // Anchors keep their real meaning when the subject was capped (^ = true start).
            return re.firstMatch(in: subject, options: range.location > 0 ? [.withoutAnchoringBounds] : [],
                                 range: range) != nil
        }
    }

    /// Case-insensitive in both modes. Invalid regex → `.invalidRegex(message)`; no search runs.
    public static func compile(_ q: Query) -> Swift.Result<Compiled, CompileError> {
        guard !q.text.isEmpty else { return .failure(.emptyPattern) }
        switch q.mode {
        case .contains:
            return .success(Compiled(query: q, matcher: Matcher(q.text), regex: nil))
        case .regex:
            // Contains semantics: leading/trailing ".*" are redundant (firstMatch is unanchored),
            // so they are stripped; a pattern that is then a plain literal uses the fast matcher.
            let core = simplifiedRegex(q.text)
            if !core.isEmpty, core.unicodeScalars.allSatisfy({ !regexMeta.contains($0) }) {
                return .success(Compiled(query: q, matcher: Matcher(core), regex: nil))
            }
            do {
                let re = try NSRegularExpression(pattern: core.isEmpty ? q.text : core, options: [.caseInsensitive])
                return .success(Compiled(query: q, matcher: nil, regex: re))
            } catch {
                let msg = (error as NSError).userInfo["NSInvalidValue"].map { "\($0)" } ?? q.text
                return .failure(.invalidRegex(msg))
            }
        }
    }

    static let regexMeta = Set("\\^$.|?*+()[]{}".unicodeScalars)
    /// Strips redundant leading ".*" / ".*?" and trailing ".*" / ".*?" (not escaped) from a
    /// contains-style regex. Invalid patterns are left for NSRegularExpression to reject.
    public static func simplifiedRegex(_ p: String) -> String {
        var s = Substring(p)
        while true {
            if s.hasPrefix(".*?") { s = s.dropFirst(3) } else if s.hasPrefix(".*") { s = s.dropFirst(2) } else { break }
        }
        func escapedAt(_ i: String.Index) -> Bool {     // odd number of backslashes before i
            var n = 0, j = i
            while j > s.startIndex { j = s.index(before: j); if s[j] == "\\" { n += 1 } else { break } }
            return n % 2 == 1
        }
        while true {
            if s.hasSuffix(".*?"), !escapedAt(s.index(s.endIndex, offsetBy: -3)) { s = s.dropLast(3) }
            else if s.hasSuffix(".*"), !escapedAt(s.index(s.endIndex, offsetBy: -2)) { s = s.dropLast(2) }
            else { break }
        }
        return String(s)
    }

    /// Search with options (contains/regex × name/path). Synchronous: call off the main thread.
    /// Checks `token` and the `timeout` deadline between nodes.
    public static func run(root: FileNode, compiled: Compiled, limit: Int = TreeSearch.limit,
                           token: Token = Token(), timeout: TimeInterval = TreeSearch.regexTimeout,
                           size: (FileNode) -> Double = { $0.sunburstSize }) -> Result {
        let q = compiled.query
        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(0, timeout) * 1e9)
        // Regex: deadline + cancel checked before EVERY node (a clock read is ~25 ns vs µs+ per
        // match), so a run stops within one match of the deadline. Contains: every 4096 nodes.
        let checkEvery = compiled.regex != nil ? 0 : 4095
        var stack: [(FileNode, String)] = root.children.map { ($0, "") }   // (node, parent rel path) in path mode
        var cand: [(node: FileNode, size: Double)] = []
        cand.reserveCapacity(limit * 2 + 1)
        var floor = -Double.infinity
        var total = 0, visited = 0
        let pathMode = q.scope == .path
        while let (n, parentPath) = stack.popLast() {
            visited += 1
            if visited & checkEvery == 0 {
                if token.isCancelled { return Result(query: q.text, hits: [], total: total, visited: visited, cancelled: true) }
                if DispatchTime.now().uptimeNanoseconds > deadline {
                    return Result(query: q.text, hits: [], total: total, visited: visited, cancelled: false, timedOut: true)
                }
            }
            let rel = pathMode ? (parentPath.isEmpty ? n.name : parentPath + "/" + n.name) : ""
            if compiled.matches(pathMode ? rel : n.name) {
                total += 1
                let sz = size(n)
                if sz >= floor {
                    cand.append((n, sz))
                    if cand.count >= 2 * limit {
                        cand.sort { order($0.size, $0.node, $1.size, $1.node) }
                        cand.removeLast(cand.count - limit)
                        floor = cand.last!.size
                    }
                }
            }
            if !n.children.isEmpty {
                for c in n.children { stack.append((c, rel)) }
            }
        }
        if token.isCancelled { return Result(query: q.text, hits: [], total: total, visited: visited, cancelled: true) }
        cand.sort { order($0.size, $0.node, $1.size, $1.node) }
        if cand.count > limit { cand.removeLast(cand.count - limit) }
        let hits = cand.map { Hit(node: $0.node, size: $0.size, relativePath: relativeParentPath($0.node, root: root)) }
        return Result(query: q.text, hits: hits, total: total, visited: visited, cancelled: false)
    }

    /// Magnifier-menu choices for this app session. Deliberately NOT persisted: every launch
    /// starts in Contains / names (regex is opt-in per session; "/pattern/" opts in per query).
    public struct Settings: Equatable, Sendable {
        public var mode: Mode
        public var scope: Scope
        public init(mode: Mode = .contains, scope: Scope = .name) { self.mode = mode; self.scope = scope }
        /// The state every app launch starts with.
        public static let launch = Settings()
        public var regexEnabled: Bool { mode == .regex }
    }

    /// Case-insensitive substring matcher, prepared once per query.
    public struct Matcher: Sendable {
        public let query: String
        let folded: [UInt8]               // ASCII-lowercased query bytes (ASCII queries)
        let ascii: Bool
        public init(_ q: String) {
            query = q.trimmingCharacters(in: .whitespacesAndNewlines)
            let bytes = Array(query.utf8)
            ascii = bytes.allSatisfy { $0 < 0x80 }
            folded = bytes.map { ($0 >= 65 && $0 <= 90) ? $0 + 32 : $0 }
        }
        public var isEmpty: Bool { query.isEmpty }
        public func matches(_ name: String) -> Bool {
            if query.isEmpty { return false }
            if !ascii { return name.range(of: query, options: [.caseInsensitive]) != nil }
            let q = folded, n = q.count
            var name = name
            return name.withUTF8 { b -> Bool in
                let m = b.count
                if m < n { return false }
                let first = q[0]
                var i = 0
                while i <= m - n {
                    var c = b[i]; if c >= 65 && c <= 90 { c += 32 }
                    if c == first {
                        var j = 1
                        while j < n {
                            var d = b[i + j]; if d >= 65 && d <= 90 { d += 32 }
                            if d != q[j] { break }
                            j += 1
                        }
                        if j == n { return true }
                    }
                    i += 1
                }
                return false
            }
        }
    }

    /// Searches every descendant of `root` (not the root itself). Synchronous: call it off the
    /// main thread. Returns `cancelled = true` (and no hits) when the token fired.
    public static func run(root: FileNode, query: String, limit: Int = TreeSearch.limit,
                           token: Token = Token(), size: (FileNode) -> Double = { $0.sunburstSize }) -> Result {
        let matcher = Matcher(query)
        guard !matcher.isEmpty else { return Result(query: matcher.query, hits: [], total: 0, visited: 0, cancelled: false) }
        var stack: [FileNode] = root.children
        var cand: [(node: FileNode, size: Double)] = []
        cand.reserveCapacity(limit * 2 + 1)
        var floor = -Double.infinity            // smallest size still kept once trimmed
        var total = 0, visited = 0
        func trim() {
            cand.sort { order($0.size, $0.node, $1.size, $1.node) }
            cand.removeLast(cand.count - limit)
            floor = cand.last!.size
        }
        while let n = stack.popLast() {
            visited += 1
            if visited & 4095 == 0, token.isCancelled {
                return Result(query: matcher.query, hits: [], total: total, visited: visited, cancelled: true)
            }
            if matcher.matches(n.name) {
                total += 1
                let s = size(n)
                if s >= floor {
                    cand.append((n, s))
                    if cand.count >= 2 * limit { trim() }
                }
            }
            if !n.children.isEmpty { stack.append(contentsOf: n.children) }
        }
        if token.isCancelled { return Result(query: matcher.query, hits: [], total: total, visited: visited, cancelled: true) }
        cand.sort { order($0.size, $0.node, $1.size, $1.node) }
        if cand.count > limit { cand.removeLast(cand.count - limit) }
        let hits = cand.map { Hit(node: $0.node, size: $0.size, relativePath: relativeParentPath($0.node, root: root)) }
        return Result(query: matcher.query, hits: hits, total: total, visited: visited, cancelled: false)
    }

    /// Size descending; ties by name, then path (stable, deterministic).
    static func order(_ sa: Double, _ a: FileNode, _ sb: Double, _ b: FileNode) -> Bool {
        if sa != sb { return sa > sb }
        if a.name != b.name { return a.name < b.name }
        return a.path < b.path
    }

    /// Parent folder of `node` relative to `root`, components joined by "/".
    public static func relativeParentPath(_ node: FileNode, root: FileNode) -> String {
        var parts: [String] = []
        var cur = node.parent
        while let c = cur, c !== root { parts.append(c.sunburstName); cur = c.parent }
        return parts.reversed().joined(separator: "/")
    }

    /// Clicking a result: the chart drills to the hit's parent (root when it has none) and
    /// selects the hit there.
    public static func locate(_ node: FileNode, root: FileNode) -> (focus: FileNode, select: FileNode) {
        (node.parent ?? root, node)
    }
}

/// Search UI state (pure): query, the view to restore on Esc, and stale-result protection.
/// Search-field presentation for the regex state. Deliberately NO view inside the field:
/// only the placeholder, the tooltip and a footer prefix change.
public struct SearchFieldConfig: Equatable, Sendable {
    public let regexActive: Bool
    public let placeholderKey: String
    public let toolTipKey: String
    public let footerPrefixKey: String?
    /// The controller never adds a subview into the NSSearchField (gate: search-field.py).
    public static let addsSubviewsToField = false
    public static func make(text: String, settings: TreeSearch.Settings) -> SearchFieldConfig {
        let on = SearchModeIndicator.regexBadgeVisible(text: text, settings: settings)
        return SearchFieldConfig(regexActive: on,
                                 placeholderKey: settings.regexEnabled ? "search.placeholder.regex" : "search.placeholder",
                                 toolTipKey: on ? "search.tip.regex" : "search.tip.contains",
                                 footerPrefixKey: on ? "search.footer.regexPrefix" : nil)
    }
    public static let launch = make(text: "", settings: .launch)
}

/// Whether the effective mode is regex: visible only while the effective mode is regex
/// (menu toggle on, or the current text is a /pattern/ query). Hidden at launch.
public enum SearchModeIndicator {
    public static func regexBadgeVisible(text: String, settings: TreeSearch.Settings) -> Bool {
        TreeSearch.Query.parse(text, mode: settings.mode, scope: settings.scope).mode == .regex
    }
}

public struct SearchState<Focus: AnyObject> {
    public private(set) var query = ""
    /// Focus before the search started; Esc navigates back to it.
    public private(set) weak var restoreFocus: Focus?
    /// Bumped on every change; a result is shown only if its generation is current.
    public private(set) var generation = 0
    public var isActive: Bool { !query.isEmpty }
    public init() {}

    public enum Action: Equatable { case none, start(generation: Int, query: String), clear }
    /// The field text changed (after the debounce).
    public mutating func typed(_ text: String, current: Focus?) -> Action {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q != query else { return .none }
        if query.isEmpty { restoreFocus = current }       // remember the view the search started from
        query = q
        generation += 1
        if q.isEmpty { restoreFocus = nil; return .clear }
        return .start(generation: generation, query: q)
    }
    /// Esc: clears and returns the focus to restore (nil = stay).
    public mutating func escape() -> Focus? {
        guard isActive else { return nil }
        let r = restoreFocus
        query = ""; restoreFocus = nil; generation += 1
        return r
    }
    /// Tree changed (deletion): same query, new generation (keeps the Esc restore target).
    public mutating func refresh() -> Action {
        guard isActive else { return .none }
        generation += 1
        return .start(generation: generation, query: query)
    }
    /// New scan: clears without restoring.
    public mutating func rescan() { query = ""; restoreFocus = nil; generation += 1 }
    /// Whether a finished search may be shown.
    public func accepts(generation g: Int) -> Bool { isActive && g == generation }
}
