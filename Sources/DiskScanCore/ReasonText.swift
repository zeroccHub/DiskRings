import Foundation

/// Localization of core refusal reasons, cautions, details and deletion
/// errors. The core keeps its enum codes and English `description`s (used by
/// tests and the CLI); the presentation layer renders them through a lookup
/// (NSLocalizedString in the app). Without a lookup, or for a key the lookup
/// doesn't know, the English template below is used, so output on Linux and
/// in tests is unchanged. `ReasonTextTests` checks that every template renders
/// exactly the English `description` and that en.lproj contains the same text.
public enum ReasonText {
    /// A localizable message: a stable key plus string arguments (`%@`/`%n$@`).
    public struct Message: Equatable, Sendable {
        public let key: String
        public let args: [String]
        public init(_ key: String, _ args: [String] = []) { self.key = key; self.args = args }
    }

    public typealias Lookup = (String) -> String?

    // MARK: English templates (source of truth for en.lproj)

    public static let english: [String: String] = [
        "reason.filesystemRoot": "Protected: filesystem root",
        "reason.volumeRoot": "Protected: volume root (%@)",
        "reason.containsVolume": "Protected: contains the mounted volume %@",
        "reason.homeFolder": "Protected: your home folder",
        "reason.containsHomeFolder": "Protected: contains your home folder",
        "reason.systemLocation": "Protected: system location (%@)",
        "reason.containsProtected": "Protected: contains system location %@",
        "reason.essentialFolder": "Protected: essential folder (%@)",
        "reason.sipProtected": "SIP-protected (restricted / no-unlink flag)",
        "reason.unsafePath": "Refused: unsafe path (%@)",
        "reason.containsOtherDevice": "Refused: contains another volume or mount (%@)",
        "reason.containsRestricted": "Refused: contains a SIP-protected item (%@)",
        "reason.contentsNotVerifiable": "Refused: contents could not be fully checked (%@)",
        "reason.changedSinceCheck": "Refused: item changed since it was checked (%@)",
        "reason.cannotDelete": "Refused: can't be deleted completely — %1$@ (%2$@)",
        "reason.cancelled": "Cancelled",

        "caution.launchdJob": "Background service definition (%@). Removing it can break or disable software (VPNs, drivers, updaters, security tools); the change takes effect at next login/boot.",
        "caution.applicationBundle": "Application bundle (%@). Deleting an app does not remove its helpers or data, and some apps need a vendor uninstaller.",
        "caution.systemTempFolders": "Per-user system caches and temp files (%@). Running apps may crash or lose state; macOS recreates what it needs after a restart.",

        "detail.fullDiskAccess": Detail.fullDiskAccess,
        "detail.folderNotWritableToMove": Detail.folderNotWritableToMove,
        "detail.folderReadError": "folder could not be read completely (%@)",
        "detail.folderFlagged": "folder is %@ (entries can't be removed)",
        "detail.folderACLDenyChild": Detail.folderACLDenyChild,
        "detail.folderReadOnly": Detail.folderReadOnly,
        "detail.entryACLDeny": Detail.entryACLDeny,
        "detail.stickyOtherUser": Detail.stickyOtherUser,
        "flag.uchg": "locked (uchg)",
        "flag.uappnd": "append-only (uappnd)",
        "flag.schg": "system-immutable (schg)",
        "flag.sappnd": "system-append-only (sappnd)",
        "flag.generic": "flagged",
        "list.separator": ", ",

        "error.posix": "%1$@ failed for %2$@: %3$@ (errno %4$@)",
        "error.posixWithHint": "%1$@ failed for %2$@: %3$@ (errno %4$@). %5$@",
        "error.trashUnavailable": "The Trash is not available on this system",
        "error.refusedRoot": "Refused to delete %@",
        "error.privilegedHelper": "Administrator deletion is not implemented",
        "error.underlying": "%1$@: %2$@",
        "error.blocked": "%1$@: %2$@",
        "error.needsConfirmation": "%1$@: needs extra confirmation — %2$@",
        "error.partiallyDeleted": "%1$@: PARTIALLY deleted (%2$@ entries removed) — %3$@. Rescan this folder.",
        "error.cancelled": "Cancelled before this item was touched",
    ]

    /// Exact English detail texts emitted by DeletabilityChecker.
    public enum Detail {
        public static let fullDiskAccess = "macOS privacy protection (no Full Disk Access) — grant DiskRings Full Disk Access in System Settings > Privacy & Security > Full Disk Access"
        public static let folderNotWritableToMove = "folder is not writable (needed to move it)"
        public static let folderACLDenyChild = "folder has an ACL that denies deleting its contents (delete_child)"
        public static let folderReadOnly = "folder is read-only for you (its contents can't be removed)"
        public static let entryACLDeny = "an ACL denies deleting this item (delete)"
        public static let stickyOtherUser = "sticky folder: owned by another user"
    }

    // MARK: Mapping

    public static func message(_ r: DeletionGuard.Reason, lookup: Lookup? = nil) -> Message {
        switch r {
        case .filesystemRoot: return Message("reason.filesystemRoot")
        case .volumeRoot(let p): return Message("reason.volumeRoot", [p])
        case .containsVolume(let p): return Message("reason.containsVolume", [p])
        case .homeFolder: return Message("reason.homeFolder")
        case .containsHomeFolder: return Message("reason.containsHomeFolder")
        case .systemLocation(let p): return Message("reason.systemLocation", [p])
        case .containsProtected(let p): return Message("reason.containsProtected", [p])
        case .essentialFolder(let p): return Message("reason.essentialFolder", [p])
        case .sipProtected: return Message("reason.sipProtected")
        case .unsafePath(let why): return Message("reason.unsafePath", [why])
        case .containsOtherDevice(let p): return Message("reason.containsOtherDevice", [p])
        case .containsRestricted(let p): return Message("reason.containsRestricted", [p])
        case .contentsNotVerifiable(let p): return Message("reason.contentsNotVerifiable", [p])
        case .changedSinceCheck(let p): return Message("reason.changedSinceCheck", [p])
        case .cannotDelete(let p, let why): return Message("reason.cannotDelete", [detail(why, lookup: lookup), p])
        case .cancelled: return Message("reason.cancelled")
        }
    }

