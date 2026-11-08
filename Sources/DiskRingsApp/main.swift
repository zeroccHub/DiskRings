// DiskRings entry point.
//
// macOS: launches the AppKit UI (or a text report with `--cli <path>`).
// Other platforms (e.g. the Linux CI box): only the text report is available.
import Foundation
#if !SINGLE_MODULE  // SwiftPM: separate modules. build.sh compiles one module with -D SINGLE_MODULE.
import DiskScanCore
#endif
#if canImport(AppKit)
import AppKit
#endif

let launchArguments = CommandLine.arguments

#if canImport(AppKit)
if launchArguments.count >= 3 && launchArguments[1] == "--cli" {
    exit(CLIReport.run(path: launchArguments[2]))
}
// Top-level code runs on the main thread but is not statically main-actor isolated in Swift 5
// mode; AppDelegate is @MainActor, so enter the main actor explicitly (traps if not on main).
// NSApplication.delegate is weak; `delegate` stays alive because app.run() never returns
// (withExtendedLifetime makes that explicit).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
#else
if launchArguments.count >= 3 && launchArguments[1] == "--cli" {
    exit(CLIReport.run(path: launchArguments[2]))
}
print("DiskRings: the graphical app requires macOS (AppKit).")
print("On this platform you can run the portable scanner: DiskRings --cli <path>")
exit(launchArguments.count > 1 ? 2 : 0)
#endif
