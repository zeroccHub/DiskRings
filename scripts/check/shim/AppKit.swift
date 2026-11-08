// Linux type-check shim for AppKit. APPROXIMATION of the macOS SDK (Xcode 16 / macOS 15 SDK,
// deployment target macOS 12): only members DiskRings uses, with signatures transcribed from
// the SDK's Swift interface. Bodies are dummies; this module is type-checked, never run.
// APIs newer than macOS 12 are marked `@available(*, deprecated, message: "macOS NN+")` so the
// gate reports any use (callers must guard with #available — reviewed by hand).
@_exported import Foundation
@_exported import QuartzCore

// ObjectiveC stand-ins. `#selector(x)` is rewritten to `__selector(x)` by prep.py so the
// referenced method must exist; @objc-ness itself is checked textually by prep.py.
public struct Selector: Hashable, ExpressibleByStringLiteral, @unchecked Sendable {
    public init(_ s: String) {}
    public init(stringLiteral s: String) {}
}
public func __selector(_ f: @MainActor () -> Void) -> Selector { Selector("") }

public typealias NSRect = CGRect
public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public func NSMakeRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { .zero }

public struct NSDirectionalEdgeInsets { public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {} }

// MARK: - Layout
public struct NSLayoutPriority: RawRepresentable, Hashable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, Sendable {
    public var rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public init(_ v: Float) { rawValue = v }
    public init(floatLiteral v: Float) { rawValue = v }
    public init(integerLiteral v: Int) { rawValue = Float(v) }
    public static let required = Self(1000), defaultHigh = Self(750), dragThatCanResizeWindow = Self(510),
        windowSizeStayPut = Self(500), dragThatCannotResizeWindow = Self(490), defaultLow = Self(250),
        fittingSizeCompression = Self(50)
    @discardableResult public static func + (l: Self, r: Float) -> Self { Self(l.rawValue + r) }
    @discardableResult public static func - (l: Self, r: Float) -> Self { Self(l.rawValue - r) }
}
@preconcurrency @MainActor open class NSLayoutConstraint: NSObject {
    public enum Orientation: Int, Sendable { case horizontal = 0, vertical = 1 }
    open var isActive = false
    open var constant: CGFloat = 0
    open var priority: NSLayoutPriority = .required
    open var identifier: String?
    open var multiplier: CGFloat { 1 }
    open class func activate(_ constraints: [NSLayoutConstraint]) {}
    open class func deactivate(_ constraints: [NSLayoutConstraint]) {}
}
@preconcurrency @MainActor open class NSLayoutAnchor<AnchorType: AnyObject>: NSObject {
    @discardableResult open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { .init() }
}
@preconcurrency @MainActor open class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
@preconcurrency @MainActor open class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}
@preconcurrency @MainActor open class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    @discardableResult open func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { .init() }
    @discardableResult open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { .init() }
}
@preconcurrency @MainActor open class NSLayoutGuide: NSObject {
    open var leadingAnchor: NSLayoutXAxisAnchor { .init() }; open var trailingAnchor: NSLayoutXAxisAnchor { .init() }
    open var leftAnchor: NSLayoutXAxisAnchor { .init() }; open var rightAnchor: NSLayoutXAxisAnchor { .init() }
    open var centerXAnchor: NSLayoutXAxisAnchor { .init() }; open var centerYAnchor: NSLayoutYAxisAnchor { .init() }
    open var topAnchor: NSLayoutYAxisAnchor { .init() }; open var bottomAnchor: NSLayoutYAxisAnchor { .init() }
    open var widthAnchor: NSLayoutDimension { .init() }; open var heightAnchor: NSLayoutDimension { .init() }
}

