import Foundation

public enum TranscriptionError: Error, LocalizedError {
    case engineUnavailable(String)
    case emptyTranscript
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason):
            return "Transcription server unavailable: \(reason)"
        case .emptyTranscript:
            return "No speech was recognized. Try recording again with the microphone closer or less background noise."
        case .cancelled:
            return "Transcription was cancelled."
        }
    }
}
