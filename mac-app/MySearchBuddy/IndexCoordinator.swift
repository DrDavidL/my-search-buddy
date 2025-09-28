import Foundation
import FinderCoreFFI
import SwiftUI

final class IndexCoordinator: ObservableObject {
    @Published var isIndexing = false
    @Published var status: String = "Idle"
    @Published var filesIndexed: Int = 0
    @Published var lastIndexDate: Date?
    @Published private(set) var samplingPolicy = ContentCoverageSettings.defaultSamplingPolicy()

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

    func applySamplingPolicy(_ policy: ContentSamplingPolicy) {
        samplingPolicy = policy
    }

    func startIndexing(roots: [URL]) {
        guard !roots.isEmpty else { return }
        cancel()

        isIndexing = true
        status = "Preparing…"
        filesIndexed = 0

        let policy = samplingPolicy

        FinderCore.close()
        FinderCore.initIndex(at: indexDirectory.path)

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let startTime = Date()

            var totalProcessed = 0
            for root in roots {
                if Task.isCancelled { break }
                let processed = await self.indexRoot(root, startingFrom: totalProcessed, policy: policy)
                totalProcessed += processed
            }

            let finalTotal = totalProcessed
            await MainActor.run {
                self.isIndexing = false
                if Task.isCancelled {
                    self.status = "Indexing cancelled."
                } else {
                    let elapsed = Date().timeIntervalSince(startTime)
                    self.status = String(format: "Indexed %d files (%.1fs)", finalTotal, elapsed)
                    self.lastIndexDate = Date()
                }
                self.filesIndexed = finalTotal
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

    private func process(
        url: URL,
        keys: Set<URLResourceKey>,
        processed: inout Int,
        lastCommit: inout Date,
        policy: ContentSamplingPolicy
    ) -> Bool {
        var didUpdate = false

        autoreleasepool {
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true else {
                return
            }

            let size = Int64(values.fileSize ?? 0)
            if size <= 0 {
                return
            }

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

            guard FinderCore.shouldReindex(meta: meta) else {
                return
            }

            let content = loadContentIfPossible(from: url, size: size, policy: policy)

            if FinderCore.addOrUpdate(meta: meta, content: content) {
                processed += 1
                didUpdate = true
            }

            let now = Date()
            if now.timeIntervalSince(lastCommit) > 2.0 || (processed % 1000 == 0 && processed > 0) {
                FinderCore.commitAndRefresh()
                lastCommit = now
            }
        }

        return didUpdate
    }

    private func indexRoot(
        _ root: URL,
        startingFrom totalProcessed: Int,
        policy: ContentSamplingPolicy
    ) async -> Int {
        var processed = 0
        guard root.startAccessingSecurityScopedResource() else { return 0 }
        defer { root.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .producesRelativePathURLs]) else {
            return 0
        }

        var lastCommit = Date()
        while let entry = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }

            if process(url: entry,
                       keys: keys,
                       processed: &processed,
                       lastCommit: &lastCommit,
                       policy: policy) {
                let runningTotal = totalProcessed + processed
                if processed % 50 == 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.filesIndexed = runningTotal
                        self.status = "Indexed \(runningTotal) files…"
                    }
                }
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

    func resetIndex() {
        cancel()
        FinderCore.close()
        try? FileManager.default.removeItem(at: indexDirectory)
        ensureIndexDirectoryExists()
        FinderCore.initIndex(at: indexDirectory.path)
        filesIndexed = 0
        status = "Index reset"
        lastIndexDate = nil
    }

    private func loadContentIfPossible(
        from url: URL,
        size: Int64,
        policy: ContentSamplingPolicy
    ) -> String? {
        guard size > 0 else { return nil }
        guard size <= policy.maxBytes else { return nil }

        if !policy.isEnabled {
            return readFullContent(from: url)
        }

        if size <= policy.smallFileThreshold {
            return readFullContent(from: url)
        }

        let sampleBudget = min(Int64(Double(size) * policy.coverageFraction), min(policy.maxBytes, size))
        if sampleBudget <= 0 || sampleBudget >= size {
            return readFullContent(from: url)
        }

        return readSampledContent(from: url, size: size, policy: policy, budget: sampleBudget)
    }

    private func readFullContent(from url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
            if isLikelyBinary(data: data) { return nil }
            return decode(data)
        } catch {
            NSLog("[Index] Failed to read content for %@: %@", url.path, error.localizedDescription)
            return nil
        }
    }

    private func readSampledContent(
        from url: URL,
        size: Int64,
        policy: ContentSamplingPolicy,
        budget: Int64
    ) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var headBytes = min(Int64(Double(size) * policy.headFraction), budget)
            var tailBytes = max(budget - headBytes, 0)

            if headBytes < policy.minHeadBytes && budget >= policy.minHeadBytes {
                headBytes = min(policy.minHeadBytes, budget)
                tailBytes = max(budget - headBytes, 0)
            }

            if tailBytes < policy.minTailBytes && (budget - headBytes) >= policy.minTailBytes {
                tailBytes = min(policy.minTailBytes, budget - headBytes)
                headBytes = max(budget - tailBytes, 0)
            }

            headBytes = min(headBytes, size)
            tailBytes = min(tailBytes, max(0, budget - headBytes))

            if headBytes + tailBytes >= size {
                return readFullContent(from: url)
            }

            let headData = try handle.read(upToCount: Int(headBytes)) ?? Data()
            if isLikelyBinary(data: headData, sniffLimit: policy.sniffBytes) { return nil }

            guard tailBytes > 0 else {
                return decode(headData)
            }

            let tailStart = max(Int64(0), size - tailBytes)
            try handle.seek(toOffset: UInt64(tailStart))
            var tailData = try handle.readToEnd() ?? Data()
            if tailData.count > Int(tailBytes) {
                tailData = tailData.suffix(Int(tailBytes))
            }

            if isLikelyBinary(data: tailData, sniffLimit: policy.sniffBytes) {
                return decode(headData)
            }

            let headString = decode(headData)
            let tailString = decode(tailData)

            if tailString.isEmpty {
                return headString
            }
            if headString.isEmpty {
                return tailString
            }
            return headString + "\n…\n" + tailString
        } catch {
            NSLog("[Index] Failed to read sampled content for %@: %@", url.path, error.localizedDescription)
            return nil
        }
    }

    private func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func isLikelyBinary(data: Data, sniffLimit: Int = 8_192) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(sniffLimit)
        if sample.contains(0) { return true }
        let nonPrintable = sample.reduce(0) { partial, byte -> Int in
            if byte < 9 || (byte > 13 && byte < 32) {
                return partial + 1
            }
            return partial
        }
        return Double(nonPrintable) / Double(sample.count) > 0.10
    }
}

extension IndexCoordinator: @unchecked Sendable {}
