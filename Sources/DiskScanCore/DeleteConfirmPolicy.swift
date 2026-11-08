import Foundation

/// Portable policy for the Batch-3 delete-confirm sheet (§4.6).
/// Does not call DeletionGuard; the sheet still runs deletions through the existing pipeline.
public enum DeleteConfirmPolicy {
    public enum Method: String, Sendable, Equatable, CaseIterable {
        case trash
        case permanent
    }

    /// What the primary action requires after the user picks a method.
    public enum SecondaryConfirm: Equatable, Sendable {
        case none                          // Trash: normal one-click confirm on the sheet
        case typePhrase(String)            // Permanent: always type the phrase (simplify-v2 §6)
    }

    public struct Item: Equatable, Sendable {
        public var id: String              // stable path
        public var name: String
        public var path: String
        public var bytes: UInt64
        public var isHighRisk: Bool
        public var riskReasons: [String]
        public var checked: Bool

        public init(id: String, name: String, path: String, bytes: UInt64,
                    isHighRisk: Bool, riskReasons: [String], checked: Bool = true) {
            self.id = id; self.name = name; self.path = path; self.bytes = bytes
            self.isHighRisk = isHighRisk; self.riskReasons = riskReasons; self.checked = checked
        }
    }

    public struct ExcludedItem: Equatable, Sendable {
        public var name: String
        public var path: String
        public var bytes: UInt64
        public var reasonCode: String      // opaque; UI localizes
        public init(name: String, path: String, bytes: UInt64, reasonCode: String) {
            self.name = name; self.path = path; self.bytes = bytes; self.reasonCode = reasonCode
        }
    }

    public struct Snapshot: Equatable, Sendable {
        public var items: [Item]
        public var excluded: [ExcludedItem]
        public var method: Method

        public init(items: [Item], excluded: [ExcludedItem] = [], method: Method = .trash) {
            self.items = items; self.excluded = excluded; self.method = method
        }

        public var checkedItems: [Item] { items.filter(\.checked) }
        public var checkedCount: Int { checkedItems.count }
        public var checkedBytes: UInt64 { checkedItems.reduce(0) { $0 &+ $1.bytes } }
        public var checkedHighRiskCount: Int { checkedItems.filter(\.isHighRisk).count }
        public var highRiskItems: [Item] { items.filter { $0.isHighRisk } }
        public var normalItems: [Item] { items.filter { !$0.isHighRisk } }
        public var excludedCount: Int { excluded.count }
    }

    /// Exact phrase the user must type for any permanent delete.
    /// zh: “永久删除” · en: “Delete Permanently”.
    public static func typeConfirmPhrase(languageIsChinese: Bool) -> String {
        languageIsChinese ? "永久删除" : "Delete Permanently"
    }

    /// Secondary confirm required for the current method.
    public static func secondaryConfirm(for snapshot: Snapshot, languageIsChinese: Bool) -> SecondaryConfirm {
        switch snapshot.method {
        case .trash: return .none
        case .permanent: return .typePhrase(typeConfirmPhrase(languageIsChinese: languageIsChinese))
        }
    }

    /// Return/Enter must NOT trigger delete when Permanent is selected (no keyEquivalent).
    public static func returnKeyTriggersPrimary(method: Method) -> Bool {
        method == .trash
    }

    /// Primary button enabled?
    public static func primaryEnabled(snapshot: Snapshot, typedText: String, languageIsChinese: Bool) -> Bool {
        guard snapshot.checkedCount > 0 else { return false }
        switch secondaryConfirm(for: snapshot, languageIsChinese: languageIsChinese) {
        case .none:
            return true
        case .typePhrase(let phrase):
            return typedText == phrase
        }
    }

    /// Toggle / set checked by id; returns updated snapshot.
    public static func settingChecked(id: String, checked: Bool, in snapshot: Snapshot) -> Snapshot {
        var s = snapshot
        if let i = s.items.firstIndex(where: { $0.id == id }) {
            s.items[i].checked = checked
        }
        return s
    }

    public static func settingMethod(_ method: Method, in snapshot: Snapshot) -> Snapshot {
        var s = snapshot
        s.method = method
        return s
    }

    /// Build a snapshot from basket nodes + protected refusals.
    public static func build(
        nodes: [FileNode],
        excluded: [(node: FileNode, reasonCode: String)],
        homeDirectory: String,
        preferredMethod: Method
    ) -> Snapshot {
        let items: [Item] = nodes.map { n in
            let v = BasketRisk.classify(n, homeDirectory: homeDirectory)
            return Item(id: n.path, name: n.name, path: n.path,
                        bytes: n.contributedSize(.actual),
                        isHighRisk: v.isHighRisk, riskReasons: v.reasons, checked: true)
        }
        let excl: [ExcludedItem] = excluded.map {
            ExcludedItem(name: $0.node.name, path: $0.node.path,
                         bytes: $0.node.contributedSize(.actual), reasonCode: $0.reasonCode)
        }
        return Snapshot(items: items, excluded: excl, method: preferredMethod)
    }

    /// Consequence copy key for a risk reason (UI looks up localized string).
    public static func consequenceKey(for reasons: [String]) -> String {
        if reasons.contains("appBundle") { return "confirm.consequence.app" }
        if reasons.contains("library") { return "confirm.consequence.library" }
        if reasons.contains("hidden") { return "confirm.consequence.hidden" }
        if reasons.contains("over50GB") { return "confirm.consequence.large" }
        return "confirm.consequence.generic"
    }
}
