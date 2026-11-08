import XCTest
@testable import DiskScanCore

/// Builds getattrlistbulk-style records byte by byte, then checks the parser.
final class BulkAttributeParserTests: XCTestCase {
    struct RecordSpec {
        var name: String
        var objType: UInt32
        var dev: Int32 = 16777220
        var fileID: UInt64
        var error: UInt32? = nil
        var mountStatus: UInt32? = nil       // directories
        var links: UInt32? = nil             // files
        var total: Int64? = nil
        var alloc: Int64? = nil
        var omitName = false
        var privateSize: Int64? = nil        // commonext
        var cloneID: UInt64? = nil
        var extFlags: UInt64? = nil
    }

    func encode(_ s: RecordSpec) -> [UInt8] {
        var common = BulkAttr.cmnReturnedAttrs | BulkAttr.cmnDevID | BulkAttr.cmnObjType | BulkAttr.cmnFileID
        if !s.omitName { common |= BulkAttr.cmnName }
        if s.error != nil { common |= BulkAttr.cmnError }
        var dir: UInt32 = 0, file: UInt32 = 0
        if s.mountStatus != nil { dir |= BulkAttr.dirMountStatus }
        if s.links != nil { file |= BulkAttr.fileLinkCount }
        if s.total != nil { file |= BulkAttr.fileTotalSize }
        if s.alloc != nil { file |= BulkAttr.fileAllocSize }
        var ext: UInt32 = 0
        if s.privateSize != nil { ext |= BulkAttr.cmnextPrivateSize }
        if s.cloneID != nil { ext |= BulkAttr.cmnextCloneID }
        if s.extFlags != nil { ext |= BulkAttr.cmnextExtFlags }

        var body: [UInt8] = []
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { body.append(contentsOf: $0) } }
        put(UInt32(0)) // length placeholder
        put(common); put(UInt32(0)); put(dir); put(file); put(ext)
        if let e = s.error { put(e) }
        var nameRefOffset = -1
        if !s.omitName { nameRefOffset = body.count; put(Int32(0)); put(UInt32(0)) }
        put(s.dev); put(s.objType); put(s.fileID)
        if let m = s.mountStatus { put(m) }
        if let l = s.links { put(l) }
        if let t = s.total { put(t) }
        if let a = s.alloc { put(a) }
        // commonext group comes after the file group, in bit order
        if let p = s.privateSize { put(p) }
        if let c = s.cloneID { put(c) }
        if let f = s.extFlags { put(f) }
        if nameRefOffset >= 0 {
            let nameBytes = Array(s.name.utf8) + [0]
            let dataStart = body.count
            body += nameBytes
            while body.count % 4 != 0 { body.append(0) }
            let rel = Int32(dataStart - nameRefOffset)
            withUnsafeBytes(of: rel.littleEndian) { for (i, b) in $0.enumerated() { body[nameRefOffset + i] = b } }
            withUnsafeBytes(of: UInt32(nameBytes.count).littleEndian) { for (i, b) in $0.enumerated() { body[nameRefOffset + 4 + i] = b } }
        }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { for (i, b) in $0.enumerated() { body[i] = b } }
        return body
    }

    func parse(_ specs: [RecordSpec], extraCapacity: Int = 64) throws -> [DirectoryEntry] {
        var buf = specs.flatMap(encode)
        buf += [UInt8](repeating: 0xEE, count: extraCapacity) // garbage after the records must be ignored
        return try buf.withUnsafeBytes { try BulkAttributeParser.parse($0, count: specs.count) }
    }

    func testParsesFilesDirsSymlinks() throws {
        let entries = try parse([
            RecordSpec(name: "report.pdf", objType: BulkAttr.vReg, fileID: 42, links: 2, total: 12345, alloc: 16384),
            RecordSpec(name: "Volumes-ish", objType: BulkAttr.vDir, fileID: 43, mountStatus: BulkAttr.dirMountStatusMountPoint),
            RecordSpec(name: "plain dir", objType: BulkAttr.vDir, fileID: 44, mountStatus: 0),
            RecordSpec(name: "ln", objType: BulkAttr.vLnk, fileID: 45, links: 1, total: 9, alloc: 0),
            RecordSpec(name: "ünïcødé 名前", objType: BulkAttr.vReg, dev: -5, fileID: UInt64.max, links: 1, total: 1, alloc: 4096),
        ])
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0], DirectoryEntry(name: "report.pdf", kind: .file, device: 16777220, fileID: 42,
                                                  linkCount: 2, logicalSize: 12345, allocatedSize: 16384))
        XCTAssertEqual(entries[1].kind, .directory)
        XCTAssertTrue(entries[1].isMountPoint)
        XCTAssertFalse(entries[2].isMountPoint)
        XCTAssertEqual(entries[3].kind, .symlink)
        XCTAssertEqual(entries[4].name, "ünïcødé 名前")
        XCTAssertEqual(entries[4].device, UInt64(UInt32(bitPattern: -5)), "dev_t reinterpreted as UInt32 bit pattern, like lstat")
        XCTAssertEqual(entries[4].fileID, UInt64.max)
    }

    func testSkipsErrorRecordsAndNamelessRecords() throws {
        let entries = try parse([
            RecordSpec(name: "bad", objType: BulkAttr.vReg, fileID: 1, error: 13),
            RecordSpec(name: "good", objType: BulkAttr.vReg, fileID: 2, error: 0, links: 1, total: 1, alloc: 4096),
            RecordSpec(name: "", objType: BulkAttr.vReg, fileID: 3, omitName: true),
        ])
        XCTAssertEqual(entries.map(\.name), ["good"])
    }

    func testRejectsTruncatedBuffer() {
        let rec = encode(RecordSpec(name: "x", objType: BulkAttr.vReg, fileID: 1, links: 1, total: 1, alloc: 1))
        let truncated = Array(rec.prefix(rec.count - 6))
        XCTAssertThrowsError(try truncated.withUnsafeBytes { try BulkAttributeParser.parse($0, count: 1) })
    }

    func testParsesCommonExtendedCloneAttributes() throws {
        let entries = try parse([
            RecordSpec(name: "clone-a", objType: BulkAttr.vReg, fileID: 10, links: 1, total: 1_000_000, alloc: 1_003_520,
                       privateSize: 4096, cloneID: 0xABCD_0000_0001, extFlags: BulkAttr.efMayShareBlocks),
            // Only some commonext bits returned: the parser must not shift later fields.
            RecordSpec(name: "clone-only", objType: BulkAttr.vReg, fileID: 11, links: 1, total: 5, alloc: 4096,
                       cloneID: 77),
            RecordSpec(name: "flags-only", objType: BulkAttr.vReg, fileID: 12, links: 1, total: 5, alloc: 4096,
                       extFlags: 0),
            // Directory with commonext returned: clone fields ignored for non-files.
            RecordSpec(name: "dir", objType: BulkAttr.vDir, fileID: 13, mountStatus: 0, cloneID: 5),
            // Legacy record without commonext follows and must still parse.
            RecordSpec(name: "plain", objType: BulkAttr.vReg, fileID: 14, links: 1, total: 9, alloc: 4096),
        ])
        XCTAssertEqual(entries.map(\.name), ["clone-a", "clone-only", "flags-only", "dir", "plain"])
        XCTAssertEqual(entries[0].cloneID, 0xABCD_0000_0001)
        XCTAssertEqual(entries[0].privateSize, 4096)
        XCTAssertEqual(entries[0].extFlags, BulkAttr.efMayShareBlocks)
        XCTAssertEqual(entries[0].allocatedSize, 1_003_520)
        XCTAssertTrue(entries[0].mayShareBlocks)
        XCTAssertEqual(entries[1].cloneID, 77)
        XCTAssertNil(entries[1].privateSize)
        XCTAssertFalse(entries[1].mayShareBlocks, "unknown flags/private size => conservative, no dedup")
        XCTAssertNil(entries[2].cloneID)
        XCTAssertEqual(entries[2].extFlags, 0)
        XCTAssertFalse(entries[2].mayShareBlocks)
        XCTAssertNil(entries[3].cloneID)
        XCTAssertNil(entries[4].cloneID)
        XCTAssertEqual(entries[4].allocatedSize, 4096)
    }
}
