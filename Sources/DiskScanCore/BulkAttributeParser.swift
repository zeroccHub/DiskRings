import Foundation

/// Attribute bit values from the public `<sys/attr.h>` header (Apple API
/// constants). Re-declared here so the buffer parser can be compiled and
/// unit-tested on non-Darwin platforms. On Darwin, `BulkAttributeEnumerator`
/// asserts these match the SDK's macros.
public enum BulkAttr {
    public static let bitmapCount: UInt16 = 5               // ATTR_BIT_MAP_COUNT

    public static let cmnName: UInt32         = 0x0000_0001 // ATTR_CMN_NAME
    public static let cmnDevID: UInt32        = 0x0000_0002 // ATTR_CMN_DEVID
    public static let cmnObjType: UInt32      = 0x0000_0008 // ATTR_CMN_OBJTYPE
    public static let cmnFileID: UInt32       = 0x0200_0000 // ATTR_CMN_FILEID
    public static let cmnError: UInt32        = 0x2000_0000 // ATTR_CMN_ERROR
    public static let cmnReturnedAttrs: UInt32 = 0x8000_0000 // ATTR_CMN_RETURNED_ATTRS

    public static let dirMountStatus: UInt32  = 0x0000_0004 // ATTR_DIR_MOUNTSTATUS
    public static let dirMountStatusMountPoint: UInt32 = 0x1 // DIR_MNTSTATUS_MNTPOINT

    public static let fileLinkCount: UInt32   = 0x0000_0001 // ATTR_FILE_LINKCOUNT
    public static let fileTotalSize: UInt32   = 0x0000_0002 // ATTR_FILE_TOTALSIZE
    public static let fileAllocSize: UInt32   = 0x0000_0004 // ATTR_FILE_ALLOCSIZE

    // Extended common attributes ("commonext"). They are requested and
    // returned in the attrlist/attribute_set_t `forkattr` slot when the
    // FSOPT_ATTR_CMN_EXTENDED option is passed.
    public static let cmnextPrivateSize: UInt32 = 0x0000_0008 // ATTR_CMNEXT_PRIVATESIZE (off_t)
    public static let cmnextCloneID: UInt32     = 0x0000_0100 // ATTR_CMNEXT_CLONEID     (u_int64_t)
    public static let cmnextExtFlags: UInt32    = 0x0000_0200 // ATTR_CMNEXT_EXT_FLAGS   (u_int64_t)
    public static let fsoptAttrCmnExtended: UInt64 = 0x0000_0020 // FSOPT_ATTR_CMN_EXTENDED

    // ATTR_CMNEXT_EXT_FLAGS bits (<sys/attr.h>)
    public static let efMayShareBlocks: UInt64  = 0x0000_0001 // EF_MAY_SHARE_BLOCKS
    public static let efSharesAllBlocks: UInt64 = 0x0000_0040 // EF_SHARES_ALL_BLOCKS

    // fsobj_type_t values (enum vtype in <sys/vnode.h>)
    public static let vReg: UInt32 = 1
    public static let vDir: UInt32 = 2
    public static let vLnk: UInt32 = 5

    /// The attribute groups this scanner requests.
    public static let requestedCommon: UInt32 =
        cmnReturnedAttrs | cmnName | cmnError | cmnDevID | cmnObjType | cmnFileID
    public static let requestedDir: UInt32 = dirMountStatus
    public static let requestedFile: UInt32 = fileLinkCount | fileTotalSize | fileAllocSize
    public static let requestedCommonExt: UInt32 = cmnextPrivateSize | cmnextCloneID | cmnextExtFlags
}

/// Parses the packed records written by `getattrlistbulk(2)` for the
/// attribute set in `BulkAttr.requested*`.
///
/// Record layout (each field present only if its bit is set in the record's
/// returned-attributes set; all fixed fields are 4-byte aligned and may be
/// unaligned for 8-byte loads):
///
///     u32              record length (bytes, including this field)
///     attribute_set_t  returned attrs (5 x u32: common, vol, dir, file, fork)
///     u32              ATTR_CMN_ERROR      (if set)
///     attrreference_t  ATTR_CMN_NAME       (i32 offset from this field, u32 length incl. NUL)
///     dev_t (i32)      ATTR_CMN_DEVID
///     u32              ATTR_CMN_OBJTYPE
///     u64              ATTR_CMN_FILEID
///     u32              ATTR_DIR_MOUNTSTATUS (directories only)
///     u32              ATTR_FILE_LINKCOUNT  (files only)
///     off_t (i64)      ATTR_FILE_TOTALSIZE
///     off_t (i64)      ATTR_FILE_ALLOCSIZE
///     -- extended common attributes (bits in the 5th returned word) --
///     off_t (i64)      ATTR_CMNEXT_PRIVATESIZE
///     u64              ATTR_CMNEXT_CLONEID
///     u64              ATTR_CMNEXT_EXT_FLAGS
///
/// Groups are packed common → (vol) → dir → file → commonext, and by
/// ascending bit value inside each group.
public enum BulkAttributeParser {
    public struct ParseError: Error, Equatable { public let offset: Int }

