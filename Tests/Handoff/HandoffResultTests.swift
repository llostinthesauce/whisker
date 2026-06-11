import XCTest
@testable import WhiskerHandoff

final class HandoffResultTests: XCTestCase {
    func testRecordingStatusTelemetryRoundTrips() throws {
        let timestamp = Date(timeIntervalSince1970: 1_774_000_000)
        let result = HandoffResult(
            text: "",
            timestamp: timestamp,
            backend: "Remote server",
            status: .recording,
            elapsedSeconds: 92.4,
            maxDurationSeconds: 300
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HandoffResult.self, from: data)

        XCTAssertEqual(decoded.elapsedSeconds, 92.4)
        XCTAssertEqual(decoded.maxDurationSeconds, 300)
    }

    func testLegacyResultPayloadDecodesWithoutTelemetry() throws {
        let json = """
        {
          "text": "",
          "timestamp": "2026-05-28T12:00:00Z",
          "backend": "Remote server",
          "status": "standby"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HandoffResult.self, from: Data(json.utf8))

        XCTAssertNil(decoded.elapsedSeconds)
        XCTAssertNil(decoded.maxDurationSeconds)
    }
}
