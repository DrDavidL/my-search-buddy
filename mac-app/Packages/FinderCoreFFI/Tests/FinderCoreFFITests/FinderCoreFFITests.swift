import XCTest
@testable import FinderCoreFFI

final class FinderCoreFFITests: XCTestCase {
    func testRoundtripWhenLibraryAvailable() throws {
        let dylibPath = FinderCoreFFI.defaultLibraryPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            throw XCTSkip("finder-core dylib not found at \(dylibPath). Build the Rust library first.")
        }

        let ffi = try FinderCoreFFI(libraryPath: dylibPath)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let indexPath = tempDir.appendingPathComponent("index").path
        XCTAssertNoThrow(try ffi.initIndex(at: indexPath))

        let fileURL = tempDir.appendingPathComponent("hello.txt")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertNoThrow(try ffi.addOrUpdate(
            path: fileURL.path,
            name: fileURL.lastPathComponent,
            ext: fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension,
            modifiedAt: 0,
            size: 11,
            inode: 0,
            dev: 0,
            content: "hello world"
        ))

        XCTAssertNoThrow(try ffi.commit())

        let hits = try ffi.search(term: "hello")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.path, fileURL.path)
    }
}
