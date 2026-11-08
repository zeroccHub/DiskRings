// (AppKit shim, part 2: responders, views, controls) — see AppKit.swift header.
import Foundation
import QuartzCore

public struct NSUserInterfaceItemIdentifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ s: String) { rawValue = s }
    public init(stringLiteral s: String) { rawValue = s }
}
public struct NSAccessibilityRole: RawRepresentable, Hashable, Sendable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let button = Self(rawValue: "AXButton"), staticText = Self(rawValue: "AXStaticText"), group = Self(rawValue: "AXGroup"),
        image = Self(rawValue: "AXImage"), list = Self(rawValue: "AXList"), row = Self(rawValue: "AXRow"), progressIndicator = Self(rawValue: "AXProgressIndicator"),
        levelIndicator = Self(rawValue: "AXLevelIndicator"), unknown = Self(rawValue: "AXUnknown"), layoutArea = Self(rawValue: "AXLayoutArea"), layoutItem = Self(rawValue: "AXLayoutItem") }
public struct NSAccessibilitySubrole: RawRepresentable, Hashable, Sendable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public enum NSAccessibilityPriorityLevel: Int, Sendable { case low = 10, medium = 50, high = 90 }
public enum NSAccessibility {
    public struct Notification: RawRepresentable, Hashable, Sendable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let announcementRequested = Self(rawValue: "AXAnnouncementRequested"), layoutChanged = Self(rawValue: "AXLayoutChanged"),
            valueChanged = Self(rawValue: "AXValueChanged"), selectedChildrenChanged = Self(rawValue: "AXSelectedChildrenChanged") }
    public struct NotificationUserInfoKey: RawRepresentable, Hashable, Sendable { public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let announcement = Self(rawValue: "AXAnnouncementKey"), priority = Self(rawValue: "AXPriorityKey") }
    public typealias Role = NSAccessibilityRole
    @preconcurrency @MainActor public static func post(element: Any, notification: NSAccessibility.Notification, userInfo: [NSAccessibility.NotificationUserInfoKey: Any]?) {}
    @preconcurrency @MainActor public static func post(element: Any, notification: NSAccessibility.Notification) {}
}
@preconcurrency @MainActor open class NSAccessibilityElement: NSObject {
    @discardableResult open class func element(withRole role: NSAccessibility.Role, frame: NSRect, label: String?, parent: Any?) -> Any { NSObject() }
    open func setAccessibilityRole(_ r: NSAccessibility.Role?) {}
    open func setAccessibilityLabel(_ l: String?) {}
    open func setAccessibilityParent(_ p: Any?) {}
    open func setAccessibilityFrameInParentSpace(_ f: NSRect) {}
    open func setAccessibilityHelp(_ h: String?) {}
    open func setAccessibilityValue(_ v: Any?) {}
    open func setAccessibilityElement(_ b: Bool) {}
    open var accessibilityFrameInParentSpace: NSRect = .zero
    open func accessibilityPerformPress() -> Bool { false }
}

@preconcurrency @MainActor open class NSResponder: NSObject {
    public override init() {}
    public required init?(coder: NSCoder) {}
    open var nextResponder: NSResponder?
    open var acceptsFirstResponder: Bool { false }
    @discardableResult open func becomeFirstResponder() -> Bool { true }
    @discardableResult open func resignFirstResponder() -> Bool { true }
    open func keyDown(with event: NSEvent) {}
    open func keyUp(with event: NSEvent) {}
    open func flagsChanged(with event: NSEvent) {}
    open func mouseDown(with event: NSEvent) {}
    open func mouseUp(with event: NSEvent) {}
    open func mouseDragged(with event: NSEvent) {}
    open func mouseMoved(with event: NSEvent) {}
    open func mouseEntered(with event: NSEvent) {}
    open func mouseExited(with event: NSEvent) {}
    open func rightMouseDown(with event: NSEvent) {}
    open func otherMouseDown(with event: NSEvent) {}
    open func scrollWheel(with event: NSEvent) {}
    open func cancelOperation(_ sender: Any?) {}
    open func insertNewline(_ sender: Any?) {}
    @discardableResult open func performKeyEquivalent(with event: NSEvent) -> Bool { false }
    open func interpretKeyEvents(_ events: [NSEvent]) {}
    open func noResponder(for eventSelector: Selector) {}
    open var menu: NSMenu?
    @discardableResult open func validateProposedFirstResponder(_ r: NSResponder, for event: NSEvent?) -> Bool { true }
    @discardableResult open func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? { nil }
    open var undoManager: UndoManager? { nil }
    open func quickLookPreviewItems(_ sender: Any?) {}
    // QLPreviewPanelController (informal protocol from Quartz, category on NSObject).
    open func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { false }
    open func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {}
    open func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
    // NSAccessibility (informal, on every NSResponder subclass we use)
    open func setAccessibilityRole(_ r: NSAccessibility.Role?) {}
    open func setAccessibilityLabel(_ l: String?) {}
    open func setAccessibilityHelp(_ h: String?) {}
    open func setAccessibilityValue(_ v: Any?) {}
    open func setAccessibilityElement(_ b: Bool) {}
    open func setAccessibilityChildren(_ c: [Any]?) {}
    open func setAccessibilityIdentifier(_ i: String?) {}
    @discardableResult open func accessibilityChildren() -> [Any]? { nil }
    @discardableResult open func accessibilityLabel() -> String? { nil }
    @discardableResult open func accessibilityRole() -> NSAccessibility.Role? { nil }
    @discardableResult open func isAccessibilityElement() -> Bool { false }
}

