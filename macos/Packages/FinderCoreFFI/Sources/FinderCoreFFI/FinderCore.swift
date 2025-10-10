import FinderCoreShims
import Foundation

public enum FinderCore {
    public enum Scope: Int32 {
        case name = 0
        case content = 1
        case both = 2
    }

    public struct Hit: Sendable, Equatable {
        public let path: String
        public let name: String
        public let mtime: Int64
        public let size: UInt64
        public let score: Float

        public init(path: String, name: String, mtime: Int64, size: UInt64, score: Float) {
            self.path = path
            self.name = name
            self.mtime = mtime
            self.size = size
            self.score = score
        }
    }

    @discardableResult
    public static func initIndex(at path: String) -> Bool {
        return path.withCString { pointer in
            fc_init_index(pointer)
        }
    }

    public static func close() {
        fc_close_index()
    }

    public struct FileMeta {
        public let path: String
        public let name: String
        public let ext: String?
        public let modifiedAt: Int64
        public let size: UInt64
        public let inode: UInt64
        public let dev: UInt64

        public init(path: String, name: String, ext: String?, modifiedAt: Int64, size: UInt64, inode: UInt64, dev: UInt64) {
            self.path = path
            self.name = name
            self.ext = ext
            self.modifiedAt = modifiedAt
            self.size = size
            self.inode = inode
            self.dev = dev
        }
    }

    public static func shouldReindex(meta: FileMeta) -> Bool {
        var should = true

        meta.path.withCString { pathPtr in
            meta.name.withCString { namePtr in
                let extCString = meta.ext.map { Array($0.utf8CString) }
                var extBuffer = extCString

                should = withOptionalCStringBuffer(&extBuffer) { extPtr in
                    var cMeta = FCFileMeta(
                        path: pathPtr,
                        name: namePtr,
                        ext: extPtr,
                        mtime: meta.modifiedAt,
                        size: meta.size,
                        inode: meta.inode,
                        dev: meta.dev
                    )

                    return fc_should_reindex(&cMeta)
                }
            }
        }

        return should
    }

    @discardableResult
    public static func addOrUpdate(meta: FileMeta, content: String?) -> Bool {
        var success = false

        meta.path.withCString { pathPtr in
            meta.name.withCString { namePtr in
                let extCString = meta.ext.map { Array($0.utf8CString) }
                var extBuffer = extCString

                success = withOptionalCStringBuffer(&extBuffer) { extPtr in
                    var cMeta = FCFileMeta(
                        path: pathPtr,
                        name: namePtr,
                        ext: extPtr,
                        mtime: meta.modifiedAt,
                        size: meta.size,
                        inode: meta.inode,
                        dev: meta.dev
                    )

                    if let content {
                        var contentBuffer = Array(content.utf8CString)
                        return contentBuffer.withUnsafeMutableBufferPointer { pointer in
                            fc_add_or_update(&cMeta, pointer.baseAddress)
                        }
                    } else {
                        return fc_add_or_update(&cMeta, nil)
                    }
                }
            }
        }

        return success
    }

    @discardableResult
    public static func commitAndRefresh() -> Bool {
        fc_commit_and_refresh()
    }

    public static func search(
        _ term: String,
        scope: Scope = .both,
        glob: String? = nil,
        limit: Int32 = 50,
        sortByModifiedDescending: Bool = true
    ) -> [Hit] {
        var termBuffer: [CChar] = Array(term.utf8CString)
        var globBuffer: [CChar]? = glob.map { Array($0.utf8CString) }

        return termBuffer.withUnsafeMutableBufferPointer { termPointer in
            let qPtr = termPointer.baseAddress
            return withOptionalCStringBuffer(&globBuffer) { globPtr in
                var query = FCQuery(
                    q: qPtr,
                    glob: globPtr,
                    scope: scope.rawValue,
                    limit: limit
                )

                var results = fc_search(&query)
                defer { fc_free_results(&results) }

                guard results.count > 0, let base = results.hits else {
                    return []
                }

                let buffer = UnsafeBufferPointer(start: base, count: Int(results.count))
                let hits = buffer.compactMap { raw -> Hit? in
                    guard let pathPtr = raw.path, let namePtr = raw.name else {
                        return nil
                    }
                    let path = String(cString: pathPtr)
                    let name = String(cString: namePtr)
                    return Hit(path: path, name: name, mtime: raw.mtime, size: raw.size, score: raw.score)
                }

                if sortByModifiedDescending {
                    return hits.sorted { $0.mtime > $1.mtime }
                }
                return hits
            }
        }
    }
}

private func withOptionalCStringBuffer<R>(
    _ buffer: inout [CChar]?,
    _ body: (UnsafeMutablePointer<CChar>?) -> R
) -> R {
    if var existing = buffer {
        let result = existing.withUnsafeMutableBufferPointer { pointer in
            body(pointer.baseAddress)
        }
        buffer = existing
        return result
    }
    return body(nil)
}
