import Foundation

public enum CleanupMode: String, CaseIterable, Codable, Sendable {
    case raw
    case light
    case message
    case email
    case notes
    case bullets

    public static let implementedCases: [CleanupMode] = CleanupMode.allCases

    public var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .light: return "Light"
        case .message: return "Message"
        case .email: return "Email"
        case .notes: return "Notes"
        case .bullets: return "Bullets"
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
        }
    }

    public var isImplemented: Bool {
        Self.implementedCases.contains(self)
    }
}