@preconcurrency @MainActor open class NSTrackingArea: NSObject {
    public struct Options: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mouseEnteredAndExited = Options(rawValue: 1), mouseMoved = Options(rawValue: 2), cursorUpdate = Options(rawValue: 4),
            activeWhenFirstResponder = Options(rawValue: 0x10), activeInKeyWindow = Options(rawValue: 0x20), activeInActiveApp = Options(rawValue: 0x40),
            activeAlways = Options(rawValue: 0x80), assumeInside = Options(rawValue: 0x100), inVisibleRect = Options(rawValue: 0x200),
            enabledDuringMouseDrag = Options(rawValue: 0x400) }
    public init(rect: NSRect, options: NSTrackingArea.Options, owner: Any?, userInfo: [AnyHashable: Any]? = nil) {}
    open var rect: NSRect { .zero }
}
@preconcurrency @MainActor open class NSGestureRecognizer: NSObject {
    public init(target: Any?, action: Selector?) {}
    open var view: NSView? { nil }
    open var isEnabled = true
    @discardableResult open func location(in view: NSView?) -> NSPoint { .zero }
    public enum State: Int, Sendable { case possible, began, changed, ended, cancelled, failed }
    open var state: State { .possible }
}
@preconcurrency @MainActor open class NSClickGestureRecognizer: NSGestureRecognizer {
    open var numberOfClicksRequired = 1
    open var buttonMask = 1
}

public typealias NSViewToolTipTag = Int
@preconcurrency @MainActor public protocol NSViewToolTipOwner: NSObjectProtocol {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String
}

