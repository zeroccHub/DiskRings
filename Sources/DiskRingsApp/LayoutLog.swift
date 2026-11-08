#if canImport(AppKit)
import Foundation
import os

/// Startup layout diagnostics (unified log, subsystem app.diskrings.DiskRings, category layout).
/// Read on the Mac with:
///   log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "layout"'
enum LayoutLog {
    static let log = OSLog(subsystem: "app.diskrings.DiskRings", category: "layout")
    static func write(_ message: String, problem: Bool) {
        os_log("%{public}@", log: log, type: problem ? .error : .default, ((problem ? "PROBLEM " : "") + message) as NSString)
    }
}

/// 「筛选此文件夹」 diagnostics (same subsystem, category filter). Read on the Mac with:
///   log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "filter"'
/// The query text itself is logged only as its length (privacy).
enum FilterLog {
    static let log = OSLog(subsystem: "app.diskrings.DiskRings", category: "filter")
    static func write(_ message: String, problem: Bool = false) {
        os_log("%{public}@", log: log, type: problem ? .error : .default, ((problem ? "PROBLEM " : "") + message) as NSString)
    }
}
#endif
