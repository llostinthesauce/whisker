import Foundation
import AVFoundation

enum AudioRecorderExternalStop: Equatable {
    case interrupted(segment: (url: URL, duration: Double)?)
    case writeFailed(String)

    static func == (lhs: AudioRecorderExternalStop, rhs: AudioRecorderExternalStop) -> Bool {
        switch (lhs, rhs) {
        case (.writeFailed(let left), .writeFailed(let right)):
            return left == right
        case (.interrupted, .interrupted):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    var onExternalStop: ((AudioRecorderExternalStop) -> Void)?

    private var engine: AVAudioEngine?
    private let writerBox = AudioFileWriterBox()
    private let bufferSinkBox = BufferSinkBox()
    private var inputFormat: AVAudioFormat?
    private(set) var currentFileURL: URL?
    private var recordingStartDate: Date?
    private var standbySessionActive = false

    private var interruptionObserver: NSObjectProtocol?

    // MARK: - Public

    static func removeStaleTemporaryRecordings() {
        let tempDirectory = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where url.lastPathComponent.hasPrefix("whisker-") && url.pathExtension == "caf" {
            do {
                try FileManager.default.removeItem(at: url)
                WLogger.recorder.info("Deleted stale temporary audio file \(url.lastPathComponent)")
            } catch {
                WLogger.recorder.error("Failed to delete stale temporary audio file: \(error)")
            }
        }
    }

    func startRecording() throws -> URL {
        let url = makeTemporaryURL()
        if standbySessionActive, engine != nil, inputFormat != nil {
            WLogger.recorder.info("Recording using active keyboard standby audio engine")
        } else {
            try configureSession()
            try ensureEngineRunning()
        }
        subscribeToInterruptions()
        guard let inputFormat else {
            throw AudioRecorderError.inputFormatUnavailable
        }
        try writerBox.startWriting(to: url, format: inputFormat)
        isRecording = true
        recordingStartDate = Date()
        currentFileURL = url
        WLogger.recorder.info("Recording started → \(url.lastPathComponent)")
        return url
    }

    func stopRecording() -> (url: URL, duration: Double)? {
        guard isRecording, let url = currentFileURL, let start = recordingStartDate else { return nil }
        let duration = Date().timeIntervalSince(start)
        writerBox.stopWriting()
        isRecording = false
        currentFileURL = nil
        recordingStartDate = nil
        if !standbySessionActive {
            tearDown()
        }
        WLogger.recorder.info("Recording stopped. Duration: \(String(format: "%.1f", duration))s")
        return (url, duration)
    }

    func startStandbySession() throws {
        do {
            try configureSession()
            try ensureEngineRunning()
            subscribeToInterruptions()
            standbySessionActive = true
            WLogger.recorder.info("Keyboard standby audio engine started")
        } catch {
            standbySessionActive = false
            tearDown()
            throw error
        }
    }

    func stopStandbySession() {
        standbySessionActive = false
        guard !isRecording else { return }
        tearDown()
        WLogger.recorder.info("Keyboard standby audio engine stopped")
    }

    /// The microphone input format, available after recording/standby has started.
    var currentInputFormat: AVAudioFormat? { inputFormat }

    /// Install a sink that receives every captured PCM buffer (called on the audio
    /// thread). Pass `nil` to remove it. Used by streaming segmentation.
    func setBufferSink(_ sink: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        bufferSinkBox.set(sink)
    }

    // MARK: - Private

    private func makeTemporaryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("whisker-\(UUID().uuidString).caf")
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
#if compiler(>=6.2)
        // .allowBluetooth was renamed .allowBluetoothHFP in the iOS 26 SDK;
        // CI's stable Xcode only has the old name.
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .mixWithOthers])
#else
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .mixWithOthers])
#endif
        try session.setActive(true)
    }

    private func ensureEngineRunning() throws {
        if engine == nil {
            try startEngine()
        }
        guard inputFormat != nil else {
            throw AudioRecorderError.inputFormatUnavailable
        }
    }

    private func startEngine() throws {
        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        inputFormat = format

        let tap = makeAudioTap(writerBox: writerBox, sinkBox: bufferSinkBox) { [weak self] in
            self?.stopAfterWriteFailure()
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: tap)

        try audioEngine.start()
        engine = audioEngine
    }

    private func tearDown() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        writerBox.stopWriting()
        bufferSinkBox.set(nil)
        inputFormat = nil
        isRecording = false
        standbySessionActive = false
        currentFileURL = nil
        recordingStartDate = nil
        unsubscribeFromInterruptions()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopAfterWriteFailure() {
        guard isRecording else { return }
        let url = currentFileURL
        WLogger.recorder.error("Audio file write failed; stopping recording")
        tearDown()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        onExternalStop?(.writeFailed("Audio file write failed. Try recording again."))
    }

    private func subscribeToInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let type = Self.interruptionType(from: note) else { return }
            Task { @MainActor [weak self] in
                self?.handleInterruption(type)
            }
        }
    }

    private func unsubscribeFromInterruptions() {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
    }

    nonisolated private static func interruptionType(from notification: Notification) -> AVAudioSession.InterruptionType? {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return nil }

        return type
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType) {
        switch type {
        case .began:
            WLogger.recorder.info("Audio session interrupted — stopping recording")
            let segment = stopRecording()
            if !isRecording {
                tearDown()
            }
            onExternalStop?(.interrupted(segment: segment))
        case .ended:
            // Don't auto-resume. Let the user re-tap.
            WLogger.recorder.info("Audio session interruption ended")
        @unknown default:
            break
        }
    }
}

enum AudioRecorderError: Error, LocalizedError {
    case inputFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .inputFormatUnavailable:
            return "Microphone input format is unavailable. Try recording again."
        }
    }
}

private func makeAudioTap(
    writerBox: AudioFileWriterBox,
    sinkBox: BufferSinkBox,
    onWriteFailure: @escaping @MainActor () -> Void
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        switch writerBox.write(buffer) {
        case .wrote:
            sinkBox.forward(buffer)
        case .noWriter:
            break
        case .failed:
            Task { @MainActor in
                onWriteFailure()
            }
        }
    }
}

private final class BufferSinkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func set(_ sink: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    func forward(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = sink
        lock.unlock()
        current?(buffer)
    }
}

private final class AudioFileWriterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: AudioFileWriter?

    func startWriting(to url: URL, format: AVAudioFormat) throws {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        lock.lock()
        writer = AudioFileWriter(file: file)
        lock.unlock()
    }

    func stopWriting() {
        lock.lock()
        writer = nil
        lock.unlock()
    }

    func write(_ buffer: AVAudioPCMBuffer) -> AudioFileWriteOutcome {
        lock.lock()
        let currentWriter = writer
        lock.unlock()
        guard let currentWriter else { return .noWriter }
        return currentWriter.write(buffer) ? .wrote : .failed
    }
}

private enum AudioFileWriteOutcome {
    case wrote
    case noWriter
    case failed
}

private final class AudioFileWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()
    private(set) var lastError: Error?

    init(file: AVAudioFile) {
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard lastError == nil else { return false }

        do {
            try file.write(from: buffer)
            return true
        } catch {
            lastError = error
            return false
        }
    }
}
