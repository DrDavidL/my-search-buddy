import Foundation
import SwiftUI

struct ContentSamplingPolicy: Equatable, Sendable {
    let coverageFraction: Double
    let headFraction: Double
    let tailFraction: Double
    let maxBytes: Int64
    let smallFileThreshold: Int64
    let minHeadBytes: Int64
    let minTailBytes: Int64
    let sniffBytes: Int

    var isEnabled: Bool { coverageFraction > 0 }
    var headPercentage: Double { headFraction * 100 }
    var tailPercentage: Double { tailFraction * 100 }
}

extension ContentSamplingPolicy {
    static func fromPercentage(
        _ percentage: Double,
        headShare: Double,
        maxBytes: Int64,
        smallFileThreshold: Int64,
        minHeadBytes: Int64,
        minTailBytes: Int64,
        sniffBytes: Int
    ) -> ContentSamplingPolicy {
        let clampedPercentage = max(0, percentage)
        let fraction = clampedPercentage / 100.0
        let clampedHeadShare = headShare.clamped(to: 0...1)
        let head = fraction * clampedHeadShare
        let tail = max(fraction - head, 0)

        return ContentSamplingPolicy(
            coverageFraction: fraction,
            headFraction: head,
            tailFraction: tail,
            maxBytes: maxBytes,
            smallFileThreshold: smallFileThreshold,
            minHeadBytes: minHeadBytes,
            minTailBytes: minTailBytes,
            sniffBytes: sniffBytes
        )
    }
}

@MainActor
final class ContentCoverageSettings: ObservableObject {
    private enum Constants {
        static let defaultsKey = "contentCoveragePercent.v1"
        static let envKey = "MSB_CONTENT_PERCENT"
        static let defaultPercentage = 10.0
        static let minSliderPercentage = 2.0
        static let maxSliderPercentage = 50.0
        static let headShare = 0.8
        static let maxBytes: Int64 = 1_572_864
        static let smallFileThreshold: Int64 = 128 * 1024
        static let minHeadBytes: Int64 = 4 * 1024
        static let minTailBytes: Int64 = 1 * 1024
        static let sniffBytes = 8_192
    }

    private let defaults: UserDefaults
    private let envOverride: Double?

    @Published private(set) var userPercentage: Double
    @Published private(set) var samplingPolicy: ContentSamplingPolicy

    var sliderRange: ClosedRange<Double> {
        Constants.minSliderPercentage...Constants.maxSliderPercentage
    }

    var isOverrideActive: Bool { envOverride != nil }

    var effectivePercentage: Double { envOverride ?? userPercentage }

    var headPercentage: Double { samplingPolicy.headPercentage }
    var tailPercentage: Double { samplingPolicy.tailPercentage }

    init(
        defaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.defaults = defaults

        let envPercent = ContentCoverageSettings.parsePercentage(
            processInfo.environment[Constants.envKey]
        )
        self.envOverride = envPercent

        let stored = defaults.object(forKey: Constants.defaultsKey) as? Double
        let initial = envPercent ?? stored ?? Constants.defaultPercentage
        self.userPercentage = ContentCoverageSettings.clamp(initial)
        self.samplingPolicy = ContentSamplingPolicy.fromPercentage(
            envPercent ?? self.userPercentage,
            headShare: Constants.headShare,
            maxBytes: Constants.maxBytes,
            smallFileThreshold: Constants.smallFileThreshold,
            minHeadBytes: Constants.minHeadBytes,
            minTailBytes: Constants.minTailBytes,
            sniffBytes: Constants.sniffBytes
        )
        refreshPolicy()
    }

    func setPercentage(_ value: Double) {
        guard !isOverrideActive else { return }
        let clamped = ContentCoverageSettings.clamp(value)
        guard clamped != userPercentage else { return }
        userPercentage = clamped
        defaults.set(clamped, forKey: Constants.defaultsKey)
        refreshPolicy()
    }

    func refreshPolicy() {
        samplingPolicy = ContentSamplingPolicy.fromPercentage(
            effectivePercentage,
            headShare: Constants.headShare,
            maxBytes: Constants.maxBytes,
            smallFileThreshold: Constants.smallFileThreshold,
            minHeadBytes: Constants.minHeadBytes,
            minTailBytes: Constants.minTailBytes,
            sniffBytes: Constants.sniffBytes
        )
    }

    static func defaultSamplingPolicy() -> ContentSamplingPolicy {
        ContentSamplingPolicy.fromPercentage(
            Constants.defaultPercentage,
            headShare: Constants.headShare,
            maxBytes: Constants.maxBytes,
            smallFileThreshold: Constants.smallFileThreshold,
            minHeadBytes: Constants.minHeadBytes,
            minTailBytes: Constants.minTailBytes,
            sniffBytes: Constants.sniffBytes
        )
    }

    func bindingForSlider() -> Binding<Double> {
        Binding(
            get: { self.userPercentage },
            set: { self.setPercentage($0) }
        )
    }

    private static func parsePercentage(_ raw: String?) -> Double? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else { return nil }
        return clamp(value)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, Constants.minSliderPercentage), Constants.maxSliderPercentage)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
