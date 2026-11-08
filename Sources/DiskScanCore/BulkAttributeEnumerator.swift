#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin enumerator using `getattrlistbulk(2)`: one syscall returns a batch
/// of entries with name, type, device, file id, link count and sizes, so no
/// per-file `lstat` is needed. Symlinks are reported as `.symlink` and never
/// followed (the directory itself is opened with O_NOFOLLOW).
///
/// NOTE: written against the public SDK headers but NOT compiled or run on a
/// Mac as part of this delivery (see README). The record parser it relies on
/// (`BulkAttributeParser`) is unit-tested on Linux with synthesized buffers.
public struct BulkAttributeEnumerator: DirectoryEnumerator {
    /// Size of the reusable result buffer per call.
    public var bufferSize: Int

    public init(bufferSize: Int = 128 * 1024) {
        self.bufferSize = bufferSize
        assert(BulkAttr.cmnName == UInt32(ATTR_CMN_NAME))
        assert(BulkAttr.cmnDevID == UInt32(ATTR_CMN_DEVID))
        assert(BulkAttr.cmnObjType == UInt32(ATTR_CMN_OBJTYPE))
        assert(BulkAttr.cmnFileID == UInt32(ATTR_CMN_FILEID))
        assert(BulkAttr.cmnError == UInt32(ATTR_CMN_ERROR))
        assert(BulkAttr.cmnReturnedAttrs == UInt32(ATTR_CMN_RETURNED_ATTRS))
        assert(BulkAttr.dirMountStatus == UInt32(ATTR_DIR_MOUNTSTATUS))
        assert(BulkAttr.fileLinkCount == UInt32(ATTR_FILE_LINKCOUNT))
        assert(BulkAttr.fileTotalSize == UInt32(ATTR_FILE_TOTALSIZE))
        assert(BulkAttr.fileAllocSize == UInt32(ATTR_FILE_ALLOCSIZE))
        assert(BulkAttr.cmnextPrivateSize == UInt32(ATTR_CMNEXT_PRIVATESIZE))
        assert(BulkAttr.cmnextCloneID == UInt32(ATTR_CMNEXT_CLONEID))
        assert(BulkAttr.cmnextExtFlags == UInt32(ATTR_CMNEXT_EXT_FLAGS))
        assert(BulkAttr.fsoptAttrCmnExtended == UInt64(FSOPT_ATTR_CMN_EXTENDED))
    }

    public func rootEntry(at path: String) throws -> DirectoryEntry {
        try PosixDirectoryEnumerator.lstatEntry(path: path, name: path)
    }

    public func entries(inDirectoryAt path: String) throws -> [DirectoryEntry] {
        do {
            return try enumerate(path, extended: true)
        } catch EnumeratorError.posix(_, let code) where code == EINVAL {
            // Volume/kernel rejected the extended (clone) attributes: fall back
            // to the basic set; clone dedup is then simply not applied.
            return try enumerate(path, extended: false)
        }
    }

    private func enumerate(_ path: String, extended: Bool) throws -> [DirectoryEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw EnumeratorError.posix(path: path, code: errno) }
        defer { close(fd) }

        var list = attrlist()
        list.bitmapcount = u_short(BulkAttr.bitmapCount)
        list.commonattr = attrgroup_t(BulkAttr.requestedCommon)
        list.dirattr = attrgroup_t(BulkAttr.requestedDir)
        list.fileattr = attrgroup_t(BulkAttr.requestedFile)
        // With FSOPT_ATTR_CMN_EXTENDED the forkattr slot carries ATTR_CMNEXT_* bits.
        list.forkattr = extended ? attrgroup_t(BulkAttr.requestedCommonExt) : 0
        let options: UInt64 = extended ? BulkAttr.fsoptAttrCmnExtended : 0

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var result: [DirectoryEntry] = []
        while true {
            let n = getattrlistbulk(fd, &list, buffer, bufferSize, options)
            if n == 0 { break }
            if n < 0 {
                let code = errno
                if code == EINTR { continue }
                throw EnumeratorError.posix(path: path, code: code)
            }
            let raw = UnsafeRawBufferPointer(start: buffer, count: bufferSize)
            result.append(contentsOf: try BulkAttributeParser.parse(raw, count: Int(n)))
        }
        return result
    }
}
#endif
