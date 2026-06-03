import Foundation
#if SWIFT_PACKAGE
import WhiskerCleanup
#endif

public struct DictationResult: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let rawTranscript: Transcript
    public let cleanedText: String?
    public let cleanupMode: CleanupMode
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        rawTranscript: Transcript,
        cleanedText: String? = nil,
        cleanupMode: CleanupMode = .raw,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.cleanedText = cleanedText
        self.cleanupMode = cleanupMode
        self.createdAt = createdAt
    }

    public var displayText: String {
        cleanedText ?? rawTranscript.text
    }
}
