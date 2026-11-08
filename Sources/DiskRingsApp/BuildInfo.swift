#if canImport(AppKit)
import AppKit
import os

/// Build stamp written by build.sh into Info.plist (DiskRingsBuildID):
/// "<version> (<build>) src:<12 hex of source SHA-256> git:<commit|none> <UTC build time>".
/// Logged at startup (category build) and shown in the About panel.
/// Check on the Mac (read-only, no sudo):
///   defaults read "$PWD/build/DiskRings.app/Contents/Info" DiskRingsBuildID
///   log show --last 10m --style compact --predicate 'subsystem == "app.diskrings.DiskRings" AND category == "build"'
enum BuildInfo {
    static let log = OSLog(subsystem: "app.diskrings.DiskRings", category: "build")
    static var buildID: String {
        (Bundle.main.object(forInfoDictionaryKey: "DiskRingsBuildID") as? String) ?? "unstamped (not built by build.sh app)"
    }
    static func logAtStartup() {
        os_log("%{public}@", log: log, type: .default, ("build=" + buildID) as NSString)
    }
    @MainActor static func showAboutPanel() {
        let credits = NSAttributedString(string: tr("about.build", buildID),
                                         attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                                                      .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
#endif