    public static func message(_ c: DeletionGuard.Caution) -> Message {
        switch c {
        case .launchdJob(let p): return Message("caution.launchdJob", [p])
        case .applicationBundle(let p): return Message("caution.applicationBundle", [p])
        case .systemTempFolders(let p): return Message("caution.systemTempFolders", [p])
        }
    }

    public static func message(_ e: DeletionError, lookup: Lookup? = nil) -> Message {
        switch e {
        case .posix(let p, let op, let code):
            let base = [op, p, String(cString: strerror(code)), String(code)]
            return code == EPERM ? Message("error.posixWithHint", base + [render(Message("detail.fullDiskAccess"), lookup: lookup)])
                                 : Message("error.posix", base)
        case .trashUnavailable: return Message("error.trashUnavailable")
        case .refusedRoot(let p): return Message("error.refusedRoot", [p])
        case .privilegedHelperNotImplemented: return Message("error.privilegedHelper")
        case .underlying(let p, let d): return Message("error.underlying", [p, d])
        case .blocked(let p, let r): return Message("error.blocked", [p, text(r, lookup: lookup)])
        case .needsConfirmation(let p, let c): return Message("error.needsConfirmation", [p, render(message(c), lookup: lookup)])
        case .partiallyDeleted(let p, let n, let cause): return Message("error.partiallyDeleted", [p, String(n), cause])
        case .cancelled: return Message("error.cancelled")
        }
    }

    /// Localizes a free-text detail from DeletabilityChecker. Unknown text is
    /// returned unchanged (English).
    public static func detail(_ why: String, lookup: Lookup? = nil) -> String {
        let exact: [String: String] = [
            Detail.fullDiskAccess: "detail.fullDiskAccess",
            Detail.folderNotWritableToMove: "detail.folderNotWritableToMove",
            Detail.folderACLDenyChild: "detail.folderACLDenyChild",
            Detail.folderReadOnly: "detail.folderReadOnly",
            Detail.entryACLDeny: "detail.entryACLDeny",
            Detail.stickyOtherUser: "detail.stickyOtherUser",
        ]
        if let k = exact[why] { return render(Message(k), lookup: lookup) }
        let rp = "folder could not be read completely (", fp = "folder is ", fs = " (entries can't be removed)"
        if why.hasPrefix(rp), why.hasSuffix(")") {
            return render(Message("detail.folderReadError", [String(why.dropFirst(rp.count).dropLast())]), lookup: lookup)
        }
        if why.hasPrefix(fp), why.hasSuffix(fs), let flags = flags(String(why.dropFirst(fp.count).dropLast(fs.count)), lookup: lookup) {
            return render(Message("detail.folderFlagged", [flags]), lookup: lookup)
        }
        return flags(why, lookup: lookup) ?? why
    }

    /// "locked (uchg), append-only (uappnd)" → localized list; nil if not a flag list.
    static func flags(_ s: String, lookup: Lookup?) -> String? {
        let keys = ["flag.uchg", "flag.uappnd", "flag.schg", "flag.sappnd", "flag.generic"]
        var out: [String] = []
        for part in s.components(separatedBy: ", ") {
            guard let k = keys.first(where: { english[$0] == part }) else { return nil }
            out.append(render(Message(k), lookup: lookup))
        }
        return out.joined(separator: render(Message("list.separator"), lookup: lookup))
    }

    // MARK: Rendering

    public static func text(_ r: DeletionGuard.Reason, lookup: Lookup? = nil) -> String { render(message(r, lookup: lookup), lookup: lookup) }
    public static func text(_ c: DeletionGuard.Caution, lookup: Lookup? = nil) -> String { render(message(c), lookup: lookup) }
    public static func text(_ e: DeletionError, lookup: Lookup? = nil) -> String { render(message(e, lookup: lookup), lookup: lookup) }

    /// Fills `%@` / `%n$@` placeholders with string arguments (no other
    /// specifiers are allowed in these keys). Falls back to English when the
    /// lookup has no usable value.
    public static func render(_ m: Message, lookup: Lookup? = nil) -> String {
        var template = english[m.key] ?? m.key
        if let l = lookup?(m.key), !l.isEmpty, l != m.key { template = l }
        return substitute(template, m.args)
    }

    public static func substitute(_ template: String, _ args: [String]) -> String {
        var out = ""
        var next = 0
        var i = template.startIndex
        while i < template.endIndex {
            let ch = template[i]
            guard ch == "%" else { out.append(ch); i = template.index(after: i); continue }
            var j = template.index(after: i)
            guard j < template.endIndex else { out.append(ch); break }
            if template[j] == "%" { out.append("%"); i = template.index(after: j); continue }
            var digits = ""
            while j < template.endIndex, template[j].isNumber { digits.append(template[j]); j = template.index(after: j) }
            var index = next
            if !digits.isEmpty, j < template.endIndex, template[j] == "$" { index = (Int(digits) ?? 1) - 1; j = template.index(after: j) }
            if j < template.endIndex, template[j] == "@" {
                out += index < args.count ? args[index] : ""
                if digits.isEmpty { next += 1 }
                i = template.index(after: j)
            } else { out.append(ch); i = template.index(after: i) }
        }
        return out
    }
}
