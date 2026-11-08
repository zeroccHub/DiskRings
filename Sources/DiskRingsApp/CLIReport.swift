import Foundation
#if !SINGLE_MODULE  // SwiftPM: separate modules. build.sh compiles one module with -D SINGLE_MODULE.
import DiskScanCore
#endif

/// Portable text report: scans a directory and prints the largest children
/// with logical size and actual on-disk usage (APFS clones counted once).
enum CLIReport {
    static func run(path: String) -> Int32 {
        let engine = ScanEngine()
        do {
            let r = try engine.scanBlocking(path: path)
            let root = r.root
            print("\(root.path): \(SizeText.format(root.logicalSize)) logical / ≈\(SizeText.format(root.actualSize)) actual usage (estimate), \(root.itemCount) items")
            print(String(format: "scanned %d dirs, %d files in %.2fs; %d hard-link duplicates; %d clone duplicates (%@ shared); %d unreadable dirs",
                         r.progress.directoriesScanned, r.progress.filesSeen, r.duration,
                         r.hardLinkDuplicates, r.cloneDuplicates, SizeText.format(r.cloneSharedBytes),
                         r.restrictedPaths.count))
            print("  ACTUAL = estimated on-disk usage (hard links once; APFS clones: lowest-inode member full, others private bytes)")
            print("  " + pad("LOGICAL") + " " + pad("ACTUAL~") + " NAME")
            for child in root.children.prefix(20) {
                var flags = ""
                if child.isOtherFilesystem { flags += " [other filesystem, not scanned]" }
                if child.isRestricted { flags += " [unreadable]" }
                if child.isHardLinkDuplicate { flags += " [hard link]" }
                if child.isCloneDuplicate { flags += " [clone]" }
                let marker = child.isDirectory ? "/" : ""
                print("  \(pad(SizeText.format(child.contributedSize(.logical)))) \(pad(SizeText.format(child.contributedSize(.actual)))) \(child.name)\(marker)\(flags)")
            }
            return 0
        } catch {
            FileHandle.standardError.write("scan failed: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }

    private static func pad(_ s: String) -> String { s.padding(toLength: 11, withPad: " ", startingAt: 0) }
}
