import Foundation

enum RecordingLimits {
    static let maxDurationSeconds: Double = 5 * 60
    static let warningThresholdSeconds: Double = maxDurationSeconds - 30

    static func maxDurationSeconds(keyboardSessionActive: Bool) -> Double {
        maxDurationSeconds
    }

    static func warningThresholdSeconds(keyboardSessionActive: Bool) -> Double {
        warningThresholdSeconds
    }
}
