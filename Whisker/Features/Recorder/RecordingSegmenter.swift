import Foundation
import AVFoundation
#if SWIFT_PACKAGE
import WhiskerRemote
#endif

/// Splits a live PCM stream into per-segment `.caf` files on silence boundaries,
/// emitting each finalized segment (URL + index) for upload. Thread-safe: `ingest`
/// runs on the realtime audio thread; callbacks hop to the main thread.
final class RecordingSegmenter: @unchecked Sendable {
    /// Called on the main thread when a segment file is complete.
    var onSegmentFinalized: ((URL, Int) -> Void)?

    private let format: AVAudioFormat
    private let lock = NSLock()
    private var detector = SegmentBoundaryDetector()
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var nextIndex = 0
    private var finished = false

    init(format: AVAudioFormat) {
        self.format = format
    }

    var currentSegmentURLForTesting: URL? {
        lock.lock()
        defer { lock.unlock() }
        return currentURL
    }

    /// Feed one captured buffer (audio thread).
    func ingest(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        ensureFileLocked()
        try? currentFile?.write(from: buffer)

        let rms = Self.rms(of: buffer)
        let sampleRate = buffer.format.sampleRate
        let duration = sampleRate > 0 ? Double(buffer.frameLength) / sampleRate : 0
        if detector.observe(rms: rms, durationSeconds: duration) == .cut {
            finalizeCurrentLocked()
        }
    }

    /// Finalize the in-progress segment as the last one and return it synchronously
    /// (no async callback), so the caller can ingest it before starting transcription
    /// — guaranteeing the final segment is never dropped from the join. Call once at
    /// Stop. Returns nil if there is no in-progress audio.
    func finalize() -> (url: URL, index: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        guard let url = currentURL else { return nil }
        currentFile = nil // closing the AVAudioFile flushes it
        currentURL = nil
        let index = nextIndex
        nextIndex += 1
        return (url, index)
    }

    func discardTemporaryAudio() {
        lock.lock()
        let url = currentURL
        currentFile = nil
        currentURL = nil
        finished = true
        lock.unlock()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private (lock must be held)

    private func ensureFileLocked() {
        guard currentFile == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisker-seg-\(UUID().uuidString).caf")
        if let file = try? AVAudioFile(forWriting: url, settings: format.settings) {
            currentFile = file
            currentURL = url
        }
    }

    private func finalizeCurrentLocked() {
        guard let url = currentURL else { return }
        currentFile = nil // closing the AVAudioFile flushes it
        currentURL = nil
        detector.reset()
        let index = nextIndex
        nextIndex += 1
        let callback = onSegmentFinalized
        #if !SWIFT_PACKAGE
        WLogger.recorder.info("Streaming segment finalized index=\(index) file=\(url.lastPathComponent)")
        #endif
        DispatchQueue.main.async { callback?(url, index) }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumSquares: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sumSquares += sample * sample
        }
        return (sumSquares / Float(count)).squareRoot()
    }
}
