// Linux type-check shim for QuartzCore/CoreGraphics. APPROXIMATION of the macOS SDK:
// only the members DiskRings uses, signatures copied from the SDK headers as rendered in
// Swift (macOS 12+). Bodies are fatalError(); this module is never executed.
@_exported import Foundation

public typealias CGFloat = Foundation.CGFloat
open class CGColor: @unchecked Sendable {
    public static let clear = CGColor(); public static let white = CGColor(); public static let black = CGColor()
    public init() {}
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(gray: CGFloat, alpha: CGFloat) {}
    public var alpha: CGFloat { 1 }
    @discardableResult public func copy(alpha: CGFloat) -> CGColor? { nil }
}
open class CGPath { public init() {}
    public var boundingBox: CGRect { .zero }
    @discardableResult public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool { false }
}
public enum CGPathFillRule: Int32 { case winding, evenOdd }
public enum CGLineJoin: Int32 { case miter, round, bevel }
public enum CGLineCap: Int32 { case butt, round, square }
public struct CGAffineTransform { public static let identity = CGAffineTransform(); public init() {}; public init(rotationAngle angle: CGFloat) {}; public init(scaleX sx: CGFloat, y sy: CGFloat) {}; public init(translationX tx: CGFloat, y ty: CGFloat) {} }
open class CGMutablePath: CGPath {
    public override init() {}
    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) {}
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) {}
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) {}
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {}
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {}
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {}
    public func closeSubpath() {}
}
public enum CGBlendMode: Int32 { case normal, multiply, sourceAtop, copy, clear }
open class CGContext { public init() {}
    public func saveGState() {}; public func restoreGState() {}
    public func setBlendMode(_ mode: CGBlendMode) {}
    public func setFillColor(_ color: CGColor) {}; public func setStrokeColor(_ color: CGColor) {}
    public func setLineWidth(_ width: CGFloat) {}
    public func addPath(_ path: CGPath) {}; public func clip() {}
    public func fill(_ rect: CGRect) {}; public func fillPath(using rule: CGPathFillRule = .winding) {}
    public func strokePath() {}; public func clip(to rect: CGRect) {}
    public func move(to point: CGPoint) {}; public func addLine(to point: CGPoint) {}
}

public struct CATransform3D { public init() {} }
public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D { .init() }
public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D { .init() }
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D { .init() }

public struct CALayerContentsGravity: RawRepresentable, Hashable {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = Self(rawValue: "center"), resize = Self(rawValue: "resize"),
        resizeAspect = Self(rawValue: "resizeAspect"), resizeAspectFill = Self(rawValue: "resizeAspectFill")
}
public struct CAShapeLayerLineJoin: RawRepresentable, Hashable {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = Self(rawValue: "miter"), round = Self(rawValue: "round"), bevel = Self(rawValue: "bevel")
}
public struct CAShapeLayerLineCap: RawRepresentable, Hashable {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = Self(rawValue: "butt"), round = Self(rawValue: "round"), square = Self(rawValue: "square")
}
public struct CATextLayerAlignmentMode: RawRepresentable, Hashable {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let natural = Self(rawValue: "natural"), left = Self(rawValue: "left"), right = Self(rawValue: "right"),
        center = Self(rawValue: "center"), justified = Self(rawValue: "justified")
}
public struct CATextLayerTruncationMode: RawRepresentable, Hashable {
    public var rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
    public static let none = Self(rawValue: "none"), start = Self(rawValue: "start"), end = Self(rawValue: "end"), middle = Self(rawValue: "middle")
}
public struct CACornerMask: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let layerMinXMinYCorner = Self(rawValue: 1), layerMaxXMinYCorner = Self(rawValue: 2),
        layerMinXMaxYCorner = Self(rawValue: 4), layerMaxXMaxYCorner = Self(rawValue: 8) }

open class CALayer: NSObject {
    public override init() {}
    public init(layer: Any) {}
    open var bounds: CGRect = .zero
    open var frame: CGRect = .zero
    open var position: CGPoint = .zero
    open var anchorPoint: CGPoint = .zero
    open var zPosition: CGFloat = 0
    open var transform = CATransform3D()
    open var sublayerTransform = CATransform3D()
    open var isHidden = false
    open var opacity: Float = 1
    open var name: String?
    open var contents: Any?
    open var contentsGravity: CALayerContentsGravity = .resize
    open var contentsScale: CGFloat = 1
    open var backgroundColor: CGColor?
    open var borderColor: CGColor?
    open var borderWidth: CGFloat = 0
    open var cornerRadius: CGFloat = 0
    open var maskedCorners: CACornerMask = []
    open var masksToBounds = false
    open var mask: CALayer?
    open var shadowColor: CGColor?
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 0
    open var shadowOffset: CGSize = .zero
    open var sublayers: [CALayer]?
    open var superlayer: CALayer? { nil }
    open var delegate: AnyObject?
    open var actions: [String: Any]?
    open func addSublayer(_ layer: CALayer) {}
    open func insertSublayer(_ layer: CALayer, at idx: UInt32) {}
    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {}
    open func removeFromSuperlayer() {}
    open func setNeedsDisplay() {}
    open func setNeedsLayout() {}
    open func layoutSublayers() {}
    open func draw(in ctx: CGContext) {}
    @discardableResult open func hitTest(_ p: CGPoint) -> CALayer? { nil }
    @discardableResult open func contains(_ p: CGPoint) -> Bool { false }
    @discardableResult open func convert(_ p: CGPoint, from l: CALayer?) -> CGPoint { p }
    @discardableResult open func convert(_ p: CGPoint, to l: CALayer?) -> CGPoint { p }
    open func removeAllAnimations() {}
    open func setAffineTransform(_ m: CGAffineTransform) {}
    open func affineTransform() -> CGAffineTransform { .identity }
}
open class CAShapeLayer: CALayer {
    open var path: CGPath?
    open var fillColor: CGColor?
    open var strokeColor: CGColor?
    open var lineWidth: CGFloat = 1
    open var lineJoin: CAShapeLayerLineJoin = .miter
    open var lineCap: CAShapeLayerLineCap = .butt
    open var lineDashPattern: [NSNumber]?
    open var fillRule: String = "non-zero"
}
open class CATextLayer: CALayer {
    open var string: Any?
    open var font: AnyObject?
    open var fontSize: CGFloat = 36
    open var foregroundColor: CGColor?
    open var isWrapped = false
    open var truncationMode: CATextLayerTruncationMode = .none
    open var alignmentMode: CATextLayerAlignmentMode = .natural
}
open class CATransaction: NSObject {
    open class func begin() {}
    open class func commit() {}
    open class func flush() {}
    open class func setDisableActions(_ flag: Bool) {}
    open class func setAnimationDuration(_ dur: TimeInterval) {}
    open class func setCompletionBlock(_ block: (@Sendable () -> Void)?) {}
}
