import Foundation
#if SWIFT_PACKAGE
import WhiskerCleanup
import WhiskerModels
import WhiskerProcessing
import WhiskerTranscriptionCore
#endif

final class RemoteMacProcessor: DictationProcessor, @unchecked Sendable {
    let displayName = "Remote server"

    private let client: any RemoteMacClientProtocol

    init(client: any RemoteMacClientProtocol) {
        self.client = client
    }

    convenience init(configuration: RemoteMacClientConfiguration) {
        self.init(client: RemoteMacClient(configuration: configuration))
    }

    func prepare() async throws {
        let health = try await client.health()
        guard health.ok else {
            throw TranscriptionError.engineUnavailable("Server is not healthy.")
        }
    }

    func process(audioURL: URL, durationSeconds: Double, cleanupMode: CleanupMode) async throws -> DictationResult {
        let response: RemoteTranscriptionResponse
        do {
            response = try await client.transcribe(
                audioURL: audioURL,
                cleanupMode: cleanupMode,
                returnCleaned: cleanupMode != .raw
            )
        } catch RemoteMacError.emptyTranscript {
            throw TranscriptionError.emptyTranscript
        }
        let transcript = Transcript(
            text: response.text,
            durationSeconds: response.durationSeconds,
            engineName: engineName(for: response)
        )
        guard !transcript.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        let cleanedText: String?
        if cleanupMode == .raw {
            cleanedText = nil
        } else {
            cleanedText = response.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? response.cleanedText
                : nil
        }

        return DictationResult(
            rawTranscript: transcript,
            cleanedText: cleanedText,
            cleanupMode: cleanupMode
        )
    }

    func cancel() {}

    private func engineName(for response: RemoteTranscriptionResponse) -> String {
        let parts = [response.engine, response.model]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? displayName : parts.joined(separator: "/")
    }
}

extension RemoteMacProcessor: StreamingSessionProviding {
    func makeStreamingSession(
        cleanupMode: CleanupMode,
        fullRecordingURL: URL,
        onSegmentText: (@Sendable (Int, String) -> Void)?
    ) -> StreamingDictationSession {
        StreamingDictationSession(
            client: client,
            cleanupMode: cleanupMode,
            fullRecordingURL: fullRecordingURL,
            onSegmentText: onSegmentText
        )
    }
}
