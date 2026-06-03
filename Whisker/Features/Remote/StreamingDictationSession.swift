import Foundation
#if SWIFT_PACKAGE
import WhiskerCleanup
import WhiskerModels
import WhiskerTranscriptionCore
#endif

/// A processor that can drive segment-pipelined ("streaming") dictation.
protocol StreamingSessionProviding {
    func makeStreamingSession(
        cleanupMode: CleanupMode,
        fullRecordingURL: URL,
        onSegmentText: (@Sendable (Int, String) -> Void)?
    ) -> StreamingDictationSession
}

extension StreamingSessionProviding {
    func makeStreamingSession(cleanupMode: CleanupMode, fullRecordingURL: URL) -> StreamingDictationSession {
        makeStreamingSession(cleanupMode: cleanupMode, fullRecordingURL: fullRecordingURL, onSegmentText: nil)
    }
}

private enum StreamingDictationError: Error {
    case segmentGap(Int)
}

/// Orchestrates segment-pipelined transcription: each finalized audio segment is
/// uploaded as it arrives; at `finish` the ordered results are joined and cleaned
/// once on-device. Any segment failure (or all-empty output) falls back to a single
/// whole-file batch transcription of the full recording.
actor StreamingDictationSession {
    private let client: any RemoteMacClientProtocol
    private let cleanupMode: CleanupMode
    private let fullRecordingURL: URL
    private let cleanup: CleanupPipeline
    private let onSegmentText: (@Sendable (Int, String) -> Void)?

    private var segmentTasks: [Int: Task<String, Error>] = [:]
    private var highestIndex = -1

    init(
        client: any RemoteMacClientProtocol,
        cleanupMode: CleanupMode,
        fullRecordingURL: URL,
        cleanup: CleanupPipeline = CleanupPipeline(),
        onSegmentText: (@Sendable (Int, String) -> Void)? = nil
    ) {
        self.client = client
        self.cleanupMode = cleanupMode
        self.fullRecordingURL = fullRecordingURL
        self.cleanup = cleanup
        self.onSegmentText = onSegmentText
    }

    /// Begin uploading a finalized segment. Call with strictly increasing indexes.
    func ingest(segmentURL: URL, index: Int) {
        guard segmentTasks[index] == nil else {
            assertionFailure("ingest called twice for index \(index)")
            try? FileManager.default.removeItem(at: segmentURL)
            return
        }
        highestIndex = max(highestIndex, index)
        let client = self.client
        #if !SWIFT_PACKAGE
        WLogger.transcription.info("Streaming upload queued index=\(index) file=\(segmentURL.lastPathComponent)")
        #endif
        segmentTasks[index] = Task {
            defer { try? FileManager.default.removeItem(at: segmentURL) }
            let response = try await client.transcribe(
                audioURL: segmentURL,
                cleanupMode: .raw,
                returnCleaned: false
            )
            #if !SWIFT_PACKAGE
            WLogger.transcription.info("Streaming upload completed index=\(index) chars=\(response.text.count)")
            #endif
            let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onSegmentText?(index, trimmed)
            }
            return response.text
        }
    }

    /// Await all segments in order, join, and clean. Falls back to whole-file batch
    /// on any segment error or when no segment produced text.
    func finish(durationSeconds: Double) async throws -> DictationResult {
        do {
            let joined = try await joinedSegmentText()
            if !joined.isEmpty {
                #if !SWIFT_PACKAGE
                WLogger.transcription.info("Streaming finish using joined segments chars=\(joined.count)")
                #endif
                return try await makeStreamingResult(rawText: joined, durationSeconds: durationSeconds)
            }
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            #if !SWIFT_PACKAGE
            WLogger.transcription.error("Streaming finish falling back to whole file: \(error)")
            #endif
            // Any segment failure — fall through to whole-file fallback.
        }
        #if !SWIFT_PACKAGE
        WLogger.transcription.info("Streaming finish falling back to whole file because segment output was empty or missing")
        #endif
        return try await fallbackWholeFile()
    }

    func cancel() {
        for task in segmentTasks.values { task.cancel() }
        segmentTasks.removeAll()
        highestIndex = -1
    }

    private func joinedSegmentText() async throws -> String {
        guard highestIndex >= 0 else { return "" }
        var pieces: [String] = []
        for index in 0...highestIndex {
            guard let task = segmentTasks[index] else {
                throw StreamingDictationError.segmentGap(index)
            }
            let trimmed = try await task.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pieces.append(trimmed) }
        }
        return pieces.joined(separator: " ")
    }

    private func makeStreamingResult(rawText: String, durationSeconds: Double) async throws -> DictationResult {
        let cleanedText: String?
        if cleanupMode == .raw {
            cleanedText = nil
        } else {
            let cleaned = try await cleanup.process(rawText, mode: cleanupMode)
            cleanedText = cleaned.isEmpty ? nil : cleaned
        }
        return DictationResult(
            rawTranscript: Transcript(text: rawText, durationSeconds: durationSeconds, engineName: "streaming"),
            cleanedText: cleanedText,
            cleanupMode: cleanupMode
        )
    }

    private func fallbackWholeFile() async throws -> DictationResult {
        for task in segmentTasks.values { task.cancel() }
        let response = try await client.transcribe(
            audioURL: fullRecordingURL,
            cleanupMode: cleanupMode,
            returnCleaned: cleanupMode != .raw
        )
        let raw = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw TranscriptionError.emptyTranscript }
        let cleaned = (cleanupMode != .raw)
            ? response.cleanedText.flatMap { $0.isEmpty ? nil : $0 }
            : nil
        return DictationResult(
            rawTranscript: Transcript(
                text: response.text,
                durationSeconds: response.durationSeconds,
                engineName: response.engine
            ),
            cleanedText: cleaned,
            cleanupMode: cleanupMode
        )
    }
}
