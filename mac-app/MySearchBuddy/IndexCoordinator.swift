import Foundation
import FinderCoreFFI
import SwiftUI

final class IndexCoordinator: ObservableObject {
    @Published var isIndexing = false
    @Published var status: String = "Idle"
    @Published var filesIndexed: Int = 0
    @Published var lastIndexDate: Date?
    @Published private(set) var samplingPolicy = ContentCoverageSettings.defaultSamplingPolicy()
    @Published private(set) var cloudPlaceholders: Set<String> = []
    @Published private(set) var currentPhase: IndexPhase?

    private var task: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private let indexDirectory: URL
    private let defaults = UserDefaults.standard
    private let lastIndexDefaultsKey = "indexCoordinator.lastIndexDate"
    private let bucketProgressKey = "indexCoordinator.bucketProgress"
    private let scheduleEnabledKey = "indexCoordinator.scheduleWindowEnabled"
    private let autoIndexInterval: TimeInterval = 60
    private var lastAutoIndexAttempt: Date?
    private let scheduleQueue = DispatchQueue(label: "com.mysearchbuddy.scheduleQueue")
    private var scheduledWorkItem: DispatchWorkItem?

    @Published var scheduleWindowEnabled: Bool = false {
        didSet {
            defaults.set(scheduleWindowEnabled, forKey: scheduleEnabledKey)
            if !scheduleWindowEnabled {
                cancelScheduledRun()
            }
        }
    }
    @Published private(set) var nextScheduledRun: Date?

    enum IndexMode {
        case incremental
        case full
    }

    enum IndexPhase {
        case initial      // Fast: only recent files (last 90 days)
        case background   // Slow: older files, runs in background
    }

    private enum RecencyBucket: Int, CaseIterable {
        case last3Months
        case last6Months
        case last12Months
        case older

        static let secondsInDay: TimeInterval = 24 * 60 * 60

        static func bucket(for age: TimeInterval) -> RecencyBucket {
            if age <= 90 * secondsInDay {
                return .last3Months
            } else if age <= 180 * secondsInDay {
                return .last6Months
            } else if age <= 365 * secondsInDay {
                return .last12Months
            } else {
                return .older
            }
        }

        var startStatus: String {
            switch self {
            case .last3Months: return "Indexing last 90 days…"
            case .last6Months: return "Indexing last 6 months…"
            case .last12Months: return "Indexing last 12 months…"
            case .older: return "Indexing older files…"
            }
        }
    }

    private struct PendingFile {
        let url: URL
        let size: Int64
        let modificationDate: Date
        let isCloudItem: Bool
        let downloadStatus: URLUbiquitousItemDownloadingStatus
    }

