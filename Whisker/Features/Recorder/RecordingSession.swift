import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case stopping
    case transcribing
    case finished(DictationResult)
    case failed(String)

    var isActive: Bool {
        if case .recording = self { return true }
        return false
    }

    var elapsedSeconds: Double {
        if case .recording(let start) = self {
            return Date().timeIntervalSince(start)
        }
        return 0
    }
}
