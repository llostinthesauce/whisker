import Foundation

/// Data contract for keyboard extension ↔ main app communication via App Group.
struct HandoffResult: Codable, Equatable, Sendable {
    let text: String
    let timestamp: Date
    let backend: String
    let status: HandoffStatus
    let elapsedSeconds: Double?
    let maxDurationSeconds: Double?

    init(
        text: String,
        timestamp: Date,
        backend: String,
        status: HandoffStatus,
        elapsedSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil
    ) {
        self.text = text
        self.timestamp = timestamp
        self.backend = backend
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.maxDurationSeconds = maxDurationSeconds
    }

    enum HandoffStatus: String, Codable, Sendable {
        case pending
        case standby
        case recording
        case transcribing
        case ready
        case error
    }
}
