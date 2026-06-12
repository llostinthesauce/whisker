import XCTest
@testable import WhiskerModels

final class WhiskerStatsTests: XCTestCase {

    func testEmptyEntriesReturnsZeroStats() {
        let stats = WhiskerStats.compute(from: [])

        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.transcriptionsToday, 0)
        XCTAssertEqual(stats.totalAudioSeconds, 0)
        XCTAssertEqual(stats.totalTranscriptions, 0)
        XCTAssertTrue(stats.perEngineBreakdown.isEmpty)
    }

    func testWordCountSumsAcrossEntries() {
        let entries = [
            makeEntry(text: "hello world", durationSeconds: 5),
            makeEntry(text: "one two three", durationSeconds: 10),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.totalWords, 5)
    }

    func testWordCountIgnoresExtraWhitespace() {
        let entries = [makeEntry(text: "  hello   world  \n\n  ", durationSeconds: 5)]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.totalWords, 2)
    }

    func testTotalAudioSecondsIsSum() {
        let entries = [
            makeEntry(text: "a", durationSeconds: 30),
            makeEntry(text: "b", durationSeconds: 45),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.totalAudioSeconds, 75, accuracy: 0.001)
    }

    func testLongestSessionIsMax() {
        let entries = [
            makeEntry(text: "a", durationSeconds: 30),
            makeEntry(text: "b", durationSeconds: 120),
            makeEntry(text: "c", durationSeconds: 45),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.longestSessionSeconds, 120, accuracy: 0.001)
    }

    func testAverageDurationIsCorrect() {
        let entries = [
            makeEntry(text: "a", durationSeconds: 30),
            makeEntry(text: "b", durationSeconds: 90),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.averageDurationSeconds, 60, accuracy: 0.001)
    }

    func testAverageWordsPerSession() {
        let entries = [
            makeEntry(text: "hello world", durationSeconds: 5),   // 2 words
            makeEntry(text: "one two three four", durationSeconds: 5), // 4 words
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.averageWordsPerSession, 3.0, accuracy: 0.001)
    }

    func testTranscriptionsTodayCountsOnlyToday() {
        let yesterday = Date().addingTimeInterval(-86400)
        let entries = [
            makeEntry(text: "today", durationSeconds: 5, createdAt: Date()),
            makeEntry(text: "yesterday", durationSeconds: 5, createdAt: yesterday),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.transcriptionsToday, 1)
    }

    func testPerEngineBreakdownGroupsByEngine() {
        let entries = [
            makeEntry(text: "hello world", durationSeconds: 5, engineName: "parakeet"),
            makeEntry(text: "one two", durationSeconds: 5, engineName: "parakeet"),
            makeEntry(text: "test", durationSeconds: 5, engineName: "qwen"),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.perEngineBreakdown.count, 2)
        XCTAssertEqual(stats.perEngineBreakdown[0].engine, "parakeet")
        XCTAssertEqual(stats.perEngineBreakdown[0].count, 2)
        XCTAssertEqual(stats.perEngineBreakdown[0].words, 4)
        XCTAssertEqual(stats.perEngineBreakdown[1].engine, "qwen")
        XCTAssertEqual(stats.perEngineBreakdown[1].count, 1)
        XCTAssertEqual(stats.perEngineBreakdown[1].words, 1)
    }

    func testTotalTranscriptionsIsEntryCount() {
        let entries = [
            makeEntry(text: "a", durationSeconds: 5),
            makeEntry(text: "b", durationSeconds: 5),
            makeEntry(text: "c", durationSeconds: 5),
        ]

        let stats = WhiskerStats.compute(from: entries)

        XCTAssertEqual(stats.totalTranscriptions, 3)
    }

    // MARK: - Helpers

    private func makeEntry(
        text: String,
        durationSeconds: Double,
        engineName: String = "parakeet",
        createdAt: Date = Date()
    ) -> DictationResult {
        DictationResult(
            rawTranscript: Transcript(
                text: text,
                createdAt: createdAt,
                durationSeconds: durationSeconds,
                engineName: engineName
            ),
            createdAt: createdAt
        )
    }
}
