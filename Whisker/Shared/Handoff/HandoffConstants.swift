import Foundation

/// Shared constants for the handoff flow between the keyboard extension and main app.
enum HandoffConstants {
    /// URL scheme registered by the main app.
    static let urlScheme = "whisker"

    /// URL the extension opens to trigger a recording in the main app.
    static var recordURL: URL {
        URL(string: "\(urlScheme)://record?source=keyboard")!
    }
}
