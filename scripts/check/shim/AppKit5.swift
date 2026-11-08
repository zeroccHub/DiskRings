// (AppKit shim, part 5: toolbar, application, alerts, panels, workspace) — see AppKit.swift header.
import Foundation
import QuartzCore
import UniformTypeIdentifiers

@preconcurrency @MainActor open class NSToolbarItem: NSObject {
    public struct Identifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ s: String) { rawValue = s }
        public init(stringLiteral s: String) { rawValue = s }
        public static let flexibleSpace = Self("NSToolbarFlexibleSpaceItem"), space = Self("NSToolbarSpaceItem"),
            toggleSidebar = Self("NSToolbarToggleSidebarItem"), sidebarTrackingSeparator = Self("NSToolbarSidebarTrackingSeparatorItemIdentifier")
    }
    public struct VisibilityPriority: RawRepresentable, Hashable, Sendable { public var rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let standard = Self(rawValue: 0), low = Self(rawValue: -1000), high = Self(rawValue: 1000), user = Self(rawValue: 2000) }
    public init(itemIdentifier: NSToolbarItem.Identifier) { super.init() }
    open var itemIdentifier: NSToolbarItem.Identifier { .init("") }
    open var label = ""
    open var paletteLabel = ""
    open var toolTip: String?
    open var image: NSImage?
    open var view: NSView?
    open var target: AnyObject?
    open var action: Selector?
    open var isEnabled = true
    open var isBordered = false
    open var isNavigational = false
    open var tag = 0
    open var menuFormRepresentation: NSMenuItem?
    open var visibilityPriority: VisibilityPriority = .standard
    open var autovalidates = true
    @available(*, deprecated, message: "deprecated in macOS 12 SDK; set constraints on the view") open var minSize: NSSize { get { .zero } set {} }
    @available(*, deprecated, message: "deprecated in macOS 12 SDK; set constraints on the view") open var maxSize: NSSize { get { .zero } set {} }
}
@preconcurrency @MainActor open class NSSearchToolbarItem: NSToolbarItem {
    open var searchField: NSSearchField = .init()
    open var preferredWidthForSearchField: CGFloat = 0
    open var resignsFirstResponderWithCancel = true
}
@preconcurrency @MainActor open class NSTrackingSeparatorToolbarItem: NSToolbarItem {}
@preconcurrency @MainActor open class NSToolbarItemGroup: NSToolbarItem {
    public enum SelectionMode: Int, Sendable { case selectOne, selectAny, momentary }
    public enum ControlRepresentation: Int, Sendable { case automatic, expanded, collapsed }
    public convenience init(itemIdentifier: NSToolbarItem.Identifier, titles: [String], selectionMode: SelectionMode, labels: [String]?, target: Any?, action: Selector?) { self.init(itemIdentifier: itemIdentifier) }
    public convenience init(itemIdentifier: NSToolbarItem.Identifier, images: [NSImage], selectionMode: SelectionMode, labels: [String]?, target: Any?, action: Selector?) { self.init(itemIdentifier: itemIdentifier) }
    open var subitems: [NSToolbarItem] = []
    open var controlRepresentation: ControlRepresentation = .automatic
    open var selectedIndex = -1
    open func setSelected(_ s: Bool, at i: Int) {}
    @discardableResult open func isSelected(at i: Int) -> Bool { false }
}
@preconcurrency @MainActor open class NSToolbar: NSObject {
    public typealias Identifier = String
    public enum DisplayMode: UInt, Sendable { case `default` = 0, iconAndLabel, iconOnly, labelOnly }
    public init(identifier: NSToolbar.Identifier) { super.init() }
    open weak var delegate: NSToolbarDelegate?
    open var displayMode: DisplayMode = .default
    open var allowsUserCustomization = false
    open var autosavesConfiguration = false
    open var showsBaselineSeparator = true
    open var isVisible = true
    open var items: [NSToolbarItem] { [] }
    open var visibleItems: [NSToolbarItem]? { nil }
    open var centeredItemIdentifier: NSToolbarItem.Identifier?
    open func validateVisibleItems() {}
    open func insertItem(withItemIdentifier i: NSToolbarItem.Identifier, at idx: Int) {}
    open func removeItem(at i: Int) {}
}
@preconcurrency @MainActor public protocol NSToolbarDelegate: NSObjectProtocol {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem?
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbarWillAddItem(_ notification: Notification)
    func toolbarDidRemoveItem(_ notification: Notification)
}
extension NSToolbarDelegate {
    @discardableResult public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier i: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }
    @discardableResult public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    @discardableResult public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    @discardableResult public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    public func toolbarWillAddItem(_ notification: Notification) {}
    public func toolbarDidRemoveItem(_ notification: Notification) {}
}