// MARK: - Appearance / colour / font / image
open class NSAppearance: NSObject {
    public struct Name: RawRepresentable, Hashable, Sendable {
        public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ s: String) { rawValue = s }
        public static let aqua = Name("aqua"), darkAqua = Name("darkAqua"), vibrantLight = Name("vibrantLight"),
            vibrantDark = Name("vibrantDark"), accessibilityHighContrastAqua = Name("hca"), accessibilityHighContrastDarkAqua = Name("hcda")
    }
    public init?(named: NSAppearance.Name) {}
    open var name: NSAppearance.Name { .aqua }
    @discardableResult open func bestMatch(from appearances: [NSAppearance.Name]) -> NSAppearance.Name? { nil }
    open class var current: NSAppearance! { get { nil } set {} }
    open class var currentDrawing: NSAppearance { NSAppearance(named: .aqua)! }
    open func performAsCurrentDrawingAppearance(_ block: () -> Void) {}
}
open class NSColor: NSObject, @unchecked Sendable {
    public typealias Name = String
    public override init() {}
    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    public init(name colorName: NSColor.Name?, dynamicProvider: @escaping @Sendable (NSAppearance) -> NSColor) {}
    public init?(cgColor: CGColor) {}
    public init(patternImage image: NSImage) {}
    open var cgColor: CGColor { CGColor() }
    open var alphaComponent: CGFloat { 1 }
    @discardableResult open func withAlphaComponent(_ alpha: CGFloat) -> NSColor { self }
    @discardableResult open func blended(withFraction fraction: CGFloat, of color: NSColor) -> NSColor? { self }
    @discardableResult open func usingColorSpace(_ space: NSColorSpace) -> NSColor? { self }
    open var redComponent: CGFloat { 0 }; open var greenComponent: CGFloat { 0 }; open var blueComponent: CGFloat { 0 }
    open func set() {}; open func setFill() {}; open func setStroke() {}
    open class var clear: NSColor { .init() }
    open class var white: NSColor { .init() }
    open class var black: NSColor { .init() }
    open class var gray: NSColor { .init() }
    open class var red: NSColor { .init() }
    open class var labelColor: NSColor { .init() }
    open class var secondaryLabelColor: NSColor { .init() }
    open class var tertiaryLabelColor: NSColor { .init() }
    open class var quaternaryLabelColor: NSColor { .init() }
    open class var linkColor: NSColor { .init() }
    open class var separatorColor: NSColor { .init() }
    open class var gridColor: NSColor { .init() }
    open class var windowBackgroundColor: NSColor { .init() }
    open class var controlBackgroundColor: NSColor { .init() }
    open class var underPageBackgroundColor: NSColor { .init() }
    open class var textBackgroundColor: NSColor { .init() }
    open class var textColor: NSColor { .init() }
    open class var controlColor: NSColor { .init() }
    open class var controlTextColor: NSColor { .init() }
    open class var disabledControlTextColor: NSColor { .init() }
    open class var selectedContentBackgroundColor: NSColor { .init() }
    open class var unemphasizedSelectedContentBackgroundColor: NSColor { .init() }
    open class var alternateSelectedControlTextColor: NSColor { .init() }
    open class var controlAccentColor: NSColor { .init() }
    open class var keyboardFocusIndicatorColor: NSColor { .init() }
    open class var systemRed: NSColor { .init() }
    open class var systemGreen: NSColor { .init() }
    open class var systemBlue: NSColor { .init() }
    open class var systemOrange: NSColor { .init() }
    open class var systemYellow: NSColor { .init() }
    open class var systemGray: NSColor { .init() }
    open class var systemFill: NSColor { .init() }
}
open class NSColorSpace: NSObject { open class var sRGB: NSColorSpace { .init() }; open class var deviceRGB: NSColorSpace { .init() } }
open class NSFont: NSObject, @unchecked Sendable {
    public struct Weight: RawRepresentable, Hashable, Sendable {
        public var rawValue: CGFloat; public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(rawValue: -0.8), thin = Weight(rawValue: -0.6), light = Weight(rawValue: -0.4),
            regular = Weight(rawValue: 0), medium = Weight(rawValue: 0.23), semibold = Weight(rawValue: 0.3),
            bold = Weight(rawValue: 0.4), heavy = Weight(rawValue: 0.56), black = Weight(rawValue: 0.62)
    }
    public enum TextStyle: String, Sendable { case largeTitle, title1, title2, title3, headline, subheadline, body, callout, footnote, caption1, caption2 }
    @discardableResult open class func systemFont(ofSize fontSize: CGFloat) -> NSFont { .init() }
    @discardableResult open class func systemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { .init() }
    @discardableResult open class func boldSystemFont(ofSize fontSize: CGFloat) -> NSFont { .init() }
    @discardableResult open class func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { .init() }
    @discardableResult open class func monospacedSystemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { .init() }
    @discardableResult open class func preferredFont(forTextStyle style: NSFont.TextStyle, options: [String: Any] = [:]) -> NSFont { .init() }
    open class var systemFontSize: CGFloat { 13 }
    open class var smallSystemFontSize: CGFloat { 11 }
    @discardableResult open class func systemFontSize(for controlSize: NSControl.ControlSize) -> CGFloat { 13 }
    open var pointSize: CGFloat { 13 }
    open var ascender: CGFloat { 0 }; open var descender: CGFloat { 0 }; open var capHeight: CGFloat { 0 }
    open var fontName: String { "" }
    @discardableResult open func withSize(_ s: CGFloat) -> NSFont { self }
}
open class NSImage: NSObject, @unchecked Sendable {
    public typealias Name = String
    public struct SymbolConfiguration: Sendable {
        public init(pointSize: CGFloat, weight: NSFont.Weight) {}
        public init(pointSize: CGFloat, weight: NSFont.Weight, scale: NSImage.SymbolScale) {}
        public init(scale: NSImage.SymbolScale) {}
        public init(textStyle: NSFont.TextStyle, scale: NSImage.SymbolScale) {}
        public init(paletteColors: [NSColor]) {}
        public init(hierarchicalColor: NSColor) {}
        @discardableResult public func applying(_ c: NSImage.SymbolConfiguration) -> NSImage.SymbolConfiguration { self }
    }
    public enum SymbolScale: Int, Sendable { case `default` = 0, small, medium, large }
    public override init() {}
    public init(size: NSSize) {}
    public init(size: NSSize, flipped drawingHandlerShouldBeCalledWithFlippedContext: Bool, drawingHandler: @escaping (NSRect) -> Bool) {}
    public init?(systemSymbolName symbolName: String, accessibilityDescription description: String?) {}
    public init?(named name: NSImage.Name) {}
    public init?(contentsOf url: URL) {}
    public init(cgImage: AnyObject, size: NSSize) {}
    open var size: NSSize = .zero
    open var isTemplate = false
    open var accessibilityDescription: String?
    @discardableResult open func withSymbolConfiguration(_ configuration: NSImage.SymbolConfiguration) -> NSImage? { self }
    open func lockFocus() {}; open func unlockFocus() {}
    open func draw(in rect: NSRect) {}
    @discardableResult open func layerContents(forContentsScale layerContentsScale: CGFloat) -> Any { self }
    @discardableResult open func recommendedLayerContentsScale(_ s: CGFloat) -> CGFloat { s }
    @discardableResult open func cgImage(forProposedRect r: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?, hints: [String: Any]?) -> AnyObject? { nil }
    open class var applicationIconName: NSImage.Name { "" }
}
extension NSImage.Name { public static let applicationIcon = "NSApplicationIcon"; public static let caution = "NSCaution" }
open class NSGraphicsContext: NSObject {
    open class var current: NSGraphicsContext? { get { nil } set {} }
    open var cgContext: CGContext { CGContext() }
    open class func saveGraphicsState() {}; open class func restoreGraphicsState() {}
}
open class NSBezierPath: NSObject {
    public override init() {}
    public init(rect: NSRect) {}
    public init(ovalIn rect: NSRect) {}
    public init(roundedRect rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {}
    open var lineWidth: CGFloat = 1
    open var bounds: NSRect { .zero }
    open func move(to p: NSPoint) {}; open func line(to p: NSPoint) {}; open func close() {}
    open func curve(to p: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {}
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) {}
    open func append(_ p: NSBezierPath) {}
    open func fill() {}; open func stroke() {}; open func addClip() {}
    @discardableResult open func contains(_ p: NSPoint) -> Bool { false }
    open class func fill(_ rect: NSRect) {}
    open class func stroke(_ rect: NSRect) {}
    open class func strokeLine(from: NSPoint, to: NSPoint) {}
    open var cgPath: CGPath { CGPath() }   // macOS 14+ in the real SDK; see check below
}

#if os(Linux)
// Foundation types that swift-corelibs-foundation lacks but macOS Foundation has.
open class UndoManager: NSObject {}
extension Timer {
    // Darwin Foundation (target/selector API).
    @discardableResult public class func scheduledTimer(timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector, userInfo: Any?, repeats yesOrNo: Bool) -> Timer { fatalError() }
    public convenience init(timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector, userInfo: Any?, repeats yesOrNo: Bool) { fatalError() }
}
extension URLResourceKey {
    // Darwin-only keys (macOS 10.13+).
    public static let volumeAvailableCapacityForImportantUsageKey = URLResourceKey(rawValue: "NSURLVolumeAvailableCapacityForImportantUsageKey")
    public static let volumeAvailableCapacityForOpportunisticUsageKey = URLResourceKey(rawValue: "NSURLVolumeAvailableCapacityForOpportunisticUsageKey")
}
extension URLResourceValues {
    public var volumeAvailableCapacityForImportantUsage: Int64? { nil }
    public var volumeAvailableCapacityForOpportunisticUsage: Int64? { nil }
}
extension NSMutableAttributedString { public convenience init() { self.init(string: "") } }
extension NotificationCenter {
    public func addObserver(_ observer: Any, selector aSelector: Selector, name aName: NSNotification.Name?, object anObject: Any?) {}
}
extension NSObject {
    public func perform(_ aSelector: Selector, with object: Any?, afterDelay delay: TimeInterval) {}
    public class func cancelPreviousPerformRequests(withTarget aTarget: Any) {}
    public class func cancelPreviousPerformRequests(withTarget aTarget: Any, selector aSelector: Selector, object anArgument: Any?) {}
    public func responds(to aSelector: Selector!) -> Bool { false }
}
#endif

open class NSPasteboard: NSObject, @unchecked Sendable {
    public struct PasteboardType: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let string = Self(rawValue: "public.utf8-plain-text")
        public static let fileURL = Self(rawValue: "public.file-url")
    }
    open class var general: NSPasteboard { .init() }
    @discardableResult open func clearContents() -> Int { 0 }
    @discardableResult open func setString(_ s: String, forType t: PasteboardType) -> Bool { true }
    @discardableResult open func string(forType type: PasteboardType) -> String? { nil }
    @discardableResult open func writeObjects(_ o: [Any]) -> Bool { true }
    @discardableResult open func declareTypes(_ types: [PasteboardType], owner: Any?) -> Int { 0 }
    @discardableResult open func readObjects(forClasses classes: [AnyClass], options: [AnyHashable: Any]? = nil) -> [Any]? { nil }
}

