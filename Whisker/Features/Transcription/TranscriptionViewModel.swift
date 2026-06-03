import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var cleanupMode: CleanupMode = ModelSettings.currentDefaultCleanupMode
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var keyboardSessionActive = false
    @Published private(set) var keyboardSessionRemainingSeconds = 0
    @Published private(set) var liveTranscriptText = ""

    private let recorder: AudioRecorder
    private var processor: any DictationProcessor
    private let historyStore: HistoryStore
    private let clipboard: ClipboardService

    private var elapsedTimer: AnyCancellable?
    private var keyboardCommandTimer: AnyCancellable?
    private var keyboardIdleTimer: AnyCancellable?
    private var transcriptionTask: Task<Void, Never>?
    private var segmenter: RecordingSegmenter?
    private var streamingSession: StreamingDictationSession?
    private var liveSegmentTexts: [Int: String] = [:]
    private var lastKeyboardCommandID: UUID?
    private var lastKeyboardActivityDate: Date?
    private var keyboardCommandRecordingActive = false
    private let keyboardIdleTimeoutSeconds = KeyboardSessionDefaults.idleTimeoutSeconds
    private let keyboardStatusHeartbeatSeconds: TimeInterval = 2
#if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

    init(
        recorder: AudioRecorder,
        processor: any DictationProcessor,
        historyStore: HistoryStore,
        clipboard: ClipboardService
    ) {
        self.recorder = recorder
        self.processor = processor
        self.historyStore = historyStore
        self.clipboard = clipboard
        AudioRecorder.removeStaleTemporaryRecordings()
        self.recorder.onExternalStop = { [weak self] event in
            self?.handleExternalStop(event)
        }
    }

    // MARK: - Actions

    func toggleRecording() {
        switch state {
        case .idle, .finished, .failed:
            _ = startRecordingIfPossible()
        case .recording:
            stopRecording()
        default:
            break
        }
    }

    @discardableResult
    func startRecordingIfPossible() -> Bool {
        switch state {
        case .idle, .finished, .failed:
            startRecording()
            if case .recording = state {
                return true
            }
            return false
        default:
            return false
        }
    }

    func copyToClipboard() {
        guard case .finished(let result) = state else { return }
        clipboard.copy(result.displayText)
    }

    func dismiss() {
        state = .idle
        elapsedSeconds = 0
        resetLiveTranscript()
    }

    func stopRecordingIfNeeded() {
        guard case .recording = state else { return }
        stopRecording()
    }

    func setKeyboardSessionActive(_ active: Bool) {
        if active == keyboardSessionActive {
            if active {
                markKeyboardActivity()
                try? HandoffService.writeStatus(.standby, backend: processor.displayName)
            }
            return
        }
        active ? startKeyboardSession() : stopKeyboardSession()
    }

    func setProcessor(_ processor: any DictationProcessor) {
        self.processor.cancel()
        self.processor = processor
    }

    // MARK: - Private

    private func startRecording() {
        do {
            cleanupMode = ModelSettings.currentDefaultCleanupMode
            resetLiveTranscript()
            _ = try recorder.startRecording()
            state = .recording(startedAt: Date())
            startElapsedTimer()
            beginStreamingIfSupported()
        } catch {
            state = .failed(recordingFailureMessage(for: error))
            WLogger.recorder.error("Failed to start recording: \(error)")
        }
    }

    private func beginStreamingIfSupported() {
        segmenter = nil
        streamingSession = nil
        guard let provider = processor as? StreamingSessionProviding else {
            WLogger.transcription.info("Streaming disabled: processor \(String(describing: type(of: self.processor))) does not provide streaming")
            return
        }
        guard let format = recorder.currentInputFormat else {
            WLogger.transcription.info("Streaming disabled: recorder input format unavailable")
            return
        }
        guard let fullURL = recorder.currentFileURL else {
            WLogger.transcription.info("Streaming disabled: full recording URL unavailable")
            return
        }

        let session = provider.makeStreamingSession(
            cleanupMode: ModelSettings.currentDefaultCleanupMode,
            fullRecordingURL: fullURL,
            onSegmentText: { [weak self] index, text in
                Task { @MainActor [weak self] in
                    self?.appendLiveSegmentText(text, index: index)
                }
            }
        )
        let segmenter = RecordingSegmenter(format: format)
        segmenter.onSegmentFinalized = { url, index in
            Task { await session.ingest(segmentURL: url, index: index) }
        }
        self.segmenter = segmenter
        self.streamingSession = session
        recorder.setBufferSink { [weak segmenter] buffer in
            segmenter?.ingest(buffer)
        }
        WLogger.transcription.info("Streaming enabled fullFile=\(fullURL.lastPathComponent) sampleRate=\(format.sampleRate)")
    }

    private func stopRecording() {
        stopElapsedTimer()
        guard let segment = recorder.stopRecording() else {
            state = .failed("Failed to save audio.")
            return
        }
        recorder.setBufferSink(nil)
        let lastSegment = segmenter?.finalize()
        state = .transcribing
        beginTranscriptionBackgroundTask()
        if let session = streamingSession {
            let duration = segment.duration
            transcriptionTask = Task {
                if let lastSegment {
                    WLogger.transcription.info("Streaming final segment queued index=\(lastSegment.index) file=\(lastSegment.url.lastPathComponent)")
                    await session.ingest(segmentURL: lastSegment.url, index: lastSegment.index)
                }
                await transcribeStreaming(session: session, fullURL: segment.url, duration: duration)
            }
        } else {
            transcriptionTask = Task { await transcribe(segment: segment) }
        }
    }

    private func transcribe(segment: (url: URL, duration: Double)) async {
        defer {
            deleteTemporaryAudio(at: segment.url)
            endTranscriptionBackgroundTask()
        }

        do {
            try await processor.prepare()
            let mode = ModelSettings.currentDefaultCleanupMode
            cleanupMode = mode
            let result = try await processor.process(
                audioURL: segment.url,
                durationSeconds: segment.duration,
                cleanupMode: mode
            )
            if PrivacySettings.currentSaveHistory {
                historyStore.save(result)
            }
            if PrivacySettings.currentAutoCopyResult {
                clipboard.copy(result.displayText)
            }
            state = .finished(result)
            if keyboardCommandRecordingActive {
                writeKeyboardResult(
                    result.displayText,
                    status: .ready,
                    elapsedSeconds: segment.duration,
                    maxDurationSeconds: keyboardRecordingLimitSeconds
                )
                keyboardCommandRecordingActive = false
            }
        } catch TranscriptionError.cancelled {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
            if keyboardCommandRecordingActive {
                writeKeyboardResult(error.localizedDescription, status: .error)
                keyboardCommandRecordingActive = false
            }
            WLogger.transcription.error("Transcription failed: \(error)")
        }
    }

    private func transcribeStreaming(session: StreamingDictationSession, fullURL: URL, duration: Double) async {
        defer {
            deleteTemporaryAudio(at: fullURL)
            endTranscriptionBackgroundTask()
            segmenter = nil
            streamingSession = nil
        }

        do {
            let result = try await session.finish(durationSeconds: duration)
            if PrivacySettings.currentSaveHistory {
                historyStore.save(result)
            }
            if PrivacySettings.currentAutoCopyResult {
                clipboard.copy(result.displayText)
            }
            state = .finished(result)
            if keyboardCommandRecordingActive {
                writeKeyboardResult(
                    result.displayText,
                    status: .ready,
                    elapsedSeconds: duration,
                    maxDurationSeconds: keyboardRecordingLimitSeconds
                )
                keyboardCommandRecordingActive = false
            }
        } catch TranscriptionError.cancelled {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
            if keyboardCommandRecordingActive {
                writeKeyboardResult(error.localizedDescription, status: .error)
                keyboardCommandRecordingActive = false
            }
            WLogger.transcription.error("Streaming transcription failed: \(error)")
        }
    }

    private func appendLiveSegmentText(_ text: String, index: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveSegmentTexts[index] = trimmed

        var pieces: [String] = []
        var nextIndex = 0
        while let piece = liveSegmentTexts[nextIndex] {
            pieces.append(piece)
            nextIndex += 1
        }
        liveTranscriptText = pieces.joined(separator: " ")
        WLogger.transcription.info("Streaming live text updated segments=\(pieces.count) chars=\(self.liveTranscriptText.count)")
        writeKeyboardLiveStatusIfNeeded(status: .recording)
    }

    private func resetLiveTranscript() {
        liveSegmentTexts.removeAll()
        liveTranscriptText = ""
    }

    private func handleExternalStop(_ event: AudioRecorderExternalStop) {
        stopElapsedTimer()
        switch event {
        case .interrupted(let segment):
            guard case .recording = state else { return }
            guard let segment else {
                state = .failed("Recording was interrupted before audio could be saved.")
                return
            }
            recorder.setBufferSink(nil)
            let lastSegment = segmenter?.finalize()
            state = .transcribing
            beginTranscriptionBackgroundTask()
            if let session = streamingSession {
                let duration = segment.duration
                transcriptionTask = Task {
                    if let lastSegment {
                        WLogger.transcription.info("Streaming final interrupted segment queued index=\(lastSegment.index) file=\(lastSegment.url.lastPathComponent)")
                        await session.ingest(segmentURL: lastSegment.url, index: lastSegment.index)
                    }
                    await transcribeStreaming(session: session, fullURL: segment.url, duration: duration)
                }
            } else {
                transcriptionTask = Task { await transcribe(segment: segment) }
            }
        case .writeFailed(let message):
            recorder.setBufferSink(nil)
            segmenter?.discardTemporaryAudio()
            if let streamingSession {
                Task { await streamingSession.cancel() }
            }
            segmenter = nil
            streamingSession = nil
            state = .failed(message)
        }
    }

    private func startElapsedTimer() {
        elapsedSeconds = 0
        elapsedTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, case .recording(let start) = self.state else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
                if self.elapsedSeconds >= self.currentRecordingLimitSeconds {
                    self.stopRecording()
                }
            }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }

    private func startKeyboardSession() {
        do {
            try recorder.startStandbySession()
            keyboardSessionActive = true
            markKeyboardActivity()
            HandoffService.clearCommand()
            try? HandoffService.writeStatus(.standby, backend: processor.displayName)
            startKeyboardCommandPolling()
            startKeyboardIdleTimer()
            HandoffSignal.observe(.command) { [weak self] in
                self?.processKeyboardCommandIfNeeded()
                self?.refreshKeyboardStatusIfNeeded()
            }
        } catch {
            state = .failed(recordingFailureMessage(for: error))
            WLogger.recorder.error("Failed to start keyboard session: \(error)")
        }
    }

    private func stopKeyboardSession() {
        keyboardCommandTimer?.cancel()
        keyboardCommandTimer = nil
        HandoffSignal.stopObserving(.command)
        keyboardIdleTimer?.cancel()
        keyboardIdleTimer = nil
        keyboardSessionActive = false
        keyboardSessionRemainingSeconds = 0
        lastKeyboardActivityDate = nil
        if case .recording = state {
            stopRecording()
        }
        recorder.stopStandbySession()
        if let result = HandoffService.readResult(), result.status == .standby || result.status == .recording {
            HandoffService.clearResult()
        }
        HandoffService.clearCommand()
    }

    private func startKeyboardCommandPolling() {
        keyboardCommandTimer?.cancel()
        keyboardCommandTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.processKeyboardCommandIfNeeded()
                self?.refreshKeyboardStatusIfNeeded()
            }
    }

    private func startKeyboardIdleTimer() {
        keyboardIdleTimer?.cancel()
        keyboardIdleTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateKeyboardIdleCountdown()
            }
    }

    private func processKeyboardCommandIfNeeded() {
        guard keyboardSessionActive, let command = HandoffService.readCommand() else { return }
        guard command.id != lastKeyboardCommandID else { return }
        guard Date().timeIntervalSince(command.timestamp) <= 30 else {
            lastKeyboardCommandID = command.id
            HandoffService.clearCommand()
            return
        }

        lastKeyboardCommandID = command.id
        HandoffService.clearCommand()
        markKeyboardActivity()

        switch command.action {
        case .startRecording:
            guard startRecordingIfPossible() else {
                if case .failed(let message) = state {
                    writeKeyboardResult(message, status: .error)
                }
                return
            }
            keyboardCommandRecordingActive = true
            try? HandoffService.writeStatus(
                .recording,
                backend: processor.displayName,
                elapsedSeconds: elapsedSeconds,
                maxDurationSeconds: keyboardRecordingLimitSeconds
            )

        case .stopRecording:
            guard case .recording = state else { return }
            stopRecording()
            try? HandoffService.writeStatus(
                .transcribing,
                backend: processor.displayName,
                elapsedSeconds: elapsedSeconds,
                maxDurationSeconds: keyboardRecordingLimitSeconds
            )
        }
    }

    private func refreshKeyboardStatusIfNeeded() {
        guard keyboardSessionActive else { return }
        let desiredStatus: HandoffResult.HandoffStatus
        switch state {
        case .idle, .finished, .failed:
            desiredStatus = .standby
        case .recording:
            desiredStatus = .recording
        case .stopping, .transcribing:
            desiredStatus = .transcribing
        }

        guard shouldRefreshKeyboardStatus(to: desiredStatus) else { return }
        let telemetry = keyboardStatusTelemetry(for: desiredStatus)
        let text = desiredStatus == .recording || desiredStatus == .transcribing ? liveTranscriptText : ""
        writeKeyboardResult(
            text,
            status: desiredStatus,
            elapsedSeconds: telemetry.elapsedSeconds,
            maxDurationSeconds: telemetry.maxDurationSeconds
        )
    }

    private func shouldRefreshKeyboardStatus(to desiredStatus: HandoffResult.HandoffStatus) -> Bool {
        guard let result = HandoffService.readResult() else { return true }
        switch result.status {
        case .ready, .error, .pending:
            return false
        case let status where status == desiredStatus:
            return Date().timeIntervalSince(result.timestamp) >= keyboardStatusHeartbeatSeconds
        default:
            return true
        }
    }

    private func updateKeyboardIdleCountdown() {
        guard keyboardSessionActive, let lastKeyboardActivityDate else { return }
        let elapsed = Date().timeIntervalSince(lastKeyboardActivityDate)
        let remaining = max(0, Int(keyboardIdleTimeoutSeconds - elapsed))
        keyboardSessionRemainingSeconds = remaining
        if remaining == 0 {
            stopKeyboardSession()
        }
    }

    private func markKeyboardActivity() {
        lastKeyboardActivityDate = Date()
        keyboardSessionRemainingSeconds = Int(keyboardIdleTimeoutSeconds)
    }

    private var currentRecordingLimitSeconds: Double {
        RecordingLimits.maxDurationSeconds(keyboardSessionActive: keyboardSessionActive)
    }

    private var keyboardRecordingLimitSeconds: Double {
        RecordingLimits.maxDurationSeconds(keyboardSessionActive: true)
    }

    private func keyboardStatusTelemetry(for status: HandoffResult.HandoffStatus) -> (elapsedSeconds: Double?, maxDurationSeconds: Double?) {
        switch status {
        case .recording, .transcribing:
            return (elapsedSeconds, keyboardRecordingLimitSeconds)
        default:
            return (nil, nil)
        }
    }

    private func writeKeyboardResult(
        _ text: String,
        status: HandoffResult.HandoffStatus,
        elapsedSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil
    ) {
        let result = HandoffResult(
            text: text,
            timestamp: Date(),
            backend: processor.displayName,
            status: status,
            elapsedSeconds: elapsedSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
        try? HandoffService.writeResult(result)
    }

    private func writeKeyboardLiveStatusIfNeeded(status: HandoffResult.HandoffStatus) {
        guard keyboardCommandRecordingActive || keyboardSessionActive else { return }
        let telemetry = keyboardStatusTelemetry(for: status)
        writeKeyboardResult(
            liveTranscriptText,
            status: status,
            elapsedSeconds: telemetry.elapsedSeconds,
            maxDurationSeconds: telemetry.maxDurationSeconds
        )
    }

    private func recordingFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == 560557684 {
            return "whisker could not take the microphone. Open whisker, start the keyboard session again, then return to the keyboard."
        }
        return error.localizedDescription
    }

    private func deleteTemporaryAudio(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            WLogger.recorder.info("Deleted temporary audio file \(url.lastPathComponent)")
        } catch {
            WLogger.recorder.error("Failed to delete temporary audio file: \(error)")
        }
    }

#if os(iOS)
    private func beginTranscriptionBackgroundTask() {
        guard backgroundTaskIdentifier == .invalid else { return }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "WhiskerTranscription") { [weak self] in
            Task { @MainActor in
                self?.endTranscriptionBackgroundTask()
            }
        }
    }

    private func endTranscriptionBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }
#else
    private func beginTranscriptionBackgroundTask() {}
    private func endTranscriptionBackgroundTask() {}
#endif
}
