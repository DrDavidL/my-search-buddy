import Foundation
import FinderCoreShims
import Darwin

public enum FinderCoreScope: Int32 {
    case name = 0
    case content = 1
    case both = 2

    var domain: Int32 { rawValue }
}

public struct FinderCoreHit: Sendable, Equatable {
    public let path: String
    public let name: String
    public let modifiedAt: Int64
    public let size: UInt64
    public let score: Float
}

public enum FinderCoreError: Error, CustomStringConvertible {
    case libraryNotFound(String)
    case symbolMissing(String)
    case callFailed(String)

    public var description: String {
        switch self {
        case .libraryNotFound(let path):
            return "finder-core dynamic library not found at \(path)"
        case .symbolMissing(let name):
            return "missing required symbol \(name) in finder-core library"
        case .callFailed(let context):
            return "finder-core call failed: \(context)"
        }
    }
}

final class FinderCoreDynamicLibrary {
    private let handle: UnsafeMutableRawPointer

    let initIndex: @convention(c) (UnsafePointer<CChar>) -> Bool
    let closeIndex: @convention(c) () -> Void
    let shouldReindex: @convention(c) (UnsafePointer<FCFileMeta>?) -> Bool
    let addOrUpdate: @convention(c) (UnsafePointer<FCFileMeta>?, UnsafePointer<CChar>?) -> Bool
    let commitAndRefresh: @convention(c) () -> Bool
    let search: @convention(c) (UnsafePointer<FCQuery>?) -> FCResults
    let freeResults: @convention(c) (UnsafeMutablePointer<FCResults>?) -> Void

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw FinderCoreError.libraryNotFound(path)
        }
        self.handle = handle

        self.initIndex = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_init_index", handle: handle)
        self.closeIndex = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_close_index", handle: handle)
        self.shouldReindex = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_should_reindex", handle: handle)
        self.addOrUpdate = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_add_or_update", handle: handle)
        self.commitAndRefresh = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_commit_and_refresh", handle: handle)
        self.search = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_search", handle: handle)
        self.freeResults = try FinderCoreDynamicLibrary.loadSymbol(named: "fc_free_results", handle: handle)
    }

    deinit {
        dlclose(handle)
    }

    private static func loadSymbol<T>(named name: String, handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw FinderCoreError.symbolMissing(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

public final class FinderCoreFFI {
    private let lib: FinderCoreDynamicLibrary

    public init(libraryPath: String? = nil) throws {
        let path = libraryPath ?? FinderCoreFFI.defaultLibraryPath()
        self.lib = try FinderCoreDynamicLibrary(path: path)
    }

    deinit {
        lib.closeIndex()
    }

    public static func defaultLibraryPath() -> String {
        if let override = ProcessInfo.processInfo.environment["FINDER_CORE_DYLIB"] {
            return override
        }
        // Default to workspace target directories (debug first, then release).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FinderCoreFFI.swift
            .deletingLastPathComponent() // FinderCoreFFI
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // FinderCoreFFI package root
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // mac-app

        let debugPath = root
            .appendingPathComponent("target")
            .appendingPathComponent("debug")
            .appendingPathComponent("libfinder_core.dylib")

        if FileManager.default.fileExists(atPath: debugPath.path) {
            return debugPath.path
        }

        let releasePath = root
            .appendingPathComponent("target")
            .appendingPathComponent("release")
            .appendingPathComponent("libfinder_core.dylib")

        return releasePath.path
    }

    @discardableResult
    public func initIndex(at path: String) throws -> Bool {
        return try withCString(path) { pointer in
            guard lib.initIndex(pointer) else {
                throw FinderCoreError.callFailed("init_index")
            }
            return true
        }
    }

    public func shouldReindex(
        path: String,
        name: String,
        ext: String?,
        modifiedAt: Int64,
        size: UInt64,
        inode: UInt64,
        dev: UInt64
    ) throws -> Bool {
        try withFileMeta(
            path: path,
            name: name,
            ext: ext,
            modifiedAt: modifiedAt,
            size: size,
            inode: inode,
            dev: dev
        ) { meta in
            withUnsafePointer(to: &meta) { pointer in
                lib.shouldReindex(pointer)
            }
        }
    }

    @discardableResult
    public func addOrUpdate(
        path: String,
        name: String,
        ext: String?,
        modifiedAt: Int64,
        size: UInt64,
        inode: UInt64,
        dev: UInt64,
        content: String?
    ) throws -> Bool {
        try withFileMeta(
            path: path,
            name: name,
            ext: ext,
            modifiedAt: modifiedAt,
            size: size,
            inode: inode,
            dev: dev
        ) { meta in
            if let content {
                return try content.utf8CString.withUnsafeBufferPointer { buffer in
                    try callAddOrUpdate(meta: &meta, contentPtr: buffer.baseAddress)
                }
            } else {
                return try callAddOrUpdate(meta: &meta, contentPtr: nil)
            }
        }
    }

    private func callAddOrUpdate(meta: inout FCFileMeta, contentPtr: UnsafePointer<CChar>?) throws -> Bool {
        let success = withUnsafePointer(to: &meta) { pointer in
            lib.addOrUpdate(pointer, contentPtr)
        }
        if !success {
            throw FinderCoreError.callFailed("add_or_update")
        }
        return true
    }

    @discardableResult
    public func commit() throws -> Bool {
        guard lib.commitAndRefresh() else {
            throw FinderCoreError.callFailed("commit_and_refresh")
        }
        return true
    }

    public func search(term: String, scope: FinderCoreScope = .both, glob: String? = nil, limit: Int32 = 50) throws -> [FinderCoreHit] {
        var termBuffer: [CChar] = Array(term.utf8CString)
        var globBuffer: [CChar]? = glob.map { Array($0.utf8CString) }

        return try termBuffer.withUnsafeMutableBufferPointer { termPtr -> [FinderCoreHit] in
            let termBase = termPtr.baseAddress
            return try withOptionalMutableCStringBuffer(&globBuffer) { globBase in
                var query = FCQuery(
                    q: termBase,
                    glob: globBase,
                    scope: scope.domain,
                    limit: limit
                )

                let results = withUnsafePointer(to: &query) { pointer in
                    lib.search(pointer)
                }
                return try handleResults(results)
            }
        }
    }

    private func handleResults(_ results: FCResults) throws -> [FinderCoreHit] {
        guard results.count > 0, let basePtr = results.hits else {
            return []
        }

        let buffer = UnsafeBufferPointer(start: basePtr, count: Int(results.count))
        let hits: [FinderCoreHit] = buffer.compactMap { raw in
            guard
                let pathPtr = raw.path,
                let namePtr = raw.name,
                let path = String(validatingCString: pathPtr),
                let name = String(validatingCString: namePtr)
            else {
                return nil
            }
            return FinderCoreHit(
                path: path,
                name: name,
                modifiedAt: raw.mtime,
                size: raw.size,
                score: raw.score
            )
        }

        var mutableResults = results
        lib.freeResults(&mutableResults)
        return hits
    }
}

private extension FinderCoreFFI {
    func withCString<T>(_ string: String, _ body: (UnsafePointer<CChar>) throws -> T) throws -> T {
        return try string.utf8CString.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                throw FinderCoreError.callFailed("invalid utf8 string")
            }
            return try body(base)
        }
    }

    func withFileMeta<T>(
        path: String,
        name: String,
        ext: String?,
        modifiedAt: Int64,
        size: UInt64,
        inode: UInt64,
        dev: UInt64,
        _ body: (inout FCFileMeta) throws -> T
    ) throws -> T {
        var extBuffer: [CChar]? = ext.map { Array($0.utf8CString) }
        return try withCString(path) { pathPtr in
            try withCString(name) { namePtr in
                try withOptionalMutableCStringBuffer(&extBuffer) { extPtr in
                    var meta = FCFileMeta(
                        path: pathPtr,
                        name: namePtr,
                        ext: extPtr,
                        mtime: modifiedAt,
                        size: size,
                        inode: inode,
                        dev: dev
                    )
                    return try body(&meta)
                }
            }
        }
    }

    func withOptionalMutableCStringBuffer<T>(
        _ value: inout [CChar]?,
        _ body: (UnsafeMutablePointer<CChar>?) throws -> T
    ) rethrows -> T {
        if var value {
            return try value.withUnsafeMutableBufferPointer { buffer in
                try body(buffer.baseAddress)
            }
        }
        return try body(nil)
    }
}
