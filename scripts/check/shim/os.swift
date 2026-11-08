// Linux type-check shim for the `os` module (unified logging only). APPROXIMATION of the SDK.
@_exported import Foundation
public final class OSLog: @unchecked Sendable {
    public init(subsystem: String, category: String) {}
    public static let `default` = OSLog(subsystem: "", category: "")
    public static let disabled = OSLog(subsystem: "", category: "")
}
public struct OSLogType: Equatable, Sendable {
    let raw: UInt8
    public static let `default` = OSLogType(raw: 0), info = OSLogType(raw: 1), debug = OSLogType(raw: 2),
        error = OSLogType(raw: 16), fault = OSLogType(raw: 17)
}
public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = #dsohandle, log: OSLog = .default, type: OSLogType = .default, _ args: CVarArg...) {}
public func os_log(_ type: OSLogType, dso: UnsafeRawPointer? = #dsohandle, log: OSLog = .default, _ message: StaticString, _ args: CVarArg...) {}