@preconcurrency @MainActor open class NSView: NSResponder {
    open var enclosingScrollView: NSScrollView? { nil }
    public typealias ToolTipTag = Int
    public enum BackgroundStyle: Int, Sendable { case normal = 0, emphasized, raised, lowered }
    public struct AutoresizingMask: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none = Self([]), minXMargin = Self(rawValue: 1), width = Self(rawValue: 2), maxXMargin = Self(rawValue: 4),
            minYMargin = Self(rawValue: 8), height = Self(rawValue: 16), maxYMargin = Self(rawValue: 32) }
    public enum LayerContentsRedrawPolicy: Int, Sendable { case never, onSetNeedsDisplay, duringViewResize, beforeViewResize, crossfade }
    public static let noIntrinsicMetric: CGFloat = -1
    public init(frame frameRect: NSRect) { super.init() }
    public convenience override init() { self.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init() }
    open var frame: NSRect = .zero
    open var bounds: NSRect = .zero
    open var isFlipped: Bool { false }
    open var isHidden = false
    open var isHiddenOrHasHiddenAncestor: Bool { false }
    open var alphaValue: CGFloat = 1
    open var wantsLayer = false
    open var layer: CALayer?
    open var wantsUpdateLayer: Bool { false }
    open var layerContentsRedrawPolicy: LayerContentsRedrawPolicy = .duringViewResize
    open var needsDisplay = false
    open var needsLayout = false
    open var toolTip: String?
    open var identifier: NSUserInterfaceItemIdentifier?
    open var superview: NSView? { nil }
    open var subviews: [NSView] = []
    open var window: NSWindow? { nil }
    open var appearance: NSAppearance?
    open var effectiveAppearance: NSAppearance { NSAppearance(named: .aqua)! }
    open var translatesAutoresizingMaskIntoConstraints = true
    open var autoresizingMask: AutoresizingMask = []
    open var autoresizesSubviews = true
    open var intrinsicContentSize: NSSize { .zero }
    open var fittingSize: NSSize { .zero }
    open var visibleRect: NSRect { .zero }
    open var trackingAreas: [NSTrackingArea] { [] }
    open var inLiveResize: Bool { false }
    open var constraints: [NSLayoutConstraint] { [] }
    open var safeAreaLayoutGuide: NSLayoutGuide { .init() }
    open var layoutMarginsGuide: NSLayoutGuide { .init() }
    open var leadingAnchor: NSLayoutXAxisAnchor { .init() }; open var trailingAnchor: NSLayoutXAxisAnchor { .init() }
    open var leftAnchor: NSLayoutXAxisAnchor { .init() }; open var rightAnchor: NSLayoutXAxisAnchor { .init() }
    open var centerXAnchor: NSLayoutXAxisAnchor { .init() }; open var centerYAnchor: NSLayoutYAxisAnchor { .init() }
    open var topAnchor: NSLayoutYAxisAnchor { .init() }; open var bottomAnchor: NSLayoutYAxisAnchor { .init() }
    open var widthAnchor: NSLayoutDimension { .init() }; open var heightAnchor: NSLayoutDimension { .init() }
    open var firstBaselineAnchor: NSLayoutYAxisAnchor { .init() }; open var lastBaselineAnchor: NSLayoutYAxisAnchor { .init() }
    open var gestureRecognizers: [NSGestureRecognizer] = []
    open func addSubview(_ view: NSView) {}
    open func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo otherView: NSView?) {}
    open func removeFromSuperview() {}
    open func addConstraint(_ c: NSLayoutConstraint) {}
    open func addConstraints(_ c: [NSLayoutConstraint]) {}
    open func removeConstraints(_ c: [NSLayoutConstraint]) {}
    open func addGestureRecognizer(_ g: NSGestureRecognizer) {}
    open func removeGestureRecognizer(_ g: NSGestureRecognizer) {}
    open func addTrackingArea(_ t: NSTrackingArea) {}
    open func removeTrackingArea(_ t: NSTrackingArea) {}
    open func updateTrackingAreas() {}
    open func setFrameSize(_ s: NSSize) {}
    open func setFrameOrigin(_ p: NSPoint) {}
    open func setNeedsDisplay(_ r: NSRect) {}
    open func display() {}
    open func draw(_ dirtyRect: NSRect) {}
    open func updateLayer() {}
    open func layout() {}
    open func layoutSubtreeIfNeeded() {}
    open func updateConstraints() {}
    open func invalidateIntrinsicContentSize() {}
    open func viewDidMoveToWindow() {}
    open func viewWillMove(toWindow w: NSWindow?) {}
    open func viewDidMoveToSuperview() {}
    open func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) {}
    open func unregisterDraggedTypes() {}
    open func setDraggingSourceOperationMask(_ mask: NSDragOperation, forLocal isLocal: Bool) {}
    @discardableResult open func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: NSDraggingSource) -> NSDraggingSession { NSDraggingSession() }
    open func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { [] }
    open func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { [] }
    open func draggingExited(_ sender: NSDraggingInfo?) {}
    @discardableResult open func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    @discardableResult open func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
    open func concludeDragOperation(_ sender: NSDraggingInfo?) {}
    open func viewDidChangeEffectiveAppearance() {}
    open func viewWillStartLiveResize() {}
    open func viewDidEndLiveResize() {}
    open func viewDidChangeBackingProperties() {}
    open func drawFocusRingMask() {}
    open var focusRingMaskBounds: NSRect { .zero }
    open func noteFocusRingMaskChanged() {}
    open var focusRingType: NSFocusRingType = .default
    open func resize(withOldSuperviewSize s: NSSize) {}
    open func resizeSubviews(withOldSize s: NSSize) {}
    @discardableResult open func hitTest(_ p: NSPoint) -> NSView? { nil }
    @discardableResult open func convert(_ p: NSPoint, from v: NSView?) -> NSPoint { p }
    @discardableResult open func convert(_ p: NSPoint, to v: NSView?) -> NSPoint { p }
    @discardableResult open func convert(_ r: NSRect, from v: NSView?) -> NSRect { r }
    @discardableResult open func convert(_ r: NSRect, to v: NSView?) -> NSRect { r }
    @discardableResult open func isMousePoint(_ p: NSPoint, in r: NSRect) -> Bool { false }
    @discardableResult open func addToolTip(_ rect: NSRect, owner: NSViewToolTipOwner, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag { 0 }
    @discardableResult open func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag { 0 }
    open func removeToolTip(_ tag: NSView.ToolTipTag) {}
    open func removeAllToolTips() {}
    open func setContentHuggingPriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    open func setContentCompressionResistancePriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    @discardableResult open func contentHuggingPriority(for o: NSLayoutConstraint.Orientation) -> NSLayoutPriority { .defaultLow }
    @discardableResult open func contentCompressionResistancePriority(for o: NSLayoutConstraint.Orientation) -> NSLayoutPriority { .defaultHigh }
    @discardableResult open func scrollToVisible(_ r: NSRect) -> Bool { false }
    @discardableResult open func menu(for event: NSEvent) -> NSMenu? { nil }
    @discardableResult open func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    @discardableResult open func viewWithTag(_ tag: Int) -> NSView? { nil }
    open var tag: Int { -1 }
    @discardableResult open func backingAlignedRect(_ r: NSRect, options: AlignmentOptions) -> NSRect { r }
    public struct AlignmentOptions: OptionSet, Sendable { public let rawValue: UInt64; public init(rawValue: UInt64) { self.rawValue = rawValue }; public static let alignAllEdgesNearest = Self(rawValue: 0xF00) }
    open func setAccessibilityFrameInParentSpace(_ f: NSRect) {}
    open func setAccessibilityParent(_ p: Any?) {}
}

