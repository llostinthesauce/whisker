import XCTest
@testable import WhiskerCleanup
@testable import WhiskerModels
@testable import WhiskerRemote
@testable import WhiskerTranscriptionCore

final class RemoteMacProcessorTests: XCTestCase {
    override func tearDown() {
        FallbackURLProtocol.reset()
        super.tearDown()
    }

    func testPrepareCallsHealthEndpoint() async throws {
        let client = StubRemoteMacClient(
            health: RemoteHealthResponse(
                ok: true,
                server: "mac",
                version: "0.1.0",
                engine: "whisper.cpp",
                model: "base",
                cleanup: ["raw"],
                maxDurationSeconds: 300
            ),
            transcription: .sample
        )
        let processor = RemoteMacProcessor(client: client)

        try await processor.prepare()

        XCTAssertEqual(client.healthCallCount, 1)
    }

    func testProcessMapsRemoteResponseToDictationResult() async throws {
        let client = StubRemoteMacClient(
            health: nil,
            transcription: RemoteTranscriptionResponse(
                id: "abc",
                text: "raw remote text",
                cleanedText: "cleaned remote text",
                durationSeconds: 4.2,
                engine: "sherpa-onnx",
                model: "parakeet",
                processingSeconds: 0.8,
                segments: [],
                warnings: []
            )
        )
        let processor = RemoteMacProcessor(client: client)

        let result = try await processor.process(
            audioURL: URL(fileURLWithPath: "/tmp/recording.caf"),
            durationSeconds: 5,
            cleanupMode: .message
        )

        XCTAssertEqual(client.transcribeCallCount, 1)
        XCTAssertEqual(client.lastCleanupMode, .message)
        XCTAssertEqual(result.rawTranscript.text, "raw remote text")
        XCTAssertEqual(result.rawTranscript.durationSeconds, 4.2)
        XCTAssertEqual(result.rawTranscript.engineName, "sherpa-onnx/parakeet")
        XCTAssertEqual(result.cleanedText, "cleaned remote text")
        XCTAssertEqual(result.displayText, "cleaned remote text")
    }

    func testProvidesStreamingSession() async throws {
        let client = StubRemoteMacClient(
            health: nil,
            transcription: RemoteTranscriptionResponse(
                id: "abc", text: "whole file", cleanedText: nil, durationSeconds: 2,
                engine: "stub", model: "m", processingSeconds: nil, segments: [], warnings: []
            )
        )
        let processor = RemoteMacProcessor(client: client)
        let provider = processor as? StreamingSessionProviding
        XCTAssertNotNil(provider, "RemoteMacProcessor should provide a streaming session")

        // With no segments ingested, finish() falls back to the whole-file path.
        let session = provider!.makeStreamingSession(
            cleanupMode: .raw,
            fullRecordingURL: URL(fileURLWithPath: "/tmp/full.caf")
        )
        let result = try await session.finish(durationSeconds: 2)
        XCTAssertEqual(result.rawTranscript.text, "whole file")
        XCTAssertEqual(client.transcribeCallCount, 1)
    }

    func testProcessRejectsEmptyRemoteTranscript() async {
        let client = StubRemoteMacClient(
            health: nil,
            transcription: RemoteTranscriptionResponse(
                id: "abc",
                text: " ",
                cleanedText: nil,
                durationSeconds: 1,
                engine: "whisper.cpp",
                model: "base",
                processingSeconds: nil,
                segments: [],
                warnings: []
            )
        )
        let processor = RemoteMacProcessor(client: client)

        do {
            _ = try await processor.process(
                audioURL: URL(fileURLWithPath: "/tmp/recording.caf"),
                durationSeconds: 1,
                cleanupMode: .raw
            )
            XCTFail("Expected empty transcript to throw")
        } catch TranscriptionError.emptyTranscript {
            XCTAssertEqual(client.transcribeCallCount, 1)
        } catch {
            XCTFail("Expected emptyTranscript, got \(error)")
        }
    }

