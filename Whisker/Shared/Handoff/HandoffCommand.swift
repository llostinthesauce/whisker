import Foundation

/// Command contract written by the keyboard extension and consumed by the main app.
struct HandoffCommand: Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let action: Action

    enum Action: String, Codable, Sendable {
        case startRecording
        case stopRecording
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), action: Action) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
    }
}
