import Foundation

public struct Transcript: Equatable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public let durationSeconds: Double
    public let engineName: String

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        engineName: String
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.engineName = engineName
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
