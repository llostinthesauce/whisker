import Foundation

public struct WhiskerStats: Sendable {
    public let totalWords: Int
    public let transcriptionsToday: Int
    public let totalAudioSeconds: Double
    public let totalTranscriptions: Int
    public let averageDurationSeconds: Double
    public let averageWordsPerSession: Double
    public let longestSessionSeconds: Double
    public let perEngineBreakdown: [(engine: String, count: Int, words: Int)]

    public static let empty = WhiskerStats(
        totalWords: 0,
        transcriptionsToday: 0,
        totalAudioSeconds: 0,
        totalTranscriptions: 0,
        averageDurationSeconds: 0,
        averageWordsPerSession: 0,
        longestSessionSeconds: 0,
        perEngineBreakdown: []
    )

    public static func compute(from entries: [DictationResult]) -> WhiskerStats {
        guard !entries.isEmpty else { return .empty }

        let today = Calendar.current.startOfDay(for: Date())
        var totalWords = 0
        var transcriptionsToday = 0
        var totalAudioSeconds = 0.0
        var longestSessionSeconds = 0.0
        var engineCounts: [String: (count: Int, words: Int)] = [:]

        for entry in entries {
            let words = entry.displayText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
            totalWords += words

            if entry.createdAt >= today {
                transcriptionsToday += 1
            }

            let duration = entry.rawTranscript.durationSeconds
            totalAudioSeconds += duration
            longestSessionSeconds = max(longestSessionSeconds, duration)

            let engine = entry.rawTranscript.engineName
            let prior = engineCounts[engine] ?? (count: 0, words: 0)
            engineCounts[engine] = (count: prior.count + 1, words: prior.words + words)
        }

        let count = entries.count
        let breakdown = engineCounts
            .map { (engine: $0.key, count: $0.value.count, words: $0.value.words) }
            .sorted { $0.count > $1.count }

        return WhiskerStats(
            totalWords: totalWords,
            transcriptionsToday: transcriptionsToday,
            totalAudioSeconds: totalAudioSeconds,
            totalTranscriptions: count,
            averageDurationSeconds: totalAudioSeconds / Double(count),
            averageWordsPerSession: Double(totalWords) / Double(count),
            longestSessionSeconds: longestSessionSeconds,
            perEngineBreakdown: breakdown
        )
    }
}
