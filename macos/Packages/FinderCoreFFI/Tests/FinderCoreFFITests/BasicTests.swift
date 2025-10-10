import XCTest
import Foundation
@testable import FinderCoreFFI

final class BasicTests: XCTestCase {
    func testInitSearch() throws {
        let dylibPath = FinderCoreFFI.defaultLibraryPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            throw XCTSkip("finder-core dylib not found at \(dylibPath). Build the Rust library first.")
        }

        XCTAssertTrue(FinderCore.initIndex(at: NSTemporaryDirectory()))
        let hits = FinderCore.search("README", scope: .name, limit: 5)
        XCTAssertNotNil(hits)
        FinderCore.close()
    }
}
