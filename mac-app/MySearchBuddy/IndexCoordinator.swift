import Foundation
import FinderCoreFFI
import SwiftUI

@MainActor
final class IndexCoordinator: ObservableObject {
    @Published var isIndexing = false
    @Published var status: String = "Idle"
    @Published var filesIndexed: Int = 0

    private var task: Task<Void, Never>?
    private let indexDirectory: URL

    init() {
        indexDirectory = IndexCoordinator.defaultIndexDirectory()
        ensureIndexDirectoryExists()
        FinderCore.initIndex(at: indexDirectory.path)
    }

    static func defaultIndexDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return base.appendingPathComponent("MySearchBuddy/Index", isDirectory: true)
    }

    var indexDirectoryURL: URL { indexDirectory }

    func startIndexing(roots: [URL]) {
        guard !roots.isEmpty else { return }
        cancel()

        isIndexing = true
        status = "Preparing…"
        filesIndexed = 0

        FinderCore.close()
        FinderCore.initIndex(at: indexDirectory.path)

        task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let startTime = Date()

            var totalProcessed = 0
            for root in roots {
                if Task.isCancelled { break }
                let processed = await self.indexRoot(root, startingFrom: totalProcessed)
                totalProcessed += processed
            }

            await MainActor.run {
                self.isIndexing = false
                if Task.isCancelled {
                    self.status = "Indexing cancelled."
                } else {
                    let elapsed = Date().timeIntervalSince(startTime)
                    self.status = String(format: "Indexed %d files (%.1fs)", totalProcessed, elapsed)
                }
                self.filesIndexed = totalProcessed
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isIndexing {
            status = "Cancelling…"
        }
    }

    private func ensureIndexDirectoryExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
    }

    private func indexRoot(_ root: URL, startingFrom totalProcessed: Int) async -> Int {
        var processed = 0
        guard root.startAccessingSecurityScopedResource() else { return 0 }
        defer { root.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .producesRelativePathURLs]) else {
            return 0
        }

        var lastCommit = Date()
        for case let url as URL in enumerator {
            if Task.isCancelled { break }

            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true else {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            if size <= 0 || size > 1_572_864 { continue }

            let modificationDate = values.contentModificationDate ?? Date()
            let meta = FinderCore.FileMeta(
                path: url.path,
                name: url.lastPathComponent,
                ext: url.pathExtension.isEmpty ? nil : url.pathExtension,
                modifiedAt: Int64(modificationDate.timeIntervalSince1970),
                size: UInt64(size),
                inode: 0,
                dev: 0
            )

            if FinderCore.addOrUpdate(meta: meta, content: nil) {
                processed += 1
                let runningTotal = totalProcessed + processed
                if processed % 50 == 0 {
                    await MainActor.run {
                        self.filesIndexed = runningTotal
                        self.status = "Indexed \(runningTotal) files…"
                    }
                }
            }

            let now = Date()
            if now.timeIntervalSince(lastCommit) > 2.0 || (processed % 1000 == 0 && processed > 0) {
                FinderCore.commitAndRefresh()
                lastCommit = now
            }
        }

        FinderCore.commitAndRefresh()
        let finalTotal = totalProcessed + processed
        await MainActor.run {
            self.filesIndexed = finalTotal
            self.status = "Indexed \(finalTotal) files…"
        }
        return processed
    }
}
