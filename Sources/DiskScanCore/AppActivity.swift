import Foundation

/// What the app is doing right now, and therefore which commands are allowed.
/// Pure state machine (no AppKit) so the rules are unit-tested on Linux; the
/// app consults it from `validateMenuItem`, button updates, the volume list and
/// `applicationShouldTerminate`.
public final class AppActivity {
    public enum Command: Sendable, CaseIterable {
        case scan            // open panel, volume click, (future) drag-and-drop / open requests
        case rescan
        case stopScan
        case editDeletionList // add / remove / clear
        case delete          // Move to Trash / Delete Permanently
        case quit
    }

    public enum TerminationDecision: Equatable, Sendable {
        case now
        /// Answer `.terminateLater`; call `reply(toApplicationShouldTerminate: true)`
        /// once `endDeletion()` returns `.replyTerminate`.
        case later
    }

    public enum EndAction: Equatable, Sendable {
        case none
        /// A quit was requested during the deletion: reply `true` now.
        case replyTerminate
    }

    public private(set) var isScanning = false
    public private(set) var isDeleting = false
    /// Quit was requested while deleting; the deletion was asked to stop after
    /// the current top-level item.
    public private(set) var quitPending = false

    public init() {}

    public func isAllowed(_ c: Command) -> Bool {
        switch c {
        // A new scan while scanning restarts it (the old one is cancelled).
        case .scan, .rescan: return !isDeleting
        case .stopScan: return isScanning
        case .editDeletionList, .delete: return !isDeleting && !isScanning
        // Quit is ALWAYS allowed (also while deleting and while a quit is
        // already pending): a disabled Quit item makes Cmd-Q beep.
        case .quit: return true
        }
    }

    /// Returns false (and changes nothing) if a scan may not start now.
    @discardableResult
    public func beginScan() -> Bool {
        guard isAllowed(.scan) else { return false }
        isScanning = true
        return true
    }
    public func endScan() { isScanning = false }

    /// Returns false (and changes nothing) if a deletion may not start now.
    @discardableResult
    public func beginDeletion() -> Bool {
        guard isAllowed(.delete) else { return false }
        isDeleting = true
        return true
    }

    public func endDeletion() -> EndAction {
        isDeleting = false
        if quitPending { quitPending = false; return .replyTerminate }
        return .none
    }

    /// Called from `applicationShouldTerminate`. While deleting, the caller must
    /// cancel the deletion (it stops after the current top-level item, never
    /// mid-item) and answer `.terminateLater`.
    /// Menu-validation policy for an action, by command. `nil` (unknown
    /// actions such as standard Edit/Window items) is always allowed.
    public func validate(_ command: Command?) -> Bool {
        guard let command else { return true }
        return isAllowed(command)
    }

    /// What a Cmd-Q key press while the delete sheet is up should do.
    public enum QuitKeyAction: Equatable, Sendable {
        /// Pass to `NSApp.terminate(_:)` (starts the terminateLater flow).
        case terminate
        /// A quit is already pending: swallow the key (no beep, no re-entry).
        case alreadyQuitting
    }
    public func quitKeyAction() -> QuitKeyAction { quitPending ? .alreadyQuitting : .terminate }

    /// Idempotent: a second request while a quit is pending also returns
    /// `.later`, and `endDeletion()` still replies exactly once.
    public func requestTermination() -> TerminationDecision {
        guard isDeleting else { return .now }
        quitPending = true
        return .later
    }
}
