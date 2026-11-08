import XCTest
import Foundation

/// build.sh compiles DiskScanCore + SunburstGeometry + DiskRingsApp as ONE module, so two
/// internal top-level types with the same name in different directories break the Mac build
/// even though SwiftPM (separate modules, AppKit files skipped on Linux) accepts them.
/// Mirrors scripts/check/dup-types.py so `swift test` alone also catches it.
final class SourceGateTests: XCTestCase {
    func testNoDuplicateTopLevelTypeNamesInSingleModule() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let decl = try NSRegularExpression(pattern:
            #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|open|internal|final|indirect|nonisolated)\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+([A-Za-z_]\w*)"#)
        var seen: [String: [String]] = [:]
        let files = FileManager.default.enumerator(atPath: sources.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 30)
        for rel in files {
            let text = try String(contentsOf: sources.appendingPathComponent(rel), encoding: .utf8)
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                guard let c = line.first, !c.isWhitespace else { continue }
                if line.hasPrefix("private ") || line.hasPrefix("fileprivate ") { continue }
                let r = NSRange(line.startIndex..., in: line)
                if let m = decl.firstMatch(in: line, range: r), let nr = Range(m.range(at: 1), in: line) {
                    seen[String(line[nr]), default: []].append("\(rel):\(i + 1)")
                }
            }
        }
        let dups = seen.filter { $0.value.count > 1 }
        XCTAssertTrue(dups.isEmpty, "duplicate top-level types in the single module: \(dups)")
        XCTAssertNotNil(seen["CapacityBarView"]); XCTAssertNotNil(seen["VolumeUsageBarView"])
    }
}
