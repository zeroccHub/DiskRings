// (AppKit shim, part 4: windows, menus, toolbar, app, events, panels) — see AppKit.swift header.
import Foundation
import QuartzCore

@preconcurrency @MainActor open class NSText: NSView {
    open var string = ""
    open var font: NSFont?
    open var textColor: NSColor?
    open var isEditable = true
    open var isSelectable = true
    open var drawsBackground = true
    open var backgroundColor: NSColor = .clear
    open var alignment: NSTextAlignment = .natural
    open func selectAll(_ sender: Any?) {}
    open func copy(_ sender: Any?) {}
    open func paste(_ sender: Any?) {}
    open func cut(_ sender: Any?) {}
    open func delete(_ sender: Any?) {}
    open var selectedRange: NSRange = NSRange()
}
@preconcurrency @MainActor open class NSTextView: NSText {
    open var textContainerInset: NSSize = .zero
    open var isRichText = true
    open func insertText(_ s: Any, replacementRange r: NSRange) {}
}
open class NSTextAttachment: NSObject {
    public override init() {}
    public init(data: Data?, ofType uti: String?) {}
    open var image: NSImage?
    open var bounds: CGRect = .zero
}

public struct NSUnderlineStyle: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = Self(rawValue: 1), thick = Self(rawValue: 2), double = Self(rawValue: 9) }
open class NSParagraphStyle: NSObject, @unchecked Sendable {
    open class var `default`: NSParagraphStyle { .init() }
    open var alignment: NSTextAlignment { .natural }
    open var lineBreakMode: NSLineBreakMode { .byWordWrapping }
    open override func mutableCopy() -> Any { NSMutableParagraphStyle() }
}
open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    open override var alignment: NSTextAlignment { get { .natural } set {} }
    open override var lineBreakMode: NSLineBreakMode { get { .byWordWrapping } set {} }
    open var lineSpacing: CGFloat = 0
    open var paragraphSpacing: CGFloat = 0
    open var paragraphSpacingBefore: CGFloat = 0
    open var headIndent: CGFloat = 0
    open var firstLineHeadIndent: CGFloat = 0
    open var minimumLineHeight: CGFloat = 0
    open var maximumLineHeight: CGFloat = 0
    open var lineHeightMultiple: CGFloat = 0
    open var tabStops: [NSTextTab] = []
}
open class NSTextTab: NSObject { public init(textAlignment: NSTextAlignment, location: CGFloat, options: [String: Any] = [:]) {} }
extension NSAttributedString.Key {
    public static let font = Self(rawValue: "NSFont"), foregroundColor = Self(rawValue: "NSColor"), backgroundColor = Self(rawValue: "NSBackgroundColor"),
        paragraphStyle = Self(rawValue: "NSParagraphStyle"), underlineStyle = Self(rawValue: "NSUnderline"), strikethroughStyle = Self(rawValue: "NSStrikethrough"),
        kern = Self(rawValue: "NSKern"), baselineOffset = Self(rawValue: "NSBaselineOffset"), attachment = Self(rawValue: "NSAttachment"),
        link = Self(rawValue: "NSLink"), toolTip = Self(rawValue: "NSToolTip"), cursor = Self(rawValue: "NSCursor"),
        underlineColor = Self(rawValue: "NSUnderlineColor"), strikethroughColor = Self(rawValue: "NSStrikethroughColor"), obliqueness = Self(rawValue: "NSObliqueness")
}
extension NSAttributedString {
    public convenience init(attachment: NSTextAttachment) { self.init(string: "") }
    @discardableResult public func size() -> NSSize { .zero }
    @discardableResult public func boundingRect(with size: NSSize, options: NSString.DrawingOptions_ = [], context: Any? = nil) -> NSRect { .zero }
    @preconcurrency @MainActor public func draw(at p: NSPoint) {}
    @preconcurrency @MainActor public func draw(in r: NSRect) {}
}
extension NSString {
    public struct DrawingOptions_: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let usesLineFragmentOrigin = Self(rawValue: 1), usesFontLeading = Self(rawValue: 2) }
    @discardableResult public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize { .zero }
    @preconcurrency @MainActor public func draw(at p: NSPoint, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {}
    @preconcurrency @MainActor public func draw(in r: NSRect, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {}
}
extension String {
    @discardableResult public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize { .zero }
}

// MARK: events
@preconcurrency @MainActor open class NSEvent: NSObject {
    public struct ModifierFlags: OptionSet, Hashable, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let capsLock = Self(rawValue: 1 << 16), shift = Self(rawValue: 1 << 17), control = Self(rawValue: 1 << 18),
            option = Self(rawValue: 1 << 19), command = Self(rawValue: 1 << 20), numericPad = Self(rawValue: 1 << 21),
            help = Self(rawValue: 1 << 22), function = Self(rawValue: 1 << 23), deviceIndependentFlagsMask = Self(rawValue: 0xffff0000) }
    public enum EventType: UInt, Sendable { case leftMouseDown = 1, leftMouseUp, rightMouseDown, rightMouseUp, mouseMoved, leftMouseDragged,
        rightMouseDragged, mouseEntered, mouseExited, keyDown, keyUp, flagsChanged, appKitDefined, systemDefined, applicationDefined, periodic, cursorUpdate,
        scrollWheel = 22, otherMouseDown = 25 }
    public struct EventTypeMask: OptionSet, Sendable { public let rawValue: UInt64; public init(rawValue: UInt64) { self.rawValue = rawValue }
        public static let keyDown = Self(rawValue: 1 << 10), keyUp = Self(rawValue: 1 << 11), flagsChanged = Self(rawValue: 1 << 12),
            leftMouseDown = Self(rawValue: 1 << 1), mouseMoved = Self(rawValue: 1 << 5) }
    public enum SpecialKey: Hashable, Sendable {
        case upArrow, downArrow, leftArrow, rightArrow, delete, deleteForward, carriageReturn, enter, tab, backTab, home, end, pageUp, pageDown, escape_
        public var unicodeScalar: Unicode.Scalar { "a" }
        public init(rawValue: Int) { self = .upArrow }
        public var rawValue: Int { 0 }
    }
    open var type: EventType { .keyDown }
    open var modifierFlags: ModifierFlags { [] }
    open var keyCode: UInt16 { 0 }
    open var characters: String? { nil }
    open var charactersIgnoringModifiers: String? { nil }
    open var specialKey: SpecialKey? { nil }
    open var isARepeat: Bool { false }
    open var locationInWindow: NSPoint { .zero }
    open var clickCount: Int { 1 }
    open var window: NSWindow? { nil }
    open var timestamp: TimeInterval { 0 }
    open var scrollingDeltaY: CGFloat { 0 }
    open var buttonNumber: Int { 0 }
    open class var modifierFlags: ModifierFlags { [] }
    open class var mouseLocation: NSPoint { .zero }
    @discardableResult open class func addLocalMonitorForEvents(matching mask: EventTypeMask, handler block: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    open class func removeMonitor(_ m: Any) {}
}

// MARK: windows
@preconcurrency @MainActor public protocol NSWindowDelegate: NSObjectProtocol {
    func windowShouldClose(_ sender: NSWindow) -> Bool
    func windowWillClose(_ notification: Notification)
    func windowDidBecomeKey(_ notification: Notification)
    func windowDidResignKey(_ notification: Notification)
    func windowDidResize(_ notification: Notification)
    func windowDidEndLiveResize(_ notification: Notification)
    func windowWillStartLiveResize(_ notification: Notification)
    func windowDidChangeOcclusionState(_ notification: Notification)
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager?
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect
}
extension NSWindowDelegate {
    @discardableResult public func windowShouldClose(_ sender: NSWindow) -> Bool { true }
    public func windowWillClose(_ notification: Notification) {}
    public func windowDidBecomeKey(_ notification: Notification) {}
    public func windowDidResignKey(_ notification: Notification) {}
    public func windowDidResize(_ notification: Notification) {}
    public func windowDidEndLiveResize(_ notification: Notification) {}
    public func windowWillStartLiveResize(_ notification: Notification) {}
    public func windowDidChangeOcclusionState(_ notification: Notification) {}
    @discardableResult public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { nil }
    @discardableResult public func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect { rect }
}
extension NSWindow {
    public struct StyleMask: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let borderless = Self([]), titled = Self(rawValue: 1), closable = Self(rawValue: 2), miniaturizable = Self(rawValue: 4),
            resizable = Self(rawValue: 8), utilityWindow = Self(rawValue: 16), docModalWindow = Self(rawValue: 64), nonactivatingPanel = Self(rawValue: 128),
            unifiedTitleAndToolbar = Self(rawValue: 4096), hudWindow = Self(rawValue: 8192), fullScreen = Self(rawValue: 16384), fullSizeContentView = Self(rawValue: 32768) }
    public enum BackingStoreType: UInt, Sendable { case retained = 0, nonretained = 1, buffered = 2 }
    public enum OrderingMode: Int, Sendable { case below = -1, out = 0, above = 1 }
    public enum TitleVisibility: Int, Sendable { case visible = 0, hidden = 1 }
    public enum ToolbarStyle: Int, Sendable { case automatic, expanded, preference, unified, unifiedCompact }
    public struct CollectionBehavior: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let fullScreenPrimary = Self(rawValue: 128) }
    public typealias FrameAutosaveName = String
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
    public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
    public static let willCloseNotification = Notification.Name("NSWindowWillCloseNotification")
    public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
    public static let didEndLiveResizeNotification = Notification.Name("NSWindowDidEndLiveResizeNotification")
    public static let didChangeBackingPropertiesNotification = Notification.Name("NSWindowDidChangeBackingPropertiesNotification")
    public struct Level: RawRepresentable, Hashable, Sendable { public var rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ r: Int) { rawValue = r }
        public static let normal = Self(0), floating = Self(3), modalPanel = Self(8) }
}
@preconcurrency @MainActor open class NSWindow: NSResponder {
    public init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    public convenience init(contentViewController: NSViewController) { self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false) }
    open var contentView: NSView?
    open var contentViewController: NSViewController?
    open weak var delegate: NSWindowDelegate?
    open var title = ""
    open var subtitle = ""
    open var titleVisibility: TitleVisibility = .visible
    open var titlebarAppearsTransparent = false
    open var toolbar: NSToolbar?
    open var toolbarStyle: ToolbarStyle = .automatic
    open var styleMask: StyleMask = []
    open var frame: NSRect { .zero }
    open var contentLayoutRect: NSRect { .zero }
    open var minSize: NSSize = .zero
    open var maxSize: NSSize = .zero
    open var contentMinSize: NSSize = .zero
    open var isVisible: Bool { false }
    open var isKeyWindow: Bool { false }
    open var canBecomeKey: Bool { true }
    open var canBecomeMain: Bool { true }
    open var isMainWindow: Bool { false }
    open var isReleasedWhenClosed = true
    open var isMovableByWindowBackground = false
    open var backgroundColor: NSColor! = .clear
    open var appearance: NSAppearance?
    open var effectiveAppearance: NSAppearance { NSAppearance(named: .aqua)! }
    open var backingScaleFactor: CGFloat { 2 }
    open var firstResponder: NSResponder? { nil }
    open var attachedSheet: NSWindow? { nil }
    open var sheetParent: NSWindow? { nil }
    open var sheets: [NSWindow] { [] }
    open var isSheet: Bool { false }
    open var defaultButtonCell: NSButtonCell?
    open var initialFirstResponder: NSView?
    open var level: Level = .normal
    open var collectionBehavior: CollectionBehavior = []
    open var tabbingMode: TabbingMode = .automatic
    public enum TabbingMode: Int, Sendable { case automatic, preferred, disallowed }
    open var windowController: NSWindowController? { nil }
    open var inLiveResize: Bool { false }
    open func makeKeyAndOrderFront(_ sender: Any?) {}
    open func orderFront(_ sender: Any?) {}
    open func orderOut(_ sender: Any?) {}
    open func close() {}
    open func performClose(_ sender: Any?) {}
    open func performMiniaturize(_ sender: Any?) {}
    open func performZoom(_ sender: Any?) {}
    open func miniaturize(_ sender: Any?) {}
    open func zoom(_ sender: Any?) {}
    open func center() {}
    @discardableResult open func makeFirstResponder(_ r: NSResponder?) -> Bool { true }
    open func setContentSize(_ s: NSSize) {}
    open func setFrame(_ f: NSRect, display: Bool) {}
    open func setFrame(_ f: NSRect, display: Bool, animate: Bool) {}
    @discardableResult open func setFrameAutosaveName(_ n: NSWindow.FrameAutosaveName) -> Bool { true }
    @discardableResult open func setFrameUsingName(_ n: NSWindow.FrameAutosaveName) -> Bool { true }
    open func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {}
    open func beginCriticalSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {}
    open func endSheet(_ sheetWindow: NSWindow) {}
    open func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {}
    @discardableResult open func standardWindowButton(_ b: ButtonType) -> NSButton? { nil }
    public enum ButtonType: UInt, Sendable { case closeButton, miniaturizeButton, zoomButton, toolbarButton, documentIconButton, documentVersionsButton }
    @discardableResult open func convertPoint(toScreen p: NSPoint) -> NSPoint { p }
    @discardableResult open func convertToScreen(_ r: NSRect) -> NSRect { r }
    open func invalidateCursorRects(for v: NSView) {}
    open func update() {}
    open func display() {}
    open func sendEvent(_ e: NSEvent) {}
    open func makeKey() {}
}
@preconcurrency @MainActor open class NSPanel: NSWindow {}
@preconcurrency @MainActor open class NSViewController: NSResponder {
    public init(nibName: String?, bundle: Bundle?) { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open var view: NSView = .init()
    open var title: String?
    open var preferredContentSize: NSSize = .zero
    open func loadView() {}
    open func viewDidLoad() {}
    open func viewWillAppear() {}
    open func viewDidAppear() {}
    open func viewWillDisappear() {}
    open func presentAsSheet(_ vc: NSViewController) {}
    open func dismiss(_ sender: Any?) {}
}
@preconcurrency @MainActor open class NSWindowController: NSResponder {
    public init(window: NSWindow?) { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open var window: NSWindow?
    open var contentViewController: NSViewController?
    open func showWindow(_ sender: Any?) {}
    open func close() {}
    open func windowDidLoad() {}
    open var windowFrameAutosaveName: NSWindow.FrameAutosaveName = ""
}

// MARK: menus
@preconcurrency @MainActor open class NSMenu: NSObject {
    public init(title: String) { super.init() }
    public override init() { super.init() }
    open var title = ""
    open var items: [NSMenuItem] = []
    open var numberOfItems: Int { 0 }
    open var autoenablesItems = true
    open weak var delegate: NSMenuDelegate?
    open var supermenu: NSMenu? { nil }
    open func addItem(_ i: NSMenuItem) {}
    @discardableResult open func addItem(withTitle t: String, action: Selector?, keyEquivalent: String) -> NSMenuItem { .init() }
    open func insertItem(_ i: NSMenuItem, at idx: Int) {}
    open func removeItem(_ i: NSMenuItem) {}
    open func removeItem(at i: Int) {}
    open func removeAllItems() {}
    @discardableResult open func item(at i: Int) -> NSMenuItem? { nil }
    @discardableResult open func item(withTag t: Int) -> NSMenuItem? { nil }
    @discardableResult open func item(withTitle t: String) -> NSMenuItem? { nil }
    @discardableResult open func index(of i: NSMenuItem) -> Int { -1 }
    open func update() {}
    @discardableResult open func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool { false }
    open class func popUpContextMenu(_ menu: NSMenu, with event: NSEvent, for view: NSView) {}
    @discardableResult open func performKeyEquivalent(with event: NSEvent) -> Bool { false }
    open func cancelTracking() {}
}
@preconcurrency @MainActor public protocol NSMenuDelegate: NSObjectProtocol {
    func menuNeedsUpdate(_ menu: NSMenu)
    func menuWillOpen(_ menu: NSMenu)
    func menuDidClose(_ menu: NSMenu)
}
extension NSMenuDelegate { public func menuNeedsUpdate(_ menu: NSMenu) {}; public func menuWillOpen(_ menu: NSMenu) {}; public func menuDidClose(_ menu: NSMenu) {} }
@preconcurrency @MainActor open class NSMenuItem: NSObject {
    public init(title string: String, action selector: Selector?, keyEquivalent charCode: String) { super.init() }
    public override init() { super.init() }
    @discardableResult open class func separator() -> NSMenuItem { .init() }
    open var title = ""
    open var attributedTitle: NSAttributedString?
    open var action: Selector?
    open weak var target: AnyObject?
    open var keyEquivalent = ""
    open var keyEquivalentModifierMask: NSEvent.ModifierFlags = [.command]
    open var isEnabled = true
    open var isHidden = false
    open var isAlternate = false
    open var state: NSControl.StateValue = .off
    open var tag = 0
    open var image: NSImage?
    open var submenu: NSMenu?
    open var menu: NSMenu? { nil }
    open var representedObject: Any?
    open var toolTip: String?
    open var indentationLevel = 0
    open var isSeparatorItem: Bool { false }
    open var view: NSView?
    open var allowsKeyEquivalentWhenHidden = false
    @available(*, deprecated, message: "macOS 14+") public class func sectionHeader(title: String) -> NSMenuItem { .init() }
}
@preconcurrency @MainActor public protocol NSMenuItemValidation: NSObjectProtocol {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
}
public protocol NSUserInterfaceValidations_ {}
@preconcurrency @MainActor public protocol NSValidatedUserInterfaceItem { var action: Selector? { get }; var tag: Int { get } }
@preconcurrency @MainActor public protocol NSToolbarItemValidation: NSObjectProtocol { func validateToolbarItem(_ item: NSToolbarItem) -> Bool }