    init() {
        NSLog("[IndexCoordinator] Initializing")
        indexDirectory = IndexCoordinator.defaultIndexDirectory()
        ensureIndexDirectoryExists()
        NSLog("[IndexCoordinator] Calling FinderCore.initIndex")
        FinderCore.initIndex(at: indexDirectory.path)
        NSLog("[IndexCoordinator] FinderCore.initIndex completed")

        if let storedDate = defaults.object(forKey: lastIndexDefaultsKey) as? Date {
            lastIndexDate = storedDate
        }
        scheduleWindowEnabled = defaults.bool(forKey: scheduleEnabledKey)
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

    func startIndexing(roots: [URL], mode: IndexMode = .incremental, phase: IndexPhase = .initial, scheduled: Bool = false) {
        guard !roots.isEmpty else {
            NSLog("[Index] startIndexing called with empty roots")
            return
        }
        NSLog("[Index] startIndexing called with %d roots, mode: %@, phase: %@",
              roots.count,
              mode == .full ? "full" : "incremental",
              phase == .initial ? "initial" : "background")

        if phase == .initial {
            cancel()  // Cancel any existing tasks when starting fresh
        }

        if scheduleWindowEnabled && !scheduled && mode == .incremental && phase == .initial {
            if scheduleIndexingIfNeeded(roots: roots, mode: mode) {
                return
            }
        }

        isIndexing = true
        currentPhase = phase

        if phase == .initial {
            status = "Indexing recent files (quick)…"
            filesIndexed = 0
        } else {
            status = "Indexing older files in background…"
        }

        let policy = samplingPolicy

        if mode == .full && phase == .initial {
            FinderCore.close()
            FinderCore.initIndex(at: indexDirectory.path)
        }

        let baseline = mode == .incremental ? lastIndexDate : nil
        let priority: TaskPriority = phase == .initial ? .userInitiated : .background

        task = Task.detached(priority: priority) { [weak self] in
            guard let self else { return }
            let startTime = Date()

            // Prioritize Documents folder for faster access to recent important files
            let sortedRoots = roots.sorted { lhs, rhs in
                let lhsIsDocuments = lhs.lastPathComponent == "Documents"
                let rhsIsDocuments = rhs.lastPathComponent == "Documents"
                if lhsIsDocuments != rhsIsDocuments {
                    return lhsIsDocuments  // Documents first
                }
                return lhs.path < rhs.path  // Otherwise alphabetical
            }

            var totalProcessed = 0

            // Process roots in order (Documents first for recent files)
            for root in sortedRoots {
                if Task.isCancelled { break }
                let processed = await self.indexRoot(
                    root,
                    startingFrom: totalProcessed,
                    policy: policy,
                    since: baseline,
                    mode: mode,
                    phase: phase
                )
                totalProcessed += processed
            }

            let finalTotal = totalProcessed
            await MainActor.run {
                self.isIndexing = false
                self.currentPhase = nil
                if Task.isCancelled {
                    self.status = "Indexing cancelled."
                } else {
                    let elapsed = Date().timeIntervalSince(startTime)
                    if phase == .initial {
                        if finalTotal == 0 {
                            self.status = String(format: "Recent files up to date (%.1fs)", elapsed)
                        } else {
                            self.status = String(format: "Indexed %d recent files (%.1fs)", finalTotal, elapsed)
                        }
                        // Auto-start background indexing after initial phase completes
                        NSLog("[Index] Initial phase complete, starting background indexing")
                        self.startIndexing(roots: roots, mode: mode, phase: .background, scheduled: scheduled)
                    } else {
                        if finalTotal == 0 {
                            self.status = "Index fully up to date"
                        } else {
                            self.status = String(format: "Indexed %d total files (%.1fs)", finalTotal, elapsed)
                        }
                        let completionDate = Date()
                        self.lastIndexDate = completionDate
                        self.defaults.set(completionDate, forKey: self.lastIndexDefaultsKey)
                    }
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
        cancelScheduledRun()
    }

    @MainActor
    func requestIncrementalIndexIfNeeded(roots: [URL]) {
        NSLog("[Index] requestIncrementalIndexIfNeeded called with %d roots", roots.count)
        guard !roots.isEmpty else {
            NSLog("[Index] requestIncrementalIndexIfNeeded: roots empty, returning")
            return
        }
        guard !isIndexing else {
            NSLog("[Index] requestIncrementalIndexIfNeeded: already indexing, returning")
            return
        }

        let now = Date()
        if let lastAttempt = lastAutoIndexAttempt, now.timeIntervalSince(lastAttempt) < autoIndexInterval {
            return
        }
        lastAutoIndexAttempt = now

        if let lastRun = lastIndexDate, now.timeIntervalSince(lastRun) < autoIndexInterval {
            return
        }

        startIndexing(roots: roots, mode: .incremental)
    }

    private func cancelScheduledRun() {
        scheduleQueue.sync {
            scheduledWorkItem?.cancel()
            scheduledWorkItem = nil
        }
        Task { @MainActor in
            nextScheduledRun = nil
        }
    }

    private func isWithinScheduleWindow(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let totalMinutes = hour * 60 + minute
        let startMinutes = 2 * 60
        let endMinutes = 4 * 60
        return totalMinutes >= startMinutes && totalMinutes < endMinutes
    }

    private func nextScheduleDate(after date: Date) -> Date {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = 2
        comps.minute = 0
        comps.second = 0
        var next = calendar.date(from: comps) ?? date
        if next <= date {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? date
        }
        return next
    }

    private func scheduleIndexingIfNeeded(roots: [URL], mode: IndexMode) -> Bool {
        let now = Date()
        if isWithinScheduleWindow(now) {
            return false
        }

        let target = nextScheduleDate(after: now)
        cancelScheduledRun()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.nextScheduledRun = nil
                self.startIndexing(roots: roots, mode: mode, scheduled: true)
            }
        }

        scheduleQueue.sync {
            scheduledWorkItem = workItem
        }

        Task { @MainActor in
            nextScheduledRun = target
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .medium
            status = "Scheduled for \(formatter.string(from: target))"
        }

        let delay = target.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
        return true
    }

    func isCloudPlaceholder(path: String) -> Bool {
        cloudPlaceholders.contains(path)
    }

    private func ensureIndexDirectoryExists() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("[Index] Failed to create index directory at %@: %@", indexDirectory.path, error.localizedDescription)
        }
    }

