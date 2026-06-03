import Foundation

/// Decides where to cut a dictation into segments from a running summary of
/// audio energy. Pure value logic — no audio I/O — so it is unit-testable.
public struct SegmentBoundaryDetector {
    public struct Thresholds: Sendable {
        /// RMS below this counts as silence (float PCM, normalized -1...1).
        public var silenceRMS: Float = 0.015
        /// Trailing silence needed to consider a cut.
        public var silenceCutSeconds: Double = 0.7
        /// Never cut a segment shorter than this.
        public var minSegmentSeconds: Double = 3.0
        /// Force a cut once a segment reaches this length, even without silence.
        public var maxSegmentSeconds: Double = 15.0

        public static let standard = Thresholds()
    }

    public enum Decision: Equatable {
        case `continue`
        case cut
    }

    private let thresholds: Thresholds
    public private(set) var segmentSeconds: Double = 0
    public private(set) var trailingSilenceSeconds: Double = 0

    public init(thresholds: Thresholds = .standard) {
        self.thresholds = thresholds
    }

    /// Feed one buffer's RMS and duration. Returns whether to cut AFTER this buffer.
    /// On `.cut` the caller finalizes the segment and calls `reset()`.
    public mutating func observe(rms: Float, durationSeconds: Double) -> Decision {
        segmentSeconds += durationSeconds
        if rms < thresholds.silenceRMS {
            trailingSilenceSeconds += durationSeconds
        } else {
            trailingSilenceSeconds = 0
        }

        // Use a small epsilon to guard against floating-point accumulation
        // (e.g., 150 × 0.1 accumulates to 14.9999... rather than 15.0).
        let epsilon = 1e-9
        if segmentSeconds >= thresholds.maxSegmentSeconds - epsilon {
            return .cut
        }
        if trailingSilenceSeconds >= thresholds.silenceCutSeconds - epsilon,
           segmentSeconds >= thresholds.minSegmentSeconds - epsilon {
            return .cut
        }
        return .continue
    }

    public mutating func reset() {
        segmentSeconds = 0
        trailingSilenceSeconds = 0
    }
}