// MARK: application
@preconcurrency @MainActor public var NSApp: NSApplication! = nil
@preconcurrency @MainActor open class NSApplication: NSResponder {
    public enum ActivationPolicy: Int, Sendable { case regular = 0, accessory, prohibited }
    public enum TerminateReply: UInt, Sendable { case terminateCancel = 0, terminateNow = 1, terminateLater = 2 }
    public struct ModalResponse: RawRepresentable, Hashable, Sendable { public var rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ r: Int) { rawValue = r }
        public static let OK = Self(1), cancel = Self(0), stop = Self(-1000), abort = Self(-1001), `continue` = Self(-1002),
            alertFirstButtonReturn = Self(1000), alertSecondButtonReturn = Self(1001), alertThirdButtonReturn = Self(1002) }
    public static let didBecomeActiveNotification = Notification.Name("NSApplicationDidBecomeActiveNotification")
    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
    public static let didChangeScreenParametersNotification = Notification.Name("NSApplicationDidChangeScreenParametersNotification")
    open class var shared: NSApplication { .init() }
    open weak var delegate: NSApplicationDelegate?
    open var mainMenu: NSMenu?
    open var windowsMenu: NSMenu?
    open var servicesMenu: NSMenu?
    open var helpMenu: NSMenu?
    open var appearance: NSAppearance?
    open var effectiveAppearance: NSAppearance { NSAppearance(named: .aqua)! }
    open var keyWindow: NSWindow? { nil }
    open var mainWindow: NSWindow? { nil }
    open var windows: [NSWindow] { [] }
    open var modalWindow: NSWindow? { nil }
    open var currentEvent: NSEvent? { nil }
    open var isActive: Bool { false }
    open var applicationIconImage: NSImage!
    open func run() {}
    open func stop(_ sender: Any?) {}
    open func terminate(_ sender: Any?) {}
    open func reply(toApplicationShouldTerminate shouldTerminate: Bool) {}
    open func activate(ignoringOtherApps flag: Bool) {}
    @available(*, deprecated, message: "macOS 14+") open func activate() {}
    open func hide(_ sender: Any?) {}
    open func hideOtherApplications(_ sender: Any?) {}
    open func unhideAllApplications(_ sender: Any?) {}
    open func orderFrontStandardAboutPanel(_ sender: Any?) {}
    open func orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey: Any] = [:]) {}
    public struct AboutPanelOptionKey: RawRepresentable, Hashable, Sendable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let applicationName = Self(rawValue: "ApplicationName"), applicationVersion = Self(rawValue: "ApplicationVersion"), credits = Self(rawValue: "Credits"), version = Self(rawValue: "Version") }
    @discardableResult open func setActivationPolicy(_ p: ActivationPolicy) -> Bool { true }
    @discardableResult open func runModal(for w: NSWindow) -> ModalResponse { .OK }
    open func stopModal() {}
    open func stopModal(withCode c: ModalResponse) {}
    open func abortModal() {}
    @discardableResult open func sendAction(_ a: Selector, to t: Any?, from s: Any?) -> Bool { false }
    @discardableResult open func target(forAction a: Selector) -> Any? { nil }
    @discardableResult open func requestUserAttention(_ t: RequestUserAttentionType) -> Int { 0 }
    public enum RequestUserAttentionType: UInt, Sendable { case criticalRequest = 0, informationalRequest = 10 }
    open func postEvent(_ e: NSEvent, atStart: Bool) {}
    @discardableResult open func nextEvent(matching m: NSEvent.EventTypeMask, until d: Date?, inMode mode: RunLoop.Mode, dequeue: Bool) -> NSEvent? { nil }
    open func updateWindows() {}
}
@preconcurrency @MainActor public protocol NSApplicationDelegate: NSObjectProtocol {
    func applicationWillFinishLaunching(_ notification: Notification)
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    func applicationWillTerminate(_ notification: Notification)
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool
    func applicationDidBecomeActive(_ notification: Notification)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
    func application(_ application: NSApplication, open urls: [URL])
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu?
}
extension NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {}
    public func applicationDidFinishLaunching(_ notification: Notification) {}
    @discardableResult public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
    @discardableResult public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func applicationWillTerminate(_ notification: Notification) {}
    @discardableResult public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
    public func applicationDidBecomeActive(_ notification: Notification) {}
    @discardableResult public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
    public func application(_ application: NSApplication, open urls: [URL]) {}
    @discardableResult public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { nil }
}
public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 { 0 }

