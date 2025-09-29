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

    private var task: Task<Void, Never>?
    private let indexDirectory: URL
    private let defaults = UserDefaults.standard
    private let lastIndexDefaultsKey = "indexCoordinator.lastIndexDate"
    private let bucketProgressKey = "indexCoordinator.bucketProgress"
    private let scheduleEnabledKey = "indexCoordinator.scheduleWindowEnabled"
    private let autoIndexInterval: TimeInterval = 60
    private var lastAutoIndexAttempt: Date?
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
        indexDirectory = IndexCoordinator.defaultIndexDirectory()
        ensureIndexDirectoryExists()
        FinderCore.initIndex(at: indexDirectory.path)

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

    func startIndexing(roots: [URL], mode: IndexMode = .incremental, scheduled: Bool = false) {
        guard !roots.isEmpty else { return }
        cancel()

        if scheduleWindowEnabled && !scheduled && mode == .incremental {
            if scheduleIndexingIfNeeded(roots: roots, mode: mode) {
                return
            }
        }

        isIndexing = true
        status = mode == .full ? "Rebuilding index…" : "Checking for updates…"
        filesIndexed = 0

        let policy = samplingPolicy

        if mode == .full {
            FinderCore.close()
            FinderCore.initIndex(at: indexDirectory.path)
        }

        let baseline = mode == .incremental ? lastIndexDate : nil

        task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let startTime = Date()

            var totalProcessed = 0
            for root in roots {
                if Task.isCancelled { break }
                let processed = await self.indexRoot(
                    root,
                    startingFrom: totalProcessed,
                    policy: policy,
                    since: baseline,
                    mode: mode
                )
                totalProcessed += processed
            }

            let finalTotal = totalProcessed
            await MainActor.run {
                self.isIndexing = false
                if Task.isCancelled {
                    self.status = "Indexing cancelled."
                } else {
                    let elapsed = Date().timeIntervalSince(startTime)
                    if finalTotal == 0 {
                        self.status = String(format: "Index up to date (%.1fs)", elapsed)
                    } else {
                        self.status = String(format: "Indexed %d files (%.1fs)", finalTotal, elapsed)
                    }
                    let completionDate = Date()
                    self.lastIndexDate = completionDate
                    self.defaults.set(completionDate, forKey: self.lastIndexDefaultsKey)
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
        guard !roots.isEmpty else { return }
        guard !isIndexing else { return }

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
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
        nextScheduledRun = nil
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
            self.nextScheduledRun = nil
            self.startIndexing(roots: roots, mode: mode, scheduled: true)
        }
        scheduledWorkItem = workItem
        nextScheduledRun = target

        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .medium
            self.status = "Scheduled for \(formatter.string(from: target))"
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
        try? fm.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
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

            if cloudPlaceholder {
                DispatchQueue.main.async { [weak self] in
                    self?.cloudPlaceholders.insert(pending.url.path)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.cloudPlaceholders.remove(pending.url.path)
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
        policy: ContentSamplingPolicy,
        since cutoff: Date?,
        mode: IndexMode
    ) async -> Int {
        var processed = 0
        guard root.startAccessingSecurityScopedResource() else { return 0 }
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
            return 0
        }

        var bucketed: [[PendingFile]] = Array(repeating: [], count: RecencyBucket.allCases.count)
        let now = Date()

        var lastCommit = Date()

        while let entry = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }

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

        let rootKey = root.path
        let startBucketIndex = mode == .full ? progressIndex(for: rootKey) : 0

        var cancelled = false

        bucketLoop: for bucket in RecencyBucket.allCases {
            if Task.isCancelled { break }
            if bucket.rawValue < startBucketIndex { continue }
            let files = bucketed[bucket.rawValue]
            if files.isEmpty { continue }

            await MainActor.run {
                self.status = bucket.startStatus
            }

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

            if mode == .full {
                setProgressIndex(bucket.rawValue + 1, for: rootKey)
            }
        }

        FinderCore.commitAndRefresh()
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
        defaults.removeObject(forKey: lastIndexDefaultsKey)
        cloudPlaceholders.removeAll()
        defaults.removeObject(forKey: bucketProgressKey)
        cancelScheduledRun()
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