@preconcurrency @MainActor open class NSControl: NSView {
    public enum ControlSize: UInt, Sendable { case regular = 0, small = 1, mini = 2, large = 3 }
    open var target: AnyObject?
    open var action: Selector?
    open var isEnabled = true
    open override var tag: Int { get { 0 } set {} }
    open var stringValue = ""
    open var attributedStringValue = NSAttributedString(string: "")
    open var integerValue = 0
    open var doubleValue = 0.0
    open var objectValue: Any?
    open var font: NSFont?
    open var alignment: NSTextAlignment = .natural
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping
    open var controlSize: ControlSize = .regular
    open var isContinuous = false
    open var usesSingleLineMode = false
    open var cell: NSCell?
    open var refusesFirstResponder = false
    open func sizeToFit() {}
    @discardableResult open func sendAction(_ action: Selector?, to target: Any?) -> Bool { false }
    open func takeStringValueFrom(_ sender: Any?) {}
    open var allowsExpansionToolTips = false
}
public enum NSLineBreakMode: UInt, Sendable { case byWordWrapping = 0, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle }
open class NSCell: NSObject {
    public typealias BackgroundStyle = NSView.BackgroundStyle
    open var alignment: NSTextAlignment = .natural
    open var font: NSFont?
    open var title = ""
    open var isEnabled = true
    open var backgroundStyle: BackgroundStyle = .normal
    open var truncatesLastVisibleLine = false
    open var wraps = false
    open var isScrollable = false
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping
}
open class NSActionCell: NSCell {}
open class NSTextFieldCell: NSActionCell {}
open class NSSearchFieldCell: NSTextFieldCell { open var placeholderString: String?; open var sendsWholeSearchString = false; open var sendsSearchStringImmediately = false }
open class NSButtonCell: NSActionCell {}
open class NSTableHeaderCell: NSTextFieldCell { open var stringValue = "" }

@preconcurrency @MainActor public protocol NSTextFieldDelegate: AnyObject {
    func controlTextDidChange(_ obj: Notification)
    func controlTextDidEndEditing(_ obj: Notification)
    func controlTextDidBeginEditing(_ obj: Notification)
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
}
extension NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {}
    public func controlTextDidEndEditing(_ obj: Notification) {}
    public func controlTextDidBeginEditing(_ obj: Notification) {}
    @discardableResult public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { false }
}
@preconcurrency @MainActor public protocol NSSearchFieldDelegate: NSTextFieldDelegate {}

@preconcurrency @MainActor open class NSTextField: NSControl {
    public convenience init(labelWithString s: String) { self.init(frame: .zero) }
    public convenience init(wrappingLabelWithString s: String) { self.init(frame: .zero) }
    public convenience init(labelWithAttributedString s: NSAttributedString) { self.init(frame: .zero) }
    public convenience init(string s: String) { self.init(frame: .zero) }
    open var textColor: NSColor?
    open var backgroundColor: NSColor?
    open var drawsBackground = false
    open var isBordered = false
    open var isBezeled = false
    open var bezelStyle: BezelStyle = .squareBezel
    public enum BezelStyle: UInt, Sendable { case squareBezel = 0, roundedBezel = 1 }
    open var isEditable = false
    open var isSelectable = false
    open var placeholderString: String?
    open var placeholderAttributedString: NSAttributedString?
    open var preferredMaxLayoutWidth: CGFloat = 0
    open var maximumNumberOfLines = 0
    open weak var delegate: NSTextFieldDelegate?
    open var allowsDefaultTighteningForTruncation = false
    @discardableResult open func currentEditor() -> NSText? { nil }
    open func selectText(_ sender: Any?) {}
}
@preconcurrency @MainActor open class NSSearchField: NSTextField {
    open var sendsSearchStringImmediately = false
    open var sendsWholeSearchString = false
    open var searchMenuTemplate: NSMenu?
    open var recentsAutosaveName: String?
}
@preconcurrency @MainActor open class NSTokenField: NSTextField {}
@preconcurrency @MainActor open class NSSecureTextField: NSTextField {}

public enum NSFocusRingType: UInt, Sendable { case `default` = 0, none = 1, exterior = 2 }