@preconcurrency @MainActor open class NSAlert: NSObject {
    public enum Style: UInt, Sendable { case warning = 0, informational = 1, critical = 2 }
    public override init() { super.init() }
    public convenience init(error: Error) { self.init() }
    open var messageText = ""
    open var informativeText = ""
    open var alertStyle: Style = .warning
    open var icon: NSImage!
    open var buttons: [NSButton] { [] }
    open var showsSuppressionButton = false
    open var suppressionButton: NSButton? { nil }
    open var accessoryView: NSView?
    open var window: NSWindow { .init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false) }
    open var showsHelp = false
    @discardableResult open func addButton(withTitle title: String) -> NSButton { .init() }
    @discardableResult open func runModal() -> NSApplication.ModalResponse { .OK }
    open func beginSheetModal(for sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {}
    open func layout() {}
}
@preconcurrency @MainActor open class NSSavePanel: NSPanel {
    open var directoryURL: URL?
    open var message: String?
    open var prompt: String!
    open var nameFieldStringValue = ""
    open var canCreateDirectories = true
    open var showsHiddenFiles = false
    open var treatsFilePackagesAsDirectories = false
    open var url: URL? { nil }
    @discardableResult open func runModal() -> NSApplication.ModalResponse { .OK }
    open func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {}
    open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {}
}
@preconcurrency @MainActor open class NSOpenPanel: NSSavePanel {
    public convenience init() { self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false) }
    open var canChooseFiles = true
    open var canChooseDirectories = false
    open var allowsMultipleSelection = false
    open var resolvesAliases = true
    open var urls: [URL] { [] }
}
open class NSWorkspace: NSObject, @unchecked Sendable {
    open class var shared: NSWorkspace { .init() }
    open var notificationCenter: NotificationCenter { .default }
    public static let didMountNotification = Notification.Name("NSWorkspaceDidMountNotification")
    public static let didUnmountNotification = Notification.Name("NSWorkspaceDidUnmountNotification")
    public static let didRenameVolumeNotification = Notification.Name("NSWorkspaceDidRenameVolumeNotification")
    public static let willUnmountNotification = Notification.Name("NSWorkspaceWillUnmountNotification")
    public static let volumeURLKey = "NSWorkspaceVolumeURLKey"
    @discardableResult open func open(_ url: URL) -> Bool { true }
    open func activateFileViewerSelecting(_ urls: [URL]) {}
    @discardableResult open func selectFile(_ p: String?, inFileViewerRootedAtPath r: String) -> Bool { true }
    @discardableResult open func icon(forFile path: String) -> NSImage { .init() }
    @discardableResult open func icon(for contentType: UTType) -> NSImage { .init() }   // macOS 11+
    open func recycle(_ urls: [URL], completionHandler: (([URL: URL], Error?) -> Void)? = nil) {}
    @discardableResult open func urlForApplication(withBundleIdentifier id: String) -> URL? { nil }
    @discardableResult open func isFilePackage(atPath p: String) -> Bool { false }
    open var runningApplications: [AnyObject] { [] }
}
open class NSSound: NSObject, @unchecked Sendable {
    public typealias Name = String
    public init?(named name: NSSound.Name) {}
    public init?(contentsOf url: URL, byReference: Bool) {}
    @discardableResult open func play() -> Bool { true }
    @discardableResult open func stop() -> Bool { true }
    open var volume: Float = 1
}
extension NSSound { public class func beep() {} }  // Swift name of NSBeep()
open class NSScreen: NSObject, @unchecked Sendable {
    open class var main: NSScreen? { nil }
    open class var screens: [NSScreen] { [] }
    open var frame: NSRect { .zero }
    open var visibleFrame: NSRect { .zero }
    open var backingScaleFactor: CGFloat { 2 }
}
@preconcurrency @MainActor open class NSCursor: NSObject {
    open class var arrow: NSCursor { .init() }
    open class var pointingHand: NSCursor { .init() }
    open func set() {}
    open func push() {}; open func pop() {}
}

// MARK: Quick Look (really in Quartz.framework; see Quartz.swift)


public protocol QLPreviewItem: NSObjectProtocol {
    var previewItemURL: URL! { get }
    var previewItemTitle: String! { get }
}
extension QLPreviewItem { public var previewItemTitle: String! { nil } }
extension NSURL: QLPreviewItem { public var previewItemURL: URL! { self as URL } }
@preconcurrency @MainActor public protocol QLPreviewPanelDataSource: NSObjectProtocol {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem!
}
@preconcurrency @MainActor public protocol QLPreviewPanelDelegate: NSObjectProtocol {
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect
}
extension QLPreviewPanelDelegate {
    @discardableResult public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool { false }
    @discardableResult public func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect { .zero }
}
@preconcurrency @MainActor open class QLPreviewPanel: NSPanel {
    @discardableResult open class func shared() -> QLPreviewPanel! { nil }
    @discardableResult open class func sharedPreviewPanelExists() -> Bool { false }
    open weak var dataSource: QLPreviewPanelDataSource?
    open weak var delegate_: QLPreviewPanelDelegate?
    open var currentPreviewItemIndex = 0
    open var currentController: Any? { nil }
    open func reloadData() {}
    open func refreshCurrentPreviewItem() {}
    open func updateController() {}
}


