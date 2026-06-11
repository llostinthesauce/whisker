import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case stopping
    case transcribing
    case finished(DictationResult)
    case failed(String)
}
