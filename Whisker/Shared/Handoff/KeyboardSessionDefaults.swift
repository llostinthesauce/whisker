import Foundation

enum KeyboardSessionDefaults {
    /// How long a keyboard session survives without activity before it stops
    /// itself. The session keeps the AVAudioEngine (and therefore the
    /// microphone and the orange mic indicator) live the whole time — iOS only
    /// keeps the app running in the background because audio is active — so
    /// this is a deliberate cap on mic-hot time and battery drain, not just a
    /// UX timeout.
    static let idleTimeoutSeconds: TimeInterval = 15 * 60
}
