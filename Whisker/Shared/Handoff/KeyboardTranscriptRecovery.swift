import Foundation

struct KeyboardTranscriptRecovery {
    static let defaultMaximumAge: TimeInterval = 60 * 60

    private static let textKey = "whisker.keyboard.lastInsertedTranscriptText"
    private static let timestampKey = "whisker.keyboard.lastInsertedTranscriptTimestamp"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(text: String, timestamp: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        defaults.set(trimmed, forKey: Self.textKey)
        defaults.set(timestamp.timeIntervalSince1970, forKey: Self.timestampKey)
    }

    func load(
        now: Date = Date(),
        maximumAge: TimeInterval = Self.defaultMaximumAge
    ) -> String? {
        guard let text = defaults.string(forKey: Self.textKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }

        let timestamp = defaults.double(forKey: Self.timestampKey)
        guard timestamp > 0 else { return nil }

        let age = now.timeIntervalSince(Date(timeIntervalSince1970: timestamp))
        guard age >= 0, age <= maximumAge else { return nil }
        return text
    }

    func clear() {
        defaults.removeObject(forKey: Self.textKey)
        defaults.removeObject(forKey: Self.timestampKey)
    }
}