public struct NSDragOperation: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let copy = Self(rawValue: 1)
    public static let link = Self(rawValue: 2)
    public static let generic = Self(rawValue: 4)
    public static let `private` = Self(rawValue: 8)
    public static let move = Self(rawValue: 16)
    public static let delete = Self(rawValue: 32)
    public static let every = Self(rawValue: UInt.max)
}
@preconcurrency @MainActor public protocol NSDraggingInfo: AnyObject {
    var draggingPasteboard: NSPasteboard { get }
    var draggingSource: Any? { get }
    var draggingSourceOperationMask: NSDragOperation { get }
    var draggingLocation: NSPoint { get }
    var numberOfValidItemsForDrop: Int { get set }
}
@preconcurrency @MainActor public protocol NSDraggingSource: AnyObject {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation)
}
extension NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {}
}
public enum NSDraggingContext: UInt, Sendable { case outsideApplication = 0, withinApplication = 1 }
@preconcurrency @MainActor open class NSDraggingSession: NSObject {
    open var animatesToStartingPositionsOnCancelOrFail = true
    open var draggingPasteboard: NSPasteboard { .general }
}
@preconcurrency @MainActor open class NSDraggingItem: NSObject {
    public init(pasteboardWriter: NSPasteboardWriting) {}
    open func setDraggingFrame(_ frame: NSRect, contents: Any?) {}
}
@preconcurrency @MainActor public protocol NSPasteboardWriting: AnyObject {
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType]
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any?
}
@preconcurrency @MainActor open class NSPasteboardItem: NSObject, NSPasteboardWriting {
    open func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool { true }
    open func string(forType type: NSPasteboard.PasteboardType) -> String? { nil }
    open func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [] }
    open func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? { nil }
}
