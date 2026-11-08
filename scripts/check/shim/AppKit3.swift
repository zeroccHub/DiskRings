// (AppKit shim, part 3: controls, containers, tables) — see AppKit.swift header.
import Foundation
import QuartzCore

public enum NSTextAlignment: Int, Sendable { case left = 0, right = 1, center = 2, justified = 3, natural = 4 }
public enum NSImagePosition: UInt, Sendable { case noImage = 0, imageOnly, imageLeft, imageRight, imageBelow, imageAbove, imageOverlaps, imageLeading, imageTrailing }
public enum NSImageScaling: UInt, Sendable { case scaleProportionallyDown = 0, scaleAxesIndependently, scaleNone, scaleProportionallyUpOrDown }
public enum NSImageAlignment: UInt, Sendable { case alignCenter = 0, alignTop, alignTopLeft, alignTopRight, alignLeft, alignBottom, alignBottomLeft, alignBottomRight, alignRight }

@preconcurrency @MainActor open class NSButton: NSControl {
    public enum BezelStyle: UInt, Sendable {
        case rounded = 1, regularSquare = 2, disclosure = 5, shadowlessSquare = 6, circular = 7, texturedSquare = 8,
             helpButton = 9, smallSquare = 10, texturedRounded = 11, roundRect = 12, recessed = 13, roundedDisclosure = 14, inline = 15
        @available(*, deprecated, message: "macOS 14+ name; use .rounded on macOS 12") public static var push: BezelStyle { .rounded }
        @available(*, deprecated, message: "macOS 14+ name") public static var accessoryBarAction: BezelStyle { .recessed }
    }
    public enum ButtonType: UInt, Sendable { case momentaryLight = 0, pushOnPushOff, toggle, `switch`, radio, momentaryChange, onOff, momentaryPushIn, accelerator, multiLevelAccelerator }
    public convenience init(title: String, target: Any?, action: Selector?) { self.init(frame: .zero) }
    public convenience init(image: NSImage, target: Any?, action: Selector?) { self.init(frame: .zero) }
    public convenience init(title: String, image: NSImage, target: Any?, action: Selector?) { self.init(frame: .zero) }
    public convenience init(checkboxWithTitle title: String, target: Any?, action: Selector?) { self.init(frame: .zero) }
    public convenience init(radioButtonWithTitle title: String, target: Any?, action: Selector?) { self.init(frame: .zero) }
    open var title = ""
    open var attributedTitle = NSAttributedString(string: "")
    open var alternateTitle = ""
    open var image: NSImage?
    open var alternateImage: NSImage?
    open var imagePosition: NSImagePosition = .noImage
    open var imageScaling: NSImageScaling = .scaleProportionallyDown
    open var imageHugsTitle = false
    open var bezelStyle: BezelStyle = .rounded
    open var bezelColor: NSColor?
    open var contentTintColor: NSColor?
    open var isBordered = true
    open var isTransparent = false
    open var showsBorderOnlyWhileMouseInside = false
    open var keyEquivalent = ""
    open var keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    open var state: NSControl.StateValue = .off
    open var allowsMixedState = false
    open var hasDestructiveAction = false
    open func setButtonType(_ t: ButtonType) {}
    open func performClick(_ sender: Any?) {}
}
extension NSControl {
    public struct StateValue: RawRepresentable, Hashable, Sendable { public var rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let on = Self(rawValue: 1), off = Self(rawValue: 0), mixed = Self(rawValue: -1) }
}
@preconcurrency @MainActor open class NSImageView: NSControl {
    public convenience init(image: NSImage) { self.init(frame: .zero) }
    open var image: NSImage?
    open var imageScaling: NSImageScaling = .scaleProportionallyDown
    open var imageAlignment: NSImageAlignment = .alignCenter
    open var contentTintColor: NSColor?
    open var symbolConfiguration: NSImage.SymbolConfiguration?
    open var isEditable = false
}
@preconcurrency @MainActor open class NSProgressIndicator: NSView {
    public enum Style: UInt, Sendable { case bar = 0, spinning = 1 }
    open var style: Style = .bar
    open var isIndeterminate = true
    open var doubleValue = 0.0
    open var minValue = 0.0
    open var maxValue = 100.0
    open var controlSize: NSControl.ControlSize = .regular
    open var isDisplayedWhenStopped = true
    open func startAnimation(_ sender: Any?) {}
    open func stopAnimation(_ sender: Any?) {}
    open func increment(by d: Double) {}
}
@preconcurrency @MainActor open class NSSegmentedControl: NSControl {
    public enum Style: Int, Sendable { case automatic = 0, rounded, roundRect, texturedRounded, capsule, smallSquare, separated, texturedSquare }
    public enum SwitchTracking: UInt, Sendable { case selectOne = 0, selectAny, momentary, momentaryAccelerator }
    public convenience init(labels: [String], trackingMode: SwitchTracking, target: Any?, action: Selector?) { self.init(frame: .zero) }
    public convenience init(images: [NSImage], trackingMode: SwitchTracking, target: Any?, action: Selector?) { self.init(frame: .zero) }
    open var segmentCount = 0
    open var selectedSegment = -1
    open var segmentStyle: Style = .automatic
    open var trackingMode: SwitchTracking = .selectOne
    open func setLabel(_ l: String, forSegment s: Int) {}
    open func setImage(_ i: NSImage?, forSegment s: Int) {}
    open func setEnabled(_ e: Bool, forSegment s: Int) {}
    open func setToolTip(_ t: String?, forSegment s: Int) {}
    open func setWidth(_ w: CGFloat, forSegment s: Int) {}
    open func setSelected(_ b: Bool, forSegment s: Int) {}
    @discardableResult open func isSelected(forSegment s: Int) -> Bool { false }
    @discardableResult open func label(forSegment s: Int) -> String? { nil }
}
@preconcurrency @MainActor open class NSPathControlItem: NSObject {
    open var title = ""
    open var attributedTitle = NSAttributedString(string: "")
    open var image: NSImage?
    open var url: URL? { nil }
}
@preconcurrency @MainActor open class NSPathControl: NSControl {
    public enum Style: Int, Sendable { case standard = 0, popUp = 2 }
    open var pathStyle: Style = .standard
    open var url: URL?
    open var pathItems: [NSPathControlItem] = []
    open var clickedPathItem: NSPathControlItem? { nil }
    open var isEditable = false
    open var backgroundColor: NSColor?
    open var placeholderString: String?
}