    /// - Parameters:
    ///   - buffer: bytes filled in by `getattrlistbulk`.
    ///   - count: the (positive) return value of `getattrlistbulk`.
    /// - Returns: parsed entries; records carrying `ATTR_CMN_ERROR != 0` or no name are skipped.
    public static func parse(_ buffer: UnsafeRawBufferPointer, count: Int) throws -> [DirectoryEntry] {
        var out: [DirectoryEntry] = []
        out.reserveCapacity(count)
        var recordStart = 0
        for _ in 0..<count {
            guard recordStart + 4 <= buffer.count else { throw ParseError(offset: recordStart) }
            let length = Int(buffer.loadUnaligned(fromByteOffset: recordStart, as: UInt32.self))
            guard length >= 24, recordStart + length <= buffer.count else { throw ParseError(offset: recordStart) }
            let record = UnsafeRawBufferPointer(rebasing: buffer[recordStart..<(recordStart + length)])
            if let e = try parseRecord(record) { out.append(e) }
            recordStart += length
        }
        return out
    }

    private static func parseRecord(_ r: UnsafeRawBufferPointer) throws -> DirectoryEntry? {
        var off = 4
        func need(_ n: Int) throws {
            guard off + n <= r.count else { throw ParseError(offset: off) }
        }
        func u32() throws -> UInt32 { try need(4); defer { off += 4 }; return r.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
        func i32() throws -> Int32 { try need(4); defer { off += 4 }; return r.loadUnaligned(fromByteOffset: off, as: Int32.self) }
        func u64() throws -> UInt64 { try need(8); defer { off += 8 }; return r.loadUnaligned(fromByteOffset: off, as: UInt64.self) }
        func i64() throws -> Int64 { try need(8); defer { off += 8 }; return r.loadUnaligned(fromByteOffset: off, as: Int64.self) }

        let common = try u32()
        _ = try u32() // vol
        let dir = try u32()
        let file = try u32()
        let commonExt = try u32() // forkattr slot = commonext bits with FSOPT_ATTR_CMN_EXTENDED

        if common & BulkAttr.cmnError != 0 {
            let err = try u32()
            if err != 0 { return nil }
        }
        var name: String?
        if common & BulkAttr.cmnName != 0 {
            let fieldStart = off
            let dataOffset = Int(try i32())
            let dataLength = Int(try u32())
            let start = fieldStart + dataOffset
            guard dataLength > 0, start >= 0, start + dataLength <= r.count else { throw ParseError(offset: fieldStart) }
            // Length includes the trailing NUL.
            var bytes = UnsafeRawBufferPointer(rebasing: r[start..<(start + dataLength)])
            if let nul = bytes.firstIndex(of: 0) { bytes = UnsafeRawBufferPointer(rebasing: bytes[bytes.startIndex..<nul]) }
            name = String(decoding: bytes, as: UTF8.self)
        }
        var device: UInt64 = 0
        if common & BulkAttr.cmnDevID != 0 { device = DeviceID.key(try i32()) } // same bit-pattern rule as lstat
        var objType: UInt32 = 0
        if common & BulkAttr.cmnObjType != 0 { objType = try u32() }
        var fileID: UInt64 = 0
        if common & BulkAttr.cmnFileID != 0 { fileID = try u64() }

        var mountPoint = false
        if dir & BulkAttr.dirMountStatus != 0 {
            mountPoint = (try u32()) & BulkAttr.dirMountStatusMountPoint != 0
        }
        var links: UInt32 = 1
        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        if file & BulkAttr.fileLinkCount != 0 { links = try u32() }
        if file & BulkAttr.fileTotalSize != 0 { logical = UInt64(max(0, try i64())) }
        if file & BulkAttr.fileAllocSize != 0 { allocated = UInt64(max(0, try i64())) }
        var privateSize: UInt64?
        var cloneID: UInt64?
        var extFlags: UInt64?
        if commonExt & BulkAttr.cmnextPrivateSize != 0 { privateSize = UInt64(max(0, try i64())) }
        if commonExt & BulkAttr.cmnextCloneID != 0 { cloneID = try u64() }
        if commonExt & BulkAttr.cmnextExtFlags != 0 { extFlags = try u64() }

        guard let n = name, !n.isEmpty else { return nil }
        let kind: NodeKind
        switch objType {
        case BulkAttr.vReg: kind = .file
        case BulkAttr.vDir: kind = .directory
        case BulkAttr.vLnk: kind = .symlink
        default: kind = .other
        }
        return DirectoryEntry(name: n, kind: kind, device: device, fileID: fileID, linkCount: links,
                              logicalSize: kind == .directory ? 0 : logical,
                              allocatedSize: kind == .directory ? 0 : allocated,
                              isMountPoint: mountPoint,
                              cloneID: kind == .file ? cloneID : nil,
                              privateSize: kind == .file ? privateSize : nil,
                              extFlags: kind == .file ? extFlags : nil)
    }
}
