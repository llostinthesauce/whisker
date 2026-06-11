import XCTest
@testable import WhiskerCleanup
@testable import WhiskerModels
@testable import WhiskerRemote
@testable import WhiskerTranscriptionCore

final class StreamingDictationSessionTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func testJoinsSegmentTextsInIndexOrder() async throws {
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success("hello"),
            "seg-1.caf": .success("world")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .raw,
            fullRecordingURL: url("full.caf")
        )
        await session.ingest(segmentURL: url("seg-1.caf"), index: 1)
        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)

        let result = try await session.finish(durationSeconds: 6)

        XCTAssertEqual(result.rawTranscript.text, "hello world")
        XCTAssertNil(result.cleanedText)
        XCTAssertEqual(result.displayText, "hello world")
    }

    func testAppliesClientSideCleanupOnce() async throws {
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success("hello world")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .message,
            fullRecordingURL: url("full.caf")
        )
        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)

        let result = try await session.finish(durationSeconds: 3)

        let expected = try await CleanupPipeline().process("hello world", mode: .message)
        XCTAssertEqual(result.cleanedText, expected)
        XCTAssertEqual(result.displayText, expected)
    }

    func testFallsBackToWholeFileWhenASegmentFails() async throws {
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success("partial"),
            "seg-1.caf": .failure(RemoteMacError.serverUnavailable(statusCode: 503)),
            "full.caf": .success("whole recording text")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .raw,
            fullRecordingURL: url("full.caf")
        )
        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)
        await session.ingest(segmentURL: url("seg-1.caf"), index: 1)

        let result = try await session.finish(durationSeconds: 8)

        XCTAssertEqual(result.rawTranscript.text, "whole recording text")
        XCTAssertTrue(client.requested(contains: "full.caf"))
    }

    func testGapInSegmentIndexesFallsBackToWholeFile() async throws {
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success("first"),
            "seg-2.caf": .success("third"),
            "full.caf": .success("whole recording text")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .raw,
            fullRecordingURL: url("full.caf")
        )
        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)
        await session.ingest(segmentURL: url("seg-2.caf"), index: 2) // gap at index 1

        let result = try await session.finish(durationSeconds: 5)

        XCTAssertEqual(result.rawTranscript.text, "whole recording text")
        XCTAssertTrue(client.requested(contains: "full.caf"))
    }

    func testFallsBackToWholeFileWhenAllSegmentsEmpty() async throws {
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success("   "),
            "full.caf": .success("recovered text")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .raw,
            fullRecordingURL: url("full.caf")
        )
        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)

        let result = try await session.finish(durationSeconds: 2)

        XCTAssertEqual(result.rawTranscript.text, "recovered text")
    }

    func testPublishesSegmentTextBeforeFinish() async throws {
        let received = LockedPublishedSegments()
        let published = expectation(description: "segment text published")
        let client = SegmentStubClient(responses: [
            "seg-0.caf": .success(" first live words ")
        ])
        let session = StreamingDictationSession(
            client: client,
            cleanupMode: .raw,
            fullRecordingURL: url("full.caf"),
            onSegmentText: { index, text in
                received.append(index: index, text: text)
                published.fulfill()
            }
        )

        await session.ingest(segmentURL: url("seg-0.caf"), index: 0)
        await fulfillment(of: [published], timeout: 1)

        let values = received.values
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.0, 0)
        XCTAssertEqual(values.first?.1, "first live words")
    }
}

private final class SegmentStubClient: RemoteMacClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [String: Result<String, Error>]
    private var requestedFiles: [String] = []

    init(responses: [String: Result<String, Error>]) {
        self.responses = responses
    }

    func requested(contains name: String) -> Bool {
        lock.withLock { requestedFiles.contains(name) }
    }

    func health() async throws -> RemoteHealthResponse {
        throw RemoteMacError.invalidResponse
    }

    func transcribe(audioURL: URL, cleanupMode: CleanupMode, returnCleaned: Bool) async throws -> RemoteTranscriptionResponse {
        let key = audioURL.lastPathComponent
        let outcome: Result<String, Error>? = lock.withLock {
            requestedFiles.append(key)
            return responses[key]
        }
        switch outcome {
        case .success(let text):
            return RemoteTranscriptionResponse(
                id: key, text: text, cleanedText: nil, durationSeconds: 1,
                engine: "stub", model: "m", processingSeconds: nil, segments: [], warnings: []
            )
        case .failure(let error):
            throw error
        case .none:
            throw RemoteMacError.invalidResponse
        }
    }
}

private final class LockedPublishedSegments: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [(Int, String)] = []

    var values: [(Int, String)] {
        lock.withLock { stored }
    }

    func append(index: Int, text: String) {
        lock.withLock {
            stored.append((index, text))
        }
    }
}
