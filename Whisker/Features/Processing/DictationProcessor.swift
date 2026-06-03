import Foundation
#if SWIFT_PACKAGE
import WhiskerCleanup
import WhiskerModels
import WhiskerTranscriptionCore
#endif

public protocol DictationProcessor: AnyObject, Sendable {
    var displayName: String { get }

    func prepare() async throws
    func process(audioURL: URL, durationSeconds: Double, cleanupMode: CleanupMode) async throws -> DictationResult
    func cancel()
}

final class UnavailableDictationProcessor: DictationProcessor, @unchecked Sendable {
    let displayName: String
    private let reason: String

    init(displayName: String, reason: String) {
        self.displayName = displayName
        self.reason = reason
    }

    func prepare() async throws {
        throw TranscriptionError.engineUnavailable(reason)
    }

    func process(audioURL: URL, durationSeconds: Double, cleanupMode: CleanupMode) async throws -> DictationResult {
        throw TranscriptionError.engineUnavailable(reason)
    }

    func cancel() {}
}