@preconcurrency @MainActor open class NSStackView: NSView {
    public enum Gravity: Int, Sendable { case top = 1, leading = 1_000, center = 2, bottom = 3, trailing = 3_000 }
    public enum Distribution: Int, Sendable { case gravityAreas = -1, fill = 0, fillEqually, fillProportionally, equalSpacing, equalCentering }
    public static let useDefaultSpacing: CGFloat = .greatestFiniteMagnitude
    public convenience init(views: [NSView]) { self.init(frame: .zero) }
    open var orientation: NSUserInterfaceLayoutOrientation = .horizontal
    open var alignment: NSLayoutConstraint.Attribute = .centerY
    open var distribution: Distribution = .gravityAreas
    open var spacing: CGFloat = 8
    open var edgeInsets = NSEdgeInsets()
    open var detachesHiddenViews = true
    open var arrangedSubviews: [NSView] { [] }
    open var views: [NSView] { [] }
    open func addArrangedSubview(_ v: NSView) {}
    open func insertArrangedSubview(_ v: NSView, at i: Int) {}
    open func removeArrangedSubview(_ v: NSView) {}
    open func addView(_ v: NSView, in g: Gravity) {}
    open func setViews(_ v: [NSView], in g: Gravity) {}
    open func setCustomSpacing(_ s: CGFloat, after v: NSView) {}
    @discardableResult open func customSpacing(after v: NSView) -> CGFloat { 0 }
    open func setHuggingPriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    open func setClippingResistancePriority(_ p: NSLayoutPriority, for o: NSLayoutConstraint.Orientation) {}
    open func setVisibilityPriority(_ p: NSStackView.VisibilityPriority, for v: NSView) {}
    public struct VisibilityPriority: RawRepresentable, Hashable, Sendable { public var rawValue: Float; public init(rawValue: Float) { self.rawValue = rawValue }
        public static let mustHold = Self(rawValue: 1000), detachOnlyIfNecessary = Self(rawValue: 900), notVisible = Self(rawValue: 0) }
}
public enum NSUserInterfaceLayoutOrientation: Int, Sendable { case horizontal = 0, vertical = 1 }
extension NSLayoutConstraint {
    public enum Attribute: Int, Sendable { case left = 1, right, top, bottom, leading, trailing, width, height, centerX, centerY,
        lastBaseline, firstBaseline, notAnAttribute = 0
        public static var baseline: Attribute { .lastBaseline } }
}
@preconcurrency @MainActor open class NSClipView: NSView { open var documentView: NSView?; open var drawsBackground = true }
@preconcurrency @MainActor open class NSScroller: NSControl {}
@preconcurrency @MainActor open class NSScrollView: NSView {
    open var documentView: NSView?
    open var contentView: NSClipView = .init()
    open var hasVerticalScroller = false
    open var hasHorizontalScroller = false
    open var autohidesScrollers = false
    open var drawsBackground = true
    open var backgroundColor: NSColor = .clear
    open var borderType: NSBorderType = .noBorder
    open var automaticallyAdjustsContentInsets = true
    open var contentInsets = NSEdgeInsets()
    open var scrollerStyle: NSScroller.Style_ = .overlay
    open var documentVisibleRect: NSRect { .zero }
}
extension NSScroller { public enum Style_: Int, Sendable { case legacy, overlay } }
public enum NSBorderType: UInt, Sendable { case noBorder = 0, lineBorder, bezelBorder, grooveBorder }

