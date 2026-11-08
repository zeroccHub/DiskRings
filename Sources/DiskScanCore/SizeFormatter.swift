import Foundation

/// Small, deterministic byte formatter (base-1000, like Finder) usable on all platforms.
public enum SizeText {
    public static func format(_ bytes: UInt64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        if bytes < 1000 { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
        var value = Double(bytes)
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        let digits = value >= 100 ? 0 : 1
        return String(format: "%.\(digits)f %@", value, units[i])
    }
}