    private func process(
        pending: PendingFile,
        cutoff: Date?,
        processed: inout Int,
        lastCommit: inout Date,
        policy: ContentSamplingPolicy
    ) -> Bool {
        var didUpdate = false

        autoreleasepool {
            if let cutoff, pending.modificationDate <= cutoff {
                return
            }

            let cloudPlaceholder = pending.isCloudItem && pending.downloadStatus != .current
            let urlPath = pending.url.path

            if cloudPlaceholder {
                Task { @MainActor [weak self] in
                    self?.cloudPlaceholders.insert(urlPath)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.cloudPlaceholders.remove(urlPath)
                }
            }

            if pending.size <= 0 && !cloudPlaceholder {
                return
            }

            let effectiveSize = max(pending.size, 0)

            let meta = FinderCore.FileMeta(
                path: pending.url.path,
                name: pending.url.lastPathComponent,
                ext: pending.url.pathExtension.isEmpty ? nil : pending.url.pathExtension,
                modifiedAt: Int64(pending.modificationDate.timeIntervalSince1970),
                size: UInt64(effectiveSize),
                inode: 0,
                dev: 0
            )

            guard FinderCore.shouldReindex(meta: meta) else {
                return
            }

            let content: String?
            if cloudPlaceholder {
                content = nil
            } else {
                content = loadContentIfPossible(from: pending.url, size: Int64(effectiveSize), policy: policy)
            }

            if FinderCore.addOrUpdate(meta: meta, content: content) {
                processed += 1
                didUpdate = true
                if processed == 1 || processed == 10 || processed == 100 || processed % 500 == 0 {
                    NSLog("[Index] ✅ Indexed %d files (latest: %@)", processed, pending.url.lastPathComponent)
                }
            }

            let now = Date()
            if now.timeIntervalSince(lastCommit) > 2.0 || (processed % 1000 == 0 && processed > 0) {
                NSLog("[Index] Auto-committing after %d files", processed)
                FinderCore.commitAndRefresh()
                lastCommit = now
            }
        }

        return didUpdate
    }

    private func indexRoot(
        _ root: URL,
        startingFrom totalProcessed: Int,
        policy: ContentSamplingPolicy,
        since cutoff: Date?,
        mode: IndexMode,
        phase: IndexPhase
    ) async -> Int {
        NSLog("[Index] indexRoot starting for: %@", root.path)
        var processed = 0
        guard root.startAccessingSecurityScopedResource() else {
            NSLog("[Index] Failed to access security-scoped resource for: %@", root.path)
            return 0
        }
        defer { root.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .producesRelativePathURLs]) else {
            NSLog("[Index] Failed to create enumerator for: %@", root.path)
            return 0
        }

        NSLog("[Index] Starting file enumeration for: %@ (phase: %@)", root.path, phase == .initial ? "initial" : "background")
        var bucketed: [[PendingFile]] = Array(repeating: [], count: RecencyBucket.allCases.count)
        let now = Date()

        var lastCommit = Date()
        var fileCount = 0

        // Limit enumeration in initial phase for faster startup
        let enumerationLimit: Int? = phase == .initial ? 20000 : nil

        while let entry = enumerator.nextObject() as? URL {
            fileCount += 1
            if fileCount % 1000 == 0 {
                NSLog("[Index] Enumerated %d files so far from %@", fileCount, root.path)
            }
            if Task.isCancelled { break }

            // In initial phase, limit enumeration for faster startup
            if let limit = enumerationLimit, fileCount >= limit {
                NSLog("[Index] Hit enumeration limit (%d files) in initial phase for %@", limit, root.path)
                break
            }

            guard let values = try? entry.resourceValues(forKeys: keys), values.isDirectory != true else {
                continue
            }

            let modificationDate = values.contentModificationDate ?? now
            let age = now.timeIntervalSince(modificationDate)
            let bucket = RecencyBucket.bucket(for: age)

            let size = Int64(values.fileSize ?? 0)
            let isCloudItem = values.isUbiquitousItem ?? false
            let downloadStatus = values.ubiquitousItemDownloadingStatus ?? .notDownloaded

            let pending = PendingFile(
                url: entry,
                size: size,
                modificationDate: modificationDate,
                isCloudItem: isCloudItem,
                downloadStatus: downloadStatus
            )

            bucketed[bucket.rawValue].append(pending)
        }

        NSLog("[Index] Enumeration complete. Total files found: %d", fileCount)
        let totalBucketed = bucketed.reduce(0) { $0 + $1.count }
        NSLog("[Index] Files bucketed: %d", totalBucketed)

        let rootKey = root.path
        let startBucketIndex = mode == .full ? progressIndex(for: rootKey) : 0

        var cancelled = false

        // Determine which buckets to process based on phase
        let bucketsToProcess: [RecencyBucket]
        if phase == .initial {
            // Initial phase: only recent files (last 90 days)
            bucketsToProcess = [.last3Months]
        } else {
            // Background phase: older files
            bucketsToProcess = [.last6Months, .last12Months, .older]
        }

        // Use longer commit interval for background phase
        let commitInterval: TimeInterval = phase == .initial ? 2.0 : 1800.0  // 2s for initial, 30min for background