@preconcurrency @MainActor open class NSSplitView: NSView {
    public enum DividerStyle: Int, Sendable { case thick = 1, thin = 2, paneSplitter = 3 }
    open var isVertical = false
    open var dividerStyle: DividerStyle = .thick
    open var dividerThickness: CGFloat { 1 }
    open weak var delegate: NSSplitViewDelegate?
    open var arrangedSubviews: [NSView] { [] }
    open var autosaveName: String?
    open func addArrangedSubview(_ v: NSView) {}
    open func setPosition(_ p: CGFloat, ofDividerAt i: Int) {}
    open func adjustSubviews() {}
    open func setHoldingPriority(_ p: NSLayoutPriority, forSubviewAt i: Int) {}
    @discardableResult open func holdingPriorityForSubview(at i: Int) -> NSLayoutPriority { .defaultLow }
    @discardableResult open func isSubviewCollapsed(_ v: NSView) -> Bool { false }
}
@preconcurrency @MainActor public protocol NSSplitViewDelegate: AnyObject {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool
    func splitViewDidResizeSubviews(_ notification: Notification)
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize)
}
extension NSSplitViewDelegate {
    @discardableResult public func splitView(_ splitView: NSSplitView, constrainMinCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { p }
    @discardableResult public func splitView(_ splitView: NSSplitView, constrainMaxCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { p }
    @discardableResult public func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
    @discardableResult public func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool { true }
    public func splitViewDidResizeSubviews(_ notification: Notification) {}
    public func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {}
}

// MARK: tables
@preconcurrency @MainActor open class NSTableColumn: NSObject {
    public init(identifier: NSUserInterfaceItemIdentifier) {}
    public struct ResizingOptions: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let autoresizingMask = Self(rawValue: 1), userResizingMask = Self(rawValue: 2) }
    open var identifier: NSUserInterfaceItemIdentifier = .init("")
    open var title = ""
    open var width: CGFloat = 100
    open var minWidth: CGFloat = 10
    open var maxWidth: CGFloat = 1000
    open var resizingMask: ResizingOptions = []
    open var headerCell: NSTableHeaderCell = .init()
    open var headerToolTip: String?
    open var sortDescriptorPrototype: NSSortDescriptor?
    open var isHidden = false
    open var isEditable = true
}
@preconcurrency @MainActor open class NSTableHeaderView: NSView {}
@preconcurrency @MainActor open class NSTableRowView: NSView {
    open var isSelected = false
    open var isEmphasized = false
    open var isGroupRowStyle = false
    open var backgroundColor: NSColor = .clear
    open var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    open func drawSelection(in r: NSRect) {}
    open func drawBackground(in r: NSRect) {}
    open var selectionHighlightStyle: NSTableView.SelectionHighlightStyle = .regular
}
@preconcurrency @MainActor open class NSTableCellView: NSView {
    open var textField: NSTextField?
    open var imageView: NSImageView?
    open var objectValue: Any?
    open var backgroundStyle: NSView.BackgroundStyle = .normal
}
@preconcurrency @MainActor open class NSTableView: NSControl {
    public enum SelectionHighlightStyle: Int, Sendable { case none = -1, regular = 0, sourceList = 1 }
    public enum Style: Int, Sendable { case automatic, fullWidth, inset, sourceList, plain }
    public enum ColumnAutoresizingStyle: UInt, Sendable { case noColumnAutoresizing = 0, uniformColumnAutoresizingStyle, sequentialColumnAutoresizingStyle, reverseSequentialColumnAutoresizingStyle, lastColumnOnlyAutoresizingStyle, firstColumnOnlyAutoresizingStyle }
    public enum RowSizeStyle: Int, Sendable { case `default` = -1, custom = 0, small, medium, large }
    public struct GridLineStyle: OptionSet, Sendable { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let solidVerticalGridLineMask = Self(rawValue: 1), solidHorizontalGridLineMask = Self(rawValue: 2) }
    open var headerView: NSTableHeaderView?
    open var tableColumns: [NSTableColumn] { [] }
    open var rowHeight: CGFloat = 17
    open var intercellSpacing: NSSize = .zero
    open var style: Style = .automatic
    open var rowSizeStyle: RowSizeStyle = .default
    open var selectionHighlightStyle: SelectionHighlightStyle = .regular
    open var columnAutoresizingStyle: ColumnAutoresizingStyle = .uniformColumnAutoresizingStyle
    open var usesAlternatingRowBackgroundColors = false
    open var allowsMultipleSelection = false
    open var allowsEmptySelection = true
    open var allowsColumnReordering = true
    open var allowsColumnResizing = true
    open var allowsTypeSelect = true
    open var gridStyleMask: GridLineStyle = []
    open var backgroundColor: NSColor = .clear
    open var doubleAction: Selector?
    open var selectedRow: Int { -1 }
    open var selectedRowIndexes: IndexSet { [] }
    open var clickedRow: Int { -1 }
    open var clickedColumn: Int { -1 }
    open var numberOfRows: Int { 0 }
    open var numberOfColumns: Int { 0 }
    open var sortDescriptors: [NSSortDescriptor] = []
    open var autosaveName: String?
    open var autosaveTableColumns = false
    open var floatsGroupRows = false
    open func addTableColumn(_ c: NSTableColumn) {}
    open func removeTableColumn(_ c: NSTableColumn) {}
    open func reloadData() {}
    open func reloadData(forRowIndexes r: IndexSet, columnIndexes c: IndexSet) {}
    open func selectRowIndexes(_ i: IndexSet, byExtendingSelection e: Bool) {}
    open func deselectAll(_ sender: Any?) {}
    open func scrollRowToVisible(_ r: Int) {}
    @discardableResult open func row(at p: NSPoint) -> Int { -1 }
    @discardableResult open func row(for v: NSView) -> Int { -1 }
    @discardableResult open func column(at p: NSPoint) -> Int { -1 }
    @discardableResult open func rect(ofRow r: Int) -> NSRect { .zero }
    @discardableResult open func rows(in r: NSRect) -> NSRange { NSRange() }
    @discardableResult open func view(atColumn c: Int, row: Int, makeIfNecessary: Bool) -> NSView? { nil }
    @discardableResult open func rowView(atRow r: Int, makeIfNecessary: Bool) -> NSTableRowView? { nil }
    @discardableResult open func makeView(withIdentifier i: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { nil }
    open func enumerateAvailableRowViews(_ h: (NSTableRowView, Int) -> Void) {}
    open func sizeLastColumnToFit() {}
    open func noteNumberOfRowsChanged() {}
    open func beginUpdates() {}; open func endUpdates() {}
    @discardableResult open func column(withIdentifier i: NSUserInterfaceItemIdentifier) -> Int { -1 }
    @discardableResult open func tableColumn(withIdentifier i: NSUserInterfaceItemIdentifier) -> NSTableColumn? { nil }
}
@preconcurrency @MainActor open class NSOutlineView: NSTableView {
    open weak var delegate: NSOutlineViewDelegate?
    open weak var dataSource: NSOutlineViewDataSource?
    open var outlineTableColumn: NSTableColumn?
    open var indentationPerLevel: CGFloat = 16
    open var autoresizesOutlineColumn = true
    open var indentationMarkerFollowsCell = true
    open var autosaveExpandedItems = false
    open func reloadItem(_ i: Any?) {}
    open func reloadItem(_ i: Any?, reloadChildren: Bool) {}
    open func expandItem(_ i: Any?) {}
    open func expandItem(_ i: Any?, expandChildren: Bool) {}
    open func collapseItem(_ i: Any?) {}
    open func collapseItem(_ i: Any?, collapseChildren: Bool) {}
    @discardableResult open func isItemExpanded(_ i: Any?) -> Bool { false }
    @discardableResult open func isExpandable(_ i: Any?) -> Bool { false }
    @discardableResult open func item(atRow r: Int) -> Any? { nil }
    @discardableResult open func row(forItem i: Any?) -> Int { -1 }
    @discardableResult open func parent(forItem i: Any?) -> Any? { nil }
    @discardableResult open func level(forItem i: Any?) -> Int { -1 }
    @discardableResult open func level(forRow r: Int) -> Int { -1 }
    @discardableResult open func numberOfChildren(ofItem i: Any?) -> Int { 0 }
    @discardableResult open func child(_ index: Int, ofItem i: Any?) -> Any? { nil }
    @discardableResult open func frameOfOutlineCell(atRow r: Int) -> NSRect { .zero }
}
@preconcurrency @MainActor public protocol NSOutlineViewDataSource: NSObjectProtocol {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any?
    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor])
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting?
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any])
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation)
    func outlineView(_ outlineView: NSOutlineView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo)
}
extension NSOutlineViewDataSource {
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { 0 }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { 0 }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? { nil }
    public func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {}
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? { nil }
    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {}
    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {}
    public func outlineView(_ outlineView: NSOutlineView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo) {}
}
@preconcurrency @MainActor public protocol NSOutlineViewDelegate: NSObjectProtocol {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView?
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView?
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, item: Any, mouseLocation: NSPoint) -> String
    func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet
    func outlineViewSelectionDidChange(_ notification: Notification)
    func outlineViewItemDidExpand(_ notification: Notification)
    func outlineViewItemDidCollapse(_ notification: Notification)
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool
}
public typealias NSRectPointer = UnsafeMutablePointer<NSRect>
extension NSOutlineViewDelegate {
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { nil }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { nil }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 17 }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, item: Any, mouseLocation: NSPoint) -> String { "" }
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection p: IndexSet) -> IndexSet { p }
    public func outlineViewSelectionDidChange(_ notification: Notification) {}
    public func outlineViewItemDidExpand(_ notification: Notification) {}
    public func outlineViewItemDidCollapse(_ notification: Notification) {}
    @discardableResult public func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { true }
}

public enum NSCompositingOperation: UInt, Sendable { case clear = 0, copy, sourceOver, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut, destinationAtop, xor, plusDarker, plusLighter, multiply = 14 }
extension CGRect {
    // AppKit's Swift overlay: NSRectFill / NSRectFillUsingOperation / NSFrameRect.
    @preconcurrency @MainActor public func fill(using op: NSCompositingOperation = .copy) {}
    @preconcurrency @MainActor public func frame(withWidth w: CGFloat = 1, using op: NSCompositingOperation = .sourceOver) {}
    @preconcurrency @MainActor public func clip() {}
}
