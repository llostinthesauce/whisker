import Foundation

public enum CleanupMode: String, CaseIterable, Codable, Sendable {
    case raw
    case light
    case message
    case email
    case notes
    case markdown
    case bullets
    case concise

    public static let implementedCases: [CleanupMode] = [.raw, .light, .message, .email, .notes, .bullets]

    public var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .light: return "Light"
        case .message: return "Message"
        case .email: return "Email"
        case .notes: return "Notes"
        case .markdown: return "Markdown"
        case .bullets: return "Bullets"
        case .concise: return "Concise"
        }
    }

    public var description: String {
        switch self {
        case .raw:
            return "Returns the server transcript exactly as received."
        case .light:
            return "Trims edges and collapses repeated spaces while preserving paragraph breaks."
        case .message:
            return "Applies light cleanup and capitalizes the first character."
        case .email:
            return "Uses message style in this build."
        case .notes:
            return "Splits transcript sentences onto separate lines."
        case .bullets:
            return "Splits transcript sentences into a bullet list."
        case .markdown:
            return "Not available in this build."
        case .concise:
            return "Not available in this build."
        }
    }

    public var isImplemented: Bool {
        Self.implementedCases.contains(self)
    }
}