        bucketLoop: for bucket in bucketsToProcess {
            if Task.isCancelled { break }
            if bucket.rawValue < startBucketIndex { continue }
            let files = bucketed[bucket.rawValue]
            if files.isEmpty { continue }

            NSLog("[Index] Processing bucket %@ with %d files (phase: %@)", bucket.startStatus, files.count, phase == .initial ? "initial" : "background")
            await MainActor.run {
                self.status = bucket.startStatus
            }

            var bucketProcessed = 0
            for pending in files {
                if Task.isCancelled {
                    cancelled = true
                    break bucketLoop
                }

                if process(pending: pending,
                           cutoff: cutoff,
                           processed: &processed,
                           lastCommit: &lastCommit,
                           policy: policy) {
                    bucketProcessed += 1
                    let runningTotal = totalProcessed + processed
                    if processed % 50 == 0 {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.filesIndexed = runningTotal
                            if phase == .initial {
                                self.status = "Indexed \(runningTotal) recent files…"
                            } else {
                                self.status = "Indexed \(runningTotal) files in background…"
                            }
                        }
                    }
                }

                // Periodic commits based on phase
                let now = Date()
                if now.timeIntervalSince(lastCommit) > commitInterval {
                    NSLog("[Index] Periodic commit after %.0f seconds (%d files processed)", now.timeIntervalSince(lastCommit), processed)
                    FinderCore.commitAndRefresh()
                    lastCommit = now
                }
            }
            NSLog("[Index] Processed %d files from bucket %@", bucketProcessed, bucket.startStatus)

            // Commit after each bucket so results appear progressively
            NSLog("[Index] Committing after bucket %@", bucket.startStatus)
            FinderCore.commitAndRefresh()
            lastCommit = Date()

            if mode == .full {
                setProgressIndex(bucket.rawValue + 1, for: rootKey)
            }
        }
        let finalTotal = totalProcessed + processed
        let indexedAnything = processed > 0
        await MainActor.run {
            self.filesIndexed = finalTotal
            if indexedAnything {
                self.status = "Indexed \(finalTotal) files…"
            }
        }

        if mode == .full && !cancelled {
            setProgressIndex(nil, for: rootKey)
        }

        NSLog("[Index] indexRoot completed for %@, processed %d files", root.path, processed)
        return processed
    }

    func resetIndex() {
        cancel()
        FinderCore.close()

        do {
            try FileManager.default.removeItem(at: indexDirectory)
        } catch {
            NSLog("[Index] Failed to remove index directory: %@", error.localizedDescription)
        }

        ensureIndexDirectoryExists()

        if !FinderCore.initIndex(at: indexDirectory.path) {
            NSLog("[Index] Failed to reinitialize index after reset")
        }

        filesIndexed = 0
        status = "Index reset"
        lastIndexDate = nil
        defaults.removeObject(forKey: lastIndexDefaultsKey)
        cloudPlaceholders.removeAll()
        defaults.removeObject(forKey: bucketProgressKey)
        cancelScheduledRun()
    }

    /// Rebuild the index from scratch without showing "canceled" state
    func rebuildIndex(roots: [URL]) {
        // Cancel any running task silently
        task?.cancel()
        task = nil

        // Close and clear index
        FinderCore.close()
        do {
            try FileManager.default.removeItem(at: indexDirectory)
        } catch {
            NSLog("[Index] Failed to remove index directory: %@", error.localizedDescription)
        }

        ensureIndexDirectoryExists()

        if !FinderCore.initIndex(at: indexDirectory.path) {
            NSLog("[Index] Failed to reinitialize index after reset")
        }

        filesIndexed = 0
        lastIndexDate = nil
        defaults.removeObject(forKey: lastIndexDefaultsKey)
        cloudPlaceholders.removeAll()
        defaults.removeObject(forKey: bucketProgressKey)
        cancelScheduledRun()

        // Immediately start indexing (no intermediate canceled state)
        startIndexing(roots: roots, mode: .full)
    }

    private func progressIndex(for root: String) -> Int {
        let dict = defaults.dictionary(forKey: bucketProgressKey) as? [String: Int] ?? [:]
        return dict[root] ?? 0
    }

    private func setProgressIndex(_ index: Int?, for root: String) {
        var dict = defaults.dictionary(forKey: bucketProgressKey) as? [String: Int] ?? [:]
        if let index {
            dict[root] = index
        } else {
            dict.removeValue(forKey: root)
        }
        defaults.set(dict, forKey: bucketProgressKey)
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
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            NSLog("[Index] Failed to open file handle for %@: %@", url.path, error.localizedDescription)
            return nil
        }
        defer { try? handle.close() }

        do {
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