    func testRemoteClientFallsBackToTailscaleWhenLocalHealthCannotConnect() async throws {
        FallbackURLProtocol.setHandler { request in
            guard let host = request.url?.host else {
                throw RemoteMacError.invalidResponse
            }
            if host == "lan-whisker.test" {
                throw URLError(.cannotConnectToHost)
            }
            return (
                200,
                Data("""
                {
                  "ok": true,
                  "server": "whisker-server",
                  "version": "0.1.0",
                  "engine": "parakeet_mlx",
                  "model": "mlx-community/parakeet-tdt-0.6b-v3",
                  "cleanup": ["raw"],
                  "max_duration_seconds": 300
                }
                """.utf8)
            )
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FallbackURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let configuration = RemoteMacClientConfiguration(
            baseURL: URL(string: "http://lan-whisker.test:8787")!,
            fallbackBaseURL: URL(string: "https://whisker-tailnet.example.test")!,
            bearerToken: "secret",
            timeoutSeconds: 1
        )

        let health = try await RemoteMacClient(configuration: configuration, session: session).health()

        XCTAssertEqual(health.server, "whisker-server")
        XCTAssertEqual(FallbackURLProtocol.requestedHosts(), ["lan-whisker.test", "whisker-tailnet.example.test"])
    }

    func testRemoteClientDoesNotFallbackWhenLocalRejectsToken() async throws {
        FallbackURLProtocol.setHandler { _ in
            (401, Data("{}".utf8))
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FallbackURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let configuration = RemoteMacClientConfiguration(
            baseURL: URL(string: "http://lan-whisker.test:8787")!,
            fallbackBaseURL: URL(string: "https://whisker-tailnet.example.test")!,
            bearerToken: "bad-token",
            timeoutSeconds: 1
        )

        do {
            _ = try await RemoteMacClient(configuration: configuration, session: session).health()
            XCTFail("Expected unauthorized")
        } catch RemoteMacError.unauthorized {
            XCTAssertEqual(FallbackURLProtocol.requestedHosts(), ["lan-whisker.test"])
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    func testRemoteClientPreflightsLocalBeforeTranscriptionFallback() async throws {
        FallbackURLProtocol.setHandler { request in
            guard let host = request.url?.host,
                  let path = request.url?.path else {
                throw RemoteMacError.invalidResponse
            }
            if host == "lan-whisker.test", path == "/v1/health" {
                throw URLError(.cannotConnectToHost)
            }
            if host == "whisker-tailnet.example.test", path == "/v1/transcribe" {
                return (
                    200,
                    Data("""
                    {
                      "id": "fallback",
                      "text": "fallback transcript",
                      "duration_seconds": 1.0,
                      "engine": "parakeet_mlx",
                      "model": "balanced",
                      "segments": [],
                      "warnings": []
                    }
                    """.utf8)
                )
            }
            throw RemoteMacError.invalidResponse
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FallbackURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let configuration = RemoteMacClientConfiguration(
            baseURL: URL(string: "http://lan-whisker.test:8787")!,
            fallbackBaseURL: URL(string: "https://whisker-tailnet.example.test")!,
            bearerToken: "secret",
            timeoutSeconds: 300
        )
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-client-preflight-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let response = try await RemoteMacClient(configuration: configuration, session: session)
            .transcribe(audioURL: audioURL, cleanupMode: .raw, returnCleaned: false)

        XCTAssertEqual(response.text, "fallback transcript")
        XCTAssertEqual(FallbackURLProtocol.requestedHosts(), ["lan-whisker.test", "whisker-tailnet.example.test"])
    }
}

private final class StubRemoteMacClient: RemoteMacClientProtocol, @unchecked Sendable {
    private let healthResponse: RemoteHealthResponse?
    private let transcriptionResponse: RemoteTranscriptionResponse

    private(set) var healthCallCount = 0
    private(set) var transcribeCallCount = 0
    private(set) var lastCleanupMode: CleanupMode?

    init(health: RemoteHealthResponse?, transcription: RemoteTranscriptionResponse) {
        self.healthResponse = health
        self.transcriptionResponse = transcription
    }

    func health() async throws -> RemoteHealthResponse {
        healthCallCount += 1
        guard let healthResponse else {
            throw RemoteMacError.invalidResponse
        }
        return healthResponse
    }

    func transcribe(audioURL: URL, cleanupMode: CleanupMode, returnCleaned: Bool) async throws -> RemoteTranscriptionResponse {
        transcribeCallCount += 1
        lastCleanupMode = cleanupMode
        return transcriptionResponse
    }
}

private extension RemoteTranscriptionResponse {
    static let sample = RemoteTranscriptionResponse(
        id: "sample",
        text: "sample text",
        cleanedText: nil,
        durationSeconds: 1,
        engine: "whisper.cpp",
        model: "base",
        processingSeconds: nil,
        segments: [],
        warnings: []
    )
}

private final class FallbackURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (statusCode: Int, data: Data)

    private static let state = FallbackURLProtocolState()

    static func setHandler(_ newHandler: @escaping Handler) {
        state.lock.lock()
        state.handler = newHandler
        state.hosts = []
        state.lock.unlock()
    }

    static func requestedHosts() -> [String] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.hosts
    }

    static func reset() {
        state.lock.lock()
        state.handler = nil
        state.hosts = []
        state.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.lock.lock()
        if let host = request.url?.host {
            Self.state.hosts.append(host)
        }
        let currentHandler = Self.state.handler
        Self.state.lock.unlock()

        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: RemoteMacError.invalidResponse)
            return
        }

        do {
            let response = try currentHandler(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FallbackURLProtocolState: @unchecked Sendable {
    let lock = NSLock()
    var handler: FallbackURLProtocol.Handler?
    var hosts: [String] = []
}
